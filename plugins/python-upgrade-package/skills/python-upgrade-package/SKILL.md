---
name: python-upgrade-package
description: Use when modernizing a legacy Python package — converting setup.py/setup.cfg/requirements.txt to uv + pyproject.toml, adding pre-commit with ruff (changed-files-only), migrating Travis CI to GitHub Actions, switching test runner to pytest, and cleaning up obsolete files — all step-by-step with one commit per change and minimal diffs
---

# Python Upgrade Package

## Overview

Step-by-step modernization of legacy Python packages. Each step is confirmed by the user and gets its own git commit. The core principle is **minimal diffs** — never reformat untouched code, never rewrite existing tests, only change what's necessary to modernize the tooling.

## When to Use

- Package uses `setup.py`, `setup.cfg`, `requirements.txt`, `Pipfile`, or `MANIFEST.in`
- Package uses Travis CI (`.travis.yml`) instead of GitHub Actions
- Package lacks pre-commit hooks or uses outdated linters (flake8, pylint without ruff)
- Package uses `unittest` runner, `nose`/`nosetests`, or Django's `manage.py test` directly
- Any combination of the above — the skill detects what's present and skips what's already modern

**Not for:** Greenfield projects, packages already on uv + pyproject.toml + GitHub Actions + pytest.

## Iron Law

**NEVER reformat or restructure existing source code.** The goal is tooling modernization, not code cleanup. Every diff should be explainable as "changed the build system" or "changed the CI config" — never "reformatted line 42 of models.py."

## Execution Model

```
For each step:
  1. Detect whether the step is needed (skip if already done)
  2. Show the user what will change
  3. Ask for confirmation via AskUserQuestion
  4. Execute the changes
  5. Commit with a descriptive message
  6. Move to the next step
```

All steps are independent — if the user skips one, continue to the next.

---

## Step 0: Reconnaissance

Before any changes, gather intel. Read and report:

1. **Packaging format:** Which of setup.py, setup.cfg, requirements.txt, Pipfile, MANIFEST.in exist?
2. **CI system:** `.travis.yml`? `.github/workflows/`? Both? Neither?
3. **Test runner:** How are tests invoked? Look for:
   - `[tool:pytest]` or `[pytest]` in setup.cfg / pyproject.toml → already pytest
   - `nose` / `nosetests` in setup.cfg, .noserc, nose.cfg, tox.ini, Makefile
   - `python -m unittest` or `unittest.main()` patterns
   - `manage.py test` → Django
   - `tox.ini` — is it only for test running, or does it configure other things?
4. **Django detection:** Does `manage.py` exist? Is `django` in dependencies? If yes, capture the **Django version constraint** (e.g., `>=4.2,<6`) — needed in Step 4 to build the Django × Python test matrix.
5. **Pre-commit:** Does `.pre-commit-config.yaml` exist? What hooks are configured?
6. **Python version constraints:** What does `python_requires` / `requires-python` say?
7. **Version management:** How is the package version defined? Look for:
   - Hardcoded `version = "x.y.z"` in `setup.py`, `setup.cfg`, or `pyproject.toml`
   - `__version__` in `__init__.py` or `_version.py` (sometimes read by setup.py)
   - `setuptools-scm` — version derived from git tags (`use_scm_version=True` in setup.py, or `[tool.setuptools_scm]` in pyproject.toml)
   - `bumpversion` / `bump2version` — `.bumpversion.cfg` or `[tool.bumpversion]`
   - `bumpver` — `[tool.bumpver]` in pyproject.toml
   - `versioneer` — `versioneer.py` at repo root, `[tool.versioneer]`
   - `pbr` — `[pbr]` in setup.cfg
   - `poetry-dynamic-versioning` or `pdm-backend` dynamic version
   - Version defined in **multiple places** (e.g., both `setup.py` and `__init__.py`) — flag as a problem

Present findings to the user as a summary table before proceeding.

---

## Step 1: Convert to uv + pyproject.toml

### Detection
Skip if `pyproject.toml` already exists with `[project]` section AND no setup.py/setup.cfg remain.

### Procedure

1. **Read all metadata sources** in priority order:
   - `setup.cfg` `[metadata]` and `[options]` sections (most structured)
   - `setup.py` — parse the `setup()` call arguments
   - `requirements.txt` — dependencies only
   - `Pipfile` — dependencies and python version
   - `MANIFEST.in` — note included data, but pyproject.toml uses `[tool.setuptools.package-data]` instead

2. **Generate `pyproject.toml`** with the following structure:
   ```toml
   [build-system]
   requires = ["setuptools>=75.0"]
   build-backend = "setuptools.build_meta"

   [project]
   name = "<package-name>"
   version = "<version>"
   description = "<short, one-line description>"
   readme = "README.md"  # or README.rst if that's what exists
   requires-python = ">=3.10"
   license = "<from LICENSE file or setup.py>"
   authors = [{name = "<author>", email = "<email>"}]
   keywords = ["<keyword1>", "<keyword2>"]
   classifiers = [
       "Development Status :: 5 - Production/Stable",       # pick the matching maturity level
       "License :: OSI Approved :: MIT License",            # match the LICENSE file exactly
       "Programming Language :: Python :: 3",
       "Programming Language :: Python :: 3.10",            # one per minor in requires-python
       "Programming Language :: Python :: 3.11",
       "Programming Language :: Python :: 3.12",
       "Programming Language :: Python :: 3.13",
       # For Django projects, also add:
       # "Framework :: Django",
       # "Framework :: Django :: 4.2",
       # "Framework :: Django :: 5.2",
   ]
   dependencies = [
       # from install_requires / requirements.txt
   ]

   [project.optional-dependencies]
   dev = [
       # from extras_require['dev'] or dev-requirements.txt
   ]

   [project.urls]
   Homepage = "https://github.com/<owner>/<repo>"
   Repository = "https://github.com/<owner>/<repo>"
   Issues = "https://github.com/<owner>/<repo>/issues"
   Changelog = "https://github.com/<owner>/<repo>/blob/main/CHANGELOG.md"
   Documentation = "https://github.com/<owner>/<repo>#readme"
   ```

   **Important considerations:**
   - If `setup.py` has dynamic version (reads from `__init__.py`), use `[tool.setuptools.dynamic] version = {attr = "package.__version__"}`
   - Preserve all entry_points / console_scripts as `[project.scripts]`
   - Preserve all extras_require as `[project.optional-dependencies]`
   - If `setup.cfg` had `[options.packages.find]`, translate to `[tool.setuptools.packages.find]`

   **`[project.urls]` extraction** (don't fabricate URLs):
   - From `setup.py`: `url=...` → `Homepage`; `project_urls={...}` → spread into the urls block
   - From `setup.cfg` `[metadata]`: `url`, `project_urls`
   - From git remote: `git remote get-url origin` → derive owner/repo
   - From existing README badges: any `https://github.com/...` link gives owner/repo
   - If no source confirms a URL, leave that key out — empty `Homepage` is worse than no Homepage
   - `Documentation`: only set if real docs exist (Read the Docs, mkdocs site). Otherwise omit
   - `Changelog`: only set if `CHANGELOG.md` actually exists in the repo

   **`keywords` extraction:**
   - From `setup.py`: `keywords=` (string or list)
   - From `setup.cfg` `[metadata]`: `keywords`
   - If absent, derive 3-5 from the description and main `Topic ::` classifiers — but ask the user

   **`classifiers` hygiene** (don't blindly copy from setup.py):
   - **Drop** `Programming Language :: Python :: 2`, `Python :: 2.7`, and any minor below `requires-python` floor (`>=3.10` → drop 3.5–3.9 entries)
   - **Add** one `Programming Language :: Python :: X.Y` per minor in the derived Python matrix (Step 4 — same list)
   - **`Development Status`** — change from `1 - Planning` (default placeholder) to the matching level: `3 - Alpha`, `4 - Beta`, `5 - Production/Stable`, `6 - Mature`, `7 - Inactive`. Ask the user if unsure
   - **`License`** classifier MUST match the actual `LICENSE` file (e.g., MIT file → `License :: OSI Approved :: MIT License`)
   - **For Django projects:** add `Framework :: Django` and one `Framework :: Django :: X.Y` per Django version in the matrix (Step 4)
   - **Drop irrelevant** classifiers — e.g., `Topic :: System :: Installation/Setup` for non-installer tools, `Operating System :: OS Independent` if the package is platform-specific
   - Validate the final list against <https://pypi.org/classifiers/> — typos silently break PyPI uploads

3. **Initialize uv:**
   ```bash
   uv sync
   ```
   This creates `uv.lock`.

4. **Update `.gitignore`** — add if not present:
   ```
   .venv/
   uv.lock
   ```

   **Note:** Whether `uv.lock` should be committed depends on the package type:
   - **Application:** commit `uv.lock`
   - **Library:** typically do NOT commit `uv.lock` — add to `.gitignore`
   - Ask the user if unclear.

5. **Delete obsolete files:**
   - `setup.py`
   - `setup.cfg` (only if ALL sections have been migrated — check for `[tool:pytest]`, `[flake8]`, etc. that still need migration in later steps)
   - **All `requirements*.txt` variants** — discover with:
     ```bash
     find . -maxdepth 3 \( -name 'requirements*.txt' -o -name '*-requirements.txt' -o -path '*/requirements/*.txt' \) -not -path './.venv/*' -not -path './node_modules/*'
     ```
     Common names: `requirements.txt`, `requirements-dev.txt`, `requirements-test.txt`, `requirements-docs.txt`, `dev-requirements.txt`, `test-requirements.txt`, `requirements/base.txt`, `requirements/dev.txt`, `requirements/prod.txt`. Migrate all of them into `[project.dependencies]` and `[project.optional-dependencies]` first, THEN delete.
     - **Prod deps** (`requirements.txt`, `requirements/base.txt`, `requirements/prod.txt`) → `[project.dependencies]`
     - **Dev/test/docs deps** → corresponding `[project.optional-dependencies]` extras (`dev`, `test`, `docs`)
     - If a `requirements/` directory ends up empty, delete the directory itself
   - `MANIFEST.in`
   - `Pipfile`, `Pipfile.lock`

   **CAUTION with setup.cfg:** If it contains `[tool:pytest]`, `[flake8]`, `[isort]`, or other tool configs, do NOT delete it yet — those sections migrate in later steps. Only delete setup.cfg when it's fully empty of useful config.

6. **Verify the migration produced valid metadata (build smoke-test)** — before committing:

   ```bash
   uv build
   uv run --with twine twine check dist/*
   ```

   - **`uv build`** must succeed and produce both `dist/*-<version>.tar.gz` (sdist) and `dist/*-<version>-*.whl` (wheel). If it fails, the new `pyproject.toml` is broken — investigate (typo in TOML, missing required field, packaging-data path mismatch) before proceeding.
   - **`twine check dist/*`** validates that the artifacts will pass PyPI's upload checks: long_description rendering (RST/Markdown), classifier validity (rejects typos against the official list), metadata completeness. **Every line must say `PASSED`** — `WARNING` is also acceptable for non-blocking issues, but `FAILED` blocks publishing.
   - **Common failures and fixes:**
     - `long_description has syntax errors` — README has invalid RST/Markdown. Either fix or set `[project.readme] content-type = "text/markdown"` explicitly.
     - `classifiers value is not a valid choice` — typo. Validate at <https://pypi.org/classifiers/>.
     - `name not normalized` — package name uses underscores or capitals. Lowercase + hyphens.
     - `Cannot find file '...'` — `[tool.setuptools.package-data]` or `include` patterns reference paths that don't exist after the `MANIFEST.in` migration.
   - **Clean up after:** `rm -rf dist/ build/ *.egg-info` (or rely on `.gitignore`). The build artefacts MUST NOT be committed.

7. **Commit:**
   ```
   Convert packaging from setup.py/setup.cfg to uv + pyproject.toml

   - Generated pyproject.toml with all metadata from setup.py/setup.cfg
   - Initialized uv (uv.lock created)
   - Removed obsolete packaging files: setup.py, setup.cfg, requirements*.txt, MANIFEST.in, Pipfile
   - Verified with `uv build` + `twine check` — all artifacts PASSED
   ```

---

## Step 2: Consolidate Version Management

### Detection

Check where the version is currently defined:

1. **Single source, already managed by a tool** (setuptools-scm, bumpver, etc.) → skip this step, already good
2. **Single source, hardcoded** (e.g., only in `pyproject.toml` `version = "1.2.3"`) → offer to add a version management tool
3. **Multiple sources** (e.g., `pyproject.toml` AND `__init__.py` AND `setup.py`) → consolidate to one place, then add a tool
4. **No version found** → ask user what version this is, set it up properly

### Procedure

#### 2a. Identify all version locations

Search for version strings across the project:

```bash
# Common version locations
grep -rn "__version__" --include="*.py" .
grep -n "^version" pyproject.toml setup.cfg setup.py 2>/dev/null
grep -rn "VERSION" --include="*.py" . | grep -v ".pyc"
```

Also check for existing version tooling:
```bash
# setuptools-scm
grep -r "setuptools.scm\|setuptools_scm\|use_scm_version" pyproject.toml setup.py setup.cfg 2>/dev/null
# bumpversion / bump2version
ls .bumpversion.cfg 2>/dev/null; grep "bumpversion\|bump2version" pyproject.toml setup.cfg 2>/dev/null
# bumpver
grep "bumpver" pyproject.toml 2>/dev/null
# versioneer
ls versioneer.py 2>/dev/null
```

#### 2b. Present findings and let user choose

Report what was found and present version management options:

**If a tool is already in use** and working → confirm it's configured correctly in `pyproject.toml` and move on.

**If no tool is in use**, present the options:

| Tool | How it works | Best for |
|---|---|---|
| **setuptools-scm** | Derives version from git tags automatically. No version string in source code at all. `git tag v1.2.3` IS the version. | Libraries with regular releases, projects that already use git tags |
| **bumpver** | Keeps version in one configured location (pyproject.toml, __init__.py, etc.). Bump via `bumpver update --minor`. Can update multiple files from one source of truth. | Projects that want explicit version strings in source, need to bump in multiple files simultaneously |
| **bump2version** | Legacy but widely used. Config in `.bumpversion.cfg` or `pyproject.toml`. Bumps version and optionally creates git tags. | Projects already using bumpversion that need a maintained fork |
| **Manual (pyproject.toml only)** | Just keep `version = "x.y.z"` in `pyproject.toml` and nowhere else. No tool. | Very simple packages with infrequent releases |

Ask the user which approach they prefer via AskUserQuestion.

#### 2c. Consolidate to single source

Regardless of tool choice, ensure the version is defined in exactly ONE place:

1. **Remove duplicate version definitions:**
   - If `__init__.py` has `__version__ = "x.y.z"` AND `pyproject.toml` has `version = "x.y.z"`:
     - For **setuptools-scm**: remove both — version comes from git tags
     - For **bumpver**: keep in `pyproject.toml`, configure bumpver to update `__init__.py` too (if the project imports `__version__` somewhere)
     - For **manual**: keep only in `pyproject.toml`, use `[tool.setuptools.dynamic]` if `__init__.py` needs it at runtime

2. **If the project exposes `__version__` at runtime** (i.e., code does `from mypackage import __version__`):
   - **setuptools-scm**: add to `pyproject.toml`:
     ```toml
     [tool.setuptools_scm]
     write_to = "src/mypackage/_version.py"
     ```
     And in `__init__.py`:
     ```python
     from mypackage._version import version as __version__
     ```
   - **bumpver**: configure to update `__init__.py`:
     ```toml
     [tool.bumpver]
     current_version = "1.2.3"
     version_pattern = "MAJOR.MINOR.PATCH"

     [tool.bumpver.file_patterns]
     "pyproject.toml" = ['version = "{version}"']
     "src/mypackage/__init__.py" = ['__version__ = "{version}"']
     ```
   - **manual**: use dynamic version from attr:
     ```toml
     [project]
     dynamic = ["version"]

     [tool.setuptools.dynamic]
     version = {attr = "mypackage.__version__"}
     ```

3. **If the project does NOT expose `__version__` at runtime** — simplest case:
   - Just set `version = "x.y.z"` in `pyproject.toml` and remove version strings everywhere else
   - For setuptools-scm, no `write_to` needed

#### 2d. Configure the chosen tool

**setuptools-scm:**
```toml
[build-system]
requires = ["setuptools>=75.0", "setuptools-scm>=8"]
build-backend = "setuptools.build_meta"

[project]
dynamic = ["version"]

[tool.setuptools_scm]
# optionally: write_to = "src/mypackage/_version.py"
```
- Remove hardcoded `version = "..."` from `[project]` — it's now dynamic
- Ensure the current version has a git tag: `git tag v<current_version>` (ask user to confirm)
- Add `setuptools-scm` to build-system requires

**bumpver:**
```toml
[tool.bumpver]
current_version = "1.2.3"
version_pattern = "MAJOR.MINOR.PATCH"
commit_message = "Bump version {old_version} -> {new_version}"
commit = true
tag = true
push = false

[tool.bumpver.file_patterns]
"pyproject.toml" = ['current_version = "{version}"', 'version = "{version}"']
```
- Add `bumpver` to dev dependencies

**bump2version:**
```toml
[tool.bumpversion]
current_version = "1.2.3"
commit = true
tag = true

[[tool.bumpversion.files]]
filename = "pyproject.toml"
search = 'version = "{current_version}"'
replace = 'version = "{new_version}"'
```
- Add `bump2version` to dev dependencies

**Manual:**
- Just ensure `version = "x.y.z"` exists only in `pyproject.toml`
- Remove from all other files

#### 2e. Clean up obsolete version files

- Delete `versioneer.py` if migrating away from versioneer
- Delete `.bumpversion.cfg` if migrating to pyproject.toml-based config
- Remove `[pbr]` section from setup.cfg if migrating away from pbr
- Remove `version.py` / `_version.py` files that were manually maintained (unless setuptools-scm writes to them)

#### 2f. Commit

```
Consolidate version management with <chosen tool>

- Version is now defined in <single location>
- Removed duplicate version definitions from <list of files>
- Configured <tool> in pyproject.toml
<- Created git tag v<version> for setuptools-scm (if applicable)>
```

---

## Step 3: Add pre-commit Configuration

### Detection
Skip if `.pre-commit-config.yaml` already exists with ruff hooks configured.

### Procedure

1. **Create `.pre-commit-config.yaml`:**

   Base config with hygiene + ruff:

   ```yaml
   repos:
     - repo: https://github.com/pre-commit/pre-commit-hooks
       rev: v5.0.0  # check for latest
       hooks:
         - id: trailing-whitespace
         - id: end-of-file-fixer
         - id: check-yaml
         - id: check-added-large-files
         - id: detect-private-key

     - repo: https://github.com/astral-sh/ruff-pre-commit
       rev: v0.11.0  # check for latest
       hooks:
         - id: ruff
           args: [--fix]
         - id: ruff-format
   ```

   **Add `pyupgrade`** (always — modernizes Python syntax to the project's minimum):
   ```yaml
     - repo: https://github.com/asottile/pyupgrade
       rev: v3.20.0  # check for latest
       hooks:
         - id: pyupgrade
           args: [--py310-plus]  # ← derive from requires-python (lowest supported), see below
   ```

   **For Django projects, also add `django-upgrade`** (skip this block on non-Django projects):
   ```yaml
     - repo: https://github.com/adamchainz/django-upgrade
       rev: 1.22.2  # check for latest
       hooks:
         - id: django-upgrade
           args: [--target-version, "4.2"]  # ← derive from project's lowest supported Django, see below
   ```

   **Target-version derivation (DO NOT hardcode):**
   - `pyupgrade --pyXY-plus`: use the **lowest** Python from `requires-python` in `pyproject.toml`. Example: `requires-python = ">=3.10"` → `--py310-plus`. `>=3.9,<3.13` → `--py39-plus`.
   - `django-upgrade --target-version X.Y`: use the **lowest** Django version from the project's Django dependency constraint (collected in Step 0). Example: `"django>=4.2"` → `--target-version 4.2`. `"django>=5.2"` → `--target-version 5.2`.
   - Both targets pin the *floor* — code is rewritten to drop compat with anything older. Pinning higher than what `requires-python` / Django constraint allows would break runtime.

   **Key point:** pre-commit runs hooks only on staged files by default. `ruff`, `pyupgrade`, and `django-upgrade` will only modify files the developer is actively changing — existing untouched code stays as-is. This is consistent with the Iron Law (minimal diff): the developer is already editing that file, so a syntax modernization rewrite of the same lines is acceptable. (Forbidding `pre-commit run --all-files` in Step 3 of this skill enforces the same principle for the rest of the codebase.)

   **Why pyupgrade in pre-commit but not as a ruff rule?** The skill explicitly disables ruff's `UP` ruleset (Step 2) to avoid bulk auto-rewrites. `pyupgrade` as a separate pre-commit hook achieves the same modernization but only on staged lines, so the diff stays scoped to the developer's actual edits. (If you ever want to retire the pyupgrade hook, switch to ruff `UP` instead — never run both.)

2. **Add ruff configuration to `pyproject.toml`** (minimal, non-invasive):
   ```toml
   [tool.ruff]
   # Derive from requires-python lowest: ">=3.10" → "py310", ">=3.9" → "py39", etc.
   # SAME source as Step 4 Python matrix — never hardcode.
   target-version = "py310"  # ← REQUIRED: replace with derived value matching requires-python floor

   [tool.ruff.lint]
   select = ["E", "F", "W"]  # basic flake8-equivalent rules only
   # Do NOT enable aggressive rules (I, UP, etc.) — goal is to catch errors, not reformat
   ```

   `target-version` derivation table (mirror of Step 4.2a):

   | `requires-python` | ruff `target-version` | pyupgrade `--py-plus` |
   |---|---|---|
   | `>=3.9` | `"py39"` | `--py39-plus` |
   | `>=3.10` | `"py310"` | `--py310-plus` |
   | `>=3.11` | `"py311"` | `--py311-plus` |
   | `>=3.12` | `"py312"` | `--py312-plus` |
   | `>=3.13` | `"py313"` | `--py313-plus` |

   **Do NOT** add `[tool.ruff.format]` section — let ruff-format use its defaults. This avoids opinionated formatting config that creates noise.

3. **Do NOT run `pre-commit run --all-files`** — this would reformat existing code and create massive diffs. Only install it:
   ```bash
   pre-commit install
   ```

4. **Migrate flake8/isort config if present:**
   - If `setup.cfg` has `[flake8]`, migrate relevant settings to `[tool.ruff.lint]`
   - If `setup.cfg` has `[isort]`, note that ruff's `I` rule handles imports — but do NOT enable it (to avoid reformatting)
   - If `.flake8` exists, migrate to `[tool.ruff.lint]` and delete `.flake8`
   - Delete `setup.cfg` now if it's empty after migration

5. **Commit:**
   ```
   Add pre-commit hooks with ruff + pyupgrade<+ django-upgrade> (staged files only)

   - Added .pre-commit-config.yaml with:
     - Standard hygiene hooks (trailing-whitespace, detect-private-key, etc.)
     - ruff lint (E, F, W) + ruff-format
     - pyupgrade with --py<XY>-plus derived from requires-python
     <- django-upgrade with --target-version <X.Y> derived from Django constraint>
   - Configured ruff with basic flake8-equivalent rules (E, F, W)
   - Hooks run only on staged files — no existing code reformatted in bulk
   ```

---

## Step 4: Migrate CI from Travis to GitHub Actions

### Detection
- Skip if no `.travis.yml` exists
- If `.github/workflows/` already exists with test workflow, ask user whether to replace or keep both

### Procedure

1. **Read `.travis.yml`** and extract:
   - Python versions in the matrix
   - Install commands
   - Test commands
   - Environment variables
   - Services (databases, redis, etc.)
   - Deploy configuration (note but do NOT migrate deploys — too risky, flag for user)

2. **Derive the test matrix from project config — never hardcode**

   ### 2a. Python version matrix

   Read `requires-python` from `pyproject.toml` and expand it into a sorted list of `"MAJOR.MINOR"` strings:
   - `>=3.10` → every minor from 3.10 up to the latest stable Python (inclusive)
   - `>=3.9,<3.13` → `["3.9", "3.10", "3.11", "3.12"]`
   - `~=3.10.0` → `["3.10"]` only (PEP 440 compatible release: `>=3.10.0,<3.11.0`)
   - `>=3.10,<4` → effectively `>=3.10` — every minor from 3.10 up to latest stable

   Determine the latest stable Python at runtime (do NOT hardcode):
   ```bash
   curl -s https://endoflife.date/api/python.json \
     | python -c "import sys, json; data = json.load(sys.stdin); rows = [d for d in data if d.get('eol') is not True]; print(max(r['cycle'] for r in rows))"
   ```
   If offline, use the most recent stable you know and ask the user to verify before committing.

   ### 2b. Django version matrix (Django projects only)

   For Django projects, also derive a matrix of Django versions:
   1. Read the Django version constraint from `pyproject.toml` `dependencies` (collected in Step 0)
   2. Use the canonical Django × Python compatibility table (below)
   3. Compute valid `(python, django)` pairs as the **intersection** of:
      - Python versions allowed by `requires-python`
      - Django versions allowed by the project's Django constraint
      - Pairs marked supported in the canonical matrix

   **Canonical Django × Python compatibility matrix:**

   Authoritative source: <https://docs.djangoproject.com/en/dev/faq/install/#what-python-version-can-i-use-with-django>

   This table is a snapshot — re-check the source whenever you run this skill, because Django ships new versions and Python EOLs change.

   | Django  | 3.9 | 3.10 | 3.11 | 3.12 | 3.13 | 3.14 | Status                       |
   |---------|-----|------|------|------|------|------|------------------------------|
   | 4.2 LTS | —   | ✓    | ✓    | ✓    | —    | —    | Extended support to Apr 2026 |
   | 5.0     | —   | ✓    | ✓    | ✓    | —    | —    | EOL Apr 2025                 |
   | 5.1     | —   | ✓    | ✓    | ✓    | ✓    | —    | EOL Dec 2025                 |
   | 5.2 LTS | —   | ✓    | ✓    | ✓    | ✓    | ✓    | Active LTS                   |

   **Filter aggressively:** drop EOL Django versions unless the project's constraint explicitly demands them. If `dependencies = ["django>=4.2"]`, the matrix should typically be just `4.2 LTS` and `5.2 LTS` — skip 5.0 and 5.1 (already EOL), unless the user opts in.

   Add the resulting table to the project README so users can see at a glance which combinations are tested. (For polished README work — badges, install instructions, rationale — cross-reference the `readme-guardian` skill.)

3. **Create `.github/workflows/tests.yml`** using the matrix derived in Step 2.

   **For pure-Python projects** (no Django):

   ```yaml
   name: Tests

   on:
     push:
       branches: [master, main]
     pull_request:
       branches: [master, main]

   jobs:
     test:
       runs-on: ubuntu-latest
       strategy:
         fail-fast: false
         matrix:
           # Derived from requires-python in pyproject.toml — DO NOT hardcode.
           python-version: ["3.10", "3.11", "3.12", "3.13"]  # ← replace with your derived list

       steps:
         - uses: actions/checkout@v4

         - name: Install uv
           uses: astral-sh/setup-uv@v5

         - name: Set up Python ${{ matrix.python-version }}
           run: uv python install ${{ matrix.python-version }}

         - name: Install dependencies
           run: uv sync --all-extras

         - name: Run tests
           run: uv run pytest
   ```

   **For Django projects** — use `include:` style with explicit `(python, django)` pairs derived in Step 2b:

   ```yaml
   name: Tests

   on:
     push:
       branches: [master, main]
     pull_request:
       branches: [master, main]

   jobs:
     test:
       runs-on: ubuntu-latest
       strategy:
         fail-fast: false
         matrix:
           # Derived from requires-python + Django constraint + canonical compat matrix.
           # DO NOT hardcode — recompute every time this skill runs.
           include:
             - { python-version: "3.10", django-version: "4.2" }
             - { python-version: "3.11", django-version: "4.2" }
             - { python-version: "3.12", django-version: "4.2" }
             - { python-version: "3.10", django-version: "5.2" }
             - { python-version: "3.11", django-version: "5.2" }
             - { python-version: "3.12", django-version: "5.2" }
             - { python-version: "3.13", django-version: "5.2" }
             - { python-version: "3.14", django-version: "5.2" }

       steps:
         - uses: actions/checkout@v4

         - name: Install uv
           uses: astral-sh/setup-uv@v5

         - name: Set up Python ${{ matrix.python-version }}
           run: uv python install ${{ matrix.python-version }}

         - name: Install dependencies (project + Django ${{ matrix.django-version }})
           run: |
             uv sync --all-extras
             uv pip install "django~=${{ matrix.django-version }}.0"

         - name: Run tests
           env:
             DJANGO_SETTINGS_MODULE: <detected settings module>
           run: uv run pytest
   ```

   `~=X.Y.0` pins to that minor series (e.g., `~=4.2.0` → `>=4.2.0,<4.3.0`).

   **Adapt based on Travis config:**
   - If Travis had services (postgres, redis), add corresponding GH Actions service containers
   - If Travis had environment variables, add them as `env:` in the workflow
   - If Travis had `before_install` / `before_script` commands, translate to additional steps
   - For Django, set `DJANGO_SETTINGS_MODULE` in `env:` (detect from `manage.py`, `tox.ini`, or existing CI config)

   **Deploy steps:** Do NOT migrate Travis deploy config automatically. Instead, add a comment:
   ```yaml
   # TODO: Travis deploy configuration was not migrated automatically.
   # Original Travis deploy config:
   # <paste relevant section>
   ```
   And warn the user explicitly.

4. **Add lint job (informational only):**
   ```yaml
     lint:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4

         - name: Install uv
           uses: astral-sh/setup-uv@v5

         - name: Set up Python
           # REQUIRED: replace HIGHEST_PY with the highest version from your derived Python matrix (Step 2a)
           # If left literal, `uv python install` will fail loudly — that's intentional.
           run: uv python install HIGHEST_PY

         - name: Install dependencies
           run: uv sync --all-extras

         - name: Lint with ruff
           run: uv run ruff check . || true

         - name: Check formatting with ruff
           run: uv run ruff format --check . || true
   ```

   Note the `|| true` — lint is informational only, never blocks CI. This is intentional: we don't want to force reformatting the entire codebase just to get green CI.

5. **Update README badges:**
   - Find Travis badge: `[![Build Status](https://travis-ci.org/...` or `[![Build Status](https://travis-ci.com/...`
   - Replace with GitHub Actions badge:
     ```markdown
     [![Tests](https://github.com/OWNER/REPO/actions/workflows/tests.yml/badge.svg)](https://github.com/OWNER/REPO/actions/workflows/tests.yml)
     ```
   - Replace any hardcoded Python version badge with one derived from the matrix:
     ```markdown
     ![Python](https://img.shields.io/badge/python-3.10%20%7C%203.11%20%7C%203.12%20%7C%203.13-blue)
     ```
   - For Django projects, add a Django version badge similarly:
     ```markdown
     ![Django](https://img.shields.io/badge/django-4.2%20%7C%205.2-blue)
     ```
   - Detect OWNER/REPO from git remote or Travis badge URL
   - For full README polish (rationale, install instructions, complete version-support matrix table), cross-reference the `readme-guardian` skill — that skill specializes in README quality

6. **Delete `.travis.yml`**

7. **Commit:**
   ```
   Migrate CI from Travis CI to GitHub Actions

   - Created .github/workflows/tests.yml with matrix derived from requires-python<and Django version constraint, if applicable>
   - Using uv for dependency installation
   - Added informational-only ruff lint job (non-blocking)
   - Removed .travis.yml
   - Updated README badges (CI + Python<+ Django>)
   ```

---

## Step 5: Convert Test Runner to pytest

### Detection
- Skip if `pytest` is already the configured test runner (check pyproject.toml `[tool.pytest]`, or if pytest is in dependencies and no other runner is configured)
- Detect current runner: unittest, nose, Django manage.py test

### Procedure

1. **Add pytest to dependencies:**
   ```toml
   # In pyproject.toml [project.optional-dependencies]
   dev = [
       "pytest",
       # If Django project:
       "pytest-django",
   ]
   ```
   Then run `uv sync`.

2. **Add pytest configuration to `pyproject.toml`:**
   ```toml
   [tool.pytest.ini_options]
   # If Django:
   DJANGO_SETTINGS_MODULE = "<detected settings module>"
   ```

   **Detect Django settings module** from:
   - `manage.py` — look for `os.environ.setdefault('DJANGO_SETTINGS_MODULE', '...')`
   - `.travis.yml` env vars
   - `tox.ini` setenv

3. **Handle nose migration:**
   - If `nose.cfg` or `.noserc` exists, check for any pytest-relevant settings (test paths, plugins) and migrate to `[tool.pytest.ini_options]`
   - Delete `nose.cfg`, `.noserc`
   - Remove `nose` / `nosetests` from dependencies
   - If `tox.ini` only contains `[nosetests]` or `[tox]` with `commands = nosetests`, delete `tox.ini`
   - Check for `from nose.tools import ...` imports in tests — flag these for the user but do NOT rewrite them (pytest can run nose-style tests)

4. **Handle unittest migration:**
   - Remove `unittest.main()` calls from test files — but ONLY the `if __name__ == '__main__': unittest.main()` block at the bottom, nothing else
   - Do NOT convert `TestCase` classes to functions
   - Do NOT rewrite `self.assertEqual` to `assert`
   - pytest runs unittest-style tests natively — the only change needed is the runner

5. **Handle Django migration:**
   - Add `pytest-django` to dev dependencies
   - Create `conftest.py` at project root (if it doesn't exist) with:
     ```python
     import django
     from django.conf import settings

     django_settings_module = "<detected>"

     def pytest_configure(config):
         settings.DJANGO_SETTINGS_MODULE = django_settings_module
         django.setup()
     ```
   - Or use the simpler `pyproject.toml` approach:
     ```toml
     [tool.pytest.ini_options]
     DJANGO_SETTINGS_MODULE = "<detected>"
     ```

6. **Handle tox.ini:**
   - If `tox.ini` only served as test config (no other envs beyond default), delete it
   - If it has multiple envs or other config, leave it but note it for the user
   - Migrate any `[pytest]` section from `tox.ini` to `pyproject.toml`

7. **Verify tests still pass:**
   ```bash
   uv run pytest
   ```
   Report results to the user. If tests fail, investigate — common issues:
   - Missing `conftest.py` for Django
   - nose-specific plugins not available
   - Test discovery path differences (pytest uses `test_*.py`, nose uses `test*.py`)

8. **Commit:**
   ```
   Switch test runner to pytest

   - Added pytest to dev dependencies
   - Added pytest configuration to pyproject.toml
   - Removed <nose.cfg / .noserc / tox.ini / unittest.main() blocks> (whichever applies)
   - Tests verified passing with pytest
   ```

---

## Step 6: Final Cleanup

### Procedure

1. **Update `.gitignore`** — ensure these patterns are present:
   ```
   # Python
   __pycache__/
   *.py[cod]
   *$py.class
   *.egg-info/
   dist/
   build/
   .eggs/
   *.egg

   # Virtual environments
   .venv/
   venv/
   ENV/

   # IDE
   .idea/
   .vscode/
   *.swp
   *.swo

   # Testing
   .pytest_cache/
   .coverage
   htmlcov/
   .tox/

   # Distribution
   *.tar.gz
   *.whl
   ```

   Only ADD missing patterns — never remove existing ones.

2. **Update README badges** (if not already done in Step 3):
   - Python version badge: `![Python](https://img.shields.io/badge/python-3.10%20|%203.11%20|%203.12%20|%203.13-blue)`
   - CI badge (if GitHub Actions was set up)

3. **Final check — are any obsolete files still around?**
   - `setup.py`, `setup.cfg` (should be gone after Steps 1-3)
   - `.travis.yml` (should be gone after Step 4)
   - `nose.cfg`, `.noserc` (should be gone after Step 5)
   - `.bumpversion.cfg`, `versioneer.py` (should be gone after Step 2)
   - `tox.ini` (if fully migrated)
   - `.flake8`, `.isort.cfg` (if migrated to ruff)

4. **Modernize `Makefile` (if present)** — show diff, ask user to confirm before applying. Concrete safe substitutions:

   | Old (Py2-era / pre-uv) | New (uv-era) |
   |---|---|
   | `python setup.py install` | `uv sync` |
   | `python setup.py develop` | `uv sync` (uv installs current package in editable mode by default) |
   | `pip install -e .` | `uv sync` |
   | `pip install -r requirements.txt` | `uv sync` |
   | `pip install -r requirements-dev.txt` | `uv sync --all-extras` |
   | `pip install .[dev]` | `uv sync --extra dev` |
   | `python setup.py test` | `uv run pytest` |
   | `python -m pytest` | `uv run pytest` |
   | `python -m unittest discover` | `uv run pytest` |
   | `nosetests` | `uv run pytest` |
   | `coverage run -m pytest && coverage report` | `uv run pytest --cov` (after configuring `pytest-cov`) |
   | `flake8 .` | `uv run ruff check .` |
   | `pylint <pkg>` | `uv run ruff check <pkg>` |
   | `black .` | `uv run ruff format .` |
   | `isort .` | `uv run ruff check --select I --fix .` (or via pre-commit) |
   | `python setup.py sdist bdist_wheel` | `uv build` |
   | `python setup.py sdist` | `uv build --sdist` |
   | `python -m build` | `uv build` |
   | `twine check dist/*` | `uv run --with twine twine check dist/*` |
   | `twine upload dist/*` | keep, OR migrate to trusted publishing via GH Actions (preferred for OSS — no PyPI token in repo) |
   | `rm -rf build dist *.egg-info` | keep (still needed) |

   **Do NOT auto-substitute** these — flag for the user to review:
   - `python setup.py compile_locale` / `compilemessages` / any custom `setup.py` command — these were defined in `setup.py` and disappear when `setup.py` is removed; the user must replace them with direct invocations (e.g., `django-admin compilemessages`)
   - `tox` invocations — depends on whether tox.ini was kept (Step 5)
   - Anything that calls a deleted `setup.py` target by name (`setup.py register`, `setup.py upload`, `setup.py check`)

   If the Makefile is mostly obsolete (just `install`, `test`, `clean`), consider proposing deletion: `make` is rarely needed when `uv` provides equivalent commands. Ask the user.

5. **Commit:**
   ```
   Clean up: update .gitignore, README badges, Makefile

   - Added modern Python .gitignore patterns
   - Updated README badges for Python versions and CI
   - Modernized Makefile targets to use uv (where safe; flagged custom targets for user)
   ```

---

## Summary Report

After all steps, present a summary:

```
Package Upgrade Summary — <package-name>
========================================

Step 1: Packaging     [DONE / SKIPPED / FAILED]
  setup.py → pyproject.toml + uv

Step 2: Versioning    [DONE / SKIPPED / FAILED]
  Consolidated to <single source> with <tool>

Step 3: Pre-commit    [DONE / SKIPPED / FAILED]
  Added ruff (staged files only) + hygiene hooks

Step 4: CI            [DONE / SKIPPED / FAILED]
  Travis CI → GitHub Actions (Python 3.10-3.13)

Step 5: Test runner   [DONE / SKIPPED / FAILED]
  <old runner> → pytest

Step 6: Cleanup       [DONE / SKIPPED / FAILED]
  .gitignore + README badges

Files deleted: <list>
Files created: <list>
Files modified: <list>
Commits created: <count>

⚠ Manual follow-up needed:
  - <any deploy config not migrated>
  - <any nose.tools imports in tests>
  - <any other flagged items>
```

## Common Mistakes

| Mistake | Prevention |
|---|---|
| Running `pre-commit run --all-files` | NEVER do this — it reformats all code, violating the minimal-diff principle |
| Rewriting `self.assertEqual` to `assert` | Runner switch only — pytest runs unittest tests natively |
| Enabling aggressive ruff rules (I, UP, B, etc.) | Stick to E, F, W — error detection, not style enforcement |
| Deleting `setup.cfg` before migrating `[tool:pytest]` | Check ALL sections are migrated before deleting |
| Hardcoding Django settings module | Always detect from manage.py or existing config |
| Committing everything in one big commit | One commit per step — easier to review and revert |
| Migrating Travis deploy config automatically | Too risky — flag for user, don't auto-migrate |
| Adding `uv.lock` to git for a library | Ask the user — libraries typically .gitignore it |
| Leaving version defined in multiple places | Grep for `__version__` and `version =` — consolidate to one source |
| Setting up setuptools-scm without a git tag | The current version MUST have a tag, or setuptools-scm will generate `0.0.0` |
| Choosing a version tool without asking the user | Always present options and let user decide |
| Hardcoding the Python matrix in tests.yml | Always derive from `requires-python` — recompute every run, never copy a previous workflow's list |
| Hardcoding Django × Python pairs without checking the canonical table | Re-check the Django docs every run; drop EOL Django releases unless the project explicitly requires them |
| Forgetting to add the Django × Python matrix table to README | If the project depends on Django, the README MUST show which combinations are tested — readers expect it |
| Hardcoding `pyupgrade --pyXY-plus` | Derive from the lowest Python in `requires-python` — same principle as the CI matrix |
| Hardcoding `django-upgrade --target-version` | Derive from the lowest Django in the project's Django constraint — pinning higher than the floor breaks runtime |
| Enabling ruff `UP` rule alongside the pyupgrade hook | Pick one — they overlap. The skill defaults to a separate pyupgrade hook because UP rule is forbidden in Step 2's ruff config |
| Running `pyupgrade` / `django-upgrade` outside pre-commit on the whole repo | Same as `pre-commit run --all-files` — defeats the minimal-diff principle |
| Skipping `uv build` + `twine check` after the packaging migration | Step 1's smoke-test catches broken `pyproject.toml` (typos, invalid classifiers, broken README rendering) before they hit PyPI. ALWAYS run before commit |
| Copying classifiers wholesale from `setup.py`, including stale entries | `Programming Language :: Python :: 2.7` etc. must be dropped. Validate the final list against <https://pypi.org/classifiers/> — typos silently fail PyPI uploads |
| Leaving placeholder `[project.urls]` like `https://github.com/<owner>/<repo>` | Either fill in real URLs or omit the key. Empty placeholder is worse than no Homepage |
| Fabricating `[project.urls]` Documentation/Changelog when no docs/CHANGELOG exists | Only set keys for resources that actually exist in the project |
| Auto-editing custom `Makefile` targets that called `setup.py <command>` | These targets disappear with `setup.py`. Flag for user — replacement depends on what the custom command did |
| Migrating only `requirements.txt` and missing `dev-requirements.txt` / `requirements/dev.txt` | Use the discovery `find` command in Step 1.5 to enumerate ALL variants. Migrate each into the right `[project.optional-dependencies]` extra before deleting |

## Red Flags — STOP

- "Let me just quickly reformat this file while I'm here" — **NO.** Minimal diffs.
- "These unittest tests would be cleaner as pytest functions" — **NO.** Runner switch only.
- "I'll enable more ruff rules for better code quality" — **NO.** E, F, W only.
- "I'll skip the user confirmation, it's obvious" — **NO.** Every step needs confirmation.
- "The deploy config is simple, I'll migrate it too" — **NO.** Flag it, don't touch it.
- "I'll run the formatter once to establish a baseline" — **NO.** That's a massive diff on existing code.
- "I'll just keep `["3.10", "3.11", "3.12", "3.13"]` since that's what the example shows" — **NO.** Derive from `requires-python`. The example is a placeholder, not a default.
- "The Django docs probably haven't changed since the canonical table was written" — **NO.** Re-check <https://docs.djangoproject.com/en/dev/faq/install/> every run. Django releases are frequent.
- "This project's Django constraint is loose, I'll just test against the latest Django" — **NO.** Test against every supported (Python, Django) pair within the project's constraints.
- "I'll just use `--py310-plus` for pyupgrade, that's modern enough" — **NO.** Derive from `requires-python`. If the project supports 3.9, pyupgrade with `--py310-plus` will rewrite code in ways that break on 3.9.
- "Let me run `pyupgrade --py310-plus .` to clean the whole codebase real quick" — **NO.** That's the same anti-pattern as `pre-commit run --all-files`. Use the hook on staged files only. (For deliberate Py2-cruft removal, use the `python2-cleanup` skill — category by category, with review.)
