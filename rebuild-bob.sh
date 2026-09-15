#!/usr/bin/env bash
# rebuild-bob.sh
# Full one-command update for the local IBM Bob build:
#   git refresh (PR + main + local commits, version bump)  ->  rebuild
#   ->  arm64 package  ->  quit/swap/enable/relaunch.
#
# RUN FROM A PLAIN TERMINAL / iTerm WINDOW, *not* from inside Orca-Bob:
# the final install step quits Orca-Bob, which would kill this script if it
# were hosting the session. The script refuses to start inside an Orca session.
#
# Usage:
#   cd /Users/wojciech/Workspace/orca-bob && ./rebuild-bob.sh
#   ./rebuild-bob.sh --skip-update    # rebuild+install only, no git refresh
#   ./rebuild-bob.sh --no-tests       # skip the Bob unit tests
set -euo pipefail

REPO="/Users/wojciech/Workspace/orca-bob"
export COREPACK_ENABLE_STRICT=0

SKIP_UPDATE=0
RUN_TESTS=1
for a in "$@"; do
  case "$a" in
    --skip-update) SKIP_UPDATE=1 ;;
    --no-tests)    RUN_TESTS=0 ;;
    *) echo "unknown flag: $a" >&2; exit 2 ;;
  esac
done

say() { printf '\n\033[1;36m======== %s ========\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

cd "$REPO"

# Refuse to run inside Orca: the install step quits Orca-Bob at the end.
if [ "${TERM_PROGRAM:-}" = "Orca" ]; then
  die "You are inside an Orca session. Open a plain Terminal/iTerm window and run this there."
fi

# --- 1. git refresh ----------------------------------------------------------
if [ "$SKIP_UPDATE" -eq 0 ]; then
  say "1/6  Refresh branch (latest PR + main + local commits, version bump)"
  ./update-bob-build.sh
else
  say "1/6  Skipping git refresh (--skip-update)"
fi

# --- 2. dependencies ---------------------------------------------------------
say "2/6  Install dependencies (frozen lockfile)"
pnpm install --frozen-lockfile

# --- 3. typecheck ------------------------------------------------------------
say "3/6  Typecheck"
pnpm run typecheck || die "typecheck failed; fix before building"

# --- 4. Bob unit tests -------------------------------------------------------
if [ "$RUN_TESTS" -eq 1 ]; then
  say "4/6  Bob unit tests"
  npx vitest run --config config/vitest.config.ts \
    src/relay/preflight-handler.test.ts \
    src/main/agent-hooks/managed-hook-detection-commands.test.ts \
    src/main/agent-hooks/managed-hook-identity-gate.test.ts \
    src/shared/bob-approval-prompt.test.ts \
    || die "Bob unit tests failed"
else
  say "4/6  Skipping unit tests (--no-tests)"
fi

# --- 5. build + arm64 package -----------------------------------------------
say "5/6  Build native helpers + desktop bundle, then package arm64"
# build:mac builds everything; its final universal-packaging step fails on this
# CLT-only machine (no x64 native variants). We tolerate that and package arm64
# ourselves below, which is all we install.
pnpm run build:mac || echo "(expected: universal packaging step skipped; packaging arm64 directly)"

IDENT_JSON=$(node -e "import('./config/scripts/build-mac-local.mjs').then(m=>console.log(JSON.stringify(m.getLocalBuildIdentity())))")
BUILD_COMMIT=$(node -e "console.log(JSON.parse(process.argv[1]).commit)" "$IDENT_JSON")
BUILD_VERSION=$(node -e "console.log(JSON.parse(process.argv[1]).version)" "$IDENT_JSON")
echo "packaging version: $BUILD_VERSION"

CI= ELECTRON_BUILDER_ALLOW_UNRESOLVED_DEPENDENCIES=true \
  ORCA_BUILD_COMMIT="$BUILD_COMMIT" ORCA_LOCAL_BUILD_VERSION="$BUILD_VERSION" \
  npx electron-builder --config config/electron-builder.config.cjs --mac dir --arm64 --publish never \
  || die "arm64 packaging failed"

[ -d "$REPO/dist/mac-arm64/Orca.app" ] || die "packaged app not found after build"

# --- 6. install (quit / swap / enable / relaunch) ---------------------------
say "6/6  Install: quit Orca-Bob, swap bundle, enable Bob, relaunch"
./install-bob-build.sh

say "ALL DONE"
