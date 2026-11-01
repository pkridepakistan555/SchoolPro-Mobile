#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_URL="https://github.com/pkridepakistan555/SchoolPro-Mobile.git"
TARGET="schoolpro-rc7"
if [[ "${1:-}" == "--main" ]]; then TARGET="main"; fi
command -v git >/dev/null 2>&1 || { echo 'Git is required.'; exit 10; }
command -v rsync >/dev/null 2>&1 || { echo 'rsync is required (pkg install rsync).'; exit 11; }
TMP="$(mktemp -d)"
cleanup(){ rm -rf "$TMP"; }
trap cleanup EXIT

echo "Cloning the current public repository main branch (no force push)..."
git clone --branch main --single-branch "$REPO_URL" "$TMP/repo"
cd "$TMP/repo"
if [[ "$TARGET" != "main" ]]; then
  git fetch origin "$TARGET:refs/remotes/origin/$TARGET" 2>/dev/null || true
  if git show-ref --verify --quiet "refs/remotes/origin/$TARGET"; then
    git switch -c "$TARGET" --track "origin/$TARGET"
  else
    git switch -c "$TARGET"
  fi
fi

echo "Copying RC7 source over the existing repository without deleting unrelated files..."
rsync -a --exclude='.git/' --exclude='.dart_tool/' --exclude='build/' --exclude='node_modules/' \
  --exclude='.firebase/' --exclude='.env' --exclude='.env.*' --exclude='local.properties' --exclude='key.properties' \
  --exclude='*.jks' --exclude='*.keystore' --exclude='*.pem' --exclude='*.p12' --exclude='*.key' \
  --exclude='service-account*.json' --exclude='firebase-debug*.log' \
  --exclude='google-services.json' --exclude='*.apk' --exclude='*.aab' \
  "$ROOT/" "$TMP/repo/"

git add -A
if git diff --cached --quiet; then echo 'No source changes to commit.'; exit 0; fi
git -c user.name='SchoolPro Release Bot' -c user.email='schoolpro-release@users.noreply.github.com' \
  commit -m "SchoolPro RC7: complete workflows, profile, finance and security upgrades"

echo "Pushing to origin/$TARGET (non-force; a moved branch will be rejected safely)..."
git push origin "HEAD:refs/heads/$TARGET"
echo "Push complete: https://github.com/pkridepakistan555/SchoolPro-Mobile/tree/$TARGET"
if [[ "$TARGET" != "main" ]]; then
  echo 'Run the GitHub Actions workflow on this branch. Merge to main only after every CI job passes.'
fi
