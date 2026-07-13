import type { Server } from 'socket.io';
import type { GamePhase, GameState, Round, RoomState } from '../types';
import { llm } from '../llm/wrapper';
import * as roomManager from './roomManager';
import { broadcastChat } from './chat';
import { recordGame } from '../db/gamePlayRepo';

// 게임/라운드 상태 머신. PLAN "Socket.IO 이벤트 계약"의 페이즈 전이를 서버가 전적으로 소유:
// 대기 → 설정 → 설명 → 토론 → 투표 → 결과 → (역전승 시도) → 게임종료(대기로 복귀)
//
// 타이머 초 값은 PLAN에 명시되어 있지 않아 이 스캐폴드에서 합리적 기본값으로 잡았다. 튜닝 대상.
export const TURN_TIME_LIMIT_SEC = 60;
export const DISCUSSION_TIME_LIMIT_SEC = 30;
export const VOTE_TIME_LIMIT_SEC = 30;
export const LIAR_GUESS_TIME_LIMIT_SEC = 30;
const BOT_THINK_DELAY_MS = 1500;

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

function normalizeWord(s: string): string {
  return s.trim().toLowerCase().replace(/\s+/g, '');
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
  const { category, realWord, liarWord } = await llm.generateWordPair(opts.category, usedWords);

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

  const round: Round = { roundNumber: 1, playerOrder, turns: [], votes: {} };
  const game: GameState = {
    gameNumber: room.gameHistory.length + 1,
    category,
    realWord,
    liarWord,
    liarIds,
    participantIds,
    aiBotCount: opts.aiBotCount,
    phase: 'setup',
    usedWordsThisGame: [realWord, liarWord],
    rounds: [round],
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
    rounds: game.rounds.map(({ votes: _votes, ...publicRound }) => publicRound),
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
  const round = currentRound(game);
  if (round.votedOutId !== uid) return;
  const socketId = roomManager.getSocketIdByUid(uid);
  if (socketId) {
    io.to(socketId).emit('liar:guessPrompt', { timeLimitSec: LIAR_GUESS_TIME_LIMIT_SEC });
  }
}

// ── 설명(턴) 페이즈 ──

function startTurn(io: Server, room: RoomState): void {
  const game = room.currentGame;
  if (!game) return;
  const round = currentRound(game);
  const idx = turnIndexByRoom.get(room.roomCode) ?? 0;

  if (idx >= round.playerOrder.length) {
    endDescribingPhase(io, room);
    return;
  }

  const playerId = round.playerOrder[idx];
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
  if (round.playerOrder[idx] !== botId) return;

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
  const round = currentRound(game);
  const idx = turnIndexByRoom.get(room.roomCode) ?? 0;
  if (round.playerOrder[idx] !== playerId) return;
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
  const round = currentRound(game);
  const idx = turnIndexByRoom.get(room.roomCode) ?? 0;
  if (round.playerOrder[idx] !== uid) return;

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
  if (idx >= currentRound(game).playerOrder.length) {
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
  const timer = setTimeout(() => startVoting(io, room), DISCUSSION_TIME_LIMIT_SEC * 1000);
  phaseTimers.set(room.roomCode, timer);
}

// ── 투표 페이즈 ──

function startVoting(io: Server, room: RoomState): void {
  const game = room.currentGame;
  if (!game) return;
  game.phase = 'voting';
  currentRound(game).votes = {};

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
export function castVote(io: Server, room: RoomState, voterId: string, votedPlayerId: string): void {
  const game = room.currentGame;
  if (!game || game.phase !== 'voting') return;
  const round = currentRound(game);
  if (round.votes[voterId]) return; // 이미 투표함 (idempotent)
  if (!game.participantIds.includes(votedPlayerId)) return;

  round.votes[voterId] = votedPlayerId;
  const votesInCount = Object.keys(round.votes).length;
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
  const round = currentRound(game);

  const tally = new Map<string, number>();
  for (const votedId of Object.values(round.votes)) {
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

  round.votedOutId = votedOutId;
  round.wasLiar = votedOutId ? game.liarIds.includes(votedOutId) : false;
  game.phase = 'resolution';

  // MVP: 라이어 1명 고정(liarIds 길이 1). 시민이 잘못 지목되거나 아무도 지목되지 않은
  // 경우엔 그 자리에서 바로 게임이 끝나(역전승 단계 없음) 실제 라이어가 누구였는지 알
  // 기회가 없으므로, wasLiar와 무관하게 항상 정체를 공개한다.
  const liarId = game.liarIds[0];
  const liarNickname = getParticipantNickname(room, liarId);
  let summary: string;
  if (!votedOutId) {
    summary = `투표가 충분히 모이지 않아 아무도 지목되지 않았습니다. 실제 라이어는 ${liarNickname}님이었습니다.`;
  } else if (round.wasLiar) {
    summary = `${getParticipantNickname(room, votedOutId)}님이 최다 득표로 지목되었습니다. (라이어 O)`;
  } else {
    summary = `${getParticipantNickname(room, votedOutId)}님이 최다 득표로 지목되었지만 라이어가 아니었습니다. 실제 라이어는 ${liarNickname}님이었습니다.`;
  }
  broadcastChat(io, room, 'system', 'system', summary);

  io.to(room.roomCode).emit('round:resolved', {
    votedOutId,
    wasLiar: round.wasLiar,
    realWord: game.realWord,
    liarWord: game.liarWord,
    liarId,
  });

  if (round.wasLiar && votedOutId) {
    startLiarGuess(io, room, votedOutId);
  } else {
    round.winner = 'liar'; // 라이어가 지목되지 않음 → 라이어 승
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
    if (room.currentGame?.phase !== 'liarGuess') return;
    const round = currentRound(room.currentGame);
    round.liarGuessCorrect = false;
    round.winner = 'citizens';
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
  const round = currentRound(game);
  if (round.votedOutId !== uid) return;

  const timer = phaseTimers.get(room.roomCode);
  if (timer) clearTimeout(timer);
  phaseTimers.delete(room.roomCode);

  let correct: boolean;
  try {
    correct = await llm.judgeLiarGuess(guess, game.realWord);
  } catch (err) {
    console.error('[gameEngine] judgeLiarGuess 실패, 단순 일치 비교로 폴백', err);
    correct = normalizeWord(guess) === normalizeWord(game.realWord);
  }
  // 판정을 기다리는 동안 타임아웃이 먼저 게임을 끝냈을 수 있으니 다시 확인.
  if (room.currentGame?.phase !== 'liarGuess') return;

  round.liarGuess = guess;
  round.liarGuessCorrect = correct;
  round.winner = correct ? 'liar' : 'citizens';
  finalizeGame(io, room, { liarGuessCorrect: correct, winner: round.winner });
}

// ── 게임 종료 ──

function finalizeGame(
  io: Server,
  room: RoomState,
  result: { liarGuessCorrect: boolean | null; winner: 'liar' | 'citizens' },
): void {
  const game = room.currentGame;
  if (!game) return;

  io.to(room.roomCode).emit('round:finalResult', result);

  const humanEntries = game.participantIds
    .filter((id) => !isBotId(id))
    .map((id) => ({
      userId: id,
      wasLiar: game.liarIds.includes(id),
      won: result.winner === 'liar' ? game.liarIds.includes(id) : !game.liarIds.includes(id),
      category: game.category,
    }));
  recordGame(humanEntries).catch((err) => console.error('[gameEngine] GamePlay 기록 실패', err));

  io.to(room.roomCode).emit('game:ended', {});

  game.phase = 'ended';
  room.gameHistory.push(game);
  room.currentGame = null;

  clearRoomTimers(room.roomCode);
  botsByRoom.delete(room.roomCode);
  turnIndexByRoom.delete(room.roomCode);
}
