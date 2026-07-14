import 'dart:convert';

import 'package:http/http.dart' as http;

import '../services/auth_service.dart';
import 'backend_config.dart';

class BackendApiException implements Exception {
  final int statusCode;
  final String message;
  BackendApiException(this.statusCode, this.message);

  @override
  String toString() => 'BackendApiException($statusCode): $message';
}

/// PLAN "REST API (전적·친구)" 참고. 실시간성이 필요 없는 전적/친구 CRUD는
/// Socket.IO가 아니라 REST로 처리하고, Firebase ID 토큰을 Bearer로 싣는다.
class BackendApi {
  BackendApi._();
  static final BackendApi instance = BackendApi._();

  Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.instance.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path) => Uri.parse('${BackendConfig.httpBaseUrl}$path');

  /// 닉네임 중복 확인. 인증 불필요(회원가입 폼에서 로그인 전에도 호출된다).
  Future<bool> isNicknameAvailable(String nickname) async {
    final res = await http.get(
      _uri('/api/users/nickname-availability/${Uri.encodeComponent(nickname)}'),
    );
    _checkOk(res);
    return (jsonDecode(res.body) as Map<String, dynamic>)['available'] as bool;
  }

  /// 회원가입/닉네임 변경 직후 로컬 DB에 즉시 반영. Firebase ID 토큰의 name 클레임은
  /// updateDisplayName 직후 바로 갱신되지 않을 수 있어(토큰이 캐시돼 있으면 다음 자연
  /// 갱신 전까지 옛 값), 닉네임을 body로 명시적으로 보내 그 지연과 무관하게 로컬 User
  /// 행을 즉시 생성/갱신한다 — 친구 요청(FK: Friendship.addresseeId → User.uid) 등이
  /// 가입 직후에도 바로 동작하게 하기 위함.
  Future<void> syncNickname(String nickname) async {
    final res = await http.put(
      _uri('/api/users/me'),
      headers: await _authHeaders(),
      body: jsonEncode({'nickname': nickname}),
    );
    _checkOk(res, allow204: true);
  }

  /// 로그인 시 프리셋 인덱스·업로드 사진을 복원하기 위한 프로필 조회.
  Future<UserProfile> getMyProfile() async {
    final res = await http.get(_uri('/api/users/me/profile'), headers: await _authHeaders());
    _checkOk(res);
    return UserProfile.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// 프로필 사진 저장. [avatarUrl]은 Firebase Storage(avatars/{uid})에 먼저 업로드한
  /// 다운로드 URL이어야 한다. null을 넘기면 사진을 지우고 기본 아이콘으로 되돌린다.
  Future<void> updateAvatarUrl(String? avatarUrl) async {
    final res = await http.patch(
      _uri('/api/users/me/avatar'),
      headers: await _authHeaders(),
      body: jsonEncode({'avatarUrl': avatarUrl}),
    );
    _checkOk(res, allow204: true);
  }

  Future<UserStats> getMyStats() async {
    final res = await http.get(_uri('/api/users/me'), headers: await _authHeaders());
    _checkOk(res);
    return UserStats.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<UserStats> getUserStats(String uid) async {
    final res = await http.get(_uri('/api/users/$uid'), headers: await _authHeaders());
    _checkOk(res);
    return UserStats.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// 임의 uid의 닉네임/프로필 사진 조회(getMyProfile의 타인 버전). 채팅 아바타 등에서
  /// 방 참가자의 실제 프로필 사진을 보여주기 위해 쓴다.
  Future<UserProfile> getUserProfile(String uid) async {
    final res = await http.get(_uri('/api/users/$uid/profile'), headers: await _authHeaders());
    _checkOk(res);
    return UserProfile.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// 회원탈퇴. 백엔드가 Firebase 계정 삭제까지 함께 처리하므로 프론트는 이 호출 하나면 끝난다
  /// (Firebase와 직접 통신하지 않음).
  Future<void> deleteMyAccount() async {
    final res = await http.delete(_uri('/api/users/me'), headers: await _authHeaders());
    _checkOk(res, allow204: true);
  }

  Future<void> sendFriendRequest(String addresseeUid) async {
    final res = await http.post(
      _uri('/api/friends/requests'),
      headers: await _authHeaders(),
      body: jsonEncode({'addresseeUid': addresseeUid}),
    );
    _checkOk(res, allow201: true);
  }

  /// 닉네임으로 친구 요청(친구 추가 UI). 서버가 닉네임→uid를 해석한다. 없으면 404.
  Future<void> sendFriendRequestByNickname(String nickname) async {
    final res = await http.post(
      _uri('/api/friends/requests'),
      headers: await _authHeaders(),
      body: jsonEncode({'addresseeNickname': nickname}),
    );
    _checkOk(res, allow201: true);
  }

  Future<List<FriendRequestSummary>> getPendingFriendRequests() async {
    final res = await http.get(_uri('/api/friends/requests'), headers: await _authHeaders());
    _checkOk(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['requests'] as List)
        .map((e) => FriendRequestSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> acceptFriendRequest(String requestId) async {
    final res = await http.post(
      _uri('/api/friends/requests/$requestId/accept'),
      headers: await _authHeaders(),
    );
    _checkOk(res);
  }

  Future<void> declineFriendRequest(String requestId) async {
    final res = await http.post(
      _uri('/api/friends/requests/$requestId/decline'),
      headers: await _authHeaders(),
    );
    _checkOk(res, allow204: true);
  }

  Future<List<FriendSummary>> getFriends() async {
    final res = await http.get(_uri('/api/friends'), headers: await _authHeaders());
    _checkOk(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['friends'] as List)
        .map((e) => FriendSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> removeFriend(String uid) async {
    final res = await http.delete(_uri('/api/friends/$uid'), headers: await _authHeaders());
    _checkOk(res, allow204: true);
  }

  void _checkOk(http.Response res, {bool allow201 = false, bool allow204 = false}) {
    final ok = res.statusCode == 200 ||
        (allow201 && res.statusCode == 201) ||
        (allow204 && res.statusCode == 204);
    if (ok) return;

    String message = res.body;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['error'] is String) {
        message = decoded['error'] as String;
      }
    } catch (_) {
      // 본문이 JSON이 아니면 원문 그대로 사용.
    }
    throw BackendApiException(res.statusCode, message);
  }
}

class UserStats {
  final int totalGames;
  final double? overallWinRate;
  final double? liarWinRate;
  final double? citizenWinRate;
  final int exp; // 누적 경험치(EXP)(단조증가, 서버 DB 저장값). PLAN "경험치(EXP) 및 레벨 정책" 참고
  final int level; // exp 기반 파생 레벨(비선형 구간, PLAN "레벨 구간" 참고)

  const UserStats({
    required this.totalGames,
    required this.overallWinRate,
    required this.liarWinRate,
    required this.citizenWinRate,
    required this.exp,
    required this.level,
  });

  /// 레벨 L의 누적 EXP 임계값: 100*(L-1) + 15*(L-1)*(L-2) (L=1이면 0). 서버와 동일 공식.
  static int levelThreshold(int level) {
    if (level <= 1) return 0;
    return 100 * (level - 1) + 15 * (level - 1) * (level - 2);
  }

  /// 현재 레벨 안에서의 진행도(0.0~1.0).
  double get levelProgress {
    final start = levelThreshold(level);
    final next = levelThreshold(level + 1);
    final span = next - start;
    if (span <= 0) return 1;
    return ((exp - start) / span).clamp(0, 1).toDouble();
  }

  /// 다음 레벨까지 남은 EXP.
  int get expToNextLevel => (levelThreshold(level + 1) - exp).clamp(0, 1 << 30);

  factory UserStats.fromJson(Map<String, dynamic> json) {
    return UserStats(
      totalGames: json['totalGames'] as int,
      overallWinRate: (json['overallWinRate'] as num?)?.toDouble(),
      liarWinRate: (json['liarWinRate'] as num?)?.toDouble(),
      citizenWinRate: (json['citizenWinRate'] as num?)?.toDouble(),
      exp: json['exp'] as int? ?? 0,
      level: json['level'] as int? ?? 1,
    );
  }
}

class UserProfile {
  final String? nickname;
  final String? avatarUrl;

  const UserProfile({required this.nickname, required this.avatarUrl});

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      nickname: json['nickname'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}

class FriendSummary {
  final String uid;
  final String nickname;
  final String? avatarUrl;
  final int level;
  final bool isOnline;

  const FriendSummary({
    required this.uid,
    required this.nickname,
    required this.avatarUrl,
    this.level = 1,
    this.isOnline = false,
  });

  factory FriendSummary.fromJson(Map<String, dynamic> json) {
    return FriendSummary(
      uid: json['uid'] as String,
      nickname: json['nickname'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      level: (json['level'] as num?)?.toInt() ?? 1,
      isOnline: json['isOnline'] as bool? ?? false,
    );
  }
}

class FriendRequestSummary {
  final String id;
  final String requesterUid;
  final String requesterNickname;

  const FriendRequestSummary({
    required this.id,
    required this.requesterUid,
    required this.requesterNickname,
  });

  factory FriendRequestSummary.fromJson(Map<String, dynamic> json) {
    final requester = json['requester'] as Map<String, dynamic>;
    return FriendRequestSummary(
      id: json['id'] as String,
      requesterUid: requester['uid'] as String,
      requesterNickname: requester['nickname'] as String,
    );
  }
}
