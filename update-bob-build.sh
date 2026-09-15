#!/usr/bin/env bash
# Update the local IBM Bob build to the latest PR + main.
# Re-applies our local commits (version bump, build fixes, enable-bob.py)
# on top of the freshest PR head. Handles the PR being rebased/force-pushed.
set -euo pipefail

REPO="/Users/wojciech/Workspace/orca-bob"
PR_NUM=20397
# Local commits are discovered dynamically (see step 5): everything after the
# marker commit, minus merges and version bumps. No hand-maintained list.


cd "$REPO"

# Marker = the commit just below our local work on the current branch
# (the "PR + main" merge tip). Everything after it, minus merges, is ours.
BASE_FILE=".bob-local-base"
if [ ! -f "$BASE_FILE" ]; then
  echo "ERROR: $BASE_FILE missing. Create it with the sha below your local commits:"
  echo "  echo c283a39f27 > $BASE_FILE   # our upstream/main merge commit"
  exit 1
fi
LOCAL_BASE=$(tr -d '[:space:]' < "$BASE_FILE")
echo "local commits are everything after: $(git log -1 --format='%h %s' "$LOCAL_BASE")"

echo "== 1. Save current branch as a dated backup =="
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_BRANCH="bob-integration-bak-$STAMP"
git branch "$BACKUP_BRANCH" bob-integration
echo "backup branch: $BACKUP_BRANCH"

echo "== 2. Fetch latest PR head and main =="
git fetch upstream main
git fetch --tags upstream
git fetch -f upstream "refs/pull/${PR_NUM}/head:pr-${PR_NUM}-new"

PR_NEW=$(git rev-parse "pr-${PR_NUM}-new")
echo "latest PR head: $PR_NEW"

echo "== 3. Recreate branch from the latest PR head =="
git checkout -B bob-integration "pr-${PR_NUM}-new"

echo "== 4. Merge latest upstream/main (PR may already include most of it) =="
if git merge upstream/main --no-edit; then
  echo "merge clean"
else
  echo "!! merge conflicts -- resolve them, 'git add', then 'git merge --continue', then re-run from step 5 manually"
  exit 2
fi
# The tip now (PR + main, before our local work) becomes next update's marker.
NEW_LOCAL_BASE=$(git rev-parse HEAD)

echo "== 5. Re-apply our local commits =="
# Local-only commits = everything after the marker on the backup branch,
# excluding merges and excluding version bumps (those are redone in step 7).
mapfile -t PICKS < <(
  git log --reverse --no-merges --format='%H %s' "${LOCAL_BASE}..${BACKUP_BRANCH}" \
    | grep -v -i 'bump .*version' \
    | awk '{print $1}'
)
if [ ${#PICKS[@]} -eq 0 ]; then
  echo "  (none found -- check $BASE_FILE)"
fi
for c in "${PICKS[@]}"; do
  echo "  cherry-pick $(git log -1 --format='%h %s' "$c")"
  if ! git cherry-pick "$c"; then
    echo "!! conflict on $c -- resolve, 'git add', 'git cherry-pick --continue', then re-run the rest manually"
    exit 3
  fi
done

echo "== 6. Record new local base for next update =="
echo "$NEW_LOCAL_BASE" > "$BASE_FILE"

echo "== 7. Bump version above newest upstream tag + installed apps =="
python3 bump-local-version.py
git add package.json "$BASE_FILE"
git commit --no-verify -m "chore: bump local build version + record base $NEW_LOCAL_BASE" || echo "(nothing to commit)"

echo "== 8. Done. New history: =="
git log --oneline -8
echo
echo "Backup of previous branch: $BACKUP_BRANCH"
echo "Next: verify (pnpm typecheck) then rebuild (see update notes)."
