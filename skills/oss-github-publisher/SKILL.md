---
name: oss-github-publisher
description: Use when preparing a repository or package for publication to GitHub as open source, before the first public push or before flipping a repo from private to public — audits for LICENSE, CI workflow with tests, pre-commit config with ruff/formatters, and scans code, tests, and fixtures for secrets, private keys, API tokens, credentials, and personal data (PII)
---

# OSS GitHub Publisher

## Overview

Pre-flight audit that must pass before a repository is pushed to a **public** GitHub remote for the first time (or flipped from private to public). Prevents accidental disclosure of secrets and PII, and ensures the project meets baseline OSS hygiene: license, CI, pre-commit.

The skill produces a single consolidated report with **PASS / WARN / FAIL** findings. A single **FAIL** blocks publication until resolved. **WARN** items require explicit user acknowledgement.

## When to Use

- Before the **first** `git push` to a public GitHub remote
- Before flipping a GitHub repo from **private → public**
- Before tagging a **v1.0** or any release intended for public consumption
- After a major refactor that added new fixtures, test data, or example scripts

**Not for:** private internal repos, forks where upstream already audited, docs-only changes.

## Audit Checklist

Run the four sections below in order. Report each finding inline as you go, then produce the consolidated report at the end.

---

### A. Licensing

1. **LICENSE file exists at repo root.** Accept any of: `LICENSE`, `LICENSE.md`, `LICENSE.txt`, `COPYING`.
   - `FAIL` if none found.
2. **License is a recognized OSS license.** Match header against MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, GPL-2.0, GPL-3.0, LGPL, MPL-2.0, ISC, Unlicense, CC0.
   - `FAIL` if unrecognized or custom/proprietary text.
3. **Copyright line is filled in.** No placeholders like `[year]`, `[fullname]`, `YOUR NAME`, `<year>`, `<copyright holder>`.
   - `FAIL` on placeholder text.
4. **Package metadata declares the same license.** Check `pyproject.toml` (`[project].license` / classifiers), `package.json` (`license`), `Cargo.toml` (`license`), `setup.cfg`/`setup.py`.
   - `WARN` on mismatch or missing declaration.
5. **README mentions the license** (usually bottom section or badge).
   - `WARN` if missing.

---

### B. CI / Test workflow

1. **`.github/workflows/` directory exists with at least one `.yml` file.**
   - `FAIL` if missing.
2. **At least one workflow runs the project's tests** (not only lint/format).
   - Look for `pytest`, `unittest`, `npm test`, `yarn test`, `cargo test`, `go test`, `mix test`, etc.
   - `FAIL` if no workflow runs tests.
3. **Workflow triggers on `push` AND `pull_request`.**
   - `WARN` if triggered only on one.
4. **Workflow tests against supported versions.** If `pyproject.toml` says `python >= 3.12`, CI should matrix-test 3.12 and newer.
   - `WARN` on version mismatch.
5. **README has a CI badge** pointing at the workflow.
   - `WARN` if missing (not blocking).

---

### C. pre-commit + formatting/linting

1. **`.pre-commit-config.yaml` exists at repo root.**
   - `FAIL` if missing.
2. **Formatter + linter hooks are configured** for the project's primary language:
   - **Python:** `ruff` (both `ruff-check` and `ruff-format`, or equivalent `ruff` + `black`/`isort`). `FAIL` if neither check nor format is present.
   - **JS/TS:** `prettier` + `eslint`. `FAIL` if neither is present.
   - **Go:** `gofmt`/`goimports` + `golangci-lint`. `FAIL` if neither.
   - **Rust:** `rustfmt` + `clippy`. `FAIL` if neither.
3. **Generic hygiene hooks from `pre-commit-hooks` are present:**
   - `trailing-whitespace`
   - `end-of-file-fixer`
   - `check-yaml`
   - `check-added-large-files`
   - `detect-private-key` ← **critical for OSS**
   - `WARN` per missing hook; `FAIL` if `detect-private-key` is missing.
4. **Run `pre-commit run --all-files`** and report any failures.
   - `FAIL` on any hook failure.

---

### D. Secrets / PII scan

Run each scan across the full repo (`git ls-files`) — include tests, fixtures, examples, docs, and scripts. Always scan the **current working tree**; also spot-check recent git history.

#### D.1 Private keys (hard FAIL on any match)

Grep for these markers:
```
BEGIN RSA PRIVATE KEY
BEGIN OPENSSH PRIVATE KEY
BEGIN EC PRIVATE KEY
BEGIN DSA PRIVATE KEY
BEGIN PGP PRIVATE KEY BLOCK
BEGIN ENCRYPTED PRIVATE KEY
BEGIN PRIVATE KEY
-----BEGIN CERTIFICATE-----
```

#### D.2 API tokens & credentials (hard FAIL on any live-looking match)

Patterns to grep (regex):
```
AKIA[0-9A-Z]{16}                          # AWS access key
ASIA[0-9A-Z]{16}                          # AWS temp key
aws_secret_access_key\s*=\s*[A-Za-z0-9/+=]{40}
ghp_[A-Za-z0-9]{36}                       # GitHub personal token
gho_[A-Za-z0-9]{36}                       # GitHub OAuth token
ghs_[A-Za-z0-9]{36}                       # GitHub server token
ghu_[A-Za-z0-9]{36}                       # GitHub user token
github_pat_[A-Za-z0-9_]{82}               # GitHub fine-grained PAT
xox[baprs]-[A-Za-z0-9-]{10,}              # Slack token
AIza[0-9A-Za-z_\-]{35}                    # Google API key
sk-[A-Za-z0-9]{32,}                       # OpenAI/Anthropic-style key
sk-ant-[A-Za-z0-9_\-]{90,}                # Anthropic API key
glpat-[A-Za-z0-9_\-]{20}                  # GitLab PAT
npm_[A-Za-z0-9]{36}                       # npm token
SG\.[A-Za-z0-9_\-]{22}\.[A-Za-z0-9_\-]{43} # SendGrid
```

Generic credential patterns (case-insensitive, treat as `WARN` unless value looks real):
```
(api[_-]?key|secret|password|passwd|token|auth[_-]?token|access[_-]?token)\s*[:=]\s*["'][^"']{8,}["']
```

Distinguish placeholders from real values: `"your-api-key-here"`, `"xxx"`, `"CHANGEME"`, `"<token>"`, `os.environ[...]`, `process.env.*` → PASS/note. Anything that looks like entropy → `FAIL`.

#### D.3 Tracked secret files

Check that these are **not tracked** by git (`git ls-files | grep -E ...`):
```
\.env$
\.env\.[^.]+$           # .env.local, .env.production (but allow .env.example, .env.sample)
\.pem$
\.key$
\.p12$
\.pfx$
id_rsa$
id_dsa$
id_ecdsa$
id_ed25519$
\.keystore$
\.jks$
credentials(\.json|\.yml|\.yaml)?$
service-account.*\.json$
```

- `FAIL` if any tracked.
- Also verify `.gitignore` covers these patterns going forward. `WARN` if not.

#### D.4 PII in fixtures / test data / examples

Scan test fixtures, example data, and docs (not source code comments).

**Polish-specific (for this user's projects):**
- **PESEL** — 11 consecutive digits in a context suggesting identity (`pesel`, `PESEL`). `FAIL` if real-looking.
- **NIP** — 10 digits in a `nip`/`NIP` context. `WARN`.
- **Phone numbers** — `\+48 ?\d{3} ?\d{3} ?\d{3}` or `\b\d{9}\b` in phone context. `WARN` if real-looking.
- **PZePUAP / auth SMS content** — literal message text containing real codes. `FAIL`.

**General:**
- Credit card candidates: `\b(?:\d[ -]*?){13,16}\b` that pass Luhn → `FAIL`.
- US SSN: `\b\d{3}-\d{2}-\d{4}\b` → `FAIL`.
- Email addresses in fixtures: `WARN` if they look real (not `test@example.com`, `@example.org`, `foo@bar.baz`).
- Real-looking full names in data files (multi-word capitalized, not `John Doe`/`Jane Smith`/`Foo Bar`) → `WARN`.
- IP addresses that are not private ranges, localhost, or documentation ranges (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24) → `WARN`.

#### D.5 Git history spot-check

```bash
git log --all -p -- | head -5000
```

Scan for the same private-key/token patterns in recent diffs. If secrets were ever committed — even if later removed — the repo history still contains them. `FAIL` means: **do not publish until history is rewritten** (`git filter-repo` / BFG) and the leaked credential is **rotated**.

#### D.6 Recommended external tools

Suggest the user run at least one of these for defense-in-depth:
- `gitleaks detect --source .`
- `trufflehog filesystem .`
- `detect-secrets scan`

Note results but do not require installation if not present.

---

## Reporting Format

Produce a single consolidated report at the end:

```
OSS Publication Audit Report — <repo name>
==========================================

A. Licensing
  [PASS] LICENSE: MIT, copyright "2026 Michał Pasternak" filled in
  [PASS] pyproject.toml declares license = "MIT"
  [WARN] README does not mention license

B. CI / Test workflow
  [PASS] .github/workflows/ci.yml runs pytest
  [PASS] Triggers: push, pull_request
  [WARN] No CI badge in README

C. pre-commit
  [FAIL] .pre-commit-config.yaml missing detect-private-key hook
  [PASS] ruff-check and ruff-format configured
  [PASS] pre-commit run --all-files: clean

D. Secrets / PII scan
  [PASS] No private key markers found
  [PASS] No API token patterns matched
  [PASS] No tracked .env / .pem / .key files
  [WARN] tests/fixtures/sample.json:42 contains email "real.person@gmail.com"
  [PASS] git log spot-check: clean

SUMMARY: 2 FAIL, 3 WARN, 9 PASS
STATUS: BLOCKED — resolve FAIL items before publishing.
```

Each finding includes: **severity** (`PASS`/`WARN`/`FAIL`), **category**, **location** (file:line when applicable), and a one-line **recommendation** if not PASS.

## Decision Rules

- **Any FAIL** → publication is **BLOCKED**. Report findings, recommend fixes, do not run `git push` or `gh repo create --public` or `gh repo edit --visibility public`.
- **Only WARNs** → surface each WARN to the user and ask for **explicit acknowledgement per WARN** before proceeding.
- **All PASS** → proceed with publication.

## Common Mistakes

| Mistake | How to catch |
|---|---|
| `LICENSE` has placeholder `[year] [fullname]` | Grep for literal `[year]`, `[fullname]`, `<year>`, `YOUR NAME` |
| `pyproject.toml` license doesn't match `LICENSE` file | Compare strings directly |
| `.env.example` tracked AND `.env` also accidentally committed | `git ls-files \| grep -E '^\.env$'` |
| Test fixtures derived from real user data (real names, real phones) | Manual review of fixture files after regex scan |
| CI workflow exists but only runs `ruff`, not tests | Grep workflow `.yml` for `pytest`/`test`/test runner |
| `detect-private-key` hook missing from pre-commit | Grep `.pre-commit-config.yaml` for `detect-private-key` |
| Secret committed, then reverted — still in history | `git log --all -p` scan |
| API key rotated but old one still in history | Rotation doesn't clean history — filter-repo required |
| Debug dumps (`dom_dump_*.html`, `*.log`) committed with real content | Check `.gitignore` covers debug outputs |

## Red Flags

- "It's just a fixture, the data isn't real" — **verify**, don't trust.
- "That token is already expired" — **still rotate and still remove from history**.
- "The repo has always been public, no point auditing now" — audit anyway; fix forward.
- "We can add the license later" — no. License is part of v1 publication.
- "pre-commit is a nice-to-have" — it's the last line of defense against future secret commits.
