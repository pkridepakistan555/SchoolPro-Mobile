# SchoolPro source update — 2026-10-29

## Included in this update
- Registration application form with applicant role (student/teacher/parent), name, phone, guardian, address, class/qualification and profile photo.
- Profile image upload to Firebase Storage.
- Admin approval list displays applicant name, role, email, phone and profile image.
- Approval transaction assigns unique `TCH-YYYY-####` or `STU-YYYY-####` identifiers using `systemCounters`.
- In-app digital profile/ID card view.
- Firestore-backed views for classes, fees, exams, homework, announcements, and teachers.
- Local Firestore and Storage rules drafts.
- One-pass Termux build/verification script.

## Not yet verified or not fully implemented
- No Flutter/Dart SDK is available in the build environment used to prepare this archive, so `flutter pub get`, `flutter analyze`, APK build and device runtime tests could not be executed here.
- SMS OTP sign-in/reset UI is not complete. Firebase email verification and email password reset remain available; SMS provider configuration and an end-to-end phone OTP flow are still required.
- FCM push notifications are not complete. In-app announcements are included; push delivery needs Firebase Messaging integration and device tests.
- Parent-to-child linking, granular data filtering for every class/result/fee record, edit workflows, report exports, and full exam/results workflows need further implementation and tests before production release.
- `google-services.json` is intentionally excluded from the source ZIP. The build script attempts to download it using Firebase CLI if authenticated, otherwise it instructs the user to restore the existing file.
- `firestore.rules` and `storage.rules` are local proposals only. They have not been deployed or tested against the live Admin Web and existing production data.
- The Admin Web source was not included in the uploaded ZIP and therefore was not modified.
