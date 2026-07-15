import type { Server } from 'socket.io';
import type { GamePhase, GameState, Round, RoomState } from '../types';
import { llm } from '../llm/wrapper';
import * as roomManager from './roomManager';
import { broadcastChat } from './chat';
import { recordGame } from '../db/gamePlayRepo';
import { awardExp, computeExpAward } from '../db/userRepo';

// 게임/라운드 상태 머신. PLAN "Socket.IO 이벤트 계약"의 페이즈 전이를 서버가 전적으로 소유:
// 대기 → 설정 → 설명 → 토론 → 투표 → 결과 → (역전승 시도) → 게임종료(대기로 복귀)
//
// 타이머 초 값은 PLAN에 명시되어 있지 않아 이 스캐폴드에서 합리적 기본값으로 잡았다. 튜닝 대상.
export const TURN_TIME_LIMIT_SEC = 45;
export const DISCUSSION_TIME_LIMIT_SEC = 40;
export const VOTE_TIME_LIMIT_SEC = 30;
export const LIAR_GUESS_TIME_LIMIT_SEC = 30;
const BOT_THINK_DELAY_MS = 1500;
// 토론 시간 단축/연장 버튼 한 번에 조절되는 폭. 참가자 누구나 누를 수 있다(방장 전용 아님).
export const DISCUSSION_TIME_ADJUST_SEC = 10;
// 단축을 남용해 0초/음수로 만들지 못하도록 최소 남은 시간.
const DISCUSSION_MIN_REMAINING_SEC = 5;
// 토론 중 AI가 실제 참가자인 척 끼어드는 간격 — 참가자에겐 절대 밝히지 않는다(끝까지 비공개).
// 매번 고정 간격이면 패턴이 읽혀 부자연스러우니, 매 턴 이 범위 안에서 균등 분포로 무작위 간격을 고른다.
const DISCUSSION_IMPERSONATION_MIN_INTERVAL_MS = 3000;
const DISCUSSION_IMPERSONATION_MAX_INTERVAL_MS = 7000;

// 문서화된 GameState/Round는 그대로 두고, 타이머 핸들·봇 목록 같은 휘발성 런타임 부가정보는
// roomCode로 키잉한 모듈 내부 맵으로 별도 관리한다(직렬화 대상 타입을 오염시키지 않기 위함).
interface BotInfo {
  id: string;
  nickname: string;
}
const botsByRoom = new Map<string, BotInfo[]>();
const turnIndexByRoom = new Map<string, number>();
const turnTimers = new Map<string, NodeJS.Timeout>();
const phaseTimers = new Map<string, NodeJS.Timeout>();
// 각 페이즈의 종료 예정 시각(ms epoch). room:rejoin 시 실제 남은 시간을 다시 계산해
// 보내주는 데 쓴다(타이머 자체는 setTimeout이 원래 스케줄대로 소유). 토론 페이즈는
// +10/-10초 조절도 있어 별도로 계속 갱신된다.
const discussionDeadlineByRoom = new Map<string, number>();
const turnDeadlineByRoom = new Map<string, number>();
const voteDeadlineByRoom = new Map<string, number>();
const liarGuessDeadlineByRoom = new Map<string, number>();

// deadline(ms epoch)까지 남은 시간을 초 단위로 계산한다. 기록이 없으면(이론상 발생 안 함)
// 원래 제한시간을 그대로 돌려준다.
function remainingSecFrom(deadline: number | undefined, fallbackSec: number): number {
  if (deadline === undefined) return fallbackSec;
  return Math.max(0, Math.round((deadline - Date.now()) / 1000));
}
// 이번 토론 페이즈에서 단축/연장 버튼을 이미 쓴 uid들 — 참가자별로 각각 한 번씩만 허용한다.
interface DiscussionAdjustUsage {
  extended: Set<string>;
  shortened: Set<string>;
}
const discussionAdjustUsageByRoom = new Map<string, DiscussionAdjustUsage>();
// 이번 투표 페이즈에서 "투표 확정"을 누른 uid들 — 후보를 고르는 것(castVote)과는 별개로,
// 전원이 명시적으로 확정해야(또는 시간 만료) 투표가 끝난다.
const voteConfirmedByRoom = new Map<string, Set<string>>();
// 전원 확정 후 바로 집계하지 않고 3초 유예를 두는 타이머(마음이 바뀌어 다시 후보를 바꿀
// 짧은 틈을 준다) — 투표 페이즈 전체 제한시간 타이머(phaseTimers)와는 별개로 관리한다.
const voteGraceTimers = new Map<string, NodeJS.Timeout>();
const VOTE_ALL_CONFIRMED_GRACE_MS = 3000;
// 토론 중 3~7초 무작위 간격으로 실제 참가자인 척 채팅에 끼어드는 사칭 타이머(roomCode 당 하나).
// setInterval이 아니라 매 턴 끝나고 다음 무작위 간격을 다시 잡는 재귀 setTimeout으로 구현한다.
const discussionImpersonationTimers = new Map<string, NodeJS.Timeout>();

function isBotId(id: string): boolean {
  return id.startsWith('bot-');
}

function clearRoomTimers(roomCode: string): void {
  const t1 = turnTimers.get(roomCode);
  if (t1) clearTimeout(t1);
  turnTimers.delete(roomCode);
  const t2 = phaseTimers.get(roomCode);
  if (t2) clearTimeout(t2);
  phaseTimers.delete(roomCode);
  const t3 = voteGraceTimers.get(roomCode);
  if (t3) clearTimeout(t3);
  voteGraceTimers.delete(roomCode);
  discussionDeadlineByRoom.delete(roomCode);
  turnDeadlineByRoom.delete(roomCode);
  voteDeadlineByRoom.delete(roomCode);
  liarGuessDeadlineByRoom.delete(roomCode);
  discussionAdjustUsageByRoom.delete(roomCode);
  voteConfirmedByRoom.delete(roomCode);
  stopDiscussionImpersonation(roomCode);
}

function stopDiscussionImpersonation(roomCode: string): void {
  const t = discussionImpersonationTimers.get(roomCode);
  if (t) clearTimeout(t);
  discussionImpersonationTimers.delete(roomCode);
}

function randomImpersonationIntervalMs(): number {
  return (
    DISCUSSION_IMPERSONATION_MIN_INTERVAL_MS +
    Math.random() * (DISCUSSION_IMPERSONATION_MAX_INTERVAL_MS - DISCUSSION_IMPERSONATION_MIN_INTERVAL_MS)
  );
}

// 실제 참가자인 척 채팅에 끼어드는 사칭 타이머를 시작한다. 토론 페이즈 시작 시(endDescribingPhase)
// 한 번만 호출되고, 투표로 넘어가는 순간(startVoting) 또는 게임 종료(clearRoomTimers)에 멈춘다.
// 매 턴이 끝난 뒤 다음 턴까지의 간격을 새로 무작위로 뽑아 재귀적으로 예약한다(고정 간격이면
// 패턴이 읽히므로 3~7초 사이 균등 분포로 매번 달라지게 함).
function startDiscussionImpersonation(io: Server, room: RoomState): void {
  stopDiscussionImpersonation(room.roomCode);
  const scheduleNext = () => {
    const timer = setTimeout(() => {
      void runDiscussionImpersonationTick(io, room).finally(() => {
        if (discussionImpersonationTimers.has(room.roomCode)) scheduleNext();
      });
    }, randomImpersonationIntervalMs());
    discussionImpersonationTimers.set(room.roomCode, timer);
  };
  scheduleNext();
}

// 참가자(사람+봇 모두) 중 한 명을 매 턴 완전히 무작위로 골라, 그 사람인 척 자유 채팅 메시지를
// 하나 만들어 그 사람의 실제 senderId로 그대로 흘려보낸다 — 클라이언트 입장에서는 그
// 참가자가 직접 보낸 일반 채팅과 완전히 동일하게 보이며, 어떤 표식도 남기지 않는다.
// 직전에 사칭한 대상을 다시 고르지 못하게 막는 로직은 의도적으로 두지 않는다(매 턴 완전 무작위).
async function runDiscussionImpersonationTick(io: Server, room: RoomState): Promise<void> {
  const game = room.currentGame;
  if (!game || game.phase !== 'discussion') return;
  if (game.participantIds.length === 0) return;

  const targetId = pickRandom(game.participantIds);

  try {
    const recentDiscussion = room.chatLog
      .filter((m) => m.type === 'chat')
      .slice(-12)
      .map((m) => ({ nickname: getParticipantNickname(room, m.senderId), text: m.text }));
    // 설명 페이즈에서 각자 제출한 설명은 최근 12개 대화 윈도우와 무관하게 항상 전체를 참고한다.
    const explanations = room.chatLog
      .filter((m) => m.type === 'turnDescription')
      .map((m) => ({ nickname: getParticipantNickname(room, m.senderId), text: m.text }));
    const otherParticipantNicknames = game.participantIds
      .filter((id) => id !== targetId)
      .map((id) => getParticipantNickname(room, id));

    const text = await llm.generateImpersonationMessage({
      category: game.category,
      targetNickname: getParticipantNickname(room, targetId),
      otherParticipantNicknames,
      recentDiscussion,
      explanations,
    });

    // 응답을 기다리는 동안 토론이 이미 끝났을 수 있으니(비동기 호출 중 페이즈 전환) 다시 확인.
    if (room.currentGame !== game || game.phase !== 'discussion') return;
    broadcastChat(io, room, targetId, 'chat', text);
  } catch (err) {
    console.error('[gameEngine] generateImpersonationMessage 실패, 이번 차례는 생략', err);
  }
}

function pickRandom<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

function shuffle<T>(arr: T[]): T[] {
  const copy = [...arr];
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

function getParticipantNickname(room: RoomState, id: string): string {
  const human = room.players.find((p) => p.id === id);
  if (human) return human.nickname;
  const bot = (botsByRoom.get(room.roomCode) ?? []).find((b) => b.id === id);
  if (bot) return bot.nickname;
  // 게임 도중 나간 사람은 room.players에서 이미 빠진 뒤 조회될 수 있다(퇴장 안내 채팅 등).
  // uid가 그대로 노출되지 않도록 게임 시작 시점 스냅샷에서 닉네임을 찾는다.
  const snapshot = room.currentGame?.participants.find((p) => p.id === id);
  return snapshot?.nickname ?? id;
}

// 동점 재투표 시 새 Round가 rounds에 계속 push되므로(startTieBreakDescribing 참고),
// "지금 진행 중인 라운드"는 항상 마지막 요소다.
function currentRound(game: GameState): Round {
  return game.rounds[game.rounds.length - 1];
}

// 설명 발화 순서 대상 — 평소엔 게임 전체 playerOrder, 동점 재설명 중이면 그 동점자들만.
function currentTurnOrder(game: GameState): string[] {
  return game.tieCandidates ?? game.playerOrder;
}

// 투표 후보 목록 — 평소엔(최초 투표) 참가자 전원, 동점 재투표면 그 동점자들만.
function currentVoteCandidates(game: GameState): string[] {
  return game.tieCandidates ?? game.participantIds;
}

// ── 게임 시작 ──

export async function startGame(
  io: Server,
  room: RoomState,
  opts: { category: string | null; aiBotCount: number },
): Promise<void> {
  const usedWords = room.gameHistory.flatMap((g) => [g.realWord, g.liarWord]);
  const { category, realWord, liarWord } = await llm.generateWordPair(
    opts.category,
    usedWords,
    room.customCategories,
  );

  // 이번 게임에 실제로 사용된 카테고리를 이 방의 재사용 목록에 추가한다(중복 제거).
  // 방장이 직접 입력한 것뿐 아니라 AI가 랜덤 생성한 카테고리(opts.category === null)도 포함한다.
  // 새로 추가됐다면 다음 게임 선택지에 바로 뜨도록 방 전체에 갱신된 목록을 브로드캐스트한다.
  if (roomManager.addCustomCategory(room, category)) {
    io.to(room.roomCode).emit('room:customCategoriesUpdated', {
      customCategories: room.customCategories,
    });
  }

  // 모든 제시어에 AI가 텍스트 설명을 미리 만들어 함께 준다(난이도 무관). real/liar 딱 2개뿐이라 한 번씩만 생성.
  const [realExplanation, liarExplanation] = await Promise.all([
    llm.explainWord(realWord, category).catch(() => null),
    llm.explainWord(liarWord, category).catch(() => null),
  ]);

  const bots: BotInfo[] = Array.from({ length: opts.aiBotCount }, (_, i) => ({
    id: `bot-${room.roomCode}-${i + 1}`,
    nickname: `AI 봇 ${i + 1}`,
  }));
  botsByRoom.set(room.roomCode, bots);

  const participantIds = [...room.players.map((p) => p.id), ...bots.map((b) => b.id)];
  const liarIds = [pickRandom(participantIds)]; // MVP: 1명 고정 (PLAN TODO: 추후 방장이 수 선택)
  const playerOrder = shuffle(participantIds);

  // 클라이언트가 투표 후보·턴 배너에 봇 닉네임까지 표시할 수 있도록 참가자 전체(봇 포함) 목록을
  // 함께 보낸다. room:playerListUpdated는 사람만 추적하므로 이 정보를 별도로 실어야 함
  // (하위호환 추가 — 기존 { gameNumber } 클라이언트도 그대로 동작).
  // 게임 상태에도 스냅샷으로 저장해, 도중에 나간 참가자의 닉네임을 계속 해석할 수 있게 한다.
  const participants = [
    ...room.players.map((p) => ({ id: p.id, nickname: p.nickname, isBot: false })),
    ...bots.map((b) => ({ id: b.id, nickname: b.nickname, isBot: true })),
  ];

  const round: Round = { roundNumber: 1, turns: [] };
  const game: GameState = {
    gameNumber: room.gameHistory.length + 1,
    category,
    realWord,
    liarWord,
    liarIds,
    participantIds,
    participants,
    aiBotCount: opts.aiBotCount,
    phase: 'setup',
    playerOrder,
    usedWordsThisGame: [realWord, liarWord],
    rounds: [round],
    votes: {},
    tieCandidates: null,
  };
  room.currentGame = game;
  roomManager.resetChatLog(room);
  turnIndexByRoom.set(room.roomCode, 0);

  io.to(room.roomCode).emit('game:started', {
    gameNumber: game.gameNumber,
    category: game.category,
    participants,
  });
  broadcastChat(io, room, 'system', 'system', `새 게임이 시작되었습니다! 카테고리: ${category}`);

  for (const player of room.players) {
    const isLiar = liarIds.includes(player.id);
    const word = isLiar ? liarWord : realWord;
    const explanation = isLiar ? liarExplanation : realExplanation;
    const socketId = roomManager.getSocketIdByUid(player.id);
    if (socketId) {
      io.to(socketId).emit('round:yourWord', explanation ? { word, explanation } : { word });
    }
  }

  game.phase = 'describing';
  startTurn(io, room);
}

// room:rejoin으로 클라이언트에 내려줄 게임 상태. liarIds/realWord/liarWord와 라운드별
// votes(서버 전용)는 절대 포함하지 않는다 — 이 정보는 round:yourWord/round:resolved로
// 각자에게 필요한 만큼만 이미 개별 전달된다.
// participants는 game:started와 동일한 모양({id, nickname, isBot})으로 봇 닉네임까지 포함해
// 클라이언트가 턴 배너·투표 후보를 새로고침 이전과 동일하게 그릴 수 있게 한다.
// resolution/liarGuess/ended 단계는 round:resolved로 이미 모두에게 realWord/liarWord가
// 공개된 이후이므로, rejoin 시에도 이 단계에서만 함께 내려준다.
const REVEALED_PHASES: GamePhase[] = ['resolution', 'liarGuess', 'ended'];

export function toPublicGameState(room: RoomState, game: GameState) {
  // 게임 시작 시점 스냅샷을 그대로 내려준다 — 도중에 나간 참가자도 포함되어 있어,
  // 재접속한 클라이언트가 그 사람의 설명/채팅을 uid가 아닌 닉네임으로 계속 그릴 수 있다.
  const participants = game.participants;
  const revealed = REVEALED_PHASES.includes(game.phase);
  return {
    gameNumber: game.gameNumber,
    category: game.category,
    aiBotCount: game.aiBotCount,
    phase: game.phase,
    participantIds: game.participantIds,
    participants,
    realWord: revealed ? game.realWord : null,
    liarWord: revealed ? game.liarWord : null,
    liarId: revealed ? game.liarIds[0] : null,
    // 설명 순서·투표 판정 결과는 게임 단위 필드. votes(개별 투표 내역)만 서버 전용이라 제외한다.
    playerOrder: game.playerOrder,
    tieCandidates: game.tieCandidates,
    votedOutId: game.votedOutId,
    wasLiar: game.wasLiar,
    liarGuess: game.liarGuess,
    liarGuessCorrect: game.liarGuessCorrect,
    winner: game.winner,
    rounds: game.rounds, // Round에는 이제 turns만 있어 그대로 내보내도 비밀이 없다
  };
}

// room:rejoin 시, 게임이 진행 중이면 그 플레이어에게 배정된 단어를 다시 보내준다
// (새로고침으로 메모리 상의 round:yourWord 수신 내역이 날아갔기 때문).
export function resendYourWord(io: Server, room: RoomState, uid: string): void {
  const game = room.currentGame;
  if (!game || game.phase === 'setup' || !game.participantIds.includes(uid)) return;
  const isLiar = game.liarIds.includes(uid);
  const word = isLiar ? game.liarWord : game.realWord;
  const socketId = roomManager.getSocketIdByUid(uid);
  if (socketId) {
    io.to(socketId).emit('round:yourWord', { word });
  }
}

// room:rejoin 시, 마침 설명(턴) 페이즈 중이었다면(최초 설명이든 동점자 재설명이든) 지금
// 차례인 사람 기준으로 turn:started를 다시 보내준다 — 재접속한 사람 본인 차례가 아니어도
// "지금 누구 차례인지"는 알아야 화면이 맞게 그려진다. 실제 턴 타이머(setTimeout)는 리셋되지
// 않고 원래 스케줄대로 진행되므로, turnDeadlineByRoom에 기록해둔 실제 종료 시각 기준으로
// 남은 시간을 다시 계산해 보낸다(그래야 재접속한 클라이언트도 다른 클라이언트와 같은
// 카운트다운을 보게 된다).
export function resendTurnStateIfPending(io: Server, room: RoomState, uid: string): void {
  const game = room.currentGame;
  if (!game || game.phase !== 'describing') return;
  const order = currentTurnOrder(game);
  const idx = turnIndexByRoom.get(room.roomCode) ?? 0;
  if (idx >= order.length) return;
  const socketId = roomManager.getSocketIdByUid(uid);
  if (socketId) {
    const timeLimitSec = remainingSecFrom(turnDeadlineByRoom.get(room.roomCode), TURN_TIME_LIMIT_SEC);
    io.to(socketId).emit('turn:started', { playerId: order[idx], timeLimitSec });
  }
}

// room:rejoin 시, 마침 투표 페이즈 중이었다면 후보 목록과 현재 확정 진행률을 다시 보내준다.
// 개인별 선택(votes)은 절대 포함하지 않는다(익명 투표 원칙). 타이머도 turn과 동일하게
// voteDeadlineByRoom 기준 실제 남은 시간으로 다시 계산한다.
export function resendVoteStateIfPending(io: Server, room: RoomState, uid: string): void {
  const game = room.currentGame;
  if (!game || game.phase !== 'voting') return;
  const socketId = roomManager.getSocketIdByUid(uid);
  if (!socketId) return;
  io.to(socketId).emit('vote:started', {
    timeLimitSec: remainingSecFrom(voteDeadlineByRoom.get(room.roomCode), VOTE_TIME_LIMIT_SEC),
    candidateIds: currentVoteCandidates(game),
  });
  const confirmed = voteConfirmedByRoom.get(room.roomCode);
  io.to(socketId).emit('vote:progress', {
    votesInCount: confirmed?.size ?? 0,
    totalCount: game.participantIds.length,
  });
}

// room:rejoin 시, 마침 라이어 역전승 판정 대상으로 지목된 상태였다면 프롬프트를 다시 보내준다.
// 실제 타이머(phaseTimers)는 리셋되지 않고 원래 스케줄대로 판정되므로, liarGuessDeadlineByRoom에
// 기록해둔 종료 시각 기준으로 실제 남은 시간을 계산해 보낸다.
export function resendLiarGuessPromptIfPending(io: Server, room: RoomState, uid: string): void {
  const game = room.currentGame;
  if (!game || game.phase !== 'liarGuess') return;
  if (game.votedOutId !== uid) return;
  const socketId = roomManager.getSocketIdByUid(uid);
  if (socketId) {
    const timeLimitSec = remainingSecFrom(liarGuessDeadlineByRoom.get(room.roomCode), LIAR_GUESS_TIME_LIMIT_SEC);
    io.to(socketId).emit('liar:guessPrompt', { timeLimitSec });
  }
}

// ── 설명(턴) 페이즈 ──

function startTurn(io: Server, room: RoomState): void {
  const game = room.currentGame;
  if (!game) return;
  const order = currentTurnOrder(game);
  const idx = turnIndexByRoom.get(room.roomCode) ?? 0;

  if (idx >= order.length) {
    endDescribingPhase(io, room);
    return;
  }

  const playerId = order[idx];
  io.to(room.roomCode).emit('turn:started', { playerId, timeLimitSec: TURN_TIME_LIMIT_SEC });
  turnDeadlineByRoom.set(room.roomCode, Date.now() + TURN_TIME_LIMIT_SEC * 1000);

  if (isBotId(playerId)) {
    setTimeout(() => void runBotTurn(io, room, playerId), BOT_THINK_DELAY_MS);
    return;
  }

  const timer = setTimeout(() => handleTurnTimeout(io, room, playerId), TURN_TIME_LIMIT_SEC * 1000);
  turnTimers.set(room.roomCode, timer);
}

async function runBotTurn(io: Server, room: RoomState, botId: string): Promise<void> {
  const game = room.currentGame;
  if (!game || game.phase !== 'describing') return;
  const round = currentRound(game);
  // 다른 곳에서 이미 넘어갔으면(방 정리 등) 무시
  const idx = turnIndexByRoom.get(room.roomCode) ?? 0;
  if (currentTurnOrder(game)[idx] !== botId) return;

  try {
    const assignedWord = game.liarIds.includes(botId) ? game.liarWord : game.realWord;
    const priorTurns = round.turns.map((t) => ({
      nickname: getParticipantNickname(room, t.playerId),
      text: t.text,
    }));
    const text = await llm.generateBotTurn({ category: game.category, assignedWord, priorTurns });
    await submitDescriptionInternal(io, room, botId, text);
  } catch (err) {
    console.error('[gameEngine] generateBotTurn 실패, 빈 턴으로 넘어감', err);
    advanceTurn(io, room);
  }
}

function handleTurnTimeout(io: Server, room: RoomState, playerId: string): void {
  const game = room.currentGame;
  if (!game || game.phase !== 'describing') return;
  const idx = turnIndexByRoom.get(room.roomCode) ?? 0;
  if (currentTurnOrder(game)[idx] !== playerId) return;
  // PLAN 타이머 만료 규칙: 미제출은 그냥 못 하는 것으로 처리(빈 채로 다음 턴).
  advanceTurn(io, room);
}

// 현재 턴인 사람만 유효 (PLAN 이벤트 계약). 소켓 핸들러에서 검증 후 호출.
export async function submitDescription(
  io: Server,
  room: RoomState,
  uid: string,
  text: string,
): Promise<void> {
  const game = room.currentGame;
  if (!game || game.phase !== 'describing') return;
  const idx = turnIndexByRoom.get(room.roomCode) ?? 0;
  if (currentTurnOrder(game)[idx] !== uid) return;

  const timer = turnTimers.get(room.roomCode);
  if (timer) clearTimeout(timer);
  turnTimers.delete(room.roomCode);

  await submitDescriptionInternal(io, room, uid, text);
}

async function submitDescriptionInternal(
  io: Server,
  room: RoomState,
  playerId: string,
  text: string,
): Promise<void> {
  const game = room.currentGame;
  if (!game) return;
  const round = currentRound(game);
  round.turns.push({ playerId, text });
  broadcastChat(io, room, playerId, 'turnDescription', text);
  advanceTurn(io, room);
}

function advanceTurn(io: Server, room: RoomState): void {
  const idx = (turnIndexByRoom.get(room.roomCode) ?? 0) + 1;
  turnIndexByRoom.set(room.roomCode, idx);
  const game = room.currentGame;
  if (!game) return;
  if (idx >= currentTurnOrder(game).length) {
    endDescribingPhase(io, room);
  } else {
    startTurn(io, room);
  }
}

function endDescribingPhase(io: Server, room: RoomState): void {
  const game = room.currentGame;
  if (!game) return;
  if (game.tieCandidates) {
    // 동점자 재설명이 끝났다 — 토론 없이 곧바로 그 동점자들만 대상으로 재투표한다.
    startVoting(io, room);
    return;
  }
  game.phase = 'discussion';
  // 설명 페이즈 종료를 명시적으로 알려 클라이언트가 "현재 턴" 배너를 내리고 자유 채팅
  // 모드로 전환할 수 있게 한다 (이전엔 system 채팅 텍스트로만 암시됐음).
  io.to(room.roomCode).emit('discussion:started', { timeLimitSec: DISCUSSION_TIME_LIMIT_SEC });
  broadcastChat(io, room, 'system', 'system', '모든 설명이 끝났습니다. 잠시 자유롭게 토론해보세요.');
  discussionDeadlineByRoom.set(room.roomCode, Date.now() + DISCUSSION_TIME_LIMIT_SEC * 1000);
  const timer = setTimeout(() => startVoting(io, room), DISCUSSION_TIME_LIMIT_SEC * 1000);
  phaseTimers.set(room.roomCode, timer);

  // 새 토론 페이즈이므로 단축/연장 사용 이력을 초기화하고, 참가자 각자에게 "아직 둘 다
  // 쓸 수 있음" 상태를 개인 소켓으로 보낸다(전원 동일한 방송이 아니라 uid별로 달라야 함).
  discussionAdjustUsageByRoom.set(room.roomCode, { extended: new Set(), shortened: new Set() });
  for (const player of room.players) {
    emitDiscussionAdjustState(io, room, player.id);
  }

  // 토론 시간 동안 AI가 실제 참가자인 척 채팅에 끼어들며 교란한다(참가자에겐 절대 비공개).
  startDiscussionImpersonation(io, room);
}

function emitDiscussionAdjustState(io: Server, room: RoomState, uid: string): void {
  const usage = discussionAdjustUsageByRoom.get(room.roomCode);
  const socketId = roomManager.getSocketIdByUid(uid);
  if (!socketId) return;
  io.to(socketId).emit('discussion:myAdjustState', {
    canShorten: !usage?.shortened.has(uid),
    canExtend: !usage?.extended.has(uid),
  });
}

// 재접속(room:rejoin) 시 본인이 이미 단축/연장을 썼는지 다시 알려준다 — 새로고침해도
// 한도가 초기화된 것처럼 보이지 않게(실제 한도는 서버가 어차피 강제하지만, 버튼이 계속
// 눌리는 것처럼 보이는 UI 혼란을 막기 위함). 아울러 discussion:started를 discussionDeadlineByRoom
// 기준 실제 남은 시간으로 다시 보내, 재접속한 클라이언트의 카운트다운이 다른 클라이언트와
// 어긋나지 않게 한다(예: 남들 화면엔 20초 남았는데 본인만 40초로 리셋되는 문제 방지).
export function resendDiscussionAdjustStateIfPending(io: Server, room: RoomState, uid: string): void {
  if (room.currentGame?.phase !== 'discussion') return;
  emitDiscussionAdjustState(io, room, uid);
  const socketId = roomManager.getSocketIdByUid(uid);
  if (socketId) {
    const timeLimitSec = remainingSecFrom(
      discussionDeadlineByRoom.get(room.roomCode),
      DISCUSSION_TIME_LIMIT_SEC,
    );
    io.to(socketId).emit('discussion:started', { timeLimitSec });
  }
}

// 토론 시간을 ±10초 조절한다. 방장 전용이 아니라 누구나 누를 수 있지만(방장의 "투표로
// 넘어가기" 전용 권한은 없앰), 참가자 한 명당 단축·연장 각각 한 번씩만 허용한다.
// 허용된 조절은 discussion:started로 다시 브로드캐스트해(같은 이벤트를 재사용) 모든
// 클라이언트가 CountdownText의 남은 시간을 동일하게 다시 계산하게 한다.
export function adjustDiscussionTime(io: Server, room: RoomState, uid: string, deltaSec: number): void {
  const game = room.currentGame;
  if (!game || game.phase !== 'discussion') return;

  const usage = discussionAdjustUsageByRoom.get(room.roomCode) ?? {
    extended: new Set<string>(),
    shortened: new Set<string>(),
  };
  discussionAdjustUsageByRoom.set(room.roomCode, usage);

  const usedSet = deltaSec > 0 ? usage.extended : usage.shortened;
  if (usedSet.has(uid)) {
    // 이미 쓴 방향으로 또 요청 — 조용히 무시하되, 버튼이 계속 눌리는 것처럼 보이지
    // 않도록 현재 상태를 다시 보내준다.
    emitDiscussionAdjustState(io, room, uid);
    return;
  }
  usedSet.add(uid);

  const deadline = discussionDeadlineByRoom.get(room.roomCode) ?? Date.now();
  const remainingSec = (deadline - Date.now()) / 1000;
  const nickname = getParticipantNickname(room, uid);

  // 남은 시간이 10초 미만인데 단축을 누르면 어중간하게 몇 초 줄이는 대신 바로 투표로 넘긴다.
  if (deltaSec < 0 && remainingSec < 10) {
    const timer = phaseTimers.get(room.roomCode);
    if (timer) clearTimeout(timer);
    broadcastChat(io, room, 'system', 'system', `${nickname}님이 토론 시간을 10초 단축했습니다.`);
    startVoting(io, room);
    return;
  }

  const nextRemainingSec = Math.max(DISCUSSION_MIN_REMAINING_SEC, remainingSec + deltaSec);

  const timer = phaseTimers.get(room.roomCode);
  if (timer) clearTimeout(timer);
  discussionDeadlineByRoom.set(room.roomCode, Date.now() + nextRemainingSec * 1000);
  phaseTimers.set(
    room.roomCode,
    setTimeout(() => startVoting(io, room), nextRemainingSec * 1000),
  );
  io.to(room.roomCode).emit('discussion:started', { timeLimitSec: Math.round(nextRemainingSec) });
  broadcastChat(
    io,
    room,
    'system',
    'system',
    deltaSec > 0
      ? `${nickname}님이 토론 시간을 ${deltaSec}초 연장했습니다.`
      : `${nickname}님이 토론 시간을 ${-deltaSec}초 단축했습니다.`,
  );
  emitDiscussionAdjustState(io, room, uid);
}

// ── 투표 페이즈 ──

function startVoting(io: Server, room: RoomState): void {
  const game = room.currentGame;
  if (!game) return;
  // 토론에서 넘어오는 경로든(자연 종료·단축) 동점 재설명에서 곧장 넘어오는 경로든, 투표가
  // 시작되면 토론용 사칭 인터벌은 더 이상 필요 없다.
  stopDiscussionImpersonation(room.roomCode);
  game.phase = 'voting';
  game.votes = {};
  voteConfirmedByRoom.set(room.roomCode, new Set());

  // 동점 재투표면 후보가 직전 동점자로 제한되고, 아니면(최초 투표) 전원이 후보다.
  const candidateIds = currentVoteCandidates(game);

  broadcastChat(
    io,
    room,
    'system',
    'system',
    game.tieCandidates
      ? `동점자(${candidateIds.map((id) => getParticipantNickname(room, id)).join(', ')})를 대상으로 재투표합니다.`
      : '투표를 시작합니다. 라이어로 의심되는 사람을 선택하세요.',
  );
  io.to(room.roomCode).emit('vote:started', { timeLimitSec: VOTE_TIME_LIMIT_SEC, candidateIds });
  voteDeadlineByRoom.set(room.roomCode, Date.now() + VOTE_TIME_LIMIT_SEC * 1000);

  const timer = setTimeout(() => resolveVoting(io, room), VOTE_TIME_LIMIT_SEC * 1000);
  phaseTimers.set(room.roomCode, timer);

  // 투표권은 후보 제한과 무관하게 참가자 전원에게 있다 — 다만 자기 자신이 후보인 경우
  // 자기 자신에게는 투표할 수 없다(castVote가 검증).
  const bots = botsByRoom.get(room.roomCode) ?? [];
  for (const bot of bots) {
    const delay = 500 + Math.random() * (VOTE_TIME_LIMIT_SEC * 1000 * 0.5);
    setTimeout(() => {
      // 이 방에서 같은 봇 인스턴스로 새 게임이 이미 시작됐다면(빠른 재시작 시 이전 게임의
      // 예약된 봇 투표가 남아있을 수 있음), 지금 진행 중인 게임에 잘못 투표되는 것을 막는다
      // — 그렇지 않으면 새 게임의 투표수가 조기에 채워져 타이머가 갑자기 사라지는 버그가 생긴다.
      if (room.currentGame !== game) return;
      const targets = candidateIds.filter((id) => id !== bot.id);
      if (targets.length === 0) return;
      const target = pickRandom(targets);
      castVote(io, room, bot.id, target);
      // 봇은 사람처럼 마음이 바뀔 일이 없으니 고르는 즉시 확정한다.
      confirmVote(io, room, bot.id);
    }, delay);
  }
}

function emitVoteProgress(io: Server, room: RoomState, game: GameState): void {
  const confirmed = voteConfirmedByRoom.get(room.roomCode);
  const votesInCount = confirmed?.size ?? 0;
  const totalCount = game.participantIds.length;
  io.to(room.roomCode).emit('vote:progress', { votesInCount, totalCount });
}

// 익명 투표, 서버 내부 집계 전용 (PLAN: 개인별 선택은 어떤 클라이언트에도 전송 안 함).
// 확정 전까지는 제한시간 안에서 자유롭게 바꿀 수 있지만(재투표 시 기존 선택을 덮어씀),
// 이것만으로는 투표가 끝나지 않고 confirmVote로 명시적으로 확정해야(또는 시간 만료)
// 집계로 넘어간다. 이미 확정한 후에는 선택을 바꿀 수 없다.
export function castVote(io: Server, room: RoomState, voterId: string, votedPlayerId: string): void {
  const game = room.currentGame;
  if (!game || game.phase !== 'voting') return;
  if (voterId === votedPlayerId) return; // 자기 자신에게는 투표할 수 없다.
  if (!currentVoteCandidates(game).includes(votedPlayerId)) return; // 지금 유효한 후보만 대상 가능.
  if (voteConfirmedByRoom.get(room.roomCode)?.has(voterId)) return;
  if (game.votes[voterId] === votedPlayerId) return;

  game.votes[voterId] = votedPlayerId;
}

// 투표를 최종 확정한다. 아직 아무도 안 골랐으면(votes[uid] 없음) 무시한다.
// 전원이 확정하면 제한시간을 다 기다리지 않고 3초 뒤 집계로 넘어간다(마음이 바뀌어
// 다시 후보를 바꿀 짧은 틈을 준다).
export function confirmVote(io: Server, room: RoomState, uid: string): void {
  const game = room.currentGame;
  if (!game || game.phase !== 'voting') return;
  if (!game.votes[uid]) return;

  const confirmed = voteConfirmedByRoom.get(room.roomCode) ?? new Set<string>();
  voteConfirmedByRoom.set(room.roomCode, confirmed);
  confirmed.add(uid);
  emitVoteProgress(io, room, game);

  if (confirmed.size >= game.participantIds.length) {
    const existingGrace = voteGraceTimers.get(room.roomCode);
    if (existingGrace) clearTimeout(existingGrace);
    voteGraceTimers.set(
      room.roomCode,
      setTimeout(() => {
        voteGraceTimers.delete(room.roomCode);
        const timer = phaseTimers.get(room.roomCode);
        if (timer) clearTimeout(timer);
        phaseTimers.delete(room.roomCode);
        resolveVoting(io, room);
      }, VOTE_ALL_CONFIRMED_GRACE_MS),
    );
  }
}

function resolveVoting(io: Server, room: RoomState): void {
  const game = room.currentGame;
  if (!game || game.phase !== 'voting') return;
  phaseTimers.delete(room.roomCode);
  const grace = voteGraceTimers.get(room.roomCode);
  if (grace) clearTimeout(grace);
  voteGraceTimers.delete(room.roomCode);

  const tally = new Map<string, number>();
  for (const votedId of Object.values(game.votes)) {
    tally.set(votedId, (tally.get(votedId) ?? 0) + 1);
  }

  let maxVotes = 0;
  let tied: string[] = [];
  for (const [id, count] of tally.entries()) {
    if (count > maxVotes) {
      maxVotes = count;
      tied = [id];
    } else if (count === maxVotes) {
      tied.push(id);
    }
  }

  // 0표(전원 기권)나 단독 최다 득표가 아니라 "2명 이상이 동률로 최다 득표"인 경우 —
  // 그 동점자들만 한 번씩 추가 설명한 뒤, 그들만 대상으로 다시 투표한다. 최다 득표가
  // 정확히 1명이 될 때까지 반복(재투표 횟수 제한 없음).
  if (tied.length > 1) {
    startTieBreakDescribing(io, room, tied);
    return;
  }

  const votedOutId = tied.length === 1 ? tied[0] : undefined;
  game.votedOutId = votedOutId;
  game.wasLiar = votedOutId ? game.liarIds.includes(votedOutId) : false;
  game.phase = 'resolution';

  // MVP: 라이어 1명 고정(liarIds 길이 1). 시민이 잘못 지목되거나 아무도 지목되지 않은
  // 경우엔 그 자리에서 바로 게임이 끝나(역전승 단계 없음) 실제 라이어가 누구였는지 알
  // 기회가 없으므로, wasLiar와 무관하게 항상 정체를 공개한다.
  // 지목된 사람·라이어 여부·실제/라이어 제시어·역전승 결과는 채팅에 작은 텍스트로 흘리지
  // 않고, 클라이언트가 round:resolved+round:finalResult를 합쳐 큰 알림창으로 보여준다.
  const liarId = game.liarIds[0];

  io.to(room.roomCode).emit('round:resolved', {
    votedOutId,
    wasLiar: game.wasLiar,
    realWord: game.realWord,
    liarWord: game.liarWord,
    liarId,
  });

  if (game.wasLiar && votedOutId) {
    startLiarGuess(io, room, votedOutId);
  } else {
    game.winner = 'liar'; // 라이어가 지목되지 않음 → 라이어 승
    finalizeGame(io, room, { liarGuessCorrect: null, winner: 'liar' });
  }
}

// 투표가 동점으로 갈린 경우: 동점자만 기존 제시어에 대해 한 번씩 추가 설명한다(새 제시어
// 생성·역할 재배정 없음). 토론 단계는 건너뛰고, 이 설명이 모두 끝나면(endDescribingPhase가
// game.tieCandidates를 보고 판단) 곧바로 이 동점자들만 대상으로 재투표한다.
function startTieBreakDescribing(io: Server, room: RoomState, tiedIds: string[]): void {
  const game = room.currentGame;
  if (!game) return;
  // tiedIds는 득표 집계(투표 도착 순서) 기준이라 순서가 뒤섞여 있을 수 있다 — 기존 설명
  // 순서(playerOrder) 기준으로 동점자만 필터링해 상대적 순서를 그대로 유지한다.
  game.tieCandidates = game.playerOrder.filter((id) => tiedIds.includes(id));
  game.phase = 'describing';
  game.rounds.push({ roundNumber: game.rounds.length + 1, turns: [] });
  turnIndexByRoom.set(room.roomCode, 0);

  const names = game.tieCandidates.map((id) => getParticipantNickname(room, id)).join(', ');
  broadcastChat(
    io,
    room,
    'system',
    'system',
    `투표가 동점이에요(${names}). 동점자만 한 번씩 더 설명한 뒤 다시 투표합니다.`,
  );

  startTurn(io, room);
}

// ── 라이어 역전승 페이즈 ──

function startLiarGuess(io: Server, room: RoomState, liarId: string): void {
  const game = room.currentGame;
  if (!game) return;
  game.phase = 'liarGuess';

  if (isBotId(liarId)) {
    // 봇 라이어도 정답을 모르므로, 자신에게 배정된 가짜 단어를 그대로 "추측"한다 (대개 오답).
    setTimeout(() => void submitLiarGuess(io, room, liarId, game.liarWord), 800);
    return;
  }

  const socketId = roomManager.getSocketIdByUid(liarId);
  if (socketId) io.to(socketId).emit('liar:guessPrompt', { timeLimitSec: LIAR_GUESS_TIME_LIMIT_SEC });
  liarGuessDeadlineByRoom.set(room.roomCode, Date.now() + LIAR_GUESS_TIME_LIMIT_SEC * 1000);

  const timer = setTimeout(() => {
    const g = room.currentGame;
    if (!g || g.phase !== 'liarGuess') return;
    g.liarGuessCorrect = false;
    g.winner = 'citizens';
    finalizeGame(io, room, { liarGuessCorrect: false, winner: 'citizens' });
  }, LIAR_GUESS_TIME_LIMIT_SEC * 1000);
  phaseTimers.set(room.roomCode, timer);
}

// 지목된 사람이 실제 라이어일 때만 유효 (PLAN 이벤트 계약).
// 정답 판정은 LLM(judgeLiarGuess)에게 위임 — 오타·맞춤법·한글/영어 표기 차이를 허용한다.
export async function submitLiarGuess(
  io: Server,
  room: RoomState,
  uid: string,
  guess: string,
): Promise<void> {
  const game = room.currentGame;
  if (!game || game.phase !== 'liarGuess') return;
  if (game.votedOutId !== uid) return;

  const timer = phaseTimers.get(room.roomCode);
  if (timer) clearTimeout(timer);
  phaseTimers.delete(room.roomCode);

  let correct: boolean;
  try {
    correct = await llm.judgeLiarGuess(guess, game.realWord, game.category);
  } catch (err) {
    // LLM 판정이 API 오류 등으로 실패한 경우에만 도는 폴백. 퍼지 매칭은 제거했으므로,
    // 오타 관용 없는 보수적 기준(정규화 후 완전 일치)으로만 정답을 인정한다.
    console.error('[gameEngine] judgeLiarGuess 실패, 정규화 완전 일치로 폴백', err);
    correct = guess.trim().toLowerCase() === game.realWord.trim().toLowerCase();
  }
  // 판정을 기다리는 동안 타임아웃이 먼저 게임을 끝냈을 수 있으니 다시 확인.
  if (room.currentGame?.phase !== 'liarGuess') return;

  game.liarGuess = guess;
  game.liarGuessCorrect = correct;
  game.winner = correct ? 'liar' : 'citizens';
  finalizeGame(io, room, { liarGuessCorrect: correct, winner: game.winner });
}

// ── 진행 중 플레이어 이탈 처리 ──

// 게임 진행 중(describing/discussion/voting/resolution/liarGuess)에 플레이어가 실제로
// 방을 나갔을 때(명시적 나가기, 또는 재접속 유예 만료) 호출한다. 일시적 연결 끊김만으로는
// 호출되지 않는다 — roomManager의 재접속 유예 기간이 끝나 확정적으로 제거된 시점에만 온다.
export function handlePlayerLeft(io: Server, room: RoomState, uid: string): void {
  const game = room.currentGame;
  if (!game || game.phase === 'ended') return;
  if (!game.participantIds.includes(uid)) return; // 이번 게임 참가자가 아니면 무관

  const nickname = getParticipantNickname(room, uid);

  if (game.liarIds.includes(uid)) {
    // 라이어가 나갔다 — 더 이상 라이어를 잡아낼 의미가 없으므로 즉시 시민 승리로 종료한다.
    broadcastChat(io, room, 'system', 'system', `${nickname}님(라이어)이 게임 도중 나가 게임을 종료합니다.`);
    finalizeGame(io, room, { liarGuessCorrect: null, winner: 'citizens' });
    return;
  }

  // 시민이 나갔다 — 이번 게임의 참가자 목록에서 완전히 제거해, 지금이든 나중이든
  // 그 사람 차례가 다시 오지 않게 한다(설명 순서/투표 후보 모두에서 제외).
  const order = currentTurnOrder(game);
  const oldIdx = turnIndexByRoom.get(room.roomCode) ?? 0;
  const leftIdx = order.indexOf(uid);
  const wasCurrentTurn = game.phase === 'describing' && leftIdx === oldIdx;

  game.participantIds = game.participantIds.filter((id) => id !== uid);
  game.playerOrder = game.playerOrder.filter((id) => id !== uid);
  if (game.tieCandidates) {
    game.tieCandidates = game.tieCandidates.filter((id) => id !== uid);
  }
  delete game.votes[uid];

  broadcastChat(io, room, 'system', 'system', `${nickname}님이 게임 도중 나갔습니다.`);

  if (game.phase === 'describing' && leftIdx !== -1 && leftIdx < oldIdx) {
    // 이미 차례가 지나간 사람이 나갔다 — 배열이 한 칸 당겨지므로 인덱스도 하나 줄여
    // "지금 차례"가 그대로 유지되게 한다(안 그러면 엉뚱한 다음 사람 차례로 밀려버림).
    turnIndexByRoom.set(room.roomCode, oldIdx - 1);
  }

  if (wasCurrentTurn) {
    // 나간 사람이 지금 차례였다 — 그 턴 타이머를 지우고 곧바로 다음 사람 차례로 넘긴다
    // (playerOrder에서 이미 빠졌으므로 같은 인덱스가 자연히 다음 사람을 가리킨다).
    const timer = turnTimers.get(room.roomCode);
    if (timer) clearTimeout(timer);
    turnTimers.delete(room.roomCode);
    startTurn(io, room);
  } else if (game.phase === 'voting') {
    // 총원이 줄었으니 진행률을 다시 보내고, 남은 사람이 이미 전원 확정했다면 유예 없이
    // 곧바로 집계로 넘어간다(나간 사람 하나 때문에 끝까지 기다릴 이유가 없다).
    emitVoteProgress(io, room, game);
    const confirmed = voteConfirmedByRoom.get(room.roomCode);
    if (confirmed && game.participantIds.length > 0 && confirmed.size >= game.participantIds.length) {
      const graceTimer = voteGraceTimers.get(room.roomCode);
      if (graceTimer) clearTimeout(graceTimer);
      voteGraceTimers.delete(room.roomCode);
      const timer = phaseTimers.get(room.roomCode);
      if (timer) clearTimeout(timer);
      phaseTimers.delete(room.roomCode);
      resolveVoting(io, room);
    }
  }
}

// ── 게임 종료 ──

function finalizeGame(
  io: Server,
  room: RoomState,
  result: { liarGuessCorrect: boolean | null; winner: 'liar' | 'citizens' },
): void {
  const game = room.currentGame;
  if (!game) return;

  // 라이어가 실제로 역전승을 시도했다면(game.liarGuess) 그때 쓴 답도 결과 발표에 함께 보낸다
  // (시도 자체가 없었으면 undefined → null).
  io.to(room.roomCode).emit('round:finalResult', { ...result, liarGuess: game.liarGuess ?? null });

  // 반복 플레이 악용 방지(PLAN): 정상 게임은 최소 3명이면 충분 — 일부가 설명을 제출하지
  // 않아도 정상 게임으로 인정한다(설명 제출 여부는 개인별 참여도 보정에서 따로 반영됨).
  // 무효 게임이면 repeatMatchMultiplier=0으로 전원 0 EXP가 된다.
  // 참여도는 최초 설명 라운드(rounds[0]) 기준으로만 판단한다 — 동점 재설명 라운드는
  // 동점자만 포함하므로, 그걸 기준으로 삼으면 동점자가 아니었던 사람이 부당하게
  // "설명 미제출"로 잡힌다.
  const mainRound = game.rounds[0];
  const submittedAll = (id: string): boolean => mainRound.turns.some((t) => t.playerId === id);
  const gameValid = game.participantIds.length >= 3;

  const winnerIsLiar = result.winner === 'liar';
  const humanIds = game.participantIds.filter((id) => !isBotId(id));

  const statEntries = humanIds.map((id) => ({
    userId: id,
    wasLiar: game.liarIds.includes(id),
    won: winnerIsLiar ? game.liarIds.includes(id) : !game.liarIds.includes(id),
  }));

  const expEntries = humanIds.map((id) => {
    const wasLiar = game.liarIds.includes(id);
    const won = winnerIsLiar ? wasLiar : !wasLiar;
    const votedFor = game.votes[id];
    return {
      userId: id,
      exp: computeExpAward({
        wasLiar,
        won,
        // 라이어가 지목된 뒤(votedOutId===id) 승리했다면 역전승(75), 아니면 기본 승리(60).
        wasComebackWin: wasLiar && won && game.votedOutId === id,
        votedForLiar: votedFor != null && game.liarIds.includes(votedFor),
        submittedAllDescriptions: submittedAll(id),
        voted: votedFor != null,
        gameValid,
      }),
    };
  });

  recordGame(statEntries).catch((err) => console.error('[gameEngine] GamePlay 기록 실패', err));
  awardExp(expEntries).catch((err) => console.error('[gameEngine] EXP 지급 실패', err));

  io.to(room.roomCode).emit('game:ended', {});
  broadcastChat(io, room, 'system', 'system', '---- 게임이 종료되었습니다 ----');

  game.phase = 'ended';
  room.gameHistory.push(game);
  room.currentGame = null;

  clearRoomTimers(room.roomCode);
  botsByRoom.delete(room.roomCode);
  turnIndexByRoom.delete(room.roomCode);

  // 로비 카드의 "진행중" 표시가 실시간으로 내려가도록(다시 입장 가능해짐).
  if (room.visibility === 'public') {
    io.emit('room:publicList', { rooms: roomManager.listPublicRooms() });
  }
}
