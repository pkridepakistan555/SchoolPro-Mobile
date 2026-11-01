#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="school-e8d44"
MODE="check"
for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    --deploy) MODE="deploy" ;;
    *) echo "Unknown argument: $arg"; echo "Usage: bash scripts/schoolpro_release.sh [--check|--deploy]"; exit 2 ;;
  esac
done
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1"; exit 10; }; }
need flutter; need dart; need node; need npm; need firebase; need java
cd "$ROOT"
echo "== Source syntax/config preflight =="
node --check functions/index.js
node --check functions/notice_notifications.js
node --check tests/rules.test.js
node --check tests/functions.test.js
node -e "JSON.parse(require('fs').readFileSync('firebase.json','utf8')); JSON.parse(require('fs').readFileSync('firestore.indexes.json','utf8')); console.log('Firebase JSON configuration: OK')"
cmp -s firestore.rules admin/SchoolPro-Admin/firestore.rules || { echo 'Root/Admin Firestore rules differ.'; exit 11; }
echo "== Dependencies =="
npm ci --prefix functions
npm ci --prefix tests

echo "== Admin Web analyze/test/build =="
cd "$ROOT/admin/SchoolPro-Admin"
flutter pub get
flutter analyze
flutter test
flutter build web --release

echo "== Android app analyze/test/build =="
cd "$ROOT"
flutter pub get
flutter analyze
flutter test
# Debug signing is intentional for verification. A Play Store release needs a
# separately configured private upload key and signing configuration.
flutter build apk --debug

echo "== Firestore/Storage emulator rules tests =="
cd "$ROOT"
firebase emulators:exec --project schoolpro-rules-test --only firestore,storage "npm --prefix tests test"
echo "== Local verification complete =="
if [[ "$MODE" == "deploy" ]]; then
  echo "Deploying SchoolPro Functions, Firestore/Storage rules, indexes and Admin Hosting to $PROJECT..."
  firebase deploy --only functions,firestore:rules,firestore:indexes,storage,hosting --project "$PROJECT"
  echo "Firebase deployment command completed. Run live role-based smoke tests before onboarding users."
else
  echo "No live deployment performed. After reviewing all successful checks, run:"
  echo "bash scripts/schoolpro_release.sh --deploy"
fi
