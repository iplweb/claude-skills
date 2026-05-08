---
name: github-build-fixer
description: Use when GitHub Actions CI is failing on the current branch — checks recent workflow runs via `gh`, diagnoses failures from logs, fixes code or CI issues, pushes, polls until green, then offers to create a PR to main
---

# GitHub Build Fixer

## Overview

Diagnoses and fixes failing GitHub Actions builds on the current branch. The skill reads CI logs via `gh`, identifies the root cause, proposes a fix, waits for user approval, commits and pushes, then polls until the new run is green. Once green, it offers to create a PR to merge into main.

## When to Use

- CI is red on the current branch and you want to fix it
- You just pushed code and want to verify + fix any CI failures
- You want to check if CI is green before merging

**Not for:** Repositories without any CI workflows, or fixing CI on branches you don't own.

## Prerequisites

- `gh` CLI installed and authenticated (`gh auth status`)
- Repository has a GitHub remote
- Git working tree is clean (no uncommitted changes) — the skill will check this

---

## Step 1: Pre-flight Checks

Run these checks before anything else. **Stop and report** if any fail.

```bash
# 1. Verify gh is available and authenticated
gh auth status

# 2. Verify we're in a git repo with a GitHub remote
gh repo view --json nameWithOwner -q .nameWithOwner

# 3. Check for uncommitted changes
git status --porcelain
```

- If `gh` is not authenticated → tell user to run `gh auth login`
- If no GitHub remote → exit, this skill requires GitHub
- If working tree is dirty → ask user to commit or stash first

---

## Step 2: Check Recent Runs

```bash
# Get the most recent workflow runs for the current branch
BRANCH=$(git branch --show-current)
gh run list --branch "$BRANCH" --limit 5 --json databaseId,status,conclusion,name,headBranch,createdAt,event
```

### Decision tree:

```
Are there any runs?
├── NO runs at all
│   └── Are there any workflow files in .github/workflows/?
│       ├── NO → Suggest using `/python-upgrade-package:python-upgrade-package` skill or offer to create
│       │         a basic workflow. Ask user what to do.
│       └── YES → The workflow may not trigger on this branch.
│                  Check workflow `on:` triggers. Report and suggest fix.
│
├── Most recent run is SUCCESS (green)
│   └── Report "CI is green ✓" and EXIT. Nothing to fix.
│
├── Most recent run is IN PROGRESS
│   └── Poll until it completes (see Step 6), then re-evaluate.
│
└── Most recent run is FAILURE
    └── Proceed to Step 3: Diagnose.
```

---

## Step 3: Diagnose the Failure

### 3a. Get failed jobs

```bash
RUN_ID=<most recent failed run ID>
gh run view "$RUN_ID" --json jobs --jq '.jobs[] | select(.conclusion == "failure") | {name: .name, conclusion: .conclusion, steps: [.steps[] | select(.conclusion == "failure") | {name: .name, conclusion: .conclusion}]}'
```

### 3b. Download logs for each failed job

```bash
# Get the full log for the failed run
gh run view "$RUN_ID" --log-failed
```

If `--log-failed` output is too large (>500 lines), focus on:
1. The last 100 lines of each failed job
2. Lines containing `error`, `Error`, `ERROR`, `FAILED`, `failed`, `assert`, `Exception`, `Traceback`

### 3c. Categorize the failure

Classify into one of these categories:

| Category | Signals | Fix approach |
|---|---|---|
| **Test failure** | `FAILED`, `AssertionError`, `pytest` output with `FAILED` | Fix the code — this is the primary case |
| **Import/syntax error** | `ImportError`, `ModuleNotFoundError`, `SyntaxError` | Fix imports or code syntax |
| **Dependency issue** | `pip install` failure, version conflicts, missing package | Fix pyproject.toml / requirements — this is a CI config issue |
| **Missing system package** | `apt`, `dpkg`, package not found, shared library errors | Add install step to workflow YAML |
| **Environment issue** | Missing display/X server, locale errors, permission denied | Add env setup to workflow YAML |
| **Timeout** | `The job running on runner ... has exceeded the maximum execution time` | Investigate slow tests, possibly skip or optimize |
| **Workflow syntax** | YAML parse errors, invalid workflow keys | Fix the workflow YAML |
| **Flaky / intermittent** | Test passes locally, random network errors, race conditions | Re-run first: `gh run rerun "$RUN_ID" --failed` |

### 3d. Analyze all failing jobs together

If multiple jobs fail (e.g., matrix), look for a common root cause:
- Same test failing across all Python versions → code bug
- Only one Python version failing → version-specific issue
- All jobs fail at dependency install → dependency issue

**Present your diagnosis to the user** with:
1. Which jobs failed and on which step
2. The relevant error output (trimmed to essential lines)
3. Your classification (from table above)
4. Your proposed fix

### 3e. When unsure

If the failure doesn't clearly fit a category, or you're unsure whether the fix should be in code vs CI config → **always ask the user**. Never guess on ambiguous failures.

---

## Step 4: Propose and Confirm Fix

Present the fix plan to the user:

```
CI Failure Diagnosis
====================

Branch: <branch>
Run: <run URL>
Failed jobs: <list>

Root cause: <one-line summary>

Category: <Test failure | Dependency issue | ...>

Error output:
  <trimmed relevant lines>

Proposed fix:
  - <file>: <what to change and why>
  - <file>: <what to change and why>

Confidence: <High | Medium | Low>
```

Use AskUserQuestion to confirm:
- **High confidence:** "Apply this fix?"
- **Medium confidence:** "Here's my best guess. Apply this fix, or investigate further?"
- **Low confidence:** "I'm not sure about this. Here's what I found — what would you like to do?"

**Do NOT proceed without user confirmation.**

---

## Step 5: Apply Fix, Commit, Push

### 5a. Apply the fix

Make the code/config changes as agreed with the user.

### 5b. Commit

Create a descriptive commit:

```bash
git add <specific files>
git commit -m "$(cat <<'EOF'
Fix CI: <one-line summary of what was wrong>

<details of what was changed and why>

Failed run: <run URL>
EOF
)"
```

### 5c. Push

```bash
git push
```

If the push fails because the branch has no upstream:
```bash
git push -u origin "$(git branch --show-current)"
```

---

## Step 6: Poll for CI Result

After pushing, poll until the new run completes. **Do NOT busy-loop with `sleep` for the long CI watch** — use `gh run watch`, which itself streams events instead of polling on a timer. The only place `sleep` is appropriate here is the short window between push and run registration (5–30s), where a one-shot retry loop with `sleep 5` is necessary because GH needs a moment to materialize the run.

```bash
BRANCH=$(git branch --show-current)
PUSH_SHA=$(git rev-parse HEAD)

# Poll for the run triggered by our push (up to ~30s — usually appears within 5s).
# `sleep 5` between iterations is REQUIRED — without it the loop fires 6 queries in
# under a second and exits before GH has a chance to register the workflow run, so
# `NEW_RUN_ID` ends up empty for fast-but-not-instant cases. The Step 1 prohibition
# on `sleep` covers long CI watch loops, not short materialization waits.
for _ in 1 2 3 4 5 6; do
  NEW_RUN_ID=$(gh run list --branch "$BRANCH" --limit 5 --json databaseId,headSha \
    --jq ".[] | select(.headSha == \"$PUSH_SHA\") | .databaseId" | head -1)
  [ -n "$NEW_RUN_ID" ] && break
  sleep 5
done

if [ -z "$NEW_RUN_ID" ]; then
  echo "No run found for $PUSH_SHA after 30s — workflow may not trigger on this branch/event"
  exit 1
fi

# Watch it (this is a long-running command — set Bash timeout to 1800000 ms / 30 min)
gh run watch "$NEW_RUN_ID" --exit-status
```

`gh run watch` streams live output and exits with 0 on success, non-zero on failure. **Set the Bash tool's `timeout` parameter to 1800000 ms** (30 min) for this call — typical CI runs are 3-15 min, but slow matrices can hit 25 min. Default 2-min Bash timeout will kill the watch prematurely.

### If the new run succeeds (green):

Report success and proceed to Step 7.

### If the new run fails again:

1. Go back to Step 3 — diagnose the new failure
2. Show the user what changed since the last attempt
3. Propose a new fix
4. Maximum 3 fix attempts before suggesting the user investigate manually

Track attempt count:
```
Attempt 1: <fix summary> → FAILED (different error)
Attempt 2: <fix summary> → FAILED (same error persists)
Attempt 3: <fix summary> → giving up, manual investigation needed
```

After 3 failed attempts, report everything you've tried and learned, and exit.

---

## Step 7: Offer to Create PR

Once the fix branch is green, ask the user:

```
CI is now green on branch '<branch>' ✓

The fix commit(s):
  <commit hash> <commit message>
  ...

Would you like to create a PR to merge this into main?
```

Use AskUserQuestion with options:
- **Create PR** — create a PR via `gh pr create`
- **No, I'll handle it** — exit, the user will merge manually
- **Push to main directly** — only if user explicitly chooses this (merge + push)

### Creating the PR:

```bash
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)

gh pr create \
  --base "$DEFAULT_BRANCH" \
  --title "Fix CI: <summary>" \
  --body "$(cat <<'EOF'
## Summary

Fixes failing CI on `<branch>`.

**Root cause:** <what was wrong>

**Fix:** <what was changed>

**Failed run:** <link to failed run>
**Green run:** <link to passing run>

---
🤖 Generated with [Claude Code](https://claude.com/claude-code) using `github-build-fixer` skill
EOF
)"
```

Report the PR URL to the user.

---

## Special Cases

### Flaky tests

If a test failure looks intermittent (passed before, random-looking error, network timeout):

1. Suggest re-running the failed jobs first:
   ```bash
   gh run rerun "$RUN_ID" --failed
   ```
2. Poll for the result
3. If it passes on re-run → report as flaky, suggest the user add retry logic or mark the test
4. If it fails again → proceed with normal diagnosis

### No workflow files at all

If `.github/workflows/` doesn't exist or is empty:

1. Report: "This repository has no GitHub Actions workflows configured."
2. Offer to create a basic test workflow for the project
3. Ask the user what they'd like to do

### Protected branches

If `git push` fails due to branch protection:
1. Detect the error message
2. Suggest creating a new branch: `fix/ci-<short-description>`
3. Push to the new branch instead
4. Proceed with PR creation

---

## Common Mistakes

| Mistake | Prevention |
|---|---|
| Fixing code without reading the test to understand intent | Always read the failing test AND the code it tests before proposing a fix |
| Assuming CI config is wrong when tests actually found a real bug | Default assumption: the CI config is correct, the code has a bug |
| Making a fix that only works for one Python version | Check if the fix is compatible across the entire matrix |
| Pushing without user confirmation | ALWAYS ask before committing and pushing |
| Infinite fix loops | Hard limit of 3 attempts, then exit with a report |
| Reformatting code while fixing a bug | Only change what's necessary to fix the failure — minimal diffs |
| Ignoring other failing jobs when one is fixed | Analyze ALL failing jobs together for a common root cause |
| Guessing at ambiguous failures | When unsure, ASK the user — never guess |

## Red Flags — STOP

- "I'll just re-run the build, it's probably flaky" — **Diagnose first.** Only re-run if evidence points to flakiness.
- "I'll fix this and also clean up the code around it" — **NO.** Fix the failure, nothing more.
- "The test is wrong, I'll change the assertion" — **Maybe.** But read the test intent first and confirm with user. Tests often catch real bugs.
- "I'll push directly to main to fix it faster" — **NO.** Always use the branch + PR flow unless user explicitly says otherwise.
- "This is a simple fix, I don't need to wait for CI" — **Always wait.** The whole point is a verified green build.
- "I'll skip user confirmation, the fix is obvious" — **NO.** Every fix needs user approval.
