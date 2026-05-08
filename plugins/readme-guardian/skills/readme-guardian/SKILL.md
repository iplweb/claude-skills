---
name: readme-guardian
description: Use when a Python project's README needs improvement — converts RST to Markdown, ensures proper badges (CI, PyPI, docs), short description, rationale, features list, multi-platform installation instructions (uv + pip), and a Python/Django version support matrix derived from project config
---

# README Guardian

## Overview

Analyzes and improves a Python project's README. Reads existing content, identifies what's missing or weak, presents suggestions to the user, and applies changes only after approval. Never discards existing content without permission — patches missing sections by default, rewrites only when the user explicitly asks.

## When to Use

- README is outdated, incomplete, or missing key sections
- README is in RST format and should be Markdown
- README lacks badges, install instructions, or version support info
- After running `/python-upgrade-package:python-upgrade-package` — the README likely needs updating to match new tooling
- Before publishing a package (complements `/oss-github-publisher:oss-github-publisher` audit)

**Not for:** Non-Python projects, generating documentation sites, writing full user guides.

---

## Step 0: Gather Project Intelligence

Before touching the README, read the project to understand it. Collect:

### 0a. Package metadata (from `pyproject.toml`)

```toml
# Look for:
[project]
name = "..."
description = "..."
requires-python = ">=3.10"
license = "..."
authors = [...]
urls = {Homepage = "...", Documentation = "...", Repository = "..."}
dependencies = [...]
classifiers = [...]
```

Extract:
- **Package name** and **description**
- **Python version constraint** (`requires-python`)
- **License**
- **URLs**: Homepage, Documentation, Repository, PyPI (derive from package name if not explicit)
- **Dependencies** — specifically check for `django` to enable Django mode

### 0b. CI configuration (from `.github/workflows/*.yml`)

Extract:
- **Workflow file name** (for badge URL)
- **Python version matrix** (e.g., `["3.10", "3.11", "3.12", "3.13"]`)
- **Django version matrix** if present (some projects matrix-test Django versions)

### 0c. Django detection

The project is a Django package if ANY of these are true:
- `django` appears in `[project].dependencies` or `[project.optional-dependencies]`
- `manage.py` exists at repo root
- `DJANGO_SETTINGS_MODULE` appears in `pyproject.toml` or `conftest.py`
- `django` appears in classifiers

If Django, also extract:
- **Supported Django versions** from:
  - Classifiers: `Framework :: Django :: 4.2`, `Framework :: Django :: 5.0`, etc.
  - CI matrix if Django versions are in the test matrix
  - Dependency constraint: `Django>=4.2,<6.0`

### 0d. Existing README

Read whatever README exists:
- `README.md`
- `README.rst`
- `README.txt`
- `README` (no extension)

Note the format, structure, and content already present.

### 0e. Other sources of information

- **Docstrings**: Read the package's `__init__.py` top-level docstring — often has a good description
- **CHANGELOG / HISTORY**: May provide context for features
- **LICENSE**: Confirm license type for the badge

---

## Step 1: RST → Markdown Conversion (if needed)

### Detection
Skip if README is already `.md` or doesn't exist at all.

### Procedure

1. **Check for pandoc:**
   ```bash
   which pandoc
   ```

2. **If pandoc is available:**
   ```bash
   pandoc README.rst -f rst -t gfm -o README.md
   ```
   Then review the output for conversion artifacts (broken links, mangled tables, etc.) and fix them.

3. **If pandoc is NOT available**, do a manual best-effort conversion:
   - Headers: `=====` underline → `#`, `-----` → `##`, `~~~~~` → `###`
   - Inline markup: `` ``code`` `` → `` `code` ``, `**bold**` stays, `*italic*` stays
   - Code blocks: `.. code-block:: python` → ````python`
   - Links: `` `text <url>`_ `` → `[text](url)`
   - Images: `.. image:: url` → `![alt](url)`
   - Directives: `.. note::` → `> **Note:**`
   - TOC: `.. contents::` → remove (GitHub auto-generates)

4. **Ask user to confirm** the conversion looks good before proceeding.

5. **Delete `README.rst`** after successful conversion.

6. **Update `pyproject.toml`** if it references `README.rst`:
   ```toml
   # Change:
   readme = "README.rst"
   # To:
   readme = "README.md"
   ```

---

## Step 2: Analyze Current README

Read the existing README (now guaranteed to be `.md` after Step 1) and check for the presence and quality of each required section:

### Required sections checklist

| Section | What to look for | Status |
|---|---|---|
| **Header badges** | CI badge, Python version badge, PyPI badge, docs badge, license badge | PRESENT / MISSING / OUTDATED |
| **Short description** | 1-2 sentence summary of what the package does | PRESENT / MISSING / WEAK |
| **Rationale** | Why does this package exist? What problem does it solve? | PRESENT / MISSING |
| **Features** | Bullet list of key features/capabilities | PRESENT / MISSING / WEAK |
| **Installation** | Install commands for macOS, Windows, Linux with uv + pip | PRESENT / MISSING / INCOMPLETE |
| **Version support** | Python versions supported (+ Django matrix if applicable) | PRESENT / MISSING / OUTDATED |
| **Basic usage** | Quick example or getting started | PRESENT / MISSING |
| **License** | License mention (even just one line) | PRESENT / MISSING |

### Present the analysis to the user:

```
README Analysis — <package-name>
================================

Current format: Markdown (123 lines)
Existing sections found: <list>

Section Status:
  [✓] Short description — present, good quality
  [!] Header badges — CI badge present but outdated (Travis), PyPI badge missing
  [✗] Rationale — missing entirely
  [✗] Features — missing entirely
  [~] Installation — present but only shows pip, missing uv/platform-specific
  [✗] Version support matrix — missing
  [✓] License — present

Recommendation: PATCH — add missing sections, update badges
  (Existing content is solid, just incomplete)

  OR

Recommendation: REWRITE — current README is minimal/boilerplate
  (Only has auto-generated content, better to start fresh preserving the description)
```

**Ask the user:** "Patch missing sections or rewrite? Here's what I'd add/change: ..."

---

## Step 3: Generate / Update README Content

Based on user's decision (patch or rewrite), generate the README. Below is the target structure — for patches, only add/update the sections marked as missing or outdated.

### Target README structure

```markdown
# <package-name>

<!-- badges -->
[![Tests](https://github.com/OWNER/REPO/actions/workflows/WORKFLOW.yml/badge.svg)](https://github.com/OWNER/REPO/actions/workflows/WORKFLOW.yml)
[![Python Version](https://img.shields.io/pypi/pyversions/PACKAGE.svg)](https://pypi.org/project/PACKAGE/)
[![PyPI Version](https://img.shields.io/pypi/v/PACKAGE.svg)](https://pypi.org/project/PACKAGE/)
[![License](https://img.shields.io/pypi/l/PACKAGE.svg)](LICENSE)
<!-- optional: docs badge if documentation URL exists -->
[![Documentation](https://readthedocs.org/projects/PACKAGE/badge/)](https://PACKAGE.readthedocs.io/)

<short description from pyproject.toml or existing README — 1-2 sentences>

## Why?

<rationale — why does this package exist? what problem does it solve?
 If not in existing README, try to infer from:
 - Package docstring
 - Description field
 - If genuinely unclear, write a placeholder and ask the user to fill in>

## Features

- <feature 1>
- <feature 2>
- <feature 3>
<Infer from code, docstrings, existing README. If unclear, ask user.>

## Supported versions

### Python

| Python | 3.10 | 3.11 | 3.12 | 3.13 |
|--------|------|------|------|------|
|        | ✓    | ✓    | ✓    | ✓    |

<Derive from requires-python and CI matrix.>

### Django (only if Django package)

**Canonical Django × Python compatibility matrix** — this skill is the source of truth for this table; other skills (e.g., `python-upgrade-package` Step 2b) reference it.

Authoritative upstream: <https://docs.djangoproject.com/en/dev/faq/install/#what-python-version-can-i-use-with-django>

**Snapshot as of 2026-05-08.** Re-check upstream every run — Django ships new releases and Python versions hit EOL on a regular cadence; this snapshot drifts.

| Django  | 3.10 | 3.11 | 3.12 | 3.13 | 3.14 | Status                                  |
|---------|------|------|------|------|------|-----------------------------------------|
| 4.2 LTS | ✓    | ✓    | ✓    | —    | —    | EOL Apr 2026                            |
| 5.0     | ✓    | ✓    | ✓    | —    | —    | EOL Apr 2025                            |
| 5.1     | ✓    | ✓    | ✓    | ✓    | —    | EOL Dec 2025                            |
| 5.2 LTS | ✓    | ✓    | ✓    | ✓    | ✓    | Active LTS (extended support Apr 2028)  |
| 6.0     | —    | —    | ✓    | ✓    | ✓    | Mainstream Aug 2026, extended Apr 2027  |

(Pre-3.10 columns omitted: Python 3.8 and 3.9 are EOL; the modern `requires-python` floor is `>=3.10`. Add columns only if the project explicitly supports older Pythons.)

**Currently supported Django series (2026-05-08): 5.2 LTS and 6.0.** Everything else in the table is included for historical reference and to help projects decide whether to bump their floor — drop those rows when generating a per-project matrix unless the project's constraint genuinely allows them.

**How to derive the per-project table:**
1. Read the project's Django version constraint (from `pyproject.toml` `[project] dependencies`)
2. Filter to versions allowed by that constraint (e.g., `django>=4.2` → all 4 rows; `django>=5.1` → only 5.1 + 5.2 LTS)
3. **Drop EOL Django versions** unless the project explicitly demands them (typically: keep only LTS rows + active non-LTS)
4. Filter columns to match `requires-python` (e.g., `>=3.11` → drop the 3.10 column)
5. Mark ✓ at the intersection of each (Django, Python) pair the project actually tests in CI

## Installation

### Using uv (recommended)

```bash
uv add <package-name>
```

### Using pip

```bash
pip install <package-name>
```

### Platform-specific notes

<Only include this subsection if there are actual platform differences.
 Common cases:
 - Package needs system libraries (e.g., libpq for psycopg2)
 - Package needs build tools on Windows
 - macOS needs Homebrew for certain deps

 If no platform-specific notes are needed, omit this subsection entirely.
 Don't fabricate differences — only document real ones.>

#### macOS

```bash
# Only if there are actual macOS-specific steps, e.g.:
brew install libfoo
uv add <package-name>
```

#### Linux (Debian/Ubuntu)

```bash
# Only if there are actual Linux-specific steps, e.g.:
sudo apt-get install libfoo-dev
uv add <package-name>
```

#### Windows

```powershell
# Only if there are actual Windows-specific steps
uv add <package-name>
```

## Quick start

<Brief usage example. Pull from existing README, docstrings, or examples/ directory.
 If nothing exists, write a minimal example and ask the user to verify.>

```python
from <package> import <main_thing>

# minimal example
```

## License

<License name> — see [LICENSE](LICENSE) for details.
```

### Content generation rules

1. **Never invent features** — only list what you can verify from the code or existing docs
2. **Rationale section**: If you can't determine why the package exists, write a best-guess and explicitly ask the user to review
3. **Badges**: Only include badges for services that actually exist:
   - CI badge: only if `.github/workflows/` has a test workflow
   - PyPI badge: only if the package is on PyPI (check `[project.urls]` or ask)
   - Docs badge: only if documentation URL exists in metadata
   - License badge: only if LICENSE file exists
4. **Version matrix**: Only mark ✓ for versions actually tested in CI — don't guess
5. **Installation**: If the package has no platform-specific dependencies, just show `uv add` and `pip install` without the platform subsections

---

## Step 4: Present and Confirm

Show the user the complete proposed README (or the diff if patching).

For **patches**, show each section being added/modified:

```
Proposed changes:
  [ADD] Header badges (CI + PyPI + License)
  [ADD] "Why?" section
  [ADD] "Features" section (4 items inferred from code)
  [UPDATE] Installation — added uv commands and platform sections
  [ADD] Python/Django version matrix
  [KEEP] Existing "Quick start" section (unchanged)
  [KEEP] Existing "License" section (unchanged)
```

For **rewrites**, show the full proposed README.

Use AskUserQuestion:
- "Apply these changes?"
- "Apply with modifications?" (user can give specific feedback)
- "Let me see the full text first" (show the complete output)

**Do NOT write the file without user approval.**

---

## Step 5: Apply and Commit

1. Write the updated `README.md`
2. If RST was converted, ensure `README.rst` is deleted and `pyproject.toml` updated
3. Commit:
   ```
   Update README with badges, install instructions, and version matrix

   - Added CI/PyPI/License badges
   - Added rationale and features sections
   - Added installation instructions (uv + pip)
   - Added Python <+ Django> version support matrix
   ```

---

## Common Mistakes

| Mistake | Prevention |
|---|---|
| Inventing features not in the code | Only list verifiable features — ask user if unsure |
| Including a PyPI badge when package isn't on PyPI | Check `[project.urls]` or ask |
| Marking Python versions as supported without CI evidence | Cross-reference CI matrix, not just `requires-python` |
| Including platform-specific install sections when there are no differences | Only add platform sections for packages with actual system dependencies |
| Discarding existing README content the user wanted to keep | Always ask before rewriting |
| Wrong GitHub Actions workflow filename in badge URL | Read actual `.github/workflows/` directory |
| Outdated Django compatibility info | Verify against Django's actual release compatibility |
| Writing the rationale yourself without flagging it | If you wrote it, tell the user "I inferred this — please verify" |

## Red Flags — STOP

- "I'll just write a complete new README, the old one is bad" — **Ask first.** The user may want to keep parts of it.
- "I know what this package does, I don't need to read the code" — **Read the code.** Don't guess features.
- "I'll add badges for all the services" — **Only for services that exist.** No aspirational badges.
- "The Django matrix is standard, I'll use the default" — **Derive from this project's actual config.** Every project is different.
- "Platform instructions are always the same" — **Check for system dependencies.** If there are none, skip platform sections.
