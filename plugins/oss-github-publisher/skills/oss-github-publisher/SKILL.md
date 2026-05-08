---
name: oss-github-publisher
description: Use when preparing a repository or package for publication to GitHub as open source, before the first public push or before flipping a repo from private to public — audits LICENSE, CI workflow with tests, pre-commit config with ruff/formatters; scans code, tests, fixtures, and git history for secrets (private keys, AWS/GitHub/Stripe/Twilio/HuggingFace/JWT tokens, DB connection URLs), credentials, PII (incl. Polish PESEL/NIP/phone), internal hostnames, ticket-referencing TODOs, IDE configs (.idea/.vscode), GPG/SSH key material, OS turds; checks GitHub Actions security (SHA-pinning, pull_request_target misuse, deprecated actions), PyPI name availability, PyPI metadata completeness, and README content quality
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
sk_live_[A-Za-z0-9]{24,}                  # Stripe live secret key (FAIL)
rk_live_[A-Za-z0-9]{24,}                  # Stripe restricted live key (FAIL)
sk_test_[A-Za-z0-9]{24,}                  # Stripe test secret (WARN — test mode but still leak)
SK[a-f0-9]{32}                            # Twilio API Key SID (FAIL when paired with auth token)
AC[a-f0-9]{32}                            # Twilio Account SID (WARN alone, FAIL with auth token nearby)
hf_[A-Za-z0-9]{34,}                       # HuggingFace token
dop_v1_[a-f0-9]{64}                       # DigitalOcean Personal Access Token
HRKU-[A-Za-z0-9]{36}                      # Heroku API key (newer format)
[a-f0-9]{32}-us[0-9]{1,2}                 # Mailchimp API key
key-[a-f0-9]{32}                          # Mailgun API key (regex generic — verify context)
shpat_[a-fA-F0-9]{32}                     # Shopify Admin API access token
shpss_[a-fA-F0-9]{32}                     # Shopify shared secret
shpca_[a-fA-F0-9]{32}                     # Shopify custom app token
sq0atp-[A-Za-z0-9_\-]{22}                 # Square access token
sq0csp-[A-Za-z0-9_\-]{43}                 # Square OAuth secret
EAACEdEose0cBA[A-Za-z0-9]+                # Facebook access token
ya29\.[A-Za-z0-9_\-]+                     # Google OAuth access token
1//0[A-Za-z0-9_\-]{40,}                   # Google OAuth refresh token
eyJ[A-Za-z0-9_\-]{20,}\.eyJ[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{20,}  # JWT — three base64url segments
(postgres|postgresql|mysql|mongodb(\+srv)?|redis|rediss|amqp|amqps|mssql|cockroachdb)://[^\s:]+:[^\s@]+@[^\s/]+  # DB connection URL with embedded creds (FAIL)
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

#### D.7 Hardcoded internal URLs / hostnames (WARN)

Not secrets, but they leak organisation structure and deployment topology — and shouldn't be in OSS code.

Grep for patterns suggesting non-public infra:

```
\.internal\b                                              # *.internal hostnames
\.intra\b                                                 # *.intra
\.corp\b                                                  # *.corp
\.lan\b                                                   # *.lan
staging[.-][a-z0-9-]+                                     # staging.acme.com, staging-api
qa[.-][a-z0-9-]+                                          # QA env URLs
dev[.-](cluster|server|api|app|env|host)[.-]              # dev environment URLs
\b(jira|confluence|gitlab|jenkins|grafana|kibana|sentry|airflow|argocd|vault|nexus|artifactory)\.[\w-]+\.[a-z]{2,4}\b  # internal SaaS instances
[a-z0-9-]+\.eu-(west|central|north|south)-\d\.elb\.amazonaws\.com  # AWS ELB DNS names
[a-z0-9-]+\.[a-z0-9-]+\.cloudfront\.net                   # CloudFront distribution IDs
\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b                         # private IP — 10.x
\b172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}\b             # private IP — 172.16-31.x
\b192\.168\.\d{1,3}\.\d{1,3}\b                            # private IP — 192.168.x
```

WARN per match; manual review required. PASS for these legitimate uses:
- `example.com`, `example.org`, `example.net`, `*.example.*` (RFC 2606 reserved)
- `localhost`, `127.0.0.1`, `0.0.0.0`, `::1`
- The project's own public docs/site URL (verify against `[project.urls]` Homepage)
- Public CDN / SaaS endpoints (`cdn.jsdelivr.net`, `api.github.com`, etc.)
- Documentation IP ranges (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24)

**FAIL** when an internal hostname is clearly specific to one organisation (e.g., `vpn.acme-corp.com`, `internal-api.acmebank.local`).

#### D.8 Code comments referencing internal tickets (WARN)

Comments like `# TODO(JIRA-1234)` or `// FIXME(BPP-42): see Confluence page` leak internal project structure: project codes, sprint numbering, ticket schemes, system names.

Grep for ticket-style annotations:

```
\b(TODO|FIXME|XXX|HACK|NOTE|BUG)\s*\(\s*[A-Z]{2,8}-\d{1,6}\s*\)            # JIRA-style: TODO(PROJECT-123)
\b(TODO|FIXME|XXX|HACK)\s*[:\(]\s*#\d{3,}                                  # GitHub-style: TODO #1234 (≥3 digits, may be internal)
\b(TODO|FIXME|XXX)\s*[-:\s]+(?:see|track|tracked|ticket|issue|ref|jira|asana|linear|trello)[\s:]+[A-Z0-9-]{3,}  # textual references
```

WARN per occurrence. Recommend converting to one of:
- Public GitHub issue reference, AFTER the repo is open-sourced: `# TODO: see #42`
- Generic prose without ticket: `# TODO: refactor to support concurrent writes`
- Removal if work is done or no longer relevant.

False positives to ignore:
- The project's own GitHub issue numbers (cross-check against `gh issue list` if the repo already has issues)
- Standard CVE references (`CVE-2024-12345`)
- RFC references (`RFC-7231`, `RFC 5322`)
- Python PEP / similar (`PEP-440`)

#### D.9 IDE / editor configs tracked

IDE config directories often contain personal absolute paths (`/Users/<name>/`, `C:\Users\<name>\`), custom run configurations referencing internal hosts, IDE caches (workspaces, indexes), and occasionally embedded credentials in launch configs.

Check what's tracked:

```bash
git ls-files | grep -E '^\.(idea|vscode|history|fleet|nova|sublime-(project|workspace)|devcontainer)/?'
```

Decision rules per path:

| Path | Decision |
|---|---|
| `.devcontainer/devcontainer.json` | **PASS** by default — typically intentional for OSS. Scan content for secrets/internal hostnames |
| `.vscode/settings.json` (workspace defaults) | **PASS** — formatter / extensions = team config, intentional |
| `.vscode/extensions.json` (recommended extensions) | **PASS** — team config |
| `.vscode/launch.json` with literal `/Users/`, `/home/`, `C:\` paths | **WARN** — content review; remove personal paths |
| `.vscode/tasks.json` with literal paths or hostnames | **WARN** |
| `.vscode/*.code-workspace` | **WARN** — workspace-specific paths |
| `.idea/` (any file) | **FAIL** — almost always personal IntelliJ/PyCharm state. Recommend `.gitignore` entry |
| `.history/` (Local History plugin) | **FAIL** — never intended for git, contains all your local edit history |
| `.fleet/` | **FAIL** — JetBrains Fleet personal state |
| `*.sublime-workspace` | **FAIL** — Sublime personal state (window layouts, breakpoints) |
| `*.sublime-project` | **WARN** — sometimes intentional shared config; check contents |
| `.nova/` | **FAIL** — Nova editor personal state |

Also grep across **all** tracked content for embedded personal absolute paths even if the IDE dir itself is properly gitignored:

```bash
rg --hidden '/Users/[a-z0-9_\-]+/|/home/[a-z0-9_\-]+/|C:\\\\Users\\\\[A-Za-z0-9_\-]+\\\\' --type-not binary
```

WARN per match — these often appear in launch configs, debug scripts, or hardcoded data files.

#### D.10 GPG / SSH key material and config (FAIL on private keys)

Beyond inline private-key blocks (D.1), check tracked key-related files:

```bash
git ls-files | grep -iE '(\.gnupg/|\.ssh/|authorized_keys|known_hosts|ssh_host_.+_key|pubring|secring|\.gpg-secret|\.gnupg-keyring|\bid_rsa\b|\bid_dsa\b|\bid_ecdsa\b|\bid_ed25519\b|\bid_ed25519_sk\b|\.kbx$|private-keys-v1\.d/)'
```

Decision rules:

| Path / pattern | Decision |
|---|---|
| `id_rsa`, `id_dsa`, `id_ecdsa`, `id_ed25519` (no `.pub` suffix) | **FAIL** — private SSH key |
| `id_*.pub`, any `*.pub` | **WARN** — public key (safe to share but reveals which keys you authorise) |
| `authorized_keys` | **WARN** — public key list; reveals which entities can log in |
| `known_hosts` | **WARN** — exposes which hosts you connect to (infra map) |
| `ssh_host_*_key` (host private keys, no `.pub`) | **FAIL** — never publish; rotate immediately |
| `secring.gpg`, `pubring.gpg` (legacy GPG keyring) | **FAIL** for `secring`; WARN for `pubring` |
| `*.gpg-secret`, `private-keys-v1.d/`, `*.kbx` | **FAIL** — GPG secret keys |
| `.gnupg/` directory tracked | **FAIL** — entire GPG home dir |
| `.ssh/config` | **WARN** — exposes hostname → user / port mappings |
| `*.asc` files | **WARN** — read content: public key block (PASS), signed message (PASS), private key block (FAIL) |

If any FAIL: do NOT publish until the file is purged from history (`git filter-repo --invert-paths --path <file>`) AND the corresponding key is rotated.

#### D.11 OS / IDE turds tracked (WARN — hygiene)

Not security-critical but signals lazy review and pollutes diffs for contributors:

```bash
git ls-files | grep -E '(\.DS_Store|Thumbs\.db|desktop\.ini|\$RECYCLE\.BIN|\.Trashes|\.Spotlight-V100|\.AppleDouble|\.fseventsd|\._[^/]+|ehthumbs\.db|ehthumbs_vista\.db|\.localized|^Icon\?$|\.directory$)'
```

WARN per file. Recommend the user add the standard `.gitignore` patterns:

```
# macOS
.DS_Store
.AppleDouble
.LSOverride
._*

# Windows
Thumbs.db
ehthumbs.db
desktop.ini
$RECYCLE.BIN/

# Linux
*~
.fuse_hidden*
.directory
.Trash-*
```

Suggest <https://github.com/github/gitignore/blob/main/Global/> as a comprehensive source.

---

### E. GitHub Actions security

OSS repositories receive PRs from forks. Misconfigured workflows can let a fork PR exfiltrate repo secrets. **Critical for public repos** in a way it is not for private ones.

1. **Third-party actions pinned to commit SHA, not tag.**
   - Tags can be silently moved by the action author (or their compromised account) to point at malicious code.
   - For every `uses:` line in `.github/workflows/*.yml`:
     - First-party `actions/*` (GitHub-maintained, e.g. `actions/checkout@v4`) using a tag → **PASS** (community-accepted)
     - Third-party (`astral-sh/setup-uv@v5`, `tj-actions/changed-files@v44`, `peaceiris/actions-gh-pages@v3`, etc.) using a tag → **WARN**, recommend SHA pin
     - Format: `uses: tj-actions/changed-files@a8f5e64...4f0c # v44.5.7` (full SHA + version comment)
   - Particularly important after the **March 2025 `tj-actions/changed-files` supply-chain incident** — that family of actions MUST be SHA-pinned.

2. **No `pull_request_target` exposing secrets to fork code.**
   - Look for workflows triggered on `pull_request_target` AND using `${{ secrets.* }}` AND checking out PR HEAD code (`actions/checkout` with `ref: ${{ github.event.pull_request.head.sha }}` or `ref: ${{ github.event.pull_request.head.ref }}`).
   - This is the canonical "PWN-the-repo" pattern — **FAIL**.
   - Safe `pull_request_target` use: only labelling, commenting, or adding reactions — without checking out untrusted code.

3. **Workflow `permissions:` block declared and minimal.**
   - GitHub's default `GITHUB_TOKEN` has more permissions than most workflows need.
   - Test workflows: `permissions: contents: read`
   - Trusted-publishing workflows (PyPI OIDC): `permissions: id-token: write, contents: read`
   - **WARN** if a workflow file has no `permissions:` block at workflow or job level.

4. **Outdated action versions** — security and reliability:
   - `actions/checkout@v2` / `@v3` → `@v4` (v2/v3 use deprecated Node 16) — **WARN**
   - `actions/setup-python@v2` / `@v3` / `@v4` → `@v5` — **WARN**
   - `actions/cache@v2` / `@v3` → `@v4` — **WARN**
   - `actions/upload-artifact@v3` / `download-artifact@v3` → **FAIL** (deprecated, will stop working)
   - Use of `::set-output::` or `::save-state::` (replaced by `$GITHUB_OUTPUT` / `$GITHUB_STATE`) → **WARN**

5. **No `${{ secrets.* }}` echoed into logs.**
   - Grep workflow files for patterns that print secrets:
     ```
     echo[^|]*\$\{\{[^}]*secrets\.
     printf[^|]*\$\{\{[^}]*secrets\.
     run:[^|]*echo[^|]*\$\{\{[^}]*secrets\.
     ```
   - **FAIL** per match — secrets in logs are visible in run output to anyone with read access (and to forks if PR triggers).

6. **`run-name:` doesn't expand untrusted PR-controlled values without quoting.**
   - `run-name: ${{ github.event.pull_request.title }}` allows PR title to inject into workflow context — script injection vector.
   - **WARN** when `run-name` references PR title, branch name, or other fork-controlled data.

7. **Concurrency control (suggestion, not a finding):**
   - For PR / push workflows, recommend:
     ```yaml
     concurrency:
       group: ${{ github.workflow }}-${{ github.ref }}
       cancel-in-progress: true
     ```
   - Saves CI minutes on rapid-push branches. Not security; informational.

---

### F. PyPI name availability (Python packages only)

Skip if the project has no `pyproject.toml` with `[project] name = ...` (i.e., not a Python package).

Before publishing, verify the package name isn't already taken on PyPI:

```bash
PKG_NAME=$(python -c "import tomllib; print(tomllib.load(open('pyproject.toml','rb'))['project']['name'])" 2>/dev/null)

if [ -n "$PKG_NAME" ]; then
  HTTP_CODE=$(curl -s -o /tmp/pypi_check.json -w '%{http_code}' "https://pypi.org/pypi/${PKG_NAME}/json")
  case "$HTTP_CODE" in
    200) echo "FAIL: PyPI name '${PKG_NAME}' is already taken"
         python -c "import json; d=json.load(open('/tmp/pypi_check.json'))['info']; print('  current author:', d.get('author','?')); print('  current version:', d.get('version','?')); print('  homepage:', d.get('home_page') or d.get('project_urls', {}).get('Homepage','?'))" ;;
    404) echo "PASS: PyPI name '${PKG_NAME}' is available" ;;
    *)   echo "WARN: unexpected response ${HTTP_CODE} from PyPI — verify manually" ;;
  esac
fi
```

Decision rules:
- **FAIL** if the name exists AND the author is clearly someone else (not the project owner / org).
- **PASS** if 404.
- **WARN** if the name exists AND the author looks like the same person/org (already published — verify it's the same project, not a name collision).

If FAIL, suggest alternatives:
- Prefix with the GitHub org: `<org>-<name>`
- Domain-style suffix: `<name>-py`, `py-<name>`, `<name>-toolkit`
- More specific descriptor (different problem domain)

PyPI name normalisation: lowercase, hyphens (not underscores or dots), no leading digit. Verify the name conforms — `My_Package` is silently normalised to `my-package` on upload, which can surprise users.

---

### G. PyPI metadata audit (Python packages only)

Skip if no `pyproject.toml` with `[project]`.

Read `pyproject.toml [project]` and verify:

1. **`description`** — non-empty, single line, < 200 chars, not a placeholder.
   - **FAIL** if missing, empty, or matches `^(TODO|Description|Add description|<your description>|My package|Project description)\.?$` (case-insensitive).
2. **`readme`** — points at an existing file at the path specified.
   - **FAIL** if the file doesn't exist.
   - **WARN** if the file is `.rst` and `[project.readme] content-type` not specified (PyPI defaults assume Markdown).
3. **`[project.urls]`** — at minimum `Homepage` AND one of (`Repository`, `Source`).
   - **WARN** if `[project.urls]` missing or has only one URL — PyPI sidebar will be sparse.
   - **FAIL** if any URL is a literal placeholder containing `<owner>`, `<repo>`, `<your`, or `example.com/yourname`.
4. **`keywords`** — non-empty list, ≥ 2 keywords, not just the package name.
   - **WARN** if missing or trivial.
5. **`classifiers`** — required entries present:
   - At least one `Programming Language :: Python :: 3.X` matching a version in `requires-python`
   - One `License :: ...` matching the `LICENSE` file
   - One `Development Status :: ...` (`3 - Alpha`, `4 - Beta`, `5 - Production/Stable`, `6 - Mature`, `7 - Inactive`)
   - **FAIL** if any of the above are missing.
   - **WARN** if `Programming Language :: Python :: 2*` or any minor below `requires-python` floor is listed.
   - **WARN** if `Development Status :: 1 - Planning` is set (default placeholder, rarely accurate).
6. **`authors` / `maintainers`** — at least one entry with `name` (and ideally `email`).
   - **WARN** if missing email.
7. **License three-way consistency** — `[project] license`, the `License :: ...` classifier, and the `LICENSE` file must agree.
   - **FAIL** on mismatch.
8. **No deprecated `[tool.setuptools]` entries** — `setup_requires`, `tests_require`, `dependency_links` shouldn't appear; deprecated since 2018.
   - **WARN** if present.

---

### H. README content audit

Read `README.md` / `README.rst` at repo root.

1. **README exists at repo root.**
   - **FAIL** if missing.
2. **Length** — ≥ 500 characters of actual content (excluding badge lines and headings only).
   - **WARN** if shorter — README is essentially empty.
3. **Title in first heading** matches the project name (or a humanised version).
   - **WARN** if title is generic ("README", "Project", "Untitled").
4. **"Installation" / "Install" section** exists (heading or clear paragraph).
   - **WARN** if missing.
5. **"Usage", "Quick Start", "Getting Started", "Example", or "Tutorial" section** exists.
   - **WARN** if missing.
6. **No template placeholders / lorem ipsum.**
   - Grep for: `TODO[:\s]`, `Lorem ipsum`, `Your project`, `<placeholder>`, `Replace this`, `Add description here`, `One paragraph of project description`, `\[badge name\]`, `<repo>`, `<owner>`, `\.\.\. coming soon \.\.\.`
   - **FAIL** per occurrence.
7. **At least one code block** (fenced ``` or indented).
   - **WARN** if missing — README explains what but not how.
8. **Badges resolve** — for each `https://img.shields.io/...` and similar badge URL, do a HEAD request:
   ```bash
   for url in $(rg -oN 'https://(img\.shields\.io|badge\.fury\.io|github\.com/[^/]+/[^/]+/actions/workflows/[^/]+/badge\.svg)[^"\)\s]*' README.md); do
     curl -sIL --max-time 5 -o /dev/null -w "%{http_code} $url\n" "$url"
   done
   ```
   - **WARN** per non-2xx response.
9. **License mention** — already covered by Section A.5; cross-link in the report if missing.

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

D. Secrets / PII / hygiene scan
  [PASS] D.1 No private key markers found
  [PASS] D.2 No API token patterns matched (incl. Stripe, Twilio, JWT, DB URLs)
  [PASS] D.3 No tracked .env / .pem / .key files
  [WARN] D.4 tests/fixtures/sample.json:42 contains email "real.person@gmail.com"
  [PASS] D.5 git log spot-check: clean
  [WARN] D.7 src/config.py:12 references "jenkins.acme-corp.com" (internal hostname)
  [WARN] D.8 src/views.py:88 has TODO(BPP-1234) (internal ticket reference)
  [FAIL] D.9 .idea/workspace.xml is tracked — contains personal absolute paths
  [PASS] D.10 No GPG/SSH key material tracked
  [PASS] D.11 No OS turds (.DS_Store etc.) tracked

E. GitHub Actions security
  [WARN] tj-actions/changed-files@v44 not pinned to SHA
  [PASS] No pull_request_target with secrets exposed
  [WARN] .github/workflows/tests.yml has no permissions: block

F. PyPI name availability
  [PASS] 'my-package' is available on PyPI

G. PyPI metadata audit
  [WARN] [project.urls] has only Homepage; missing Repository/Issues
  [WARN] Development Status :: 1 - Planning likely incorrect
  [PASS] No stale Python 2 classifiers

H. README content audit
  [PASS] README.md exists, 2.3 KB
  [PASS] Has Installation, Usage sections
  [WARN] CI badge points at 404

SUMMARY: 2 FAIL, 7 WARN, 14 PASS
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
| Database connection string with embedded password (`postgres://user:pass@host/db`) | D.2 regex matches `(postgres\|mysql\|mongodb\|redis\|amqp)://[^:]+:[^@]+@` — these always FAIL |
| JWT token committed in tests / fixtures even though "expired" | Token contains the signing-key shape; algorithm + key reuse risk. Treat all `eyJ...eyJ...` as FAIL |
| `.idea/workspace.xml` tracked with personal `/Users/<name>/` paths | D.9 IDE configs scan — `.idea/` is FAIL by default |
| Third-party GH Action used as `@v4` tag, not SHA | After `tj-actions` March 2025 incident, third-party actions MUST be SHA-pinned |
| `pull_request_target` workflow checking out PR HEAD with `secrets.*` exposed | Canonical secret-exfiltration pattern — always FAIL |
| `actions/upload-artifact@v3` still in use | Deprecated, will stop working — FAIL not WARN |
| PyPI package name conflicts with existing project | Section F: `curl https://pypi.org/pypi/<name>/json` before publishing |
| `[project.urls]` left with `<owner>/<repo>` placeholder | G.3 — angle-bracket placeholders are FAIL, not WARN |
| README has "TODO: write README" or lorem ipsum | H.6 — placeholder content is FAIL |
| Internal Jira ticket references in TODO comments (`TODO(BPP-1234)`) | D.8 grep — leaks project codes / sprint structure |
| Internal hostname in source (`staging.acme-corp.com`) | D.7 — internal infra fingerprint |

## Red Flags

- "It's just a fixture, the data isn't real" — **verify**, don't trust.
- "That token is already expired" — **still rotate and still remove from history**.
- "The repo has always been public, no point auditing now" — audit anyway; fix forward.
- "We can add the license later" — no. License is part of v1 publication.
- "pre-commit is a nice-to-have" — it's the last line of defense against future secret commits.
- "That JWT in tests is just a sample" — JWTs leak the signing algorithm and structure. Generate fresh test tokens, never reuse anything that touched production.
- "It's an internal hostname but it's behind VPN" — VPN doesn't matter once the hostname is on a public repo. Anyone scanning OSS for orgs' infra finds it.
- "I'll pin actions to SHA later" — fork PRs ship today. SHA-pin before publication.
- "PyPI name is probably free" — check with curl. Failed publishes leave a half-baked release that PyPI then refuses to overwrite.
- "The .idea folder has nothing important" — it has your username, your machine paths, and sometimes your custom credentials. Always FAIL for OSS.
- "The README is fine, README.md exists" — exists ≠ readable. Section H checks content, not just presence.
