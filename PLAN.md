# AI 라이어게임 (Liar Game) — 구현 계획

## Context

madcamp 공통과제(2인 1팀)로, 실시간 인터랙션·LLM Wrapper·Cross-Platform 세 옵션을 모두 만족하는 **AI가 개입하는 라이어게임**을 만든다.

**용어 계층**: 방(Room) > 게임(Game) > 라운드(Round). 라운드는 모든 참가자가 받은 제시어를 한 턴씩 설명하는 것으로, MVP에서는 게임당 1라운드만 돈다(라운드 재시작은 스트레치).

**게임 규칙**: 방장이 방을 만들 때 최대 인원을 지정한다(시스템상 상한 없음). 게임 시작에는 최소 3명(사람+봇 합산)이 필요하고, 방이 다 차지 않아도 이 조건만 충족하면 시작할 수 있다. 방장은 카테고리(프리셋 선택·직접 입력·"AI 랜덤 생성" 중 택1)와 AI 봇 수를 정하며, 전원(사람+봇)이 준비 완료 상태여야 방장이 게임 시작 버튼을 누를 수 있다. 참가자(사람+봇) 중 라이어(고정 1명)는 **자신이 라이어인지 모른 채** 진짜 제시어와 비슷하지만 다른 가짜 제시어를 받는다. 각자 제시어를 직접 말하지 않고 설명한 뒤 익명 투표로 라이어를 지목한다. 지목된 사람이 실제 라이어면 진짜 제시어를 맞혀 역전승할 기회를 주고, 실제 라이어가 아니면 역전승 기회 없이 그 즉시 라이어 팀 승리로 게임이 끝난다.

AI는 다섯 지점에 개입해 "LLM Wrapper" 요소를 드러낸다:
1. 방장이 지정(또는 AI 랜덤)한 카테고리로 진짜/가짜 제시어 쌍을 생성
2. 방장이 선택한 수만큼 AI 봇이 플레이어로 참여해 설명 생성 (봇도 자신이 라이어인지 모름 — 사람과 동일 조건)
3. **매 턴** 설명이 제출될 때마다 AI가 일부러 헷갈리게 하는 "교란" 코멘트를 닉네임으로 지칭해 단다
4. 제시어가 낯선 단어로 판단되면 AI가 해당 단어에 대한 텍스트 설명을 함께 제공한다 (이미지 생성은 하지 않음)
5. 역전승 시도 시 AI가 정답 여부를 유사도 기반으로 판정한다 (오타·맞춤법 오류·한글/영어 표기 차이 허용)

**방 UI는 그룹 채팅 형식**으로, 턴 설명·AI 교란 코멘트·시스템 안내·자유 채팅이 하나의 피드에 흐른다. 채팅은 **새 게임 시작 시에만 초기화**되어, 게임 종료 후에도 남아 계속 대화할 수 있다. 방은 **공개(public, 목록에서 입장)**와 **비공개(private, 4자리 코드로 입장)** 두 종류다.

**기술 스택**: Flutter(iOS/Android/Web 단일 코드베이스로 Cross-Platform 충족) + Socket.IO 온라인 방, 백엔드 Node/Express, 인증 Firebase Auth + 백엔드 로컬 DB, LLM Anthropic Claude.

## 목차

- [확정된 제품/기술 결정](#확정된-제품기술-결정)
- [인증/유저 관리 흐름](#인증유저-관리-흐름)
- [데이터 모델 (인메모리, 과도한 정규화 없이)](#데이터-모델-인메모리-과도한-정규화-없이)
- [DB 스키마 (영구 저장: 유저·전적·친구)](#db-스키마-영구-저장-유저전적친구)
- [Socket.IO 이벤트 계약 (MVP)](#socketio-이벤트-계약-mvp)
- [REST API (전적·친구)](#rest-api-전적친구)
- [LLM 래퍼 (`backend/src/llm/wrapper.ts`)](#llm-래퍼-backendsrcllmwrapperts)
- [백엔드 구현 현황 (backend 브랜치)](#백엔드-구현-현황-backend-브랜치)
- [프론트-백엔드 연결 정합성](#프론트-백엔드-연결-정합성)
- [MVP 제외 (stretch)](#mvp-제외-stretch)
- [TODO / 향후 과제](#todo--향후-과제)
- [검증 계획](#검증-계획)
- [배포 및 DB 운영](#배포-및-db-운영)

## 확정된 제품/기술 결정

- **프론트엔드**: Flutter — iOS/Android/Web 단일 코드베이스. `socket_io_client` 패키지로 Socket.IO 서버와 통신.
- **실시간**: Socket.IO 기반 온라인 방. 공개방은 로비의 방 목록에서 선택 입장, 비공개방은 4자리 코드 입력으로 입장.
- **백엔드: Node.js + Express + Socket.IO (추천)** — Socket.IO 1st-party 구현이 Node라 가장 안정적. 대안으로 FastAPI + `python-socketio`도 유효하나 기본 추천은 Node.
- **인증/DB: Firebase Authentication + 백엔드 로컬 DB (추천)**
  - FlutterFire가 Flutter SDK를 1급 지원해 로그인 구현 비용이 크게 줄어듦.
  - 백엔드는 소켓 handshake 시 `firebase-admin`으로 ID 토큰만 검증.
  - Firebase Authentication은 인증만 담당하고, 닉네임/프로필/승패 기록 등 유저 데이터는 백엔드가 관리하는 로컬 DB(Postgres 등)에 저장. 익명 계정 link로 UID가 유지되므로, 게스트에서 가입 후 추가 마이그레이션 없이 데이터가 자동으로 이어짐. 방/게임/라운드 같은 휘발성 상태는 Node 서버 **인메모리**에 둔다.
- **LLM: Anthropic Claude API (추천)**
  - 다섯 함수(제시어 쌍 생성, 봇 턴 생성, 매 턴 교란 코멘트, 낯선 단어 설명, 역전승 정답 유사판정) 모두 빈도가 높거나 지연에 민감 → **Claude Haiku 4.5**로 시작.
  - LLM 호출부는 provider(회사)와 모델을 나중에 쉽게 바꿀 수 있도록 얇은 인터페이스로만 감싸고, 과한 멀티프로바이더 프레임워크는 만들지 않음.

## 인증/유저 관리 흐름

### 화면 구조 (5개)
1. **메인 페이지** — 로그인/회원가입 버튼 + 게스트로 계속하기 버튼
2. **로그인/회원가입 페이지** — 통합 인증 폼
3. **로비** — 공개방/비공개방 진입, 내 승률·레벨·프로필 사진 표시, 로그아웃 버튼, 개인정보 수정 페이지 진입점
4. **개인정보 수정 페이지** — 닉네임 변경, 비밀번호 변경(이메일 가입자만), 프로필 사진(아바타) 변경, 로그아웃/계정 탈퇴 버튼
5. **방 페이지(게임 진행)** — 로그인/로그아웃 버튼 없음 (의도적 설계, 아래 "계정 전환 충돌 회피" 참고)

### 게스트(익명) 흐름
메인에서 "게스트로 계속하기" 클릭 → 닉네임 입력 화면 → `signInAnonymously()` 호출 → 로비 진입. 닉네임은 이 시점에 저장(Firebase `displayName` 또는 자체 DB 프로필).

### 로그인/회원가입 페이지 레이아웃
- **Google 로그인/가입 통합 버튼**: 로그인 모드·회원가입 모드 양쪽에 항상 노출
- **이메일 폼**: 기본 노출된 이메일 로그인 폼
- **폼 전환**: 폼 하단 "회원가입하기" 버튼을 누르면 이메일 회원가입 폼으로 전환 (Google 버튼은 유지, 이메일 로그인 폼만 교체)
- **회원가입 폼**: 로그인 폼으로 되돌아가는 링크 필요

### 통합 버튼 인증 로직
클릭 시점의 `auth.currentUser?.isAnonymous` 값으로 분기:

**익명 상태** → `linkWithPopup`/`linkWithCredential`(Google) 또는 `linkWithCredential`(이메일)로 익명 계정을 승격 시도. 성공하면 UID 불변 — 기존 익명 계정의 프로필/데이터가 그대로 이어짐.

**link 실패** (`auth/credential-already-in-use` 또는 이메일의 `auth/email-already-in-use`, 즉 이미 가입된 계정 존재) → `signInWithCredential`/`signInWithEmailAndPassword`로 기존 계정으로 전환, 이전 익명 계정은 폐기(discard).

**비로그인 상태** (익명도 아닌) → 그냥 일반 `signInWithPopup`/`createUserWithEmailAndPassword`/`signInWithEmailAndPassword`.

### 계정 전환 충돌 회피
"계정 전환" 케이스(위에서 기존 계정으로 넘어가는 것)는 진행 중이던 소켓의 인증 UID가 바뀌는 문제가 있음.
- **로비에서는** 소켓 재연결로 간단히 해결 가능해서 허용.
- **방 페이지는** 애초에 로그인/로그아웃 버튼 자체를 없애서 이 충돌 시나리오가 발생할 수 없게 설계함 (별도 차단 로직 불필요).

### 네비게이션
- **"뒤로가기" 버튼**: 로그인/회원가입 페이지의 "뒤로가기" 버튼은 진입 경로(메인 또는 로비)로 복귀 — 스택 기반 네비게이션이면 단순 pop으로 처리 가능.
- **인증 성공**: 로그인/가입 성공 시에는 진입 경로와 무관하게 항상 로비로 이동(메인에서 들어왔어도 로비로 감) — 이건 pop이 아니라 명시적 이동(예: pushReplacement)으로 별도 처리해야 함.

### 로비에서 로그아웃
완전히 sign out 후, 메인 페이지의 "게스트로 계속하기"를 눌렀을 때와 동일한 닉네임 입력 화면으로 이동 → 새 익명 세션 시작.

### 개인정보 수정 페이지 — 비밀번호 변경
`auth.currentUser.providerData`에 `password` 프로바이더가 있는 계정(이메일 가입자)만 "비밀번호 변경" 항목을 노출한다. Google로만 가입한 계정은 비밀번호 자체가 없으므로 이 항목을 숨긴다. Firebase는 민감한 작업에 최근 재인증을 요구하므로, `updatePassword` 호출 전 `reauthenticateWithCredential`(현재 비밀번호 재입력)로 재인증한 뒤 진행한다.

### 유저 프로필/전적 저장 위치
Firebase Authentication은 **인증 전용**으로만 쓰고, 닉네임/프로필 사진/전적 등 유저 데이터는 **자체 백엔드가 관리하는 로컬 DB**에 Firebase `uid`를 키로 저장한다 (Firestore 사용 안 함). Link 시 UID가 안 바뀌므로 게스트 때 쌓인 프로필/닉네임이 회원가입 후에도 별도 마이그레이션 코드 없이 자동으로 이어짐.

### 게스트 데이터 취급
스키마상 정회원과 동일하게 취급(uid로 동일하게 키잉). 다만 로우에 `isAnonymous`(또는 `is_anonymous`) 플래그를 같이 저장해서, 추후 리더보드 등에서 게스트 전적을 구분/필터링할 수 있게 해둔다.

### 게스트 정리(cleanup)
별도 Cloud Functions 없이, 백엔드에 이미 있는 `firebase-admin`을 활용해 백엔드 프로세스 내에서 `node-cron`으로 스케줄 작업을 돌린다. 매일 1회, 마지막 활동(`lastActive`)이 30일 이상 지난 익명 계정을 찾아 `admin.auth().deleteUser(uid)`(Firebase Auth 삭제)와 로컬 DB 로우 삭제를 함께 수행.

## 데이터 모델 (인메모리, 과도한 정규화 없이)

```ts
interface Player { id: string; nickname: string; isBot: boolean; isHost: boolean; connected: boolean; isReady: boolean; }  // 봇은 참여 즉시 isReady: true 고정

interface Round {
  roundNumber: number;
  playerOrder: string[];
  turns: { playerId: string; text: string }[];
  votes: Record<string, string>;   // 서버 전용, 클라이언트로 절대 전송 안 함
  votedOutId?: string;
  wasLiar?: boolean;
  liarGuess?: string;
  liarGuessCorrect?: boolean;
  winner?: 'liar' | 'citizens';
}

interface GameState {
  gameNumber: number;
  category: string;
  realWord: string;
  liarWord: string;
  liarIds: string[];            // 서버 전용 비밀, 라이어 본인에게도 전송 안 함. 길이 1 고정(라이어 수 선택 기능 없음, 확정)
  participantIds: string[];     // 방 플레이어 + 이번 게임에 호스트가 추가한 봇
  aiBotCount: number;
  phase: 'setup'|'describing'|'discussion'|'voting'|'resolution'|'liarGuess'|'ended';
  usedWordsThisGame: string[];
  rounds: Round[];               // MVP: 길이 1. 추후 스트레치: 라운드 재시작 지원 시 길이 증가
}

interface ChatMessage {
  id: string;
  senderId: string | 'ai' | 'system';
  type: 'chat' | 'turnDescription' | 'aiComment' | 'system';
  text: string;
  timestamp: number;
}

interface RoomState {
  roomCode: string;          // 4자리 숫자 문자열, 예: "4821"
  hostId: string;
  visibility: 'public' | 'private';
  maxPlayers: number;        // 방장이 방 생성 시 지정. 시스템상 상한 없음(사람+봇 합산 기준)
  players: Player[];
  customCategories: string[]; // 방장이 이 방에서 직접 추가한 카테고리 이름. 방 종료 시 함께 소멸(영구 저장 안 함)
  chatLog: ChatMessage[];    // 방 존재 동안 유지, 새 게임 시작 시에만 초기화
  currentGame: GameState | null;
  gameHistory: GameState[];  // 지난 게임들 (참고용)
  createdAt: number;
}
```

## DB 스키마 (영구 저장: 유저·전적·친구)

방/게임/라운드 같은 휘발성 상태는 인메모리에 두지만, **유저 프로필·전적·친구 관계는 로컬 Postgres에 Prisma로 영구 저장**한다(현재는 stretch). Firebase Auth는 인증만 담당하고, `uid`를 PK로 삼아 이 DB가 유저 데이터를 소유한다. 아래는 `backend/prisma/schema.prisma`의 영구 저장 모델 설계다.

```prisma
model User {
  uid         String   @id                  // Firebase Auth uid를 그대로 PK로 사용 (link 시 불변 → 게스트→가입 자동 이어짐)
  nickname    String   @unique               // 전역 유일. 회원가입 폼에서 중복 확인 필수(GET /api/users/nickname-availability/:nickname)
  avatarIndex Int      @default(0)
  isAnonymous Boolean  @default(true)        // 게스트 구분 (리더보드 필터링 · 30일 정리 대상 판별)
  createdAt   DateTime @default(now())
  lastActive  DateTime @default(now())       // 게스트 cleanup(마지막 활동 30일 경과) 기준

  plays                  GamePlay[]          // 참여한 게임들 (전적의 source of truth)
  sentFriendRequests     Friendship[] @relation("requester")
  receivedFriendRequests Friendship[] @relation("addressee")
}

// 사람 참가자 1명이 게임 1판을 마칠 때마다 1행 기록 (봇은 Firebase uid가 없으므로 기록 안 함).
// 전적 4종은 모두 이 테이블 집계로 파생한다 — 별도 카운터를 두지 않아 드리프트가 없고, 추후 카테고리별·기간별 통계도 확장 가능.
model GamePlay {
  id       String   @id @default(cuid())
  userId   String
  user     User     @relation(fields: [userId], references: [uid], onDelete: Cascade)
  wasLiar  Boolean                           // 이 게임에서 라이어였는지
  won      Boolean                           // 이 유저가 속한 팀이 최종 승리했는지
  category String
  playedAt DateTime @default(now())

  @@index([userId])
}

// 친구 관계 (요청→수락 모델). 한 쌍당 1행이며 방향(requester/addressee)을 보존한다.
model Friendship {
  id          String           @id @default(cuid())
  requesterId String
  addresseeId String
  requester   User             @relation("requester", fields: [requesterId], references: [uid], onDelete: Cascade)
  addressee   User             @relation("addressee", fields: [addresseeId], references: [uid], onDelete: Cascade)
  status      FriendshipStatus @default(pending)
  createdAt   DateTime         @default(now())
  respondedAt DateTime?

  @@unique([requesterId, addresseeId])       // 같은 쌍 중복 요청 방지
  @@index([addresseeId])                      // 받은 요청 조회용
}

enum FriendshipStatus {
  pending
  accepted
  blocked
}
```

**전적 4종 파생 방식** (한 유저의 `plays` 집계):
- 전체 게임수 = `count(plays)`
- 전체 승률 = `count(won = true) / count(plays)`
- 라이어 승률 = `count(won = true AND wasLiar = true) / count(wasLiar = true)`
- 시민 승률 = `count(won = true AND wasLiar = false) / count(wasLiar = false)`

분모가 0인 경우(예: 라이어를 한 번도 안 해봄)는 "기록 없음"으로 표기한다. 조회 빈도가 높아지면 `User`에 캐시 카운터를 두는 최적화를 나중에 검토하되, source of truth는 `GamePlay`로 유지한다.

**레벨**: 별도 컬럼을 두지 않고 `count(plays)`(전체 게임수)에서 파생한다 — 승패와 무관하게 참여 자체로 오르는 구간제 레벨(예: 게임수 구간에 따라 Lv.1/2/3…). 정확한 구간표는 추후 확정.

**친구 조회**: 특정 유저 X의 수락된 친구 목록은 `Friendship where (requesterId = X OR addresseeId = X) AND status = 'accepted'`로 양방향을 모두 본다. 받은 대기 요청은 `addresseeId = X AND status = 'pending'`.

**정리(cleanup)와의 정합성**: 익명 계정 삭제 시 `User` 행을 지우면 `onDelete: Cascade`로 해당 유저의 `GamePlay`·`Friendship`이 함께 삭제된다(별도 정리 코드 불필요). Firebase Auth 삭제는 기존 `firebase-admin` 스케줄 작업이 담당.

## Socket.IO 이벤트 계약 (MVP)

단일 기본 네임스페이스 + Socket.IO **room**(`socket.join(roomCode)`)으로 충분.

**Client → Server**:
- `room:create` `{ nickname, visibility: 'public'|'private', maxPlayers: number }` — 서버가 4자리 숫자 코드 발급(충돌 시 재생성). `maxPlayers`는 방장이 지정, 시스템상 상한 없음
- `room:listPublic` `{}` — 로비 진입 시 공개방 목록 요청
- `room:join` `{ roomCode, nickname }` — 방이 꽉 찼거나(`players.length >= maxPlayers`) 이미 게임 진행 중이면 `room:error`
- `room:leave` `{}` — 대기 상태(설정 전/게임 종료 후 대기 복귀 상태)에서만 유효. 게임 진행 중(`설명~역전승 시도`)에는 UI에 "방 나가기" 버튼 자체를 노출하지 않아 이 시나리오가 발생하지 않게 한다
- `chat:send` `{ text }` — 언제든 자유 채팅
- `player:ready` `{ isReady: boolean }` — 대기방에서 준비 상태 토글. 봇은 참여 즉시 서버가 `isReady: true`로 고정
- `game:configure` `{ category: string | null, aiBotCount: number }` — 호스트 전용, **전원(사람+봇)이 `isReady: true`이고 참가자 수(사람+봇)가 3명 이상일 때만** 허용, 아니면 `room:error`. `category`는 세 경로로 채워질 수 있다: (1) 프리셋 **칩 목록**(하드코딩된 기본 카테고리 + 이 방에서 그동안 추가된 `customCategories`)에서 선택한 값, (2) **자유 입력** 문자열 — 프리셋에 없는 새 이름이면 서버가 해당 방의 `customCategories`에 추가해 이후 같은 방에서 칩으로 재사용 가능(방 종료 시 함께 소멸, DB 저장 안 함), (3) `null` — 이 경우 AI가 카테고리까지 생성. 전송 즉시 새 게임 시작 + 방 채팅 초기화
- `turn:submitDescription` `{ text }` — 현재 턴인 사람만 유효
- `vote:cast` `{ votedPlayerId }` — 익명, 서버만 집계
- `liar:guessWord` `{ guess }` — 지목된 사람이 실제 라이어일 때만 유효

**Server → Client**:
- `room:created`/`room:joined` `{ roomCode, hostId, visibility, players }` — 방 생성/입장 직후 해당 소켓에만 전송되는 방 스냅샷 (`players`는 `Player[]`)
- `room:publicList` `{ rooms: [{roomCode, playerCount, maxPlayers}] }`
- `room:playerListUpdated` `{ players }` (`Player[]`) — 입장/퇴장 및 `player:ready` 토글 시 방 전체에 브로드캐스트 (`Player.isReady` 포함)
- `room:error` `{ message: string }` — 잘못된 코드, 이미 진행 중인 방 입장 시도, 호스트 아님 등 실패 케이스에서 요청한 소켓에만 전송
- `chat:message` `{ id, senderId: string|'ai'|'system', type: 'chat'|'turnDescription'|'aiComment'|'system', text, timestamp }` — **통합 채팅 피드**. 자유 채팅, 턴 설명, AI 교란 코멘트, 시스템 안내(새 게임 시작/투표 결과/제시어 공개 등) 모두 이 이벤트로 전달되어 클라이언트는 하나의 리스트에 append만 하면 됨
- `game:started` `{ gameNumber, category, participants }` — 클라이언트도 채팅 뷰 초기화. `category`는 결과 화면 등에서 표시하기 위한 필드, `participants: { id, nickname, isBot }[]`는 봇 포함 전체 참가자 목록(하위호환 추가) — `room:playerListUpdated`는 사람만 추적하므로 투표 후보·턴 배너에 봇을 표시하려면 이 필드가 필요
- `round:yourWord` (해당 소켓에만 개별 전송) `{ word }` — 진짜/가짜 여부·라이어 여부는 어떤 payload에도 포함하지 않음(본인도 모름)
- `turn:started` `{ playerId, timeLimitSec }`
- `discussion:started` `{ timeLimitSec }` — 설명 페이즈가 끝나고 토론 페이즈로 전환됐음을 명시(하위호환 추가). 이전엔 system 채팅 텍스트로만 암시돼 클라이언트가 "현재 턴" 배너를 내릴 시점을 알 수 없었음
- `vote:started` `{ timeLimitSec }`, `vote:progress` `{ votesInCount, totalCount }` — 식별정보 없이 진행률만
- `round:resolved` (chat:message type:'system'으로도 브로드캐스트) `{ votedOutId, wasLiar, realWord, liarWord }` — `wasLiar`가 `false`(오지목)면 역전승 단계 없이 바로 `round:finalResult { winner: 'liar' }`로 진행
- `liar:guessPrompt` `{ timeLimitSec }` — `wasLiar`가 `true`일 때만 발생, 지목된 사람의 소켓에만
- `round:finalResult` `{ liarGuessCorrect: boolean | null, winner: 'liar'|'citizens' }` — 오지목으로 역전승 단계 자체가 없었으면 `liarGuessCorrect: null`. 정답 판정은 서버가 LLM(`judgeLiarGuess`)에게 위임해 유사 표현·오타·한글/영어 표기 차이를 허용
- `game:ended` `{}` — 방은 대기 상태로 복귀, 채팅은 유지, 호스트는 다음 게임 설정 가능
- `room:closed`

서버가 방/게임/라운드 페이즈 전이(`대기 → 설정 → 설명 → 토론 → 투표 → 결과 → (역전승 시도) → 게임종료(대기로 복귀)`)를 전적으로 소유하고 타이머를 관리. 투표는 **개인별 선택을 어떤 클라이언트에게도 절대 전송하지 않고 서버 내부 집계로만** 사용 — `round:resolved`에도 누가 누구에게 투표했는지는 포함하지 않는다.

**타이머 만료 동작**: 설명/투표 시간이 만료되면 해당 행동은 **그냥 못 하는 것**으로 처리한다 — 설명 미제출 턴은 빈 채로 넘어가고, 미투표는 집계에서 빠진 채 다음 페이즈로 진행한다. 봇 자동 대체나 기본값 강제 같은 별도 보정 로직은 두지 않는다.

## REST API (전적·친구)

전적 조회·친구 관리는 실시간성이 필요 없는 CRUD라 Socket.IO 이벤트 계약이 아니라 **Express REST**로 구현했다(`backend/src/http/`). `GET /api/users/nickname-availability/:nickname` 하나만 예외이고, 나머지 모든 엔드포인트는 `Authorization: Bearer <Firebase ID Token>` 헤더 필수(`requireAuth` 미들웨어) — 서비스 계정 키가 없는 로컬 dev 환경에서는 소켓과 동일하게 토큰 검증을 생략하는 fallback이 적용된다.

**전적·계정** (`/api/users`, `backend/src/http/statsRoutes.ts`):
- `GET /api/users/nickname-availability/:nickname` — **인증 불필요**(회원가입 단계엔 아직 Firebase 세션 자체가 없음). 응답 `{ available: boolean }`. `User.nickname`은 DB `@unique` 제약이 걸려 있어, 프론트는 회원가입 폼에서 이 엔드포인트로 중복 확인을 통과해야만 가입 제출을 허용해야 한다
- `GET /api/users/me` — 내 전적. 응답 `{ totalGames, overallWinRate, liarWinRate, citizenWinRate }` (승률은 0~1 float, 분모 0이면 `null`)
- `GET /api/users/:uid` — 다른 유저의 전적 (동일 응답 형태)
- `DELETE /api/users/me` → 204 — **회원탈퇴**. 프론트는 이 엔드포인트 하나만 호출하면 된다(Firebase와 직접 통신 불필요). 백엔드가 `firebase-admin`으로 Firebase Auth 계정을 삭제(서버 권한이라 "최근 로그인 필요" 재인증 제약 없이 처리)하고, 로컬 DB `User` 행도 삭제한다(`onDelete: Cascade`로 `GamePlay`·`Friendship` 함께 삭제) — 게스트 정리 cron과 동일한 삭제 패턴

**친구** (`/api/friends`, `backend/src/http/friendsRoutes.ts`):
- `POST /api/friends/requests` `{ addresseeUid }` → 201 `Friendship` — 이미 상대가 나에게 보낸 대기 요청이 있으면 자동으로 맞수락 처리됨. 자기 자신·이미 친구·차단 상태면 409
- `GET /api/friends/requests` — 내가 받은 대기 요청 목록. 응답 `{ requests: [{ ...Friendship, requester: { uid, nickname, avatarIndex } }] }`
- `POST /api/friends/requests/:id/accept` → 200 `Friendship`(status: accepted)
- `POST /api/friends/requests/:id/decline` → 204 (행 삭제, 재요청 가능)
- `GET /api/friends` — 수락된 친구 목록. 응답 `{ friends: [{ uid, nickname, avatarIndex }] }`
- `DELETE /api/friends/:uid` → 204 (친구 해제)

## LLM 래퍼 (`backend/src/llm/wrapper.ts`)

```ts
interface LiarGameLLM {
  generateWordPair(category: string | null, usedWords: string[]): Promise<{ category: string; realWord: string; liarWord: string }>;
  generateBotTurn(ctx: BotTurnContext): Promise<string>;
  generateTurnComment(ctx: TurnCommentContext): Promise<string>;
  explainWordIfUnfamiliar(word: string): Promise<string | null>;   // 낯선 단어로 판단되면 설명 텍스트, 아니면 null
  judgeLiarGuess(guess: string, realWord: string): Promise<boolean>; // 역전승 정답 유사판정
}
```
- 다섯 함수 모두 Haiku 4.5로 시작. `category`가 null이면 카테고리 자체도 LLM이 생성.
- `generateWordPair` 프롬프트 핵심: 같은 카테고리 안에서 연관성은 있지만 다른 두 단어를 생성 (예: 카테고리 "동물" → realWord "사자", liarWord "호랑이") — 너무 멀면 라이어가 바로 티나고, 너무 가까우면 설명이 똑같아짐.
- `generateBotTurn` 프롬프트 핵심: "너무 완벽하지 않게, 자연스럽게" — 봇도 자신에게 배정된 단어(진짜든 가짜든)만 알고 자신이 라이어인지는 모른다는 전제로 설명 생성 (사람 라이어와 동일 조건).
- `generateTurnComment` 프롬프트 핵심: 방금 제출된 설명을 보고 **의도적으로 헷갈리게 만드는** 코멘트를 생성. 실제 라이어가 누구인지는 절대 이 프롬프트에 입력하지 않음 — 정답을 아는 채로 교란하면 너무 정교해져 게임이 망가지므로, 봇과 같은 원칙("정답을 모르는 관전자"처럼 행동)을 따라야 자연스러운 노이즈가 된다. 플레이어를 지칭할 때는 항상 닉네임을 사용한다.
- `explainWordIfUnfamiliar` 프롬프트 핵심: 해당 단어가 일반적으로 낯설/어려운 단어인지 판단하고, 그렇다면 짧은 텍스트 설명을 생성(이미지 생성은 하지 않음). `round:yourWord`에 실린 단어를 대상으로 `game:configure` 직후 호출.
- `judgeLiarGuess` 프롬프트 핵심: 라이어의 역전승 답안과 진짜 제시어를 비교해 의미상 동일한지 판정. 오타·맞춤법 오류·한글/영어 표기 차이(예: "burger"/"버거")는 정답으로 인정.

## 백엔드 구현 현황 (backend 브랜치)

이 문서의 MVP Socket.IO 계약과 "DB 스키마"(원래 선택 항목이었던 유저 전적·친구)까지 `backend` 브랜치에 구현 완료됨. 실제 Firebase 서비스 계정 키·Anthropic API 키로 동작 검증 완료(방 생성→게임 진행→투표→결과→종료까지 end-to-end, DB 기록 포함).

- **구현 완료**: `roomManager`(방 생성/입장/퇴장·4자리 코드·공개방 목록), `gameEngine`(전체 페이즈 머신, 봇 자동 턴/투표/역전승 시도, 타이머 만료 규칙), `socket/handlers`(이벤트 계약 전체), Firebase Auth(소켓 handshake + REST 양쪽 실제 `verifyIdToken`, 키 없으면 dev fallback), LLM 래퍼(Claude Haiku 4.5 실 연동, 키 없으면 mock 폴백), DB(`User`/`GamePlay`/`Friendship` + `/api/users`, `/api/friends` REST — Socket.IO 계약에는 없는 프로필 조회용 확장), 게스트 정리 cron(매일 04:00)
- **이번 결정으로 backend에 추가 반영 필요**(기존 구현 완료 당시엔 없던 요구사항): `maxPlayers`/`customCategories`(방 생성·`game:configure` 최소인원 검사), `player:ready`(준비 상태 토글 및 게임 시작 게이팅), `explainWordIfUnfamiliar`·`judgeLiarGuess`(LLM 래퍼 신규 함수), 오지목 시 즉시 `round:finalResult` 분기, `User.level` 파생 응답 필드
- **미구현으로 남은 것**: 아래 "MVP 제외(stretch)" 항목(라운드 재시작, `room:rejoin` 재접속, 방별 네임스페이스) — "라이어 수 선택"과 "준비(isReady) 기능 유지 여부"는 이번에 결정 완료되어 TODO에서 제외됨(각각 "고정 1명", "유지"로 확정)
- **프론트 연동은 별개**: 아래 "프론트-백엔드 연결 정합성" 섹션의 갭은 아직 해소되지 않음 — 프론트는 여전히 mock 데이터 기반 골격이라, 백엔드가 완성됐다고 해서 앱이 바로 붙는 것은 아님

## 프론트-백엔드 연결 정합성

현재 `frontend` 브랜치는 **mock 데이터 기반 순수 UI 골격**이라, 그대로는 이 문서의 백엔드 계약과 연결되지 않는다. 아래 항목은 **백엔드 계약(이 문서)을 source of truth로 삼고 프론트가 맞춰야 할 갭**이다. 백엔드 구현과 병행해 프론트에서 정리한다.

- **네트워킹/상태 의존성 추가**: `frontend/pubspec.yaml`에 `socket_io_client`, `firebase_core`/`firebase_auth`, `flutter_riverpod`를 추가하고, 지금 없는 `services/socket_service.dart`·`services/auth_service.dart`·`state/room_provider.dart`(Riverpod)를 신설한다. 현재의 `services/user_session.dart`(static 전역)와 빈 `lib/api/`는 이걸로 대체·정리.
- **단일 `RoomScreen` + 페이즈 패널로 재구성**: 현재 `GameScreen`/`VoteScreen`/`LiarGuessScreen`/`ResultScreen`이 `Navigator.push`로 분리돼 게임 채팅이 방 채팅과 단절돼 있다. 이 문서의 "하나의 채팅 피드" 설계대로, 화면을 쪼개지 말고 `RoomScreen` 하나에서 페이즈별 **하단 컨텍스트 패널만 교체**하고 채팅 리스트는 하나로 유지한다.
- **`ChatMessage` 모델 정렬**: 프론트 모델을 이 문서의 계약(`{ id, senderId: string|'ai'|'system', type: 'chat'|'turnDescription'|'aiComment'|'system', text, timestamp }`)에 맞춘다. 현재 프론트는 표시이름 기반 `sender`, `timestamp` 없음, `turnDescription` 타입 없음 → `senderId`·`timestamp` 추가, 턴 설명은 `turnDescription` 타입으로 구분.
- **투표/판정을 서버 소유로 전환**: 현재 `VoteScreen`은 nickname 문자열로 투표하고 mock 라이어와 비교해 **클라이언트에서 판정**한다. 계약대로 `vote:cast { votedPlayerId }`(id 기반)로 보내고 판정은 서버(`round:resolved`/`round:finalResult`)만 수행하도록 클라 판정 로직을 제거한다. id↔nickname 매핑은 `room:playerListUpdated`로 받은 플레이어 목록에서 해결.
- **개별 전송 이벤트 수신부 추가**: `round:yourWord`(본인 단어, 개별 전송)와 `liar:guessPrompt`(지목된 소켓에만)를 받을 UI가 프론트에 없다. 본인 단어 표시 영역과, 역전승 입력은 **지목된 당사자에게만** 뜨도록 수신부를 추가한다(전원에게 push하던 현재 방식 제거).
- **`RoomSummary` 필드 정리**: `room:create`에 방 제목 필드는 없으므로 프론트의 `title`은 제거한다(또는 표시하지 않는다). `maxPlayers`는 (기존 결정과 달리) 이번에 다시 계약에 포함되었으므로 유지하되, `room:publicList`도 `{ roomCode, playerCount, maxPlayers }`로 응답 형태를 맞춰야 한다.

## MVP 제외 (stretch)

- 게임 내 라운드 재시작(여러 라운드 반복)
- ~~로컬 DB 연결 및 유저 전적(전체 게임수·전체/라이어/시민 승률) 저장~~ — **백엔드 구현 완료** (스키마는 "DB 스키마" 섹션 참조)
- ~~유저 간 친구 기능(요청/수락, 친구 목록)~~ — **백엔드 구현 완료** (`Friendship` 모델 기반)
- 방별 Socket.IO 네임스페이스
- 다중 LLM 프로바이더 동시 지원 (인터페이스만 교체 가능하게 열어둠)

## TODO / 향후 과제

위 "MVP 제외(stretch)"가 **기능 백로그**라면, 여기는 아직 방향을 못 박지 못한 **미결 결정·후속 작업**을 모아둔다.

- **재접속(`room:rejoin`) 지원**: 모바일 환경에서 네트워크 끊김이 흔하므로 최소한의 재접속 처리가 필요할지 나중에 검토한다. 지금 MVP에는 넣지 않는다.
- **레벨 구간표**: 게임수 기반 레벨을 도입하기로 확정했으나(데이터 모델 섹션 참조), 구체적인 구간(몇 판당 레벨업)은 아직 미정.
- **커스텀 카테고리 악용 방지**: 방장이 자유 입력으로 추가하는 카테고리에 별도 검증이 없다. 부적절한 입력에 대한 최소 필터링이 필요한지 검토.

## 검증 계획

1. 백엔드 단독 실행 후 소켓 연결 로그 확인, `room:create`(public/private 각각, 4자리 코드 발급 확인)·`room:listPublic`·`room:join` 왕복 확인
2. Flutter 로그인 → Firebase ID 토큰 handshake 검증 성공/실패(잘못된 토큰) 케이스 확인
3. `flutter run -d chrome`에서 공개방 생성 → 목록에 뜨는지 확인
4. 별도 시뮬레이터에서 해당 공개방을 목록에서 선택 입장 + 비공개방은 4자리 코드로 입장, 두 경로 모두 확인
5. 호스트가 카테고리 직접 입력 / "AI 랜덤 생성" 두 경로, 그리고 AI 봇 추가 인원수 지정까지 게임 시작으로 이어지는지 확인
6. 한 게임을 끝까지 플레이 — 매 턴 설명 제출 직후 채팅 피드에 교란 코멘트가 다른 색/타입으로 표시되고, 매번 다른 코멘트인지 확인
7. 라이어 역할을 받은 클라이언트(사람/봇 각각 최소 1회)가 자신이 라이어라는 표시를 전혀 받지 않고 배정된 단어만 보이는지 확인
8. 투표로 실제 라이어가 지목된 라운드에서 `liar:guessPrompt`가 오고, 정답 맞히면 `winner: 'liar'`로 뒤집히는지 확인
9. 투표 진행 중/후 어떤 클라이언트도 개별 투표 선택(누가 누구를 찍었는지)을 수신하지 않는지 네트워크 로그로 확인
10. 게임 종료 후 채팅이 그대로 남아 계속 대화 가능한지, 호스트가 새 게임을 시작하면 그 시점에만 채팅이 초기화되는지 확인
11. `generateTurnComment` 호출 인자에 실제 라이어 정체가 섞여 들어가지 않는지 로그로 확인
12. 호스트 연결 종료 시 방 정리 및 공개방 목록에서도 제거되는지 확인
13. 참가자(사람+봇 합산)가 3명 미만이거나 전원 준비 완료 전에는 `game:configure`가 `room:error`로 거부되는지 확인
14. 투표로 실제 라이어가 아닌 사람이 지목됐을 때, 역전승 단계 없이 바로 `winner: 'liar'`로 게임이 종료되는지 확인
15. 방장이 프리셋에 없는 카테고리 이름을 자유 입력했을 때 해당 방에서 다음 게임부터 칩으로 재사용되는지, 방 종료 후에는 사라지는지 확인
16. `backend`→`frontend` 병합 후 클린 체크아웃에서 두 디렉터리가 충돌 없이 공존하며 각자 정상 실행되는지 확인

## 배포 및 DB 운영

### 배포 플랫폼
**Railway** — 서버리스 대비 상태 보유(in-memory 방 정보)가 필요하므로 컨테이너 호스팅 선택.

### 서비스 구성
백엔드(Node/Express)와 프론트엔드(Flutter Web 빌드 결과물)를 **Railway 서비스 1개로 통합 배포**한다. 처음엔 2개로 분리하는 대안도 검토했으나(프론트는 CDN/정적 호스팅, 백엔드는 별도), 백엔드가 게임 상태와 로비 방 정보를 메모리에 들고 있어 서비스 분리 시 상태 동기화가 복잡해지므로, 1서비스 통합으로 결정.

### 빌드 방식
Dockerfile 멀티스테이지 빌드:
1. **1단계(Builder)**: Flutter SDK 이미지에서 `flutter build web`을 실행해 정적 파일(`build/web/`) 생성
2. **2단계(Runtime)**: Node 이미지에서 1단계 결과물을 복사한 후 Express 서버 실행

Express에는 `express.static()` 미들웨어와 SPA catch-all 라우트를 추가해, 백엔드가 프론트 정적 파일을 함께 서빙한다. 이를 통해 프론트엔드 라우팅과 API 요청이 단일 origin에서 처리되므로 CORS 설정이 단순해짐.

**빌드 타이밍**: 매 배포마다 최신 프론트 코드를 자동으로 반영하는 방식(Dockerfile에서 빌드)을 택했다. 로컬에서 미리 빌드한 정적 파일(`build/web/`)을 Git 커밋해두는 대안도 검토했으나, 배포 자동화(push to dev → Railway 자동 배포) 편의를 우선해 현재 방식으로 결정.

### 추적 브랜치(Deployment Tracking)
이 통합 배포이므로 `backend`와 `frontend` 코드가 한 브랜치에 함께 있어야 한다. 개발 중에는:
- **`dev` 브랜치 추적**: PR로 백엔드/프론트 변경이 자주 `dev`에 반영되므로, Railway가 `dev`를 자동 추적하도록 설정. 최신 코드가 지속적으로 배포되는 개발 환경(staging 역할).
- **`main` 브랜치로 전환**: 제출/데모 직전에 최종 검토 후, Railway의 추적 브랜치를 `dev`에서 `main`으로 변경. 이후 제출/그레이딩 중에는 안정적인 `main` 버전이 배포됨.

### DB: PostgreSQL

#### 로컬 개발
로컬 머신에 직접 설치한 Postgres(`localhost:5432` 등)를 사용.

#### 배포 환경
**Railway의 매니지드 Postgres 플러그인** 사용. Railway Postgres는:
- DB 서버(컴퓨트)와 데이터가 저장되는 Volume(영구 디스크)이 분리
- 백엔드 서비스 재배포 시에도 Volume이 유지되므로 데이터 손실 없음
- 연결 문자열을 Railway가 자동으로 `DATABASE_URL` 환경변수로 주입

### DB 연결 관리
연결 문자열을 `DATABASE_URL` 환경변수로 완전히 분리:
- **로컬**: `.env` 파일에 `DATABASE_URL=postgresql://user:password@localhost:5432/liar_game` 설정
- **배포**: Railway가 Postgres 플러그인 생성 시 자동으로 `DATABASE_URL` 주입
- 코드 전환: 환경변수만으로 처리되므로 소스 코드 변경 없음

### ORM / DB 마이그레이션
**Prisma** 사용:
- `schema.prisma`로 테이블 및 관계 정의, 타입 안전한 쿼리 클라이언트 자동 생성
- **로컬 스키마 적용**: `prisma migrate dev` — 스키마 변경 시 마이그레이션 파일 자동 생성, 로컬 DB에 즉시 적용
- **배포 시 마이그레이션**: Railway에서 배포 직전 또는 startup hook에서 `prisma migrate deploy` 실행 — `migrations/` 폴더의 모든 마이그레이션을 Railway Postgres에 순차 적용, 스키마 동기화 완료

### 핵심 파일
- backend/src/socket/handlers.ts
- backend/src/game/gameEngine.ts
- backend/src/game/roomManager.ts
- backend/src/llm/wrapper.ts
- frontend/lib/services/socket_service.dart
- frontend/lib/state/room_provider.dart
