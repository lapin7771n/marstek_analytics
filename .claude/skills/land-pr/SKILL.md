---
name: land-pr
description: >-
  Use right after opening a pull request in marstek_analytics, and when the user says
  "land it", "watch the PR", "PR merged, clean up", "стеж за PR", "закрий після мержу".
  Waits until the PR merges or closes, then deletes the merged branch on the remote and
  locally.
---

# land-pr

A merged PR leaves its branch on the remote and in the local repo. This skill waits for the merge, then deletes both.

After `gh pr create` → section 1. On a PR that is already merged → section 2.

## 1. Wait for the merge

```bash
gh pr view <N> --json state --jq '.state'
```

`OPEN` → arm the watch. `MERGED` → section 2. `CLOSED` → nothing to clean; report and stop.

Arm the watch with the **Monitor** tool, description `PR #<N> merge watch`:

```bash
while true; do
  s=$(gh pr view <N> --json state --jq '.state' 2>/dev/null) || s=""
  case "$s" in
    MERGED) echo "PR #<N> MERGED: run land-pr section 2"; exit 0 ;;
    CLOSED) echo "PR #<N> CLOSED unmerged: no cleanup"; exit 0 ;;
  esac
  sleep 60
done
```

The loop reports both end states. A loop that waits only for `MERGED` stays silent on a closed PR, and that silence looks like "still open".

A Monitor expires after 30 minutes. On each expiry notice, check the state and re-arm it.

Tell the user in one line that the watch is armed and ends with the session. If the session ends first, running this skill again on the merged PR does the same cleanup.

Never merge the PR yourself. The owner merges.

## 2. Clean up after the merge

### 2.1 Delete the remote branch

GitHub does not always delete the head branch on merge:

```bash
git ls-remote --exit-code --heads origin <branch> && git push origin --delete <branch>
git fetch --prune
```

Only for a merged PR. A PR closed unmerged keeps its branch.

### 2.2 Delete the local branch

**In a worktree session** (cwd under `.claude/worktrees/`): leave the worktree. The app removes it when the session is archived. Detach so the branch is free, then delete it:

```bash
git switch --detach origin/master
git branch -D <branch>
```

**In the main checkout:**

```bash
git switch master && git pull --ff-only
git branch -D <branch>
```

Then run `/clean_gone` for any other branch that `git branch -v` marks `[gone]`. Run it with `LC_ALL=C` so git prints `[gone]` in English. Keep the `-v` grep: `-vv` prints `[origin/<branch>: gone]`, which the pattern misses.

## 3. Report

Two lines: the PR state with its merge commit, and what was deleted (remote branch, local branch, worktrees). In a worktree session, add one line suggesting the user archive the session.
