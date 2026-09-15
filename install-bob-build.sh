#!/usr/bin/env bash
# install-bob-build.sh
# Finish a Bob build update: quit Orca-Bob, swap the app bundle, re-enable Bob,
# and relaunch. Safe to run from a plain Terminal/iTerm window.
#
# Run this AFTER ./update-bob-build.sh + the rebuild/repackage have produced
# dist/mac-arm64/Orca.app. It does not build anything itself.
set -euo pipefail

REPO="/Users/wojciech/Workspace/orca-bob"
BUILT_APP="$REPO/dist/mac-arm64/Orca.app"
TARGET_APP="/Applications/Orca-Bob.app"

say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# --- preflight ---------------------------------------------------------------
say "Preflight checks"
[ -d "$BUILT_APP" ] || die "built app not found at $BUILT_APP (run ./update-bob-build.sh + rebuild first)"

# Refuse to run from inside Orca-Bob: quitting it would kill this script.
if [ "${TERM_PROGRAM:-}" = "Orca" ]; then
  die "You are inside an Orca session. Open a plain Terminal/iTerm window and run this there."
fi

BUILT_VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$BUILT_APP/Contents/Info.plist")
echo "built version: $BUILT_VER"
file "$BUILT_APP/Contents/MacOS/Orca" | grep -q arm64 || die "built binary is not arm64"
codesign --verify --deep --strict "$BUILT_APP" 2>/dev/null || die "code signature invalid on built app"
echo "arch + signature OK"

# --- quit running apps -------------------------------------------------------
say "Quit Orca-Bob (and stock Orca if open)"
osascript -e 'quit app "Orca-Bob"' 2>/dev/null || true
osascript -e 'quit app "Orca"' 2>/dev/null || true

# Wait for both to actually exit (up to ~30s), then hard-stop stragglers.
for i in $(seq 1 30); do
  if ! pgrep -f "/Applications/Orca-Bob.app/Contents/MacOS/Orca" >/dev/null \
     && ! pgrep -f "/Applications/Orca.app/Contents/MacOS/Orca" >/dev/null; then
    break
  fi
  sleep 1
done
if pgrep -f "/Applications/Orca-Bob.app/Contents/MacOS/Orca" >/dev/null; then
  echo "Orca-Bob still running after 30s; sending TERM"
  pkill -f "/Applications/Orca-Bob.app/Contents/MacOS/Orca" || true
  sleep 3
fi
pgrep -f "/Applications/Orca-Bob.app/Contents/MacOS/Orca" >/dev/null \
  && die "Orca-Bob will not quit; close it manually and re-run" || echo "Orca-Bob is closed"

# --- back up old app ---------------------------------------------------------
if [ -d "$TARGET_APP" ]; then
  OLD_VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$TARGET_APP/Contents/Info.plist" 2>/dev/null || echo "unknown")
  BAK="/Applications/Orca-Bob-bak-$(date +%Y%m%d-%H%M%S).app"
  say "Back up current Orca-Bob ($OLD_VER) -> $BAK"
  ditto "$TARGET_APP" "$BAK"
fi

# --- swap in the new build ---------------------------------------------------
say "Install new build -> $TARGET_APP"
rm -rf "$TARGET_APP"
ditto "$BUILT_APP" "$TARGET_APP"
NEW_VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$TARGET_APP/Contents/Info.plist")
echo "installed version: $NEW_VER"

# --- re-enable Bob in settings ----------------------------------------------
say "Re-assert Bob-enabled settings"
# enable-bob.py refuses if an Orca is running; both are quit by now.
python3 "$REPO/enable-bob.py"

# --- launch ------------------------------------------------------------------
say "Launch updated Orca-Bob"
open "$TARGET_APP"

say "Done. Orca-Bob is now $NEW_VER"
echo "If anything is wrong, the previous build is at the Orca-Bob-bak-*.app backup."
