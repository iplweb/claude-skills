# Changelog

All releases follow [CalVer](https://calver.org/) — `YYYY.0M.MICRO`. The marketplace and all plugins ship in lockstep: every release re-tags every plugin with the same version.

## 2026.05.5 — 2026-05-08

Security hardening release. Three iterative `codex` self-reviews of the repo surfaced 9 distinct sandbox/secret-handling issues in `code-review-opencode` (and adjacent skills). Every finding was reproduced empirically before fixing — `git diff --no-index /etc/hosts /dev/null`, `git log --output=PATH`, malicious-filename command injection via `xargs -I {}`, and nested-`.env` pathspec leakage all confirmed live. Round 3 returned with no new findings against the previously-fixed surfaces, so this release closes the audit. Also folds in stale Django version data from a parallel review.

### Fixed (security — `code-review-opencode`)
- **Bash `cat`/`find`/`grep`/`rg`/`head`/`tail`/`wc` wildcards removed.** The previous policy paired `read.*.env: deny` with `bash."cat *": "allow"`, so the model could `cat .env` straight through the bash channel and bypass the read-tool path policy. Replaced with `read`/`glob`/`grep` opencode tools (which respect path policy) for any file access.
- **`git *` wildcards removed.** Blanket `"git *": "allow"` accepted destructive verbs like `git checkout HEAD~5 -- /etc/passwd`, `git clean -fdx`, `git reset --hard`, `git config user.email evil@x`. Whitelist now lists only explicit read-only verbs.
- **`git diff` and `git diff *` removed entirely.** `git diff --no-index FILE1 FILE2` reads any file the user can read, fully bypassing `external_directory: deny`. Verified empirically: `git diff --no-index /etc/hosts /dev/null` dumps `/etc/hosts` content. Glob can't express "any flag except `--no-index`", so the verb is dropped — diff for `uncommitted`/`commit` modes is now pre-computed in the wrapper instead.
- **`git log *` and `git show *` removed.** Both verbs accept `--output=PATH`, which writes a file (verified: `git log --output=/tmp/x -1` creates `/tmp/x`). That bypasses the `edit` tool policy via the bash channel. `git log` and `git show` are still allowed without arguments (HEAD-only, no flag injection surface).
- **`git branch *` and `git tag *` removed.** Wildcards accepted mutating forms — `git branch -D foo`, `git tag -d v1`, `git branch new`, `git tag new` — which modify `.git/`. No-args forms (list-only) are still allowed.
- **Command injection in untracked-file pre-compute.** The previous `git ls-files --others ... | xargs -I {} sh -c '... cat -- "{}"'` template literal-substituted filenames into the `sh -c` template, so a malicious filename like `$(touch /tmp/INJECTED)` executed the substitution before reaching `sh`. Verified live: old pattern created `/tmp/INJECTED`, new pattern (NUL-delimited bash `while read -d ''` loop) does not. The new loop also doesn't `cat` content at all — opencode now reads each file via its own `read` tool under the path-deny policy.
- **`.env` pathspec was anchored to repo root only.** `:(exclude).env` and `:(exclude).env.*` excluded `./env` only; `sub/.env` and `sub/.env.local` slipped through into `git diff HEAD`. Replaced with `:(exclude,glob).env`, `:(exclude,glob)**/.env`, `:(exclude,glob).env.*`, `:(exclude,glob)**/.env.*`. Verified: with the old form `sub/.env` content leaked into the diff; new form catches all four nesting variants.
- **Tracked-diff exclusion extended to all secret families.** Was filtering `.env*` only; now mirrors the full `read` denylist (`*.pem`, `*.key`, `id_rsa*`, `id_dsa*`, `id_ed25519*`, `id_ecdsa*`, `*.p12`, `*.pfx`, `*.keystore`, `*.jks`, `credentials.json`, `*credentials*.json`, `service-account*.json`, `.npmrc`, `.pypirc`, `.netrc`) — root + every nested directory. Smoke-tested with 16 secret files across 3 directory levels: all filtered, only the benign tracked change remains.
- **Read-tool denylist was root-only.** Patterns like `id_rsa`, `.npmrc`, `service-account*.json` matched only the repo root because opencode pattern matching does not cross `/` with a single `*`. `secrets/id_rsa` and `packages/app/.npmrc` were going through. Every secret pattern is now duplicated — once without `**/` (root) and once with `**/` (any depth).

### Fixed (other skills)
- **`github-build-fixer` — short-poll loop now actually waits.** Step 6's `for _ in 1..6; do gh run list ...; done` had no delay, so it fired 6 queries in well under a second and returned "No run found" before GitHub had time to register the workflow run. Added `sleep 5` between iterations and clarified the Step 1 sleep prohibition: it covers the long CI watch (use `gh run watch` instead), not the short post-push materialization wait.
- **`readme-guardian` — Django × Python compatibility matrix updated to 2026-05-08.** Snapshot was missing Django 6.0 and treated 4.2 LTS as still in extended support (which expired Apr 2026). Verified against `djangoproject.com/download/` and the `dev/faq/install/` page: only 5.2 LTS (Python 3.10–3.14) and 6.0 (Python 3.12–3.14) are upstream-supported as of 2026-05-08; 4.2/5.0/5.1 are EOL. Table updated and dated; explicit "currently supported" callout added so consumers know which rows to filter to.
- **`python-upgrade-package` — Django matrix examples and badges propagated.** Sample CI matrix (Step 4.3), classifiers list (Step 1.2), Django badge example (Step 4.5), and the "drop EOL versions" guidance (Step 4.2b) all updated to drop 4.2/5.0/5.1 and add 6.0. The canonical table still lives in `readme-guardian` — this skill only mirrors the examples.
- **`python-upgrade-package` — Django `conftest.py` example fixed.** The Step 5.5 sample assigned `django.conf.settings.DJANGO_SETTINGS_MODULE = "..."` on the `LazySettings` proxy, which silently does nothing useful and would surface as `ImproperlyConfigured` on the next `django.setup()`. Replaced with `os.environ.setdefault("DJANGO_SETTINGS_MODULE", ...)` and demoted the snippet — the `pyproject.toml` `[tool.pytest.ini_options]` form is now presented as the preferred path.

## 2026.05.4 — 2026-05-08

Patch release: closes two MEDIUM findings from a `code-review-opencode` self-review of the repo. Fixes a real `.env` exfiltration risk in the opencode review wrapper and propagates the tmux observability/stuck-detection pattern from `code-review-external` into the `premortem-multiple` family.

### Fixed
- **`code-review-opencode` — `.env` no longer leaks into prompts in `uncommitted` mode.** The pre-computed `DIFF` (`git diff HEAD` + `cat` of every untracked file) ran in the **main agent** before the opencode restrictive config existed, so any local `.env` / `.env.local` was being read into the prompt body sent to the opencode API regardless of the in-session permission deny. Replaced with `git diff HEAD -- ':(exclude).env' ':(exclude).env.*'` plus a `grep -Ev '(^|/)\.env($|\.)'` filter on the untracked file list.

### Changed
- **`premortem-codex` — migrated to tmux pattern.** Codex now runs inside a detached `pm-codex-{TS}` tmux session (analogous to `cr-codex-{TS}` in `code-review-external`). Pane output captured via `tmux pipe-pane` to `/tmp/premortem-codex-{TS}.log`; codex still writes the final markdown report to `/tmp/premortem-codex-{TS}.md` via its `write` tool (artifact-file pattern preserved). Switched invocation from `codex exec ... > $RUN_LOG 2>&1` (raw pipe) to `codex exec --skip-git-repo-check --sandbox workspace-write ... </dev/null` inside the runner.
- **`premortem-opencode` — migrated to tmux pattern.** Opencode now runs inside a detached `pm-opencode-{TS}` tmux session. Restrictive project-local `.opencode/opencode.json` setup + cleanup trap kept intact, with one fix: the trap now also calls `tmux kill-session` so a Ctrl-C in the parent agent cleans up both the session and the config. Added `--print-logs` so the bootstrap stage is visible (and stuck-detectable) instead of buffered into silence. Combined config-setup + tmux-launch + 90 s stuck-detector + hard 600 s deadline live in **one** bash command (trap fires after polling, never before).
- **`premortem-multiple` wrapper — surfaces `tmux attach` commands.** After dispatching the three background tasks, the wrapper prints `tmux attach -t pm-codex-{TS}` and `tmux attach -t pm-opencode-{TS}` so users can watch either reviewer live. The Claude subagent stays on the `Agent` tool (no tmux) — it has its own task lifecycle and doesn't need pane observability.

### Added
- New shared file `plugins/premortem-multiple/shared/tmux-runner.md` — premortem-flavored variant of the `code-review-external` tmux runner pattern (different naming: `pm-{tool}-{TS}` sessions, `/tmp/premortem-{tool}-{TS}.{md,log}` files). Referenced by both leaf skills.

### Requires
- `tmux` ≥ 3.0 in `$PATH` for `premortem-codex` and `premortem-opencode` (preflight `which tmux`; abort with install hint if missing). Same requirement as `code-review-external`.

## 2026.05.3 — 2026-05-08

Patch release: `code-review-external` family rewritten to dispatch every reviewer (codex / opencode / claude) inside its own attachable `tmux` session, with a stuck-detector that aborts after 90 s of no log growth instead of hanging for 15+ min on a wedged provider.

### Changed
- **`code-review-external` family** — all four skills (`code-review-codex`, `code-review-opencode`, `code-review-claude`, `code-review-external`) now run their underlying CLI inside a detached tmux session named `cr-{tool}-{TS}`. Users can `tmux attach -t cr-{tool}-{TS}` at any point to watch a reviewer live. Pane output is captured to `/tmp/code-review-{tool}-{TS}.log` via `tmux pipe-pane` while the reviewer writes its final markdown to `/tmp/code-review-{tool}-{TS}.md` (artifact-file pattern preserved).
- **`code-review-claude`** — switched from `Agent`-tool subagent dispatch to a headless `claude -p` process inside tmux. Uses `--permission-mode auto`, `--add-dir /tmp`, `--add-dir <project>`, `--allowedTools "Read Grep Glob Bash Write Edit"`. Three reviewers now share identical lifecycle (tmux session) instead of mixing tmux + Agent.
- **`code-review-external` wrapper** — replaced `Bash run_in_background` + `TaskOutput x3` orchestration with a single bash command that creates three tmux sessions, prints three attach commands up-front, and runs one combined polling loop (`tmux has-session` × 3, per-session stuck detector, hard 600 s deadline). Simpler model, no `pkill`, deterministic kill via `tmux kill-session`.
- **`code-review-codex`** — switched from `codex review` to `codex exec --skip-git-repo-check --sandbox workspace-write`. The old `codex review` lacks `--skip-git-repo-check` and crashed in non-git directories with `Not inside a trusted directory`; `codex exec` works in both git and non-git contexts.

### Added
- New shared file `plugins/code-review-external/shared/tmux-runner.md` — universal tmux launch + polling pattern referenced by all four leaf/wrapper skills (naming convention, `printf %q`-based runner script, `tmux pipe-pane` capture, stuck-detector loop, combined-poll variant for the wrapper).
- `--print-logs` flag added to opencode invocations so the bootstrap stage is visible in the pane (and in `RUN_LOG`) instead of buffered into silence — makes auth/network hangs diagnosable in real time.

### Fixed
- Opencode reviews on machines where the model API is slow or wedged no longer wait 15+ min in silence — stuck detector kills the tmux session after 90 s of zero log growth and reports last log lines to the user.
- Codex reviews of design docs in fresh / non-git directories (e.g. `SPEC.md` in a brand-new project folder) no longer crash with `Not inside a trusted directory and --skip-git-repo-check was not specified`.

### Requires
- `tmux` ≥ 3.0 in `$PATH` for all `code-review-external` skills (preflight `which tmux`; abort with install hint if missing). Install: `brew install tmux` / `apt install tmux`.

## 2026.05.2 — 2026-05-08

Major release: one new plugin, big rewrites across `python-upgrade-package` and `oss-github-publisher`, DRY refactor across the multi-CLI families, HTML reports for `premortem-multiple`, and a `setuptools.build_meta` build-backend bug fix that quietly broke every previous run of `python-upgrade-package`.

Plugins included in this release:
- `code-review-external` — parallel external code review (codex + opencode + Claude subagent)
- `github-build-fixer` — diagnoses and fixes failing GitHub Actions CI builds
- `oss-github-publisher` — pre-flight audit before publishing a repo as open source
- `premortem` — Klein-style premortem on plans, launches, hires, pricing, or strategy
- `premortem-multiple` — three parallel premortems with meta-synthesis
- `python-upgrade-package` — modernizes legacy Python packages
- `python2-cleanup` ← **NEW** — removes Py2 compatibility cruft from a Py3 codebase
- `readme-guardian` — analyzes and improves Python project READMEs

### Added
- **New plugin `python2-cleanup`** — 12 categories (`__future__`, `six`, `unicode()`/`basestring`/`xrange`/`long`/`unichr`, dict iter/view methods, `dict.has_key()`, `python_2_unicode_compatible`, `u''` prefix, custom `s2u`/`u2s`/`compat.py` helpers, `__metaclass__`/`with_metaclass`/`add_metaclass`, stdlib renames, dunder renames, optional `super()` simplification). Ripgrep-first detection, one commit per category, tests after every change. Iron Law: touch only Py2 cruft, never reformat.
- **`oss-github-publisher`** rewritten with 10 new audit areas:
  - D.2 extended secret regex set: Stripe (`sk_live_`/`rk_live_`/`sk_test_`), Twilio (`SK`/`AC` SIDs), HuggingFace, DigitalOcean, Heroku HRKU, Mailchimp, Mailgun, Shopify (shpat/shpss/shpca), Square, Facebook EAACE, Google ya29 + refresh tokens, JWT, database connection URLs (postgres/mysql/mongodb/redis/amqp/mssql/cockroachdb).
  - D.7 hardcoded internal URLs / hostnames (`.internal`, `.intra`, `.corp`, staging-/qa-/dev- patterns, internal SaaS instances, AWS ELB DNS, private IP ranges).
  - D.8 TODO/FIXME comments with internal ticket references (JIRA-style, GitHub-style, Asana/Linear/Trello).
  - D.9 IDE / editor configs tracked (`.idea/.vscode/.history/.fleet/.nova/sublime-workspace`) with per-path decision table; cross-content scan for embedded `/Users/<name>/` paths.
  - D.10 GPG/SSH key material and config (private keys → FAIL, host keys → FAIL, public keys/known_hosts → WARN).
  - D.11 OS / IDE turds (`.DS_Store`, `Thumbs.db`, `desktop.ini`, etc.).
  - Section E (new) — GitHub Actions security: SHA-pinning third-party actions (post tj-actions Mar 2025 incident), `pull_request_target` misuse, deprecated actions (`upload-artifact@v3` etc.), permissions blocks, secrets in logs, `run-name` injection.
  - Section F (new) — PyPI name availability check (`curl https://pypi.org/pypi/<name>/json`, normalisation rules).
  - Section G (new) — PyPI metadata audit ([project.urls], classifiers, `Development Status`, three-way license consistency, no deprecated `[tool.setuptools]` entries).
  - Section H (new) — README content audit (length, Installation/Usage sections, no lorem ipsum, code blocks present, badges resolve).
- **`python-upgrade-package`** Step 1: build smoke-test — `uv build` + `twine check` before commit, catches broken metadata before it hits PyPI.
- **`python-upgrade-package`** Step 1: `[project.urls]`, `keywords`, and `classifiers` blocks added to the `pyproject.toml` template, with extraction rules and a "no fabricated placeholders" rule.
- **`python-upgrade-package`** Step 1: full enumeration of `requirements*.txt` variants (`requirements/`, `*-requirements.txt`, `requirements-{test,docs,dev,prod}.txt`) with `find` discovery and per-variant routing into `[project.dependencies]` vs `[project.optional-dependencies]` extras.
- **`python-upgrade-package`** Step 3: pyupgrade + django-upgrade hooks in `.pre-commit-config.yaml`, with `--py-plus` derived from `requires-python` floor and `--target-version` derived from the project's lowest Django.
- **`python-upgrade-package`** Step 4: dynamic test matrix derivation — Python versions from `requires-python`, Django × Python pairs from canonical compatibility matrix (now sourced from `readme-guardian`). `include:`-style YAML for Django projects with explicit `(python, django)` pairs.
- **`python-upgrade-package`** Step 6: Makefile substitution table — 21 concrete substitutions (e.g., `python setup.py install` → `uv sync`, `flake8` → `uv run ruff check`, `python setup.py sdist bdist_wheel` → `uv build`) plus a list of what NOT to auto-substitute.
- **`premortem-multiple`** HTML visual report (parity with single `premortem`): dark theme, synthesis above the fold, per-agent accent colors (codex cyan / opencode green / claude purple), consensus / divergence / contradiction sections with pill-badges showing which agents converged. Saved alongside markdown synthesis and transcript.
- **`code-review-external`** family: free-form mode (5th detection mode) — when argument doesn't match file/dir/commit, treat as a free-form hint passed verbatim to all three reviewers (e.g., "całe repo", "security audit src/auth/").
- **README**: skill graph with three Mermaid diagrams (Python project lifecycle / decision-making / code review), recommended sequence ("python-upgrade-package → python2-cleanup → readme-guardian → oss-github-publisher → publish"), cross-references between skills.

### Changed
- **`code-review-external` family**: DRY refactor. Extracted 3 shared files (`shared/standard-review-prompt.md`, `shared/target-detection.md`, `shared/write-directive.md`). The 4 leaf SKILL.md files reference these instead of duplicating ~80 lines × 3. Editing review criteria is now a single-file change. Net: −161 lines.
- **`premortem-multiple` family**: same DRY refactor. Extracted 2 shared files (`shared/standard-premortem-prompt.md`, `shared/write-directive.md`). Net: −77 lines.
- **All external review and premortem skills**: switched from `tee`-pipeline to artifact-file pattern. Each tool (codex / opencode / claude subagent) writes its final review or premortem directly to a designated `$OUT` file via its own `write` tool; verbose stdout / stderr go to a separate `.log` file. The wrapper reads only the clean `$OUT` files (1–3 KB of markdown each, instead of 50+ KB of banners and reasoning).
- **opencode skills (review + premortem)**: temporary project-local `.opencode/opencode.json` config with explicit allow / deny rules (read repo, bash limited to `git/ls/find/cat/etc.`, write only to `/tmp/code-review-*` or `/tmp/premortem-*`), restored via trap on `EXIT/INT/TERM`. Avoids `--dangerously-skip-permissions` and prevents 60+ minute hangs on permission asks in non-TTY mode.
- **`code-review-claude` and `premortem-claude`**: switched from "subagent returns text + main agent Writes" to "subagent writes directly to `$OUT` via Write tool" — now consistent with codex / opencode and with wrapper expectations.
- **Django × Python compatibility matrix**: now lives canonically in `readme-guardian` (single source of truth across the plugin family). `python-upgrade-package` reads from there instead of maintaining a parallel copy. The `readme-guardian` snapshot was also updated to match the canonical version (added Django 5.2 LTS, fixed two factual errors that mismarked Django 5.0 support).
- **README**: plugins regrouped under three purpose categories (Python project lifecycle / Decision-making / Code review).

### Fixed
- **`python-upgrade-package`** **BUG**: `pyproject.toml` template specified `build-backend = "setuptools.backends._legacy:_Backend"`, which is **not a real backend identifier**. Every project modernised by previous versions of this skill ended up with a `pyproject.toml` that fails to build. Replaced with `setuptools.build_meta` (the canonical default) in both spots where it appeared (Step 1 template + Step 2 setuptools-scm template). The Step 1 build smoke-test added in this release would have caught this — and now does.
- **`python-upgrade-package`** ruff `target-version` was hardcoded `"py310"` despite the skill's own "DO NOT hardcode" rule for the CI matrix. Now derived from `requires-python` floor, with an explicit derivation table mirroring Step 4.2a.
- **`python-upgrade-package`** lint-job example used `uv python install 3.13` literal — replaced with `HIGHEST_PY` placeholder so the workflow run fails loudly if not replaced (rather than silently using a wrong matrix-misaligned version).
- **`github-build-fixer`** Step 6 used `sleep 5` after `git push` to "wait for GitHub to register the push" — both a Bash antipattern blocked by the harness and unnecessary (`gh run watch` polls). Replaced with a SHA-based poll loop (up to 30 s, exits early when the run for HEAD's SHA appears) and an explicit Bash `timeout: 1800000` directive (30 min) on `gh run watch` — previously the default 2-min Bash timeout would kill the watch on any CI run longer than 2 minutes.
- **`code-review-codex`** dropped `--uncommitted` / `--commit <SHA>` flags — codex (≥ 0.129) rejects those when `[PROMPT]` is given (`the argument '--uncommitted' cannot be used with '[PROMPT]'`). Codex now runs `git diff` / `git show` itself via its bash tool, instructed by the prompt body, which also lets the artifact-file write directive co-exist with the target-specifying invocation.

## 2026.05.0 — 2026-05-07

Initial CalVer cut. Versioning scheme moved from SemVer (`1.0.0`) to CalVer (`YYYY.0M.MICRO`).

Plugins included in this release:
- `code-review-external` — parallel external code review (codex + opencode + Claude subagent)
- `github-build-fixer` — diagnoses and fixes failing GitHub Actions CI builds
- `oss-github-publisher` — pre-flight audit before publishing a repo as open source
- `premortem` — Klein-style premortem on plans, launches, hires, pricing, or strategy
- `python-upgrade-package` — modernizes legacy Python packages
- `readme-guardian` — analyzes and improves Python project READMEs

### Added
- New `premortem` plugin (migrated from a personal `~/.claude/skills/premortem.md` to a full plugin layout).
- Top-level `version` field in `.claude-plugin/marketplace.json`.
- This `CHANGELOG.md`.
- `scripts/bump-version.sh` — helper to advance every `version` field across the repo to the next CalVer.

### Changed
- All `plugin.json` and marketplace entries: `1.0.0` → `2026.05.0`.
- `README.md` tagline expanded to cover code review and decision-making workflows.
