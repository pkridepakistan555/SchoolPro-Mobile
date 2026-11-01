import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    throw UnsupportedError('SchoolPro Admin Web is configured for web only.');
  }

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
