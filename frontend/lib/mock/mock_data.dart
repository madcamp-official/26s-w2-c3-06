// [MOCK] 백엔드에 대응 엔드포인트가 없어 남겨둔 UI 데모용 목데이터.
//
// 회원가입 폼의 이메일/아이디 중복확인용 — 백엔드는 이메일 사전확인 엔드포인트가 없고
// (가입 시 Firebase가 email-already-in-use로 처리), 별도 아이디(userId) 개념 자체가 없다.
// (닉네임 중복확인은 백엔드 실연동으로 대체됨 — signup_screen 참고.)
//
// 그 외 방 목록/제시어/봇/친구 목데이터는 모두 서버 실연동으로 대체되어 제거했다.

/// [MOCK] 이미 가입되어 있다고 가정하는 이메일 목록(가입 폼 중복확인 데모용).
const mockTakenEmails = <String>['test@example.com', 'liar@game.com'];

/// [MOCK] 이미 사용 중이라고 가정하는 아이디 목록(백엔드에 userId 개념 없음 — 데모용).
const mockTakenUserIds = <String>['admin', 'liarking'];
