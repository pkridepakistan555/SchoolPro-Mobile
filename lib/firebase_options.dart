import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Public Firebase client configuration for SchoolPro's registered Android
/// and Web apps. Never put service-account credentials in this file.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError('SchoolPro currently configures Android and Web only.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC0SC35WAOn_d_3RsQLxqnv2y1SqxAHnk4',
    appId: '1:276247842578:android:8407c0fa4d0f43979c2dcb',
    messagingSenderId: '276247842578',
    projectId: 'school-e8d44',
    storageBucket: 'school-e8d44.firebasestorage.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyC0SC35WAOn_d_3RsQLxqnv2y1SqxAHnk4',
    appId: '1:276247842578:web:c700c924c9cf0e039c2dcb',
    messagingSenderId: '276247842578',
    projectId: 'school-e8d44',
    authDomain: 'school-e8d44.firebaseapp.com',
    storageBucket: 'school-e8d44.firebasestorage.app',
    measurementId: 'G-62TQ5LX2N5',
  );
}
