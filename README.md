# 26s-w2-c3-06

## 공통과제 II : 협업형 실전 산출물 제작 (2인 1팀)

**목적:** 실시간 인터랙션, LLM Wrapper, Cross-Platform 중 하나의 옵션을 선택해 구현하며, 선택한 기술을 실제로 동작하는 형태의 산출물로 완성한다.

**선택 옵션:**

| 옵션 | 설명 |
|---|---|
| 실시간 인터랙션 | 사용자 간 상태 변화, 실시간 데이터 흐름, 스트리밍 응답 등 실시간성이 드러나는 기능을 구현 |
| LLM Wrapper | LLM API를 활용하여 AI 기능이 포함된 산출물을 구현 |
| Cross-Platform | 하나의 산출물을 여러 실행 환경에서 사용할 수 있도록 구현* |

> *데스크톱 앱 ↔ 모바일 앱; 혹은 다른 폼팩터에서의 앱; 웹만/웹 기반 프레임워크(Electron, Tauri 등) 대신 다른 프레임워크를 시도해보는 것을 적극 권장

**결과물:** 선택한 옵션이 적용된 작동 가능한 산출물, 실행 가능한 코드, 시연 자료 및 관련 문서

---

## 목차

- [팀원](#팀원)
- [선택 옵션](#선택-옵션)
- [기획안](#기획안)
- [구현 명세서](#구현-명세서)
- [아키텍처](#아키텍처)
- [설계 문서](#설계-문서)
- [산출물 및 실행 방법](#산출물-및-실행-방법)
- [회고 문서](#회고-문서)
- [참고 자료](#참고-자료)

---

## 팀원

| 이름 | 학교 | GitHub | 역할 |
|---|---|---|---|
| 김혜리 | 한양대 | [ireyhye](https://github.com/ireyhye) | Frontend |
| 조준호 | KAIST | [milleion](https://github.com/milleion) | Backend |

---

## 선택 옵션

- [x] 실시간 인터랙션
- [x] LLM Wrapper
- [x] Cross-Platform

---

## 기획안

- **산출물 주제:** AI가 개입하는 라이어게임 (Liar Game)
- **제작 목적:** 실시간 인터랙션 · LLM Wrapper · Cross-Platform 세 옵션을 하나의 게임 산출물로 통합 구현
- **선택 옵션:** 실시간 인터랙션 + LLM Wrapper + Cross-Platform
- **핵심 구현 요소:**
  - 방장이 정한(또는 AI가 랜덤 생성한) 카테고리로 진짜/가짜 제시어 쌍을 LLM이 생성 — 라이어는 비슷하지만 다른 가짜 제시어를 받고, 자신이 라이어인지도 모름
  - 인원 부족 시 방장이 원하는 수만큼 AI 봇이 플레이어로 참여해 자연스럽게 설명을 생성
  - 매 턴 설명 제출마다 AI가 다른 플레이어들을 헷갈리게 하는 "분탕질" 코멘트를 실시간으로 추가
- **사용 / 시연 시나리오:** 참가자들이 각자 기기(웹/모바일)에서 공개방 목록 선택 또는 4자리 코드로 같은 방에 입장 → 방장이 카테고리·AI 봇 수를 설정하고 게임 시작 → 그룹 채팅 형태의 화면에서 순서대로 제시어 설명 제출(그때마다 AI 분탕질 코멘트 동반) → 익명 투표로 라이어 지목 → 결과 공개, 라이어로 지목되면 진짜 제시어를 맞혀 역전승 시도
- **팀원별 역할:** 김혜리 — Frontend(Flutter, iOS/Android/Web), 조준호 — Backend(Node/Express, Socket.IO, LLM 연동)

세부 아키텍처/이벤트 설계는 [PLAN.md](./PLAN.md) 참고.

### 개발 일정

| 날짜 | 목표 |
|---|---|
| Day 1 | 백엔드 기본 구조 설계 · Socket.IO 서버 구축 · 방/게임/라운드 상태 모델링 |
| Day 2 | Firebase Auth 토큰 검증 연동 · 소켓 이벤트 계약 설계 · 로그인 플로우 구현 |
| Day 3 | LLM 래퍼 구현 · 제시어 쌍 생성 · AI 봇 턴 생성 프롬프트 작성 |
| Day 4 | 게임 상태 머신 구현 · 페이즈 전이 (대기 → 설정 → 설명 → 토론 → 투표 → 결과 → 역전승) |
| Day 5 | 매 턴 분탕질 코멘트 실시간 구현 · 라이어 역전승 로직 · 백엔드 완성도 높이기 |
| Day 6 | 프론트엔드 UI 구현 (로그인 · 로비 · 방 화면) · Socket.IO 클라이언트 연동 · 상태 동기화 |
| Day 7 | 통합 테스트 · 버그 수정 · 모바일/웹 반응형 디자인 검수 · 시연 영상 준비 |

---

## 구현 명세서

| 구현 요소 | 설명 | 우선순위 |
|---|---|---|
| 공개/비공개 방 (Socket.IO) | 공개방 목록 조회·입장, 4자리 코드 비공개방 입장, 실시간 플레이어 동기화 | 필수 |
| 게임 진행 상태 머신 | 카테고리 설정 → 설명 → 토론 → 투표 → 결과 → 역전승 시도 페이즈 전이 | 필수 |
| LLM 제시어 쌍 생성 | 카테고리 기반 진짜/가짜 제시어 쌍 생성 (직접 입력 또는 AI 랜덤 카테고리) | 필수 |
| AI 봇 플레이어 | 방장이 지정한 수만큼 봇이 참여해 자연스러운 설명 생성 | 필수 |
| 매 턴 AI 분탕질 코멘트 | 설명 제출마다 LLM이 의도적으로 헷갈리게 하는 코멘트 실시간 추가 | 필수 |
| Firebase Auth 로그인 | 이메일/소셜 로그인, 소켓 handshake 시 ID 토큰 검증 | 필수 |
| 라이어 역전승 | 투표로 지목된 라이어가 진짜 제시어를 맞히면 승리 | 필수 |
| Firestore 승패 기록 | 게임 결과를 영구 저장해 프로필/통계로 노출 | 선택 |
| 게임 내 라운드 재시작 | 하나의 게임에서 설명 라운드를 여러 번 반복 | 선택 |

---

## 아키텍처

Flutter(iOS/Android/Web) 클라이언트가 `socket_io_client`로 Node/Express + Socket.IO 백엔드에 온라인 방 단위로 접속한다. 백엔드는 방/게임/라운드 상태를 인메모리로 관리하며, 소켓 handshake 시 Firebase Auth ID 토큰을 검증한다. 게임 진행 중 필요한 시점(제시어 쌍 생성, 봇 턴 생성, 매 턴 분탕질 코멘트)마다 백엔드가 Anthropic Claude API를 호출하는 LLM 래퍼를 통해 결과를 받아 Socket.IO로 실시간 브로드캐스트한다. 상세 이벤트 계약과 데이터 모델은 [PLAN.md](./PLAN.md) 참고.

---

## 설계 문서

> 프로젝트 성격에 따라 필요한 항목만 작성

### 화면 / 인터페이스 설계

로그인 → 로비(공개방 목록 / 코드로 입장 / 방 만들기) → 방 화면(RoomScreen) 하나로 통일. 방 화면은 그룹 채팅 UI 위에 게임 페이즈(대기/설정/설명/토론/투표/결과)별 하단 컨텍스트 패널만 바뀌는 구조. 화면 목업/Figma는 추후 추가 예정.

### 데이터 구조

방(Room) > 게임(Game) > 라운드(Round) 계층. 방은 인메모리 `RoomState`(방 코드, 플레이어, 채팅 로그, 현재 게임)로 관리하고, 승패 기록만 Firestore에 영구 저장(선택 구현). 상세 TypeScript 인터페이스는 [PLAN.md](./PLAN.md)의 "데이터 모델" 섹션 참고.

### API / 외부 서비스 연동

| Method / 방식 | Endpoint / 서비스 | 설명 | 요청 | 응답 | 비고 |
|---|---|---|---|---|---|
|  |  |  |  |  |  |

---

## 산출물 및 실행 방법

- **산출물 설명:**
- **실행 환경:**
- **실행 방법:**
- **시연 영상 / 이미지:** (선택)

### 실행 방법

```bash
# 환경 설정
cp .env.example .env

# 의존성 설치
npm install   # 또는 pip install -r requirements.txt 등

# 실행
npm run dev   # 또는 python main.py 등
```

### 기술 구성

| 분류 | 사용 기술 |
|---|---|
| 핵심 기술 | Flutter, Node.js + Express + Socket.IO, Anthropic Claude API |
| 실행 환경 | iOS / Android / Web (Flutter 단일 코드베이스) |
| 데이터 저장 | 인메모리(방/게임/라운드 상태), Firestore(승패 기록, 선택 구현) |
| 외부 API / 서비스 | Firebase Authentication, Firestore, Anthropic Claude API |
| 기타 | `socket_io_client`(Flutter), `firebase-admin`(백엔드 토큰 검증), Riverpod(상태관리) |

---

## 회고 문서

> [KPT 방법론 참고](https://velog.io/@habwa/%EB%8B%A8%EA%B8%B0-%ED%94%84%EB%A1%9C%EC%A0%9D%ED%8A%B8-%ED%9A%8C%EA%B3%A0-KPT-%EB%B0%A9%EB%B2%95%EB%A1%A0)

### Keep — 잘 된 점, 다음에도 유지할 것

-
-
-

### Problem — 아쉬웠던 점, 개선이 필요한 것

-
-
-

### Try — 다음번에 시도해볼 것

-
-
-

### 팀원별 소감

**김혜리:**

> 

**조준호:**

> 

---

## 참고 자료

### 실시간 인터랙션

**WebSocket**
- https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API
- https://techblog.woowahan.com/5268/
- https://tech.kakao.com/posts/391
- https://daleseo.com/websocket/
- https://kakaoentertainment-tech.tistory.com/110

**Socket.IO**
- https://socket.io/docs/v4/
- https://inpa.tistory.com/entry/SOCKET-%F0%9F%93%9A-Namespace-Room-%EA%B8%B0%EB%8A%A5
- https://adjh54.tistory.com/549
- https://fred16157.github.io/node.js/nodejs-socketio-communication-room-and-namespace/

**SSE (Server-Sent Events)**
- https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events
- https://developer.mozilla.org/ko/docs/Web/API/Server-sent_events/Using_server-sent_events
- https://api7.ai/ko/blog/what-is-sse

**TCP / UDP Socket**
- https://docs.python.org/3/library/socket.html
- https://inpa.tistory.com/entry/NW-%F0%9F%8C%90-%EC%95%84%EC%A7%81%EB%8F%84-%EB%AA%A8%ED%98%B8%ED%95%9C-TCP-UDP-%EA%B0%9C%EB%85%90-%E2%9D%93-%EC%89%BD%EA%B2%8C-%EC%9D%B4%ED%95%B4%ED%95%98%EC%9E%90

**gRPC Streaming**
- https://grpc.io/docs/what-is-grpc/core-concepts/
- https://tech.ktcloud.com/entry/gRPC%EC%9D%98-%EB%82%B4%EB%B6%80-%EA%B5%AC%EC%A1%B0-%ED%8C%8C%ED%97%A4%EC%B9%98%EA%B8%B0-HTTP2-Protobuf-%EA%B7%B8%EB%A6%AC%EA%B3%A0-%EC%8A%A4%ED%8A%B8%EB%A6%AC%EB%B0%8D
- https://tech.ktcloud.com/entry/gRPC%EC%9D%98-%EB%82%B4%EB%B6%80-%EA%B5%AC%EC%A1%B0-%ED%8C%8C%ED%97%A4%EC%B9%98%EA%B8%B02-Channel-Stub
- https://inspirit941.tistory.com/371
- https://devocean.sk.com/blog/techBoardDetail.do?ID=167433

**WebRTC**
- https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API
- https://webrtc.org/getting-started/overview
- https://web.dev/articles/webrtc-basics?hl=ko
- https://devocean.sk.com/blog/techBoardDetail.do?ID=164885
- https://beomkey-nkb.github.io/%EA%B0%9C%EB%85%90%EC%A0%95%EB%A6%AC/webRTC%EC%A0%95%EB%A6%AC/
- https://gh402.tistory.com/45
- https://on.com2us.com/tech/webrtc-coturn-turn-stun-server-setup-guide/

**QUIC / WebTransport**
- https://developer.mozilla.org/en-US/docs/Web/API/WebTransport_API
- https://datatracker.ietf.org/doc/html/rfc9000
- https://news.hada.io/topic?id=13888

#### KCLOUD VM / Cloudflare Tunnel 환경별 주의사항

| 환경 | 사용 가능(권장) 기술 | 포트/조건 | 주의할 기술 |
|---|---|---|---|
| **로컬 / 일반 VM** | HTTP/REST, WebSocket, Socket.IO, SSE, TCP Socket, gRPC Streaming, WebRTC, QUIC/WebTransport 등 대부분 가능 | 직접 포트 개방 가능. 예: 3000, 5000, 8000, 8080, 9000 등. 외부 공개 시 방화벽/보안그룹/공인 IP 설정 필요 | WebRTC는 STUN/TURN 필요 가능. QUIC/WebTransport는 HTTP/3 · UDP 지원 필요 |
| **KCLOUD VM (VPN 내부)** | HTTP/REST, WebSocket, Socket.IO, SSE, WebRTC 시그널링 | 접속 기기 VPN 필요. 기본 허용 포트: **22, 80, 443**. 개발 포트(3000, 8000, 8080 등)는 직접 접근 제한 가능 | TCP Socket은 포트 제한 있음. gRPC는 HTTP/2 설정 필요. WebRTC 미디어·UDP·QUIC/WebTransport 비권장 |
| **KCLOUD VM + Tunnel** | HTTP/REST, WebSocket, Socket.IO, SSE, WebRTC 시그널링 | VM의 `localhost:<port>`를 도메인에 연결. `localPort`는 **1024~65535**. 예: 3000, 8000, 8080 가능 | 순수 TCP Socket, UDP, WebRTC 미디어/DataChannel, QUIC/WebTransport 불가. gRPC 보장 어려움 |
| **외부 서비스 + 우리 도메인** | HTTP/REST, WebSocket, Socket.IO, SSE, WebRTC 시그널링 | Vercel/Netlify/Railway/Render/AWS/GCP 등에 배포 후 CNAME/A 레코드 연결. 보통 외부는 **443** 사용 | WebSocket/gRPC/TCP/UDP는 플랫폼 지원 여부 확인 필요. 서버리스 플랫폼은 장시간 연결 제한 가능 |
| **서버 없이 외부 SaaS 사용** | Supabase Realtime, Firebase, Pusher/Ably, LLM API Streaming | 직접 포트 관리 불필요. 각 서비스 SDK/API 사용 | 커스텀 TCP/UDP 서버 구현 불가. WebRTC는 STUN/TURN 필요할 수 있음 |

### LLM Wrapper

- https://github.com/teddylee777/openai-api-kr
- https://github.com/teddylee777/langchain-kr
- https://devocean.sk.com/blog/techBoardDetail.do?ID=167407
- https://mastra.ai/docs

### Cross-Platform

- https://flutter.dev/
- https://reactnative.dev/
- https://docs.expo.dev/
- https://kotlinlang.org/multiplatform/
