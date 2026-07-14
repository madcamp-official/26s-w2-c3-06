# L-AI-R GAME (AI 라이어게임) — 구현 계획

## 목차

- [게임 규칙](#게임-규칙)
- [확정된 제품/기술 결정](#확정된-제품기술-결정)
- [인증/유저 관리 흐름](#인증유저-관리-흐름)
- [데이터 관리 (인메모리와 DB)](#데이터-관리-인메모리와-db)
  - [인메모리 데이터 모델 (과도한 정규화 없이)](#인메모리-데이터-모델-과도한-정규화-없이)
  - [DB 스키마 (영구 저장: 유저·전적·친구)](#db-스키마-영구-저장-유저전적친구)
  - [경험치(EXP) 및 레벨 정책](#경험치exp-및-레벨-정책)
- [API 계약 (Socket.IO와 REST)](#api-계약-socketio와-rest)
  - [Socket.IO 이벤트 계약 (MVP)](#socketio-이벤트-계약-mvp)
  - [REST API (전적·친구)](#rest-api-전적친구)
- [LLM 래퍼 (`backend/src/llm/wrapper.ts`)](#llm-래퍼-backendsrcllmwrapperts)
- [백엔드 구현 현황 (backend 브랜치)](#백엔드-구현-현황-backend-브랜치)
- [프론트-백엔드 연결 정합성](#프론트-백엔드-연결-정합성)
- [MVP 제외 (stretch)](#mvp-제외-stretch)
- [TODO / 향후 과제](#todo--향후-과제)
- [검증 계획](#검증-계획)
- [배포 및 DB 운영](#배포-및-db-운영)

## 게임 규칙

**용어 계층**: 로비(Lobby) > 방(Room) > 게임(Game) > 라운드(Round). 라운드는 모든 참가자가 받은 제시어를 한 턴씩 설명하는 것으로, MVP에서는 게임당 1라운드만 돈다(라운드 재시작은 스트레치).

참가자(사람+봇) 중 라이어(고정 1명)는 **자신이 라이어인지 모른 채** 진짜 제시어와 비슷하지만 다른 가짜 제시어를 받는다. 각자 제시어를 직접 말하지 않고 설명한 뒤 익명 투표로 라이어를 지목한다. 지목된 사람이 실제 라이어면 진짜 제시어를 맞혀 역전승할 기회를 주고, 실제 라이어가 아니면 역전승 기회 없이 그 즉시 라이어 팀 승리로 게임이 끝난다. 세부 규칙(최소 참가 인원, 준비 상태 게이팅, 카테고리 지정 방식 등)은 "Socket.IO 이벤트 계약"의 `game:configure` 참고.

AI는 다섯 지점에 개입해 "LLM Wrapper" 요소를 드러낸다:
1. 방장이 지정(또는 AI 랜덤)한 카테고리로 진짜/가짜 제시어 쌍을 생성
2. 방장이 선택한 수만큼 AI 봇이 플레이어로 참여해 설명 생성 (봇도 자신이 라이어인지 모름 — 사람과 동일 조건)
3. **매 턴** 설명이 제출될 때마다 AI가 일부러 헷갈리게 하는 "교란" 코멘트를 닉네임으로 지칭해 단다
4. 모든 제시어에 대해 AI가 짧은 텍스트 설명을 미리 만들어 함께 내려준다 (난이도 무관, 이미지 생성은 하지 않음) — 유저는 "AI 설명보기" 버튼으로 원할 때 펼쳐 본다
5. 역전승 시도 시 AI가 정답 여부를 유사도 기반으로 판정한다 (오타·맞춤법 오류·한글/영어 표기 차이 허용)

**방 UI는 그룹 채팅 형식**으로, 턴 설명·AI 교란 코멘트·시스템 안내·자유 채팅이 하나의 피드에 흐른다. 채팅은 새 게임 시작 시에만 초기화된다(데이터 모델 `chatLog` 참고).

## 확정된 제품/기술 결정

- **프론트엔드**: Flutter — iOS/Android/Web 단일 코드베이스. `socket_io_client` 패키지로 Socket.IO 서버와 통신.
- **실시간**: Socket.IO 기반 온라인 방. 공개방은 로비의 방 목록에서 선택 입장, 비공개방은 4자리 코드 입력으로 입장.
- **백엔드: Node.js + Express + Socket.IO (추천)** — Socket.IO 1st-party 구현이 Node라 가장 안정적. 대안으로 FastAPI + `python-socketio`도 유효하나 기본 추천은 Node.
- **인증/DB: Firebase Authentication + 백엔드 로컬 DB (추천)**
  - FlutterFire가 Flutter SDK를 1급 지원해 로그인 구현 비용이 크게 줄어듦.
  - 백엔드는 소켓 handshake 시 `firebase-admin`으로 ID 토큰만 검증.
  - Firebase Authentication은 인증만 담당하고, 닉네임/프로필/승패 기록 등 유저 데이터는 백엔드가 관리하는 로컬 DB(Postgres 등)에 저장. 익명 계정 link로 UID가 유지되므로, 게스트에서 가입 후 추가 마이그레이션 없이 데이터가 자동으로 이어짐. 방/게임/라운드 같은 휘발성 상태는 Node 서버 **인메모리**에 둔다.
- **LLM: Anthropic Claude API / OpenAI API 중 택1 (환경변수로 전환)**
  - 다섯 함수(제시어 쌍 생성, 봇 턴 생성, 매 턴 교란 코멘트, 낯선 단어 설명, 역전승 정답 유사판정) 모두 빈도가 높거나 지연에 민감 → Anthropic은 **Claude Haiku 4.5**, OpenAI는 **gpt-4o-mini**로 시작.
  - LLM 호출부는 provider(회사)와 모델을 나중에 쉽게 바꿀 수 있도록 얇은 인터페이스로만 감싸고, 과한 멀티프로바이더 프레임워크는 만들지 않음 — 실제로 `backend/src/llm/anthropicClient.ts`/`openaiClient.ts` 두 얇은 클라이언트를 두고, `wrapper.ts`가 `LLM_PROVIDER` 환경변수(미지정 시 사용 가능한 키 기준 자동 선택, 둘 다 있으면 OpenAI 우선)로 어느 쪽을 쓸지만 결정한다. 프롬프트·파싱·거절감지 로직은 provider와 무관하게 완전히 공유.

## 인증/유저 관리 흐름

### 화면 구조 (5개)
1. **메인 페이지** — 로그인/회원가입 버튼 + 게스트로 계속하기 버튼
2. **로그인/회원가입 페이지** — 통합 인증 폼
3. **로비** — 공개방/비공개방 진입, 내 승률·레벨·프로필 사진 표시, 로그아웃 버튼, 개인정보 수정 페이지 진입점
4. **개인정보 수정 페이지** — 닉네임 변경, 프로필 사진(아바타) 변경, 로그아웃/계정 탈퇴 버튼
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
- **게스트가 개인정보 수정 페이지에서 "로그인/회원가입" 진입**: 이 경로는 로그아웃을 먼저 하지 않는다 — 로그인/회원가입 화면을 현재 게스트 세션 위에 그대로 push해, 뒤로가기를 누르면 로그아웃 없이 원래 쓰던 게스트 계정을 계속 이용할 수 있다. 실제로 로그인/가입을 완료해야만(익명 승격 또는 계정 전환) 세션이 바뀌며, 이때는 위 "인증 성공" 규칙대로 로비까지 이동한다.

### 로비에서 로그아웃
완전히 sign out 후, 메인 페이지의 "게스트로 계속하기"를 눌렀을 때와 동일한 닉네임 입력 화면으로 이동 → 새 익명 세션 시작.

### 유저 프로필/전적 저장 위치
Firebase Authentication은 **인증 전용**으로만 쓰고, 닉네임/프로필 사진/전적 등 유저 데이터는 **자체 백엔드가 관리하는 로컬 DB**에 Firebase `uid`를 키로 저장한다 (Firestore 사용 안 함). Link 시 UID가 안 바뀌므로 게스트 때 쌓인 프로필/닉네임이 회원가입 후에도 별도 마이그레이션 코드 없이 자동으로 이어짐.

### 게스트 데이터 취급
스키마상 정회원과 동일하게 취급(uid로 동일하게 키잉). 다만 로우에 `isAnonymous`(또는 `is_anonymous`) 플래그를 같이 저장해서, 추후 리더보드 등에서 게스트 전적을 구분/필터링할 수 있게 해둔다.

### 게스트 정리(cleanup)
별도 Cloud Functions 없이, 백엔드에 이미 있는 `firebase-admin`을 활용해 백엔드 프로세스 내에서 `node-cron`으로 스케줄 작업을 돌린다. 6시간마다, 마지막 활동(`lastActive`)이 30일 이상 지난 익명 계정을 찾아 `admin.auth().deleteUser(uid)`(Firebase Auth 삭제)와 로컬 DB 로우 삭제를 함께 수행.

## 데이터 관리 (인메모리와 DB)

방/게임/라운드 같은 휘발성 상태와 유저·전적·친구 같은 영구 데이터는 저장 위치는 다르지만, 둘 다 "이 서버가 다루는 데이터가 어떤 모양인가"를 정의한다는 점에서 같은 성격의 문서라 하나의 상위 섹션으로 묶는다.

### 인메모리 데이터 모델 (과도한 정규화 없이)

```ts
interface Player {
  id: string;
  nickname: string;
  isBot: boolean;
  connected: boolean;      // disconnect 시 즉시 false, 유예 시간 내 room:rejoin하면 true로 복귀
  isReady: boolean;        // 대기방 준비 상태. 봇과 방장은 참여 즉시 true로 고정(방장은 준비 토글 UI 자체가 없음)
}
// 방장 여부는 Player에 두지 않고 RoomState.hostId == player.id로 판별한다(단일 source of truth).

// 설명 한 바퀴. 설명 순서는 게임 단위로 고정이고 투표는 게임당 한 번뿐이므로,
// 순서·투표·판정 결과는 Round가 아니라 GameState에 둔다. Round는 그 바퀴의 설명(turns)만 담는다.
interface Round {
  roundNumber: number;
  turns: { playerId: string; text: string }[];
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
  playerOrder: string[];         // 설명 순서. 게임 단위로 한 번 정해 모든 라운드에서 고정 사용
  usedWordsThisGame: string[];
  rounds: Round[];               // 설명 라운드들. MVP: 길이 1. 추후 스트레치: 다중 설명 라운드 지원 시 증가

  // 투표·판정은 게임당 한 번(모든 설명 라운드 종료 후). 라운드가 아니라 게임에 귀속된다.
  votes: Record<string, string>; // 서버 전용, 클라이언트로 절대 전송 안 함
  votedOutId?: string;
  wasLiar?: boolean;
  liarGuess?: string;
  liarGuessCorrect?: boolean;
  winner?: 'liar' | 'citizens';
}

interface ChatMessage {
  id: string;
  senderId: string | 'ai' | 'system';
  type: 'chat' | 'turnDescription' | 'aiComment' | 'system';
  text: string;
  timestamp: number;
}

interface DraftGameConfig {
  category: string | null;   // null이면 AI 랜덤 생성
  aiBotCount: number;
}

interface RoomState {
  roomCode: string;          // 4자리 숫자 문자열, 예: "4821"
  hostId: string;
  title: string;             // 방 제목. 방 생성 시 지정(미지정 시 "{방장}의 방")
  emoji: string;             // 로비 목록 표시용 방 이모지. 방 생성 시 지정(미지정 시 기본 이모지)
  visibility: 'public' | 'private';
  maxPlayers: number;        // 방장이 방 생성 시 지정. 시스템상 상한 없음(사람+봇 합산 기준)
  players: Player[];
  customCategories: string[]; // 이 방에서 실제 사용된 카테고리(방장 직접 입력 + AI 랜덤 생성분 모두, 중복 제거). 다음 게임 선택지로 재사용. 방 종료 시 함께 소멸(영구 저장 안 함)
  draftConfig: DraftGameConfig; // 방장이 게임 시작 전 고르고 있는 봇 수/카테고리 (실시간 공유용, game:draftConfig와 같은 모양)
  chatLog: ChatMessage[];    // 방 존재 동안 유지, 새 게임 시작 시에만 초기화
  currentGame: GameState | null;
  gameHistory: GameState[];  // 지난 게임들 (참고용)
  createdAt: number;
}
```

### DB 스키마 (영구 저장: 유저·전적·친구)

방/게임/라운드 같은 휘발성 상태는 인메모리에 두지만, **유저 프로필·전적·친구 관계는 로컬 Postgres에 Prisma로 영구 저장**한다(원래 선택 범위(stretch) 항목이었으나 현재 구현 완료 — "백엔드 구현 현황" 참고). Firebase Auth는 인증만 담당하고, `uid`를 PK로 삼아 이 DB가 유저 데이터를 소유한다. 아래는 `backend/prisma/schema.prisma`의 영구 저장 모델 설계다.

```prisma
model User {
  uid         String   @id                  // Firebase Auth uid를 그대로 PK로 사용 (link 시 불변 → 게스트→가입 자동 이어짐)
  nickname    String   @unique               // 전역 유일. 회원가입 폼에서 중복 확인 필수(GET /api/users/nickname-availability/:nickname)
  avatarUrl   String?                        // Firebase Storage 업로드 사진(avatars/{uid}). null이면 기본 아이콘 사용
  isAnonymous Boolean  @default(true)        // 게스트 구분 (리더보드 필터링 · 30일 정리 대상 판별)
  lastActive  DateTime @default(now())       // 게스트 cleanup(마지막 활동 30일 경과) 기준
  exp         Int      @default(0)           // 누적 경험치(EXP) (정수, 단조증가만 가능 — 절대 감소하지 않음. 게임 종료 시 경험치 지급 규칙에 따라 증가). 레벨은 이 exp에서 계산하는 파생값(저장 안 함)

  plays                  GamePlay[]          // 참여한 게임들 (전적의 source of truth)
  sentFriendRequests     Friendship[] @relation("requester")
  receivedFriendRequests Friendship[] @relation("addressee")
}

// 사람 참가자 1명이 게임 1판을 마칠 때마다 1행 기록 (봇은 Firebase uid가 없으므로 기록 안 함).
// 전적 4종은 모두 이 테이블 집계로 파생한다 — 별도 카운터를 두지 않아 드리프트가 없다.
model GamePlay {
  id      String  @id @default(cuid())
  userId  String
  user    User    @relation(fields: [userId], references: [uid], onDelete: Cascade)
  wasLiar Boolean                           // 이 게임에서 라이어였는지
  won     Boolean                           // 이 유저가 속한 팀이 최종 승리했는지

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

**경험치(EXP) 및 레벨**: 누적 EXP는 `User` 테이블의 별도 컬럼(`exp` 정수형, 기본값 0, **단조증가만 가능 — 절대 감소하지 않는다**)으로 저장한다. 레벨은 누적 EXP에서 계산하는 파생값이며, DB나 API에 직접 저장되지 않는다(매번 필요할 때 계산). 정책 상세는 아래 [경험치(EXP) 및 레벨 정책](#경험치exp-및-레벨-정책) 참고.

**친구 조회**: 특정 유저 X의 수락된 친구 목록은 `Friendship where (requesterId = X OR addresseeId = X) AND status = 'accepted'`로 양방향을 모두 본다. 받은 대기 요청은 `addresseeId = X AND status = 'pending'`.

**정리(cleanup)와의 정합성**: 익명 계정 삭제 시 `User` 행을 지우면 `onDelete: Cascade`로 해당 유저의 `GamePlay`·`Friendship`이 함께 삭제된다(별도 정리 코드 불필요). Firebase Auth 삭제는 기존 `firebase-admin` 스케줄 작업이 담당.

### 경험치(EXP) 및 레벨 정책

레벨은 누적 경험치(EXP)만으로 결정되는 단일 파생값이다. 점수·랭크 점수·RP 같은 별도 지표는 두지 않고, 이 문서 전체에서 "EXP"/"경험치" 용어로 통일한다.

**핵심 원칙**
- 레벨은 누적 경험치(EXP)로 결정한다.
- **경험치는 절대 감소하지 않는다** — 어떤 경우에도 마이너스 경험치는 없다.
- 패배하거나 게임을 이탈해도 마이너스 경험치는 없다.
- 한 경기에서 획득 가능한 최소 경험치는 0 EXP이다.
- 라이어 승리는 시민 승리보다 어렵기 때문에 더 많은 경험치를 지급한다.

#### 레벨 공식

레벨 `L`에 도달하기 위한 누적 경험치는 다음 공식을 사용한다.

```text
EXP(L) = 100 × (L - 1) + 15 × (L - 1) × (L - 2)
```

(L=1이면 0. 이 닫힌 형태는 "다음 레벨까지 필요한 증분 EXP = 100 + (현재 레벨 − 1) × 30"이라는 점화식과 동치이며, 아래 표를 넘어서도 같은 공식으로 무한히 확장된다. 레벨 이름이나 칭호는 없고 화면에는 "Lv.N" 숫자만 표시한다.)

예시 레벨 구간(1~10):

| 레벨 | 필요 누적 경험치 | 이전 레벨에서 추가로 필요한 경험치 |
| -: | --------: | ------------------: |
|  1 |         0 |                   - |
|  2 |       100 |                 100 |
|  3 |       230 |                 130 |
|  4 |       390 |                 160 |
|  5 |       580 |                 190 |
|  6 |       800 |                 220 |
|  7 |     1,050 |                 250 |
|  8 |     1,330 |                 280 |
|  9 |     1,640 |                 310 |
| 10 |     1,980 |                 340 |

#### 경험치 지급 정책

역할·승패·개인 기여도(투표 대상)를 함께 반영한다. 게임 1판이 정상 종료됐을 때 사람 플레이어에게만 지급하며(AI 봇은 지급 대상 아님), 한 게임당 유저별로 한 번만 기록해 중복 지급을 막는다.

| 역할  | 게임 결과 | 개인 결과                | 획득 경험치 | 설계 의도 |
| --- | ----- | -------------------- | -----: | --- |
| 시민  | 승리    | 라이어에게 투표             | 45 EXP | 승리에 더해 라이어를 실제로 맞힌 정확한 판단을 우대 |
| 시민  | 승리    | 다른 시민에게 투표           | 30 EXP | 팀 승리에는 기여했지만 개인 판단은 틀렸으므로 기본 승리 보상보다 낮게 지급 |
| 시민  | 패배    | 라이어에게 투표             |  16 EXP | 패배해도 올바르게 라이어를 지목한 개인 기여는 소폭 보상 |
| 시민  | 패배    | 다른 시민에게 투표           |  6 EXP | 패배 + 오판이므로 참여 자체에 대한 최소 보상만 지급 |
| 라이어 | 승리    | 투표에서 지목되지 않음         | 60 EXP | 들키지 않고 승리한 기본 라이어 승리 보상 |
| 라이어 | 승리    | 지목된 후 진짜 제시어를 맞혀 역전승 | 75 EXP | 불리한 상황(지목)을 극복하고 제시어까지 맞힌 고난도 성과라 최고 보상 |
| 라이어 | 패배    | 진짜 제시어 추측 실패         |  10 EXP | 패배했지만 시도 자체에 대한 최소 보상을 남겨 참여 동기를 유지 |

라이어 승리(60/75 EXP)가 시민 승리(30/45 EXP)보다 항상 높은 것은 "라이어 승리가 시민 승리보다 어렵다"는 핵심 원칙을 그대로 반영한 결과다.

#### 참여도 보정

- 설명 제출과 투표 완료를 **모두** 한 플레이어에게만 정상 경험치(위 표의 `baseExp`) 100%를 지급한다.
- 설명 제출과 투표 완료 중 **하나만** 한 경우 획득 경험치의 50%만 지급한다.
- 설명 제출과 투표를 **모두 하지 않은** 경우 0 EXP를 지급한다.
- 고의 이탈 시 0 EXP.
- 서버 오류나 방 종료로 게임이 무효 처리된 경우 모든 플레이어에게 0 EXP를 지급한다.
- 소수점 경험치는 버림(floor) 처리한다.

최종 경험치 계산식:

```text
finalExp = max(0, floor(baseExp × participationMultiplier × repeatMatchMultiplier))
```

- `baseExp`: 위 "경험치 지급 정책" 표의 역할·결과별 기본값.
- `participationMultiplier`: 설명 제출 + 투표 완료를 모두 하면 1.0, 둘 중 하나만 하면 0.5, 둘 다 안 함(또는 고의 이탈) 시 0.
- `repeatMatchMultiplier`: 아래 "반복 플레이 악용 방지" 기준을 만족하는 정상 게임이면 1, 무효 처리된 게임이면 0.
- 모든 항목이 곱해진 뒤에도 결과는 절대 음수가 되지 않는다(`max(0, ...)`) — 경험치가 감소하는 경우는 없다.

#### 반복 플레이 악용 방지

- 경험치가 지급되는 정상 게임의 최소 인원은 3명이다.
- 일부 플레이어가 설명을 한 번도 제출하지 않아도 게임 자체는 정상 게임으로 인정한다(무효 처리하지 않는다) — 설명 미제출은 게임 전체가 아니라 위 "참여도 보정"을 통해 그 플레이어 개인의 지급액에만 반영된다. 즉 최소 인원 조건만 충족하면, 게임에 참여해 설명·투표를 정상적으로 마친 플레이어는 다른 참가자의 미제출 여부와 무관하게 정상 경험치를 받는다.

> **구현 메모**: EXP는 파생값이 아니라 `User.exp`에 누적 저장되는 값이라, 지급액은 게임 종료 시점(`gameEngine.ts`의 `finalizeGame`)에 인메모리 게임 상태(투표 내역·지목 대상·역전승 여부·라운드별 설명 제출 여부)에서 계산해 즉시 증가시킨다. 정책 표·계산식은 `userRepo.ts`의 순수 함수 `computeExpAward()`가 담당한다(역할·게임결과·개인결과별 baseExp + 참여도·반복플레이 보정). `GamePlay`에는 승률 파생용 `wasLiar`/`won`만 남기고, EXP 계산에 필요한 부가 정보는 저장하지 않는다(재계산이 아니라 증가 방식이므로 불필요).

## API 계약 (Socket.IO와 REST)

실시간 게임 진행은 Socket.IO 이벤트로, 실시간성이 필요 없는 전적·친구 CRUD는 REST로 나눠 구현했다 — 둘 다 클라이언트-서버 간 통신 규약을 정의한다는 점에서 같은 성격의 문서라 하나의 상위 섹션으로 묶는다.

### Socket.IO 이벤트 계약 (MVP)

단일 기본 네임스페이스 + Socket.IO **room**(`socket.join(roomCode)`)으로 충분.

**Client → Server**:
- `room:create` `{ nickname, visibility: 'public'|'private', maxPlayers: number, title?: string, emoji?: string }` — 서버가 4자리 숫자 코드 발급(충돌 시 재생성). `maxPlayers`는 방장이 지정, 시스템상 상한 없음. `title` 미지정 시 "{방장}의 방", `emoji` 미지정 시 기본 이모지
- `room:listPublic` `{}` — 로비 진입 시 공개방 목록 요청
- `room:join` `{ roomCode, nickname }` — 방이 꽉 찼거나(`players.length >= maxPlayers`) 이미 게임 진행 중이면 `room:error`
- `room:leave` `{}` — 대기 상태(설정 전/게임 종료 후 대기 복귀 상태)에서만 유효. 게임 진행 중(`설명~역전승 시도`)에는 UI에 "방 나가기" 버튼 자체를 노출하지 않아 이 시나리오가 발생하지 않게 한다
- `room:rejoin` `{ roomCode }` — 새로고침 등으로 연결이 끊겼다 되돌아왔을 때 방 상태 복구 요청
- `chat:send` `{ text }` — 언제든 자유 채팅
- `player:ready` `{ isReady: boolean }` — 대기방에서 준비 상태 토글. 봇은 참여 즉시 서버가 `isReady: true`로 고정
- `game:draftConfig` `{ category: string | null, aiBotCount: number }` — 호스트 전용. 게임 시작 전 대기방에서 카테고리/봇 수를 만지작거릴 때마다 보내, 다른 참가자 화면에도 실시간 미리보기로 반영(아직 게임 시작은 아님)
- `game:configure` `{ category: string | null, aiBotCount: number }` — 호스트 전용, **전원(사람+봇)이 `isReady: true`이고 참가자 수(사람+봇)가 3명 이상일 때만** 허용(방이 다 차지 않아도 이 조건만 충족하면 시작 가능), 아니면 `room:error`. `category`는 세 경로로 채워질 수 있다: (1) 프리셋 **칩 목록**(하드코딩된 기본 카테고리 + 이 방에서 그동안 사용된 `customCategories`)에서 선택한 값, (2) **자유 입력** 문자열, (3) `null` — 이 경우 AI가 카테고리까지 생성. **어느 경로든 이번 게임에 실제로 확정된 카테고리(AI 랜덤 생성분 포함)는 서버가 해당 방의 `customCategories`에 중복 없이 추가**해 이후 같은 방에서 칩으로 재사용 가능(방 종료 시 함께 소멸, DB 저장 안 함). 새 카테고리가 추가되면 서버가 `room:customCategoriesUpdated`를 방 전체에 브로드캐스트. 전송 즉시 새 게임 시작 + 방 채팅 초기화
- `turn:submitDescription` `{ text }` — 현재 턴인 사람만 유효
- `discussion:skip` `{}` — 호스트 전용. 토론 페이즈에서 제한시간을 다 기다리지 않고 곧바로 투표로 넘어간다(남은 토론 타이머 취소 후 `vote:started`). 토론 페이즈가 아니거나 호스트가 아니면 무시
- `vote:cast` `{ votedPlayerId }` — 익명, 서버만 집계
- `liar:guessWord` `{ guess }` — 지목된 사람이 실제 라이어일 때만 유효
- `friend:invite` `{ toUid }` — 현재 방으로 친구를 초대. 초대자는 방에 있어야 하고, 대상이 온라인이면 그 소켓(들)에 `room:invited`가 전송된다(방에 없거나 대상이 오프라인이면 `room:error`)

**Server → Client**:
- `room:created`/`room:joined` `{ roomCode, hostId, title, emoji, visibility, players, customCategories, draftConfig }` — 방 생성/입장 직후 해당 소켓에만 전송되는 방 스냅샷 (`players`는 `Player[]`, `customCategories`는 이 방에서 그동안 사용된 카테고리 목록, `draftConfig`는 현재 대기방 카테고리/봇 수 미리보기)
- `game:draftConfigUpdated` `{ category, aiBotCount }` — `game:draftConfig` 수신 시 방 전체 브로드캐스트, 게임 시작(`game:configure`) 시 `{ category: null, aiBotCount: 0 }`로 리셋
- `room:customCategoriesUpdated` `{ customCategories }` (`string[]`) — 새 게임 시작 시 이번 카테고리(방장 입력·AI 랜덤 포함)가 방의 재사용 목록에 새로 추가됐을 때만 방 전체에 브로드캐스트. 클라이언트는 다음 게임 카테고리 칩 목록을 이 값으로 갱신
- `room:publicList` `{ rooms: [{roomCode, title, emoji, hostNickname, category, playerCount, maxPlayers, inProgress}] }` — 로비 카드 표시용. `category`는 방장이 대기방에서 고르고 있는 값(null이면 AI 랜덤), `inProgress`는 해당 방에 진행 중인 게임이 있는지("게임 중" 표시용)
- `room:playerListUpdated` `{ players }` (`Player[]`) — 입장/퇴장 및 `player:ready` 토글 시 방 전체에 브로드캐스트 (`Player.isReady` 포함)
- `room:rejoined` `{ roomCode, hostId, title, emoji, visibility, players, customCategories, chatLog, currentGame, draftConfig }` — `room:rejoin` 성공 시 해당 소켓에만, 채팅 로그·현재 게임 상태까지 포함해 복원. 진행 중이던 라운드가 있으면 `round:yourWord`/`liar:guessPrompt`(자신이 지목된 상태였다면)도 함께 재전송
- `room:error` `{ message: string }` — 잘못된 코드, 이미 진행 중인 방 입장 시도, 호스트 아님 등 실패 케이스에서 요청한 소켓에만 전송
- `chat:message` `{ id, senderId: string|'ai'|'system', type: 'chat'|'turnDescription'|'aiComment'|'system', text, timestamp }` — **통합 채팅 피드**. 자유 채팅, 턴 설명, AI 교란 코멘트, 시스템 안내(새 게임 시작/투표 결과/제시어 공개 등) 모두 이 이벤트로 전달되어 클라이언트는 하나의 리스트에 append만 하면 됨
- `game:started` `{ gameNumber, category, participants }` — 클라이언트도 채팅 뷰 초기화. `category`는 결과 화면 등에서 표시하기 위한 필드, `participants: { id, nickname, isBot }[]`는 봇 포함 전체 참가자 목록(하위호환 추가) — `room:playerListUpdated`는 사람만 추적하므로 투표 후보·턴 배너에 봇을 표시하려면 이 필드가 필요
- `round:yourWord` (해당 소켓에만 개별 전송) `{ word, explanation }` — `explanation`은 해당 단어의 짧은 AI 설명. 서버가 게임 시작 시 미리 생성해 함께 실어 보내며(난이도 무관 항상 생성, 생성 실패 시에만 생략), 클라이언트는 곧바로 노출하지 않고 "AI 설명보기" 버튼으로 유저가 원할 때 펼쳐 본다(온디맨드 재요청 이벤트는 없음). 진짜/가짜 여부·라이어 여부는 어떤 payload에도 포함하지 않음(본인도 모름)
- `turn:started` `{ playerId, timeLimitSec }`
- `discussion:started` `{ timeLimitSec }` — 설명 페이즈가 끝나고 토론 페이즈로 전환됐음을 명시(하위호환 추가). 이전엔 system 채팅 텍스트로만 암시돼 클라이언트가 "현재 턴" 배너를 내릴 시점을 알 수 없었음
- `vote:started` `{ timeLimitSec }`, `vote:progress` `{ votesInCount, totalCount }` — 식별정보 없이 진행률만
- `round:resolved` `{ votedOutId, wasLiar, realWord, liarWord, liarId }` — `liarId`는 투표 결과와 무관하게 항상 함께 공개된다(시민이 오지목되면 역전승 단계 없이 바로 끝나 그 외엔 알 방법이 없으므로). `wasLiar`가 `false`(오지목)면 역전승 단계 없이 바로 `round:finalResult { winner: 'liar' }`로 진행. 지목된 사람·라이어 여부·실제/라이어 제시어·역전승 결과는 채팅에 작은 텍스트로 흘리지 않고, 클라이언트가 이 이벤트와 `round:finalResult`를 합쳐 큰 알림창으로 한 번에 보여준다(chat:message로는 더 이상 별도 브로드캐스트하지 않음)
- `liar:guessPrompt` `{ timeLimitSec }` — `wasLiar`가 `true`일 때만 발생, 지목된 사람의 소켓에만
- `round:finalResult` `{ liarGuessCorrect: boolean | null, winner: 'liar'|'citizens', liarGuess: string | null }` — 오지목으로 역전승 단계 자체가 없었으면 `liarGuessCorrect`/`liarGuess` 모두 `null`. 정답 판정은 서버가 우선 편집 거리 기반 유사 일치를 결정적으로 체크하고(오타 관대하게 허용), 통과 못 하면 LLM(`judgeLiarGuess`)에게 의미 판단을 맡긴다(번역·동의어 등은 LLM이 판단)
- `game:ended` `{}` — 방은 대기 상태로 복귀, 채팅은 유지, 호스트는 다음 게임 설정 가능
- `room:closed` — 호스트가 방을 나가면(재접속 유예 시간 만료 포함) 방이 폭파되며 전송. 호스트가 아닌 인원의 퇴장은 방을 유지한 채 `room:playerListUpdated`만 브로드캐스트
- `room:invited` `{ roomCode, title, emoji, fromUid, fromNickname }` — 친구가 나를 방으로 초대했을 때(`friend:invite`) 온라인인 내 소켓에 전송. 클라이언트는 알림을 띄우고 수락 시 해당 `roomCode`로 입장

서버가 방/게임/라운드 페이즈 전이(`대기 → 설정 → 설명 → 토론 → 투표 → 결과 → (역전승 시도) → 게임종료(대기로 복귀)`)를 전적으로 소유하고 타이머를 관리. 투표는 **개인별 선택을 어떤 클라이언트에게도 절대 전송하지 않고 서버 내부 집계로만** 사용 — `round:resolved`에도 누가 누구에게 투표했는지는 포함하지 않는다.

**타이머 만료 동작**: 설명/투표 시간이 만료되면 해당 행동은 **그냥 못 하는 것**으로 처리한다 — 설명 미제출 턴은 빈 채로 넘어가고, 미투표는 집계에서 빠진 채 다음 페이즈로 진행한다. 봇 자동 대체나 기본값 강제 같은 별도 보정 로직은 두지 않는다.

**토론 조기 종료**: 토론 페이즈 한정으로 호스트는 `discussion:skip`을 보내 제한시간을 다 기다리지 않고 곧바로 투표로 넘어갈 수 있다(남은 토론 타이머를 취소하고 즉시 `startVoting`). 서버가 페이즈·호스트 여부를 검증하므로 토론 페이즈가 아니거나 호스트가 아닌 요청은 무시된다.

### REST API (전적·친구)

전적 조회·친구 관리는 실시간성이 필요 없는 CRUD라 Socket.IO 이벤트 계약이 아니라 **Express REST**로 구현했다(`backend/src/http/`). `GET /api/users/nickname-availability/:nickname` 하나만 예외이고, 나머지 모든 엔드포인트는 `Authorization: Bearer <Firebase ID Token>` 헤더 필수(`requireAuth` 미들웨어) — 서비스 계정 키가 없는 로컬 dev 환경에서는 소켓과 동일하게 토큰 검증을 생략하는 fallback이 적용된다.

**전적·계정** (`/api/users`, `backend/src/http/statsRoutes.ts`):
- `GET /api/users/nickname-availability/:nickname` — **인증 불필요**(회원가입 단계엔 아직 Firebase 세션 자체가 없음). 응답 `{ available: boolean }`. `User.nickname`은 DB `@unique` 제약이 걸려 있어, 프론트는 회원가입 폼에서 이 엔드포인트로 중복 확인을 통과해야만 가입 제출을 허용해야 한다
- `PUT /api/users/me` `{ nickname }` → 204 — 회원가입/닉네임 변경 직후 로컬 DB에 즉시 반영. Firebase ID 토큰의 name 클레임이 `updateDisplayName` 직후 바로 갱신되지 않을 수 있어, 프론트가 닉네임 확정 시 명시적으로 호출해 친구 요청 등이 가입 직후에도 바로 동작하게 한다. 닉네임 중복이면 409
- `GET /api/users/me/profile` — 로그인 시 업로드한 프로필 사진을 복원하기 위한 조회. 응답 `{ nickname, avatarUrl }`
- `PATCH /api/users/me/avatar` `{ avatarUrl: string | null }` → 204 — 프로필 사진 저장/삭제. 클라이언트가 Firebase Storage(`avatars/{uid}` 경로)에 직접 업로드한 뒤 다운로드 URL만 전달하면 서버가 본인 uid 경로인지 검증 후 DB에 기록. `null`이면 사진을 지우고 기본 아이콘으로 되돌림
- `GET /api/users/me` — 내 전적. 응답 `{ totalGames, overallWinRate, liarWinRate, citizenWinRate, exp, level }` (승률은 0~1 float, 분모 0이면 `null`. `exp`는 누적 경험치(EXP) 정수값(단조증가, DB에 저장, 절대 감소하지 않음), `level`은 계산된 파생값(저장 안 함, 매번 누적 경험치로부터 계산). 자세한 경험치 지급 규칙과 레벨 계산식은 [경험치(EXP) 및 레벨 정책](#경험치exp-및-레벨-정책) 참고)
- `GET /api/users/:uid` — 다른 유저의 전적 (동일 응답 형태)
- `GET /api/users/:uid/profile` — 임의 uid의 닉네임/프로필 사진 조회(`/me/profile`의 타인 버전). 응답 `{ nickname, avatarUrl }`. 방 참가자 채팅·투표 후보 아바타에 실제 프로필 사진을 보여주는 데 쓴다(봇 id는 DB에 없어 `{ nickname: null, avatarUrl: null }`)
- `DELETE /api/users/me` → 204 — **회원탈퇴**. 프론트는 이 엔드포인트 하나만 호출하면 된다(Firebase와 직접 통신 불필요). 백엔드가 `firebase-admin`으로 Firebase Auth 계정을 삭제(서버 권한이라 "최근 로그인 필요" 재인증 제약 없이 처리)하고, 로컬 DB `User` 행도 삭제한다(`onDelete: Cascade`로 `GamePlay`·`Friendship` 함께 삭제) — 게스트 정리 cron과 동일한 삭제 패턴

**친구** (`/api/friends`, `backend/src/http/friendsRoutes.ts`):
- `POST /api/friends/requests` `{ addresseeUid }` 또는 `{ addresseeNickname }` → 201 `Friendship` — 닉네임으로 보내면 서버가 uid로 해석(없으면 404). 이미 상대가 나에게 보낸 대기 요청이 있으면 자동으로 맞수락 처리됨. 자기 자신·이미 친구·차단 상태면 409. **회원끼리만 가능** — 요청자·대상 중 한쪽이라도 게스트(익명 계정)면 403(게스트는 uid가 세션마다 바뀔 수 있어 친구 관계가 쉽게 끊어지기 때문)
- `GET /api/friends/requests` — 내가 받은 대기 요청 목록. 응답 `{ requests: [{ ...Friendship, requester: { uid, nickname, avatarUrl } }] }`
- `POST /api/friends/requests/:id/accept` → 200 `Friendship`(status: accepted)
- `POST /api/friends/requests/:id/decline` → 204 (행 삭제, 재요청 가능)
- `GET /api/friends` — 수락된 친구 목록. 응답 `{ friends: [{ uid, nickname, avatarUrl, isOnline }] }` (`isOnline`은 서버 소켓 프레젠스 스냅샷)
- `DELETE /api/friends/:uid` → 204 (친구 해제)

## LLM 래퍼 (`backend/src/llm/wrapper.ts`)

```ts
interface LiarGameLLM {
  generateWordPair(category: string | null, usedWords: string[], usedCategories: string[]): Promise<{ category: string; realWord: string; liarWord: string }>;
  generateBotTurn(ctx: BotTurnContext): Promise<string>;
  generateTurnComment(ctx: TurnCommentContext): Promise<string>;
  explainWord(word: string): Promise<string | null>;   // 제시어 설명 텍스트. 난이도 무관 모든 단어에 대해 생성(생성 실패 시에만 null)
  judgeLiarGuess(guess: string, realWord: string): Promise<boolean>; // 역전승 정답 유사판정
}
```
- 다섯 함수 모두 Haiku 4.5로 시작. `category`가 null이면 카테고리 자체도 LLM이 생성.
- `generateWordPair` 프롬프트 핵심: 같은 카테고리 안에서 연관성은 있지만 다른 두 단어를 생성 (예: 카테고리 "동물" → realWord "사자", liarWord "호랑이") — 너무 멀면 라이어가 바로 티나고, 너무 가까우면 설명이 똑같아짐. 너무 흔하고 뻔한 단어/카테고리도, 대부분이 못 알아들을 만큼 생소한 것도 피하라는 지침 포함. **LLM에게 하나만 확정해달라고 하면 매번 비슷하게 "무난한" 답으로 수렴하는 경향이 있어**, `category`가 null이면 먼저 카테고리 후보 3개(`categoryCandidatesPrompt`, 이 방에서 이미 쓴 `room.customCategories`는 회피)를 받아 서버 코드가 무작위로 하나를 고르고, 그 카테고리로 다시 제시어 쌍 후보 3개(`wordPairPrompt`, 이미 쓴 `usedWords`는 회피)를 받아 서버 코드가 무작위로 하나를 골라 확정한다 — 실제 무작위성은 LLM 샘플링이 아니라 서버 코드(`Math.random`)가 담당.
- `generateBotTurn` 프롬프트 핵심: "너무 완벽하지 않게, 자연스럽게" — 봇도 자신에게 배정된 단어(진짜든 가짜든)만 알고 자신이 라이어인지는 모른다는 전제로 설명 생성 (사람 라이어와 동일 조건). 자신이 지금 '라이어게임' 참가자로 플레이 중이라는 프레이밍을 프롬프트 서두에 명시. 단어 자체나 그 단어를 바로 연상시키는 결정적 특징은 직접 말하지 않게 하고, 대신 "이 단어를 잘 안다"는 여유·확신이 은근히 묻어나는 간접적·개인적인 힌트로 설명하도록 지시(라이어가 아니라는 인상을 슬쩍 풍기는 효과). 응답은 반드시 반말.
- `generateTurnComment` 프롬프트 핵심: 방금 제출된 설명을 보고 근거 없이 의심하는 드립을 던지는 코멘트를 생성. 실제 라이어가 누구인지·진짜/가짜 제시어가 무엇인지는 `TurnCommentContext` 자체에 그 필드가 없어 구조적으로 이 프롬프트에 입력될 수 없음 — 봇과 같은 원칙("정답을 모르는 관전자"처럼 행동)을 따라야 자연스러운 노이즈가 된다. 말투는 "초등학생이 단체 채팅방에서 떠드는" 유치하고 산만한 톤(반말, "ㅋㅋㅋ", "ㅇㅈ?" 등)으로 짓궂게 약올리되, 실제 욕설·혐오·인신공격은 금지. **별도 system 프롬프트**로 "참가자 전원이 동의한 게임 내 코미디 캐릭터 연기"임을 먼저 명시해, 모델이 이를 실제 기만 요청으로 오인해 거부하는 것을 방지한다(과거 "다른 플레이어를 의도적으로 헷갈리게 만들라"는 문구만으로는 Claude가 "정보를 꾸며내 속이라는 요청"으로 해석해 거부한 사례가 있었음). 응답이 거절 문구처럼 보이거나(영文/한글 거절 패턴) 비정상적으로 길면 `wrapper.ts`의 `assertNotRefusal`이 에러로 처리해, 거절 텍스트가 그대로 게임 채팅에 노출되지 않고 조용히 코멘트가 생략되게 한다.
- `explainWord` 프롬프트 핵심: 제시어에 대한 짧은 텍스트 설명을 생성(이미지 생성은 하지 않음). 서버가 `game:configure` 직후 real/liar 두 단어 모두에 대해 미리 호출하고, 낯섦 여부와 무관하게 생성된 설명을 각 참가자의 `round:yourWord` payload(`explanation`)에 실어 보낸다. 클라이언트는 곧바로 노출하지 않고 "AI 설명보기" 버튼으로 유저가 원할 때 펼쳐 보게 한다 — 버튼은 이미 받은 설명을 표시할 뿐, 그 시점에 새로 생성을 요청하지 않는다.
- `judgeLiarGuess` 프롬프트 핵심: 라이어의 역전승 답안과 진짜 제시어를 비교해 의미상 동일한지 판정. 오타·맞춤법 오류·한글/영어 표기 차이(예: "burger"/"버거")는 정답으로 인정. **LLM 판정만으로는 사소한 오타조차 오답 처리되는 경우가 있어**(예: "펜싱"을 "팬싱"으로 표기), `wrapper.ts`가 LLM을 호출하기 전에 `textMatch.ts`의 편집 거리 기반 결정적 체크(`isFuzzyMatch`)를 먼저 통과시킨다 — 짧은 단어는 편집 거리 1까지, 긴 단어는 길이의 20%까지 오타로 인정하고 통과하면 LLM 호출 없이 바로 정답 처리, 통과 못 하면(번역·동의어 등 표기가 많이 다른 경우) 기존처럼 LLM에게 맡긴다. LLM 호출 자체가 실패했을 때의 폴백도 완전 일치 대신 이 유사 일치로 처리.

## 백엔드 구현 현황 (backend 브랜치)

이 문서의 MVP Socket.IO 계약과 "DB 스키마"(원래 선택 항목이었던 유저 전적·친구)까지 구현 완료됨(`milleion`은 2026-07-13부터 `dev`에서 직접 작업, 그 이전 이력은 `backend` 브랜치에 동결 보존). 실제 Firebase 서비스 계정 키·Anthropic/OpenAI API 키로 동작 검증 완료(방 생성→게임 진행→투표→결과→종료까지 end-to-end, DB 기록 포함).

- **구현 완료**: `roomManager`(방 생성/입장/퇴장·4자리 코드·공개방 목록·`room:rejoin` 재접속), `gameEngine`(전체 페이즈 머신, 봇 자동 턴/투표/역전승 시도, 타이머 만료 규칙, 오지목 시 즉시 종료 분기), `socket/handlers`(이벤트 계약 전체 — `player:ready`, `game:draftConfig` 대기방 실시간 미리보기 포함), Firebase Auth(소켓 handshake + REST 양쪽 실제 `verifyIdToken`, 키 없으면 dev fallback), LLM 래퍼(Anthropic/OpenAI 이중 provider, 다섯 함수 전부, 키 없으면 mock 폴백), DB(`User`/`GamePlay`/`Friendship` + `/api/users`, `/api/friends` REST — Socket.IO 계약에는 없는 프로필 조회용 확장, `User.level` 파생 필드 포함), 게스트 정리 cron(6시간마다)
- **미구현으로 남은 것**: "MVP 제외(stretch)" 항목(라운드 재시작, 방별 네임스페이스, 라이어 다수 선택)뿐
- **프론트 연동도 완료**: `frontend-2` 브랜치가 이 문서의 백엔드 계약에 맞춰 실연동을 마쳤고, 이후 픽셀아트 UI 프론트(`frontend` 계열)와 백엔드를 하나로 합친 **풀스택 `backend` 브랜치**에서 통합이 완료됐다. 자세한 내용은 "프론트-백엔드 연결 정합성" 참고.

## 프론트-백엔드 연결 정합성

> **통합 브랜치(`backend`)**: 픽셀아트 UI 프론트(`frontend`)를 백엔드에 실연동해 `backend` 브랜치에 backend/ + frontend/ 풀스택으로 합쳤다. 서비스/상태 계층(socket_service·room_provider·auth_service·backend_api)은 `frontend-2`에서 이식하고, 화면(login/signup/lobby/profile/friends/room)은 픽셀 UI를 유지한 채 서버 권위 방식으로 재작성했다. `room_screen`은 로컬 시뮬레이션을 전면 제거하고 roomProvider 상태만 그린다. 백엔드 추가분: 방 `title`/`emoji`, 공개방 목록 메타, 친구 온라인 프레젠스(`isOnline`)와 `friend:invite`/`room:invited`, 닉네임 기반 친구 요청, Flutter 웹 정적 호스팅. 방 화면은 별도 `panels/*.dart` 없이 `screens/room/room_screen.dart` 한 파일에서 페이즈별로 분기하며, 아래 세부 항목도 이 통합 구조 기준으로 기술한다.

`frontend-2` 브랜치가 이 문서의 백엔드 계약(Socket.IO 이벤트·REST API)에 맞춰 실연동을 완료했다. 애초에 mock 데이터 기반 골격이던 프론트가 아래와 같이 정리됐다.

- **네트워킹/상태 의존성**: `frontend/pubspec.yaml`에 `socket_io_client`, `firebase_core`/`firebase_auth`, `flutter_riverpod` 추가. `services/socket_service.dart`(소켓 송수신 전담), `services/auth_service.dart`(Firebase Auth), `state/room_provider.dart`(Riverpod, 방/게임 상태) 신설. 활성 방 코드 저장용으로 `services/room_session_store.dart`(SharedPreferences)를 추가했고, 기존 `services/user_session.dart`(닉네임 등 static 전역)는 그대로 유지된다(둘은 역할이 달라 대체 관계가 아님).
- **단일 `RoomScreen` + 페이즈 분기**: `screens/room/room_screen.dart` 한 파일로 통일. 채팅 리스트는 고정하고 하단 영역만 현재 페이즈(대기/설명/토론/투표/역전승/결과)에 따라 room_screen.dart 내부에서 분기해 그려, 게임 채팅과 방 채팅이 하나의 피드로 유지된다.
- **`ChatMessage` 모델**: `models/chat_message.dart`가 계약(`{ id, senderId, type, text, timestamp }`)과 동일. `senderId`는 uid 또는 `'ai'`/`'system'` 특수값.
- **투표/판정 서버 소유**: 투표 페이즈 UI(room_screen.dart 내부)는 `vote:cast { votedPlayerId }`만 보내고, 결과는 `round:resolved`/`round:finalResult` 수신값을 그대로 반영한다(클라이언트 판정 로직 없음).
- **개별 전송 이벤트**: `socket_service.dart`가 `round:yourWord`→`onYourWord`, `liar:guessPrompt`→`onLiarGuessPrompt`를 개별 처리하고, room_screen.dart는 역전승 프롬프트를 자신에게 온 경우에만 렌더링한다.
- **`RoomSummary`**: `models/room_summary.dart`가 `room:publicList` 계약(`{ roomCode, title, emoji, hostNickname, category, playerCount, maxPlayers, inProgress }`)을 그대로 반영한다.
- **`player:ready`**: `models/player.dart`의 `isReady` 필드와 room_screen.dart 대기 페이즈의 준비 완료 토글로 반영. 방장은 이 토글 자체를 보지 않는다(서버가 `isReady: true`로 고정해두므로 항상 준비된 것으로 취급) — 방장이 아닌 참가자 전원이 준비를 마치면 방장이 "게임 시작"을 눌러 시작한다.
- **`friend:invite`/`room:invited`**: room_screen.dart 헤더 우측 상단에 방장 전용(게스트 제외) "친구 초대" 버튼을 두고, 누르면 접속 중인 친구 목록 다이얼로그를 띄운다. 목록의 "초대" 버튼이 `friend:invite`를 보내고, 상대는 로비에서 `room:invited` 수신 스낵바(+"입장" 액션)로 받는다.
- **`game:draftConfig`/`draftConfigUpdated`**: `waiting_panel.dart`가 방장 입력 시 실시간으로 emit하고, 비방장은 서버가 보낸 값을 읽기 전용으로 표시.
- **`room:rejoin`/`room:rejoined`**: `socket_service.dart`의 `rejoinRoom()`/`onRoomRejoined`, `room_provider.dart`의 `_applyRejoin()`이 새로고침 후 채팅·게임 상태를 복원.
- **`maxPlayers`/`title` 방 생성 UI**: `screens/lobby/lobby_screen.dart`의 방 만들기 다이얼로그에서 인원수는 +/- 스테퍼로(상한 없음), 방 이름은 텍스트 입력창(기본값 "{닉네임}의 방" 프리필, 수정 가능)으로 지정하고 `createRoom()`이 이 값들을 emit.
- **`discussion:started`**: `socket_service.dart`의 `onDiscussionStarted`가 페이즈를 전환하고 현재 턴 배너를 내린다.
- **`discussion:skip`**: room_screen.dart 토론 페이즈의 토론 카드에 방장 전용 "토론 건너뛰고 투표 시작" 버튼을 두고, 누르면 `socket_service.dart`의 `skipDiscussion()`으로 emit한다.
- **데스크탑 레이아웃**: lobby_screen과 동일하게 `context.isDesktop`일 때 좌측 `AppNavRail`로 나가기/초대(방장·회원만) 버튼이 이동하고, 헤더에서는 숨겨진다.

위 정리는 정적 코드 검토 기준이며, 런타임 동작(빌드/실행)은 별도로 확인해야 한다.

## MVP 제외 (stretch)

- 게임 내 라운드 재시작(여러 라운드 반복)
- 방별 Socket.IO 네임스페이스
- 다중 LLM 프로바이더 동시 지원 (인터페이스만 교체 가능하게 열어둠)
- **라이어 다수 선택**: 지금은 라이어가 1명 고정이지만(데이터 모델 `GameState.liarIds` 참고), 방장이 라이어 수를 선택할 수 있도록 확장하는 것도 고려 가능. 확장 시 배정·투표 판정(라이어 전원 지목 필요 여부 등) 규칙을 다인 라이어 기준으로 새로 정의해야 한다.

## TODO / 향후 과제

위 "MVP 제외(stretch)"가 **기능 백로그**라면, 여기는 아직 방향을 못 박지 못한 **미결 결정·후속 작업**을 모아둔다.

- **경험치 지급 정책 구현 완료**: [경험치(EXP) 및 레벨 정책](#경험치exp-및-레벨-정책)의 역할·승패·투표 대상·역전승·참여도까지 반영하는 세분화된 규칙을 백엔드에 반영했다. 지급액 계산은 `userRepo.ts`의 순수 함수 `computeExpAward()`(정책 표 baseExp + 참여도·반복플레이 보정)가 담당하고, `gameEngine.ts`의 `finalizeGame`이 게임 종료 시점의 인메모리 상태(투표 내역·지목·역전승·라운드별 설명 제출 여부)에서 인자를 채워 호출한 뒤 `User.exp`에 즉시 누적한다. 레벨 구간 공식(`100×(L−1) + 15×(L−1)×(L−2)`) 자체는 변경 없음. 향후 지급액 조정은 `computeExpAward` 한 곳만 고치면 된다(단, EXP는 누적 저장값이라 과거 기록 소급 재계산은 하지 않는다).
- **경험치·레벨 프론트 표시**: 백엔드가 `GET /api/users/me`로 누적 `exp`(저장값)와 계산된 `level`(파생값)을 내려주고, 로비 전적 카드에서 `Lv.{level} ({exp} EXP)` 형태로 표시한다(`lobby_screen.dart`). 프로필 화면에도 레벨 배지와 레벨 내 진행바(`_LevelBadge`)를 표시한다 — 진행도 계산은 `현재 레벨 시작점(누적 경험치) = 100×(level−1) + 15×(level−1)×(level−2)`, `다음 레벨까지 필요 증분 경험치 = 100 + (level−1)×30`, `진행도 = (exp − 현재_레벨_시작점) / 다음_레벨까지_필요_증분`으로 계산(`UserStats.levelProgress`/`expToNextLevel`).
- **커스텀 카테고리 악용 방지**: 방장이 자유 입력으로 추가하는 카테고리에 별도 검증이 없다. 부적절한 입력에 대한 최소 필터링이 필요한지 검토.
- **Storage CORS origin 좁히기**: Firebase Storage 버킷(`l-ai-r-game.firebasestorage.app`)의 CORS 설정이 현재 `origin: ["*"]`(전체 허용)로 되어 있다. 업로드 자체는 Storage Rules(로그인 + 본인 uid만 허용)로 막혀 있어 당장 위험하진 않지만, 배포 도메인이 확정되면 `gsutil cors set`으로 그 도메인만 허용하도록 좁혀야 한다.
- **백엔드 CORS origin 좁히기**: `backend/src/index.ts`의 Express(`app.use(cors())`)와 Socket.IO(`cors: { origin: '*' }`) 둘 다 개발 편의상 전체 허용 중(코드에 TODO 주석으로 이미 표시돼 있음). 배포 도메인이 확정되면 프론트와 단일 origin으로 좁혀야 한다.
- **Firebase Auth 승인된 도메인(authorized domains) 추가**: Google 웹 로그인은 Firebase 콘솔의 Authentication → Settings → Authorized domains에 등록된 도메인에서만 동작한다. 배포 도메인이 확정되면 그 도메인을 추가해야 한다(미등록 시 웹에서 Google 로그인 팝업이 `auth/unauthorized-domain`으로 실패). `localhost`는 기본 등록되어 로컬 개발엔 문제없음.
- **웹 빌드에 백엔드 URL 주입**: `BackendConfig`가 `--dart-define=BACKEND_URL`로 주소를 주입받고 기본값은 `http://localhost:3000`이다. 배포 시 `flutter build web --dart-define=BACKEND_URL=https://<배포도메인>`으로 빌드하지 않으면 배포된 웹이 localhost로 붙어 소켓/REST가 실패한다.
- **Firebase Auth 제공자 활성화**: Firebase 콘솔 Authentication에서 **익명 / 이메일·비밀번호 / Google** 로그인을 켜야 각 로그인 경로가 동작한다(로그인 화면의 세 버튼에 대응). Storage Rules(`avatars/{uid}` 본인만 쓰기)는 이미 설정돼 있으나 배포 전 재확인 권장.
- **백엔드 운영 환경변수**: (1) **Firebase Admin 서비스 계정 키** — 없으면 소켓/REST의 토큰 검증을 건너뛰는 dev fallback로 동작하므로(누구나 임의 uid로 접속 가능) 운영 배포 전 반드시 주입해야 한다. (2) **`ANTHROPIC_API_KEY`/`OPENAI_API_KEY`** — 둘 다 없으면 제시어/봇/훈수가 고정 mock LLM으로 대체되니, 실제 게임 품질이 필요하면 최소 하나는 주입한다. `LLM_PROVIDER`로 명시 지정 가능(미지정 시 둘 다 있으면 OpenAI 우선).

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
15. 방장이 자유 입력한 카테고리든 "AI 랜덤 생성"으로 확정된 카테고리든, 해당 방에서 다음 게임부터 칩으로 재사용되는지(`room:customCategoriesUpdated` 수신), 중복 없이 쌓이는지, 방 종료 후에는 사라지는지 확인
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
