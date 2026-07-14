import type { Server } from 'socket.io';
import type { GamePhase, GameState, Round, RoomState } from '../types';
import { llm } from '../llm/wrapper';
import { isFuzzyMatch } from '../llm/textMatch';
import * as roomManager from './roomManager';
import { broadcastChat } from './chat';
import { recordGame } from '../db/gamePlayRepo';
import { awardExp, computeExpAward } from '../db/userRepo';

// 게임/라운드 상태 머신. PLAN "Socket.IO 이벤트 계약"의 페이즈 전이를 서버가 전적으로 소유:
// 대기 → 설정 → 설명 → 토론 → 투표 → 결과 → (역전승 시도) → 게임종료(대기로 복귀)
//
// 타이머 초 값은 PLAN에 명시되어 있지 않아 이 스캐폴드에서 합리적 기본값으로 잡았다. 튜닝 대상.
export const TURN_TIME_LIMIT_SEC = 60;
export const DISCUSSION_TIME_LIMIT_SEC = 40;
export const VOTE_TIME_LIMIT_SEC = 30;
export const LIAR_GUESS_TIME_LIMIT_SEC = 30;
const BOT_THINK_DELAY_MS = 1500;
// 토론 시간 단축/연장 버튼 한 번에 조절되는 폭. 참가자 누구나 누를 수 있다(방장 전용 아님).
export const DISCUSSION_TIME_ADJUST_SEC = 10;
// 단축을 남용해 0초/음수로 만들지 못하도록 최소 남은 시간.
const DISCUSSION_MIN_REMAINING_SEC = 5;

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
// 토론 종료 예정 시각(ms epoch). +10/-10초 조절 시 남은 시간을 다시 계산하는 데 쓴다.
const discussionDeadlineByRoom = new Map<string, number>();
// 이번 토론 페이즈에서 단축/연장 버튼을 이미 쓴 uid들 — 참가자별로 각각 한 번씩만 허용한다.
interface DiscussionAdjustUsage {
  extended: Set<string>;
  shortened: Set<string>;
}
const discussionAdjustUsageByRoom = new Map<string, DiscussionAdjustUsage>();

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
  discussionDeadlineByRoom.delete(roomCode);
  discussionAdjustUsageByRoom.delete(roomCode);
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
  return bot?.nickname ?? id;
}

function currentRound(game: GameState): Round {
  return game.rounds[0];
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
    llm.explainWord(realWord).catch(() => null),
    llm.explainWord(liarWord).catch(() => null),
  ]);

  const bots: BotInfo[] = Array.from({ length: opts.aiBotCount }, (_, i) => ({
    id: `bot-${room.roomCode}-${i + 1}`,
    nickname: `AI 봇 ${i + 1}`,
  }));
  botsByRoom.set(room.roomCode, bots);

  const participantIds = [...room.players.map((p) => p.id), ...bots.map((b) => b.id)];
  const liarIds = [pickRandom(participantIds)]; // MVP: 1명 고정 (PLAN TODO: 추후 방장이 수 선택)
  const playerOrder = shuffle(participantIds);

  const round: Round = { roundNumber: 1, turns: [] };
  const game: GameState = {
    gameNumber: room.gameHistory.length + 1,
    category,
    realWord,
    liarWord,
    liarIds,
    participantIds,
    aiBotCount: opts.aiBotCount,
    phase: 'setup',
    playerOrder,
    usedWordsThisGame: [realWord, liarWord],
    rounds: [round],
    votes: {},
  };
  room.currentGame = game;
  roomManager.resetChatLog(room);
  turnIndexByRoom.set(room.roomCode, 0);

  // 클라이언트가 투표 후보·턴 배너에 봇 닉네임까지 표시할 수 있도록 참가자 전체(봇 포함) 목록을
  // 함께 보낸다. room:playerListUpdated는 사람만 추적하므로 이 정보를 별도로 실어야 함
  // (하위호환 추가 — 기존 { gameNumber } 클라이언트도 그대로 동작).
  const participants = [
    ...room.players.map((p) => ({ id: p.id, nickname: p.nickname, isBot: false })),
    ...bots.map((b) => ({ id: b.id, nickname: b.nickname, isBot: true })),
  ];
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
  const bots = botsByRoom.get(room.roomCode) ?? [];
  const participants = [
    ...room.players.map((p) => ({ id: p.id, nickname: p.nickname, isBot: false })),
    ...bots.map((b) => ({ id: b.id, nickname: b.nickname, isBot: true })),
  ];
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

// room:rejoin 시, 마침 라이어 역전승 판정 대상으로 지목된 상태였다면 프롬프트를 다시 보내준다.
// 실제 타이머(phaseTimers)는 리셋되지 않고 원래 스케줄대로 판정되므로, 남은 시간이 표시값보다
// 짧을 수 있다(재접속이 잦지 않은 30초 남짓의 좁은 구간이라 우선순위를 낮춰 단순화함).
export function resendLiarGuessPromptIfPending(io: Server, room: RoomState, uid: string): void {
  const game = room.currentGame;
  if (!game || game.phase !== 'liarGuess') return;
  if (game.votedOutId !== uid) return;
  const socketId = roomManager.getSocketIdByUid(uid);
  if (socketId) {
    io.to(socketId).emit('liar:guessPrompt', { timeLimitSec: LIAR_GUESS_TIME_LIMIT_SEC });
  }
}

// ── 설명(턴) 페이즈 ──

function startTurn(io: Server, room: RoomState): void {
  const game = room.currentGame;
  if (!game) return;
  const idx = turnIndexByRoom.get(room.roomCode) ?? 0;

  if (idx >= game.playerOrder.length) {
    endDescribingPhase(io, room);
    return;
  }

  const playerId = game.playerOrder[idx];
  io.to(room.roomCode).emit('turn:started', { playerId, timeLimitSec: TURN_TIME_LIMIT_SEC });

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
  if (game.playerOrder[idx] !== botId) return;

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
  if (game.playerOrder[idx] !== playerId) return;
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
  if (game.playerOrder[idx] !== uid) return;

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

  // 매 턴 AI 교란 코멘트 (PLAN: 라이어 정체는 절대 프롬프트에 넣지 않음).
  // 다음 턴 시작(또는 마지막 턴이면 "모든 설명이 끝났습니다" 페이즈 전환 안내)보다
  // 먼저 끝나도록 기다려, 채팅 순서가 "설명 → AI 코멘트 → 다음 안내"로 항상 고정되게 한다.
  await generateAndBroadcastComment(io, room, text, round);

  // 코멘트를 기다리는 동안 방이 정리되는 등 상태가 바뀌었을 수 있으니 다시 확인.
  if (room.currentGame?.phase !== 'describing') return;
  advanceTurn(io, room);
}

async function generateAndBroadcastComment(
  io: Server,
  room: RoomState,
  latestDescription: string,
  round: Round,
): Promise<void> {
  const game = room.currentGame;
  if (!game) return;
  try {
    const priorTurns = round.turns.slice(0, -1).map((t) => ({
      nickname: getParticipantNickname(room, t.playerId),
      text: t.text,
    }));
    const comment = await llm.generateTurnComment({
      category: game.category,
      latestDescription,
      priorTurns,
    });
    broadcastChat(io, room, 'ai', 'aiComment', comment);
  } catch (err) {
    console.error('[gameEngine] generateTurnComment 실패, 코멘트 생략', err);
  }
}

function advanceTurn(io: Server, room: RoomState): void {
  const idx = (turnIndexByRoom.get(room.roomCode) ?? 0) + 1;
  turnIndexByRoom.set(room.roomCode, idx);
  const game = room.currentGame;
  if (!game) return;
  if (idx >= game.playerOrder.length) {
    endDescribingPhase(io, room);
  } else {
    startTurn(io, room);
  }
}

function endDescribingPhase(io: Server, room: RoomState): void {
  const game = room.currentGame;
  if (!game) return;
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
// 눌리는 것처럼 보이는 UI 혼란을 막기 위함).
export function resendDiscussionAdjustStateIfPending(io: Server, room: RoomState, uid: string): void {
  if (room.currentGame?.phase !== 'discussion') return;
  emitDiscussionAdjustState(io, room, uid);
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
  const nextRemainingSec = Math.max(DISCUSSION_MIN_REMAINING_SEC, remainingSec + deltaSec);

  const timer = phaseTimers.get(room.roomCode);
  if (timer) clearTimeout(timer);
  discussionDeadlineByRoom.set(room.roomCode, Date.now() + nextRemainingSec * 1000);
  phaseTimers.set(
    room.roomCode,
    setTimeout(() => startVoting(io, room), nextRemainingSec * 1000),
  );
  io.to(room.roomCode).emit('discussion:started', { timeLimitSec: Math.round(nextRemainingSec) });
  emitDiscussionAdjustState(io, room, uid);
}

// ── 투표 페이즈 ──

function startVoting(io: Server, room: RoomState): void {
  const game = room.currentGame;
  if (!game) return;
  game.phase = 'voting';
  game.votes = {};

  broadcastChat(io, room, 'system', 'system', '투표를 시작합니다. 라이어로 의심되는 사람을 선택하세요.');
  io.to(room.roomCode).emit('vote:started', { timeLimitSec: VOTE_TIME_LIMIT_SEC });

  const timer = setTimeout(() => resolveVoting(io, room), VOTE_TIME_LIMIT_SEC * 1000);
  phaseTimers.set(room.roomCode, timer);

  const bots = botsByRoom.get(room.roomCode) ?? [];
  for (const bot of bots) {
    const delay = 500 + Math.random() * (VOTE_TIME_LIMIT_SEC * 1000 * 0.5);
    setTimeout(() => {
      const target = pickRandom(game.participantIds.filter((id) => id !== bot.id));
      castVote(io, room, bot.id, target);
    }, delay);
  }
}

// 익명 투표, 서버 내부 집계 전용 (PLAN: 개인별 선택은 어떤 클라이언트에도 전송 안 함).
// 투표 대상은 제한시간(VOTE_TIME_LIMIT_SEC) 안에서는 자유롭게 바꿀 수 있고(재투표 시 기존
// 선택을 덮어씀), 전원이 투표를 마치면 30초를 다 기다리지 않고 바로 종료한다.
export function castVote(io: Server, room: RoomState, voterId: string, votedPlayerId: string): void {
  const game = room.currentGame;
  if (!game || game.phase !== 'voting') return;
  if (!game.participantIds.includes(votedPlayerId)) return;

  game.votes[voterId] = votedPlayerId;
  const votesInCount = Object.keys(game.votes).length;
  const totalCount = game.participantIds.length;
  io.to(room.roomCode).emit('vote:progress', { votesInCount, totalCount });

  if (votesInCount >= totalCount) {
    const timer = phaseTimers.get(room.roomCode);
    if (timer) clearTimeout(timer);
    phaseTimers.delete(room.roomCode);
    resolveVoting(io, room);
  }
}

function resolveVoting(io: Server, room: RoomState): void {
  const game = room.currentGame;
  if (!game || game.phase !== 'voting') return;
  phaseTimers.delete(room.roomCode);

  const tally = new Map<string, number>();
  for (const votedId of Object.values(game.votes)) {
    tally.set(votedId, (tally.get(votedId) ?? 0) + 1);
  }

  let votedOutId: string | undefined;
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
  if (tied.length > 0) votedOutId = pickRandom(tied);

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
    correct = await llm.judgeLiarGuess(guess, game.realWord);
  } catch (err) {
    console.error('[gameEngine] judgeLiarGuess 실패, 유사 일치 비교로 폴백', err);
    correct = isFuzzyMatch(guess, game.realWord);
  }
  // 판정을 기다리는 동안 타임아웃이 먼저 게임을 끝냈을 수 있으니 다시 확인.
  if (room.currentGame?.phase !== 'liarGuess') return;

  game.liarGuess = guess;
  game.liarGuessCorrect = correct;
  game.winner = correct ? 'liar' : 'citizens';
  finalizeGame(io, room, { liarGuessCorrect: correct, winner: game.winner });
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

  // 반복 플레이 악용 방지(PLAN): 정상 게임은 최소 3명 + 모든 참가자가 최소 한 번 이상 설명 제출.
  // 무효 게임이면 repeatMatchMultiplier=0으로 전원 0 EXP가 된다(봇은 항상 자동 설명하므로,
  // 사실상 사람이 자기 차례 설명을 한 번도 안 낸 경우에만 무효가 된다).
  const submittedAll = (id: string): boolean =>
    game.rounds.every((r) => r.turns.some((t) => t.playerId === id));
  const gameValid =
    game.participantIds.length >= 3 && game.participantIds.every((id) => submittedAll(id));

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
