#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_URL="https://github.com/pkridepakistan555/SchoolPro-Mobile.git"
TARGET="schoolpro-rc7"

if [[ "${1:-}" == "--main" ]]; then
  echo "STOP: Main branch push is disabled in this release script."
  exit 20
fi

command -v git >/dev/null 2>&1 || { echo "Git required"; exit 10; }
command -v rsync >/dev/null 2>&1 || { echo "rsync required"; exit 11; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Cloning repository main branch..."
git clone --branch main --single-branch "$REPO_URL" "$TMP/repo"

cd "$TMP/repo"

echo "Fetching existing RC7 branch..."
git fetch origin "refs/heads/$TARGET"

echo "Creating local branch from fetched remote commit..."
git switch -c "$TARGET" FETCH_HEAD

echo "Overlaying RC7 source (unrelated remote files preserved)..."
rsync -a \
  --exclude='.git/' \
  --exclude='.dart_tool/' \
  --exclude='build/' \
  --exclude='node_modules/' \
  --exclude='.firebase/' \
  --exclude='.env' \
  --exclude='.env.*' \
  --exclude='local.properties' \
  --exclude='key.properties' \
  --exclude='*.jks' \
  --exclude='*.keystore' \
  --exclude='*.pem' \
  --exclude='*.p12' \
  --exclude='*.key' \
  --exclude='service-account*.json' \
  --exclude='firebase-debug*.log' \
  --exclude='google-services.json' \
  --exclude='*.apk' \
  "$ROOT/" "$TMP/repo/"

git add -A

if git diff --cached --quiet; then
  echo "No source changes to commit."
else
  git -c user.name='SchoolPro Release Bot' \
      -c user.email='schoolpro-release@users.noreply.github.com' \
      commit -m "SchoolPro RC7: fixes and release verification"
fi

echo "Pushing non-force to origin/$TARGET..."
git push origin "HEAD:refs/heads/$TARGET"

echo
echo "PUSH SUCCESSFUL"
echo "Branch: $TARGET"
echo "Repository: https://github.com/pkridepakistan555/SchoolPro-Mobile/tree/$TARGET"
