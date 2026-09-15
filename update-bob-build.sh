#!/usr/bin/env bash
# Update the local IBM Bob build to the latest PR + main.
# Re-applies our local commits (version bump, build fixes, enable-bob.py)
# on top of the freshest PR head. Handles the PR being rebased/force-pushed.
set -euo pipefail

REPO="/Users/wojciech/Workspace/orca-bob"
PR_NUM=20397
# Our local commits, oldest-first. Update this list if you add more.
# Only the build fixes + enable script get cherry-picked. The version bump is
# done dynamically afterwards (bump-local-version.py), since the right number
# depends on the newest upstream tag at update time.
LOCAL_COMMITS=(
  "7d7674749e"   # chore: add enable-bob.py + helper scripts
  "37ab7a7491"   # fix(build): native single-arch fallback
  "2f4381759e"   # fix(build): auto single-arch when only CLT
)

cd "$REPO"

echo "== 1. Save current branch as a dated backup =="
STAMP=$(date +%Y%m%d-%H%M%S)
git branch "bob-integration-bak-$STAMP" bob-integration
echo "backup branch: bob-integration-bak-$STAMP"

echo "== 2. Fetch latest PR head and main =="
git fetch upstream main
git fetch upstream "refs/pull/${PR_NUM}/head:pr-${PR_NUM}-new"

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

echo "== 5. Re-apply our local commits =="
for c in "${LOCAL_COMMITS[@]}"; do
  echo "  cherry-pick $c"
  if ! git cherry-pick "$c"; then
    echo "!! cherry-pick conflict on $c -- resolve, 'git add', 'git cherry-pick --continue', then re-run remaining picks manually"
    exit 3
  fi
done

echo "== 6. Bump version above newest upstream tag + installed apps =="
python3 bump-local-version.py
git add package.json
git commit --no-verify -m "chore: bump local build version above latest upstream" || echo "(no version change)"

echo "== 7. Done. New history: =="
git log --oneline -8
echo
echo "Next: verify then rebuild (see update notes)."
