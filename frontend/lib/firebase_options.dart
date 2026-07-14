// ignore_for_file: type=lint
// Web 설정값은 Firebase 콘솔 > 프로젝트 설정 > 일반 > "내 앱"의 웹 앱에서 채웠다
// (비밀 정보 아님 — 클라이언트 번들에 그대로 노출되는 값이라 커밋해도 안전).
//
// android/ios는 아직 플레이스홀더 — 해당 플랫폼 앱을 Firebase 콘솔에 추가로 등록하고
// 나온 값으로 교체하거나, `dart pub global activate flutterfire_cli` 후
// `flutterfire configure`를 실행하면 세 플랫폼을 한 번에 채울 수 있다.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions는 이 플랫폼을 지원하지 않습니다 — web/android/iOS만 구성했습니다.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDx-moBYDAgpGVM2hbfNKumwdHQ2Y0rOwg',
    appId: '1:372020945949:web:6ff5af9cfc84719f6112f4',
    messagingSenderId: '372020945949',
    projectId: 'l-ai-r-game',
    authDomain: 'l-ai-r-game.firebaseapp.com',
    storageBucket: 'l-ai-r-game.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC1D0_PTxOxx_hw6pRZLxVw4G2gIT9P4yE',
    appId: '1:372020945949:android:2c060dd5065e474e6112f4',
    messagingSenderId: '372020945949',
    projectId: 'l-ai-r-game',
    storageBucket: 'l-ai-r-game.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'TODO-FIREBASE-IOS-API-KEY',
    appId: 'TODO-FIREBASE-IOS-APP-ID',
    messagingSenderId: 'TODO-FIREBASE-MESSAGING-SENDER-ID',
    projectId: 'TODO-FIREBASE-PROJECT-ID',
    storageBucket: 'TODO-FIREBASE-PROJECT-ID.appspot.com',
    iosBundleId: 'com.example.madcampW2Frontend',
  );
}
