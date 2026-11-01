# SchoolPro Admin Web

Flutter Web Admin console for Firebase project `school-e8d44`.

Run locally:

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
```

Build for Firebase Hosting from the repository root:

```bash
cd admin/SchoolPro-Admin && flutter build web --release
cd ../..
firebase deploy --only hosting --project school-e8d44
```

Admin access requires a Firebase Authentication user with the server-issued custom claim `admin: true`. Do not add the claim from a client app. See the root `README_UR.md` and `QA_REPORT_RC7_UR.md` for workflows, verification status, and limitations.
