# SchoolPro

Flutter + Firebase school management app.

## Implemented in this source update
- Email/password registration and login with Firebase email verification and password-reset email.
- Role-based registration application for student, teacher, or parent with profile fields and mandatory profile photo upload to Firebase Storage.
- Admin approval queue showing applicant profile information.
- Admin manually enters Student ID and Admission Number as separate values, or a Teacher ID. Approval rejects invalid/duplicate identifiers using an admin-only ID registry and creates/updates the linked student or teacher record. IDs are not auto-generated.
- Profile / digital ID card view in the app.
- Functional Firestore-backed classes, fees, exams/results, homework, and announcements list/create screens (exact access depends on deployed rules and user role).
- Proposed Firestore and Storage security rules are included locally.

## Required Firebase setup before production use
1. Confirm Firebase project `school-e8d44` and registered Android package `com.schoolpro.schoolpro`.
2. Enable Email/Password in Firebase Authentication and configure email templates/action URLs.
3. Configure Firebase Storage bucket and billing/region as appropriate.
4. Deploy the reviewed `firestore.rules` and `storage.rules` only after testing them against the live Admin Web and existing data.
5. Ensure the designated administrator has the trusted custom claim `admin: true`; never grant this claim from the app itself.
6. Configure SMS/phone authentication separately in Firebase Console. This source version does **not** yet implement a complete SMS OTP sign-in/reset UI; email verification and email password reset are implemented. SMS delivery may incur charges and requires phone provider configuration.
7. Push notifications require an FCM integration and platform setup; in-app announcements are implemented here, but push notifications are not claimed as active until configured and tested.
8. Review role-to-child linking for parent accounts before allowing parents to view individual student records.

## Important
- No live Firebase deployment was performed by this source package build.
- Existing Admin Web is not included in this ZIP, so it was not changed.
- Firestore and Storage rules are proposed local files and must be tested before deployment.
- Test on a real Android device and against a staging Firebase project before production release.

## One-pass local build
Run `bash schoolpro_build_verify.sh` from the project folder in Termux. It creates a backup, checks/fetches Firebase Android configuration, runs `flutter pub get`, `flutter analyze`, and builds a debug APK in one pass. It does not deploy Firebase rules or Hosting.

See `CHANGELOG_SCHOOLPRO_UPDATE.md` for the changes and remaining limitations. Run `bash schoolpro_build_verify.sh` for local static checks and a debug APK build; this script never deploys Firebase rules or pushes to GitHub. This package must not be treated as production-ready until the outstanding authentication, push-notification, role-data isolation and runtime-test items are completed.
