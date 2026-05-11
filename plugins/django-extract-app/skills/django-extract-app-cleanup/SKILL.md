---
name: django-extract-app-cleanup
description: Use after `/django-extract-app:django-extract-app` has created a standalone package — wires the new package back into the original monolith as a dependency (PyPI, editable, or git URL), removes the original app directory, then verifies that monolith tests, `manage.py check`, and `makemigrations --check --dry-run` all still pass (no migration drift)
---

# Django Extract App — Cleanup Monolith

## Overview

Phase-2 companion to `/django-extract-app:django-extract-app`. The main skill creates a new package without touching the monolith. This sub-skill closes the loop:

1. Adds the new package as a dependency of the monolith
2. Removes the original `<app>/` directory from the monolith
3. Verifies the monolith still passes tests, `manage.py check`, and crucially `makemigrations --check --dry-run` (no migration drift between the monolith's DB schema and the packaged migrations)

Runs as a **separate** invocation because it's destructive (deletes files, modifies the monolith) and because the user may want a delay between extraction and cleanup (e.g., to publish the package to PyPI first, or to run additional QA on the standalone package).

## When to Use

- Right after `/django-extract-app:django-extract-app` completed in a sibling repo
- After the extracted package has been published to PyPI (or is ready for editable install)
- When the user is ready to delete the original `<app>/` from the monolith

**Not for:** First-time extraction (use the main skill). Greenfield monoliths without an extracted package yet.

## Iron Laws

1. **Always run all 3 verifications.** `pytest`, `manage.py check`, `makemigrations --check --dry-run`. If any fails after cleanup, the cleanup has broken something.
2. **No silent file deletion.** Always show the full `<app>/` directory contents to the user via `AskUserQuestion` before deleting.
3. **One commit for wiring, one commit for removal.** Wiring (add dependency, update INSTALLED_APPS if importable name changed) is reversible standalone. Removal (`git rm -r <app>/`) is a second commit so reviewers can see exactly what was deleted.
4. **Verify before each commit, not just at the end.** After wiring: import the new package, confirm `manage.py check` passes. After removal: re-run all 3 verifications.

---

## Step 0: Reconnaissance

### 0a. Confirm we're in the monolith

The current directory must:
- Have `manage.py` at the root (OR have one within a subdir that the user identifies)
- Have a `pyproject.toml` (or `setup.py` / `setup.cfg` / `requirements*.txt`)
- Have a `git` repo with clean working tree (`git status --porcelain` empty)

If working tree is dirty: abort and ask the user to commit/stash first.

### 0b. Identify the extracted package

`AskUserQuestion`:

1. **PyPI dist name** of the extracted package (e.g., `django-blog`)
2. **Importable name** (e.g., `blog`) — must already exist in monolith's `INSTALLED_APPS`
3. **Local path** to the extracted package's repo (the one created by `/django-extract-app:django-extract-app`) — used for editable installs and to confirm the package is actually there (`pyproject.toml` matches the dist name above)
4. **Wiring strategy** (see Step 1)

Confirm by reading the local package's `pyproject.toml` and showing the user: *"Wiring `<dist-name>` (importable `<importable>`) from `<local-path>` into monolith at `<monolith-path>`. Original app at `<monolith>/<app-path>` will be removed. OK?"*

### 0c. Confirm the original app exists in the monolith

The app directory must:
- Exist at the path the user specifies (default: search `<importable>` directly under the monolith root, or in common Django layouts like `src/<importable>`, `apps/<importable>`)
- Be registered in `INSTALLED_APPS` of the monolith's settings

If the original app is missing, cleanup is unnecessary — abort with a message.

---

## Step 1: Choose wiring strategy

`AskUserQuestion`:

- **PyPI (released)** — package is already on PyPI. Adds `<dist-name>>=<version>` to monolith's `[project.dependencies]` and runs `uv sync` (or `pip install -r requirements.txt` if the monolith doesn't use uv yet).
- **PyPI (placeholder, not yet released)** — user plans to publish soon. Adds `<dist-name>>=<version>` to dependencies but does NOT run `uv sync` yet (would fail). Monolith won't pass tests until PyPI release. Commits a TODO and warns user.
- **Editable local install** — `uv add --editable <local-path>` or `pip install -e <local-path>`. For internal packages or active co-development. Adds `<dist-name> @ file://<local-path>` (or PEP 660 reference) to `pyproject.toml`.
- **Git URL (specific commit/tag)** — for monoliths that consume from a private GitHub repo. Adds `<dist-name> @ git+ssh://git@github.com/<owner>/<repo>.git@<ref>` to `pyproject.toml`. User provides owner/repo/ref.

The strategy determines the exact `pyproject.toml` change in Step 2.

---

## Step 2: Wire the dependency (commit #1)

### 2a. Modify dependencies file

Detect the monolith's dependency file:

- `pyproject.toml` with `[project].dependencies` → add to that list
- `requirements.txt` (any variant) → add line `<dist-name>>=<version>` (or git/editable form)
- `setup.py` / `setup.cfg` with `install_requires` → add (if monolith is pre-modernization)
- `Pipfile` → add to `[packages]`

For each strategy:

**PyPI (released):**
```toml
[project]
dependencies = [
    # ... existing
    "<dist-name>>=<version>",
]
```

Then: `uv sync` (or `pip install -e .`).

**PyPI (placeholder):**
Same as above but commented inline:
```toml
"<dist-name>>=<version>",  # TODO: publish to PyPI before running uv sync
```

Do NOT run `uv sync`. Add a TODO entry in the commit body.

**Editable local install:**
```bash
uv add --editable <local-path>
# OR for non-uv monolith:
pip install -e <local-path>
```

Verify the edit landed in `pyproject.toml` (uv handles this automatically; for pip-based monoliths edit manually):
```toml
[tool.uv.sources]
"<dist-name>" = { path = "<local-path>", editable = true }
```

**Git URL:**
```bash
uv add "<dist-name> @ git+ssh://git@github.com/<owner>/<repo>.git@<ref>"
```

### 2b. INSTALLED_APPS — usually no change

If the importable name in the package matches the original app's name (the recommended case from the main skill), `INSTALLED_APPS` already lists the importable name correctly — no change needed.

If they differ (user picked a different importable in Step 2c of the main skill): edit settings.py to replace the old entry with the new importable name. Grep for ALL settings files:

```bash
grep -rn "INSTALLED_APPS" --include="*.py" .
```

Edit every occurrence consistently.

### 2c. Verify the wiring works

```bash
# Activate the env (uv handles this) and import the package
uv run python -c "import <importable>; print(<importable>.__file__)"
```

Expected: prints a path to the new package's site-packages location (for PyPI install) or the editable source (for editable install). If `ImportError`: stop and report — the wiring did not land correctly.

```bash
# Django still loads
uv run python manage.py check
```

Expected: `System check identified no issues (0 silenced).` If errors: stop and report. Common causes: missing dependencies in the new package's `pyproject.toml` (something the monolith was supplying via its own `[project.dependencies]` is no longer reachable).

**Important:** Do NOT yet remove the original `<app>/` directory. At this point the import resolution may still prefer the local directory over the installed package — that's fine, the verification just confirms imports/checks work. Removal happens in Step 3.

### 2d. Commit

```
Wire <dist-name> as a dependency

- Added <dist-name> via <strategy> (PyPI / editable / git)
- Source: <PyPI | local path | git URL@ref>
<- TODO: <dist-name> not yet on PyPI — `uv sync` will fail until released>
- manage.py check: PASSED
```

---

## Step 3: Remove the original app (commit #2)

### 3a. Show the user what will be deleted

```bash
find <monolith>/<app-path> -type f | sort
```

Present the full file list. `AskUserQuestion`: *"Delete these N files and the `<app-path>` directory? This is reversible via git but irreversible in the working tree."* — default **No**.

### 3b. Migration safety check (BEFORE deletion)

This is the most important pre-deletion check. If the monolith's DB has migrations applied for `<app-name>`, those migration records (`django_migrations` table) reference `<app-name>` and migration files that will, after deletion, only exist in the *installed package*. Django will look them up in the installed package by `app_label`, which is the AppConfig's `name`/`label`.

Confirm:

1. **AppConfig label matches.** The installed package's `apps.py` must declare an `AppConfig` whose `name` (or explicit `label`) is the same as the `app_label` recorded in `django_migrations`. The main skill's Step 3 preserves `apps.py` byte-for-byte from the monolith, so this should hold. Verify:

   ```bash
   uv run python -c "from django.apps import apps; print(apps.get_app_config('<importable>').label)"
   ```

   Compare against (if the DB exists locally):
   ```bash
   uv run python manage.py showmigrations <importable>
   ```

   The label/name must match. If not — stop, ask the user to align.

2. **Migration filenames match.** Migration records reference `(app_label, migration_name)`. The set of migration filenames in `<installed package>/migrations/` must be a superset of (or equal to) the names in `django_migrations` for this app. Diff:

   ```bash
   # Filenames currently in installed package
   uv run python -c "import <importable>.migrations, os; print(sorted(f[:-3] for f in os.listdir(os.path.dirname(<importable>.migrations.__file__)) if f.startswith('0') and f.endswith('.py')))"
   # vs. monolith's <app-path>/migrations/
   ls <monolith>/<app-path>/migrations/*.py | xargs -n1 basename | sed 's/\.py$//' | sort
   ```

   If sets differ, stop. Investigate before deletion. Most common cause: someone added a migration to the monolith after the extraction — that migration is missing from the installed package and removal will break things.

### 3c. Delete the directory

```bash
cd <monolith-path>
git rm -r <app-path>
```

### 3d. Re-verify (THE critical step)

Run all three:

```bash
uv run python manage.py check
# Expected: System check identified no issues.

uv run python manage.py makemigrations --check --dry-run
# Expected: No changes detected.
# CRITICAL: If this says "Migrations for '<importable>':" — there is drift between
# the monolith's models and the packaged models. Stop, do NOT commit, investigate.

uv run pytest                                    # or whatever the monolith's test command is
# Expected: same pass/fail count as before deletion (modulo flakes).
```

If `makemigrations --check` fails: the packaged app's models differ from what the monolith expected. Likely causes:
- The main skill's Step 3 lost a file (e.g., a custom field referenced from `models.py`)
- The monolith depends on a runtime mutation to the app's models (signal-based, AppConfig.ready())
- The installed package version differs from the local source (PyPI lag)

Stop, report to user. Do not commit. `git restore --staged <app-path>` and `git checkout HEAD -- <app-path>` to bring back the deleted directory if needed.

### 3e. Commit

```
Remove <app-name>/ — now provided by <dist-name>

- Deleted <monolith>/<app-path>/ (N files)
- Verifications after removal:
  - manage.py check:                          PASSED
  - makemigrations --check --dry-run:         No changes detected
  - pytest:                                   <N> passed, <N> failed (matches pre-cleanup baseline)
```

---

## Step 4: Final report

```
Monolith Cleanup Summary
========================

Monolith:          <monolith-path>
Removed app:       <app-path> (N files)
New dependency:    <dist-name> via <strategy>
Local package:     <local-path>

Verifications (post-cleanup):
  manage.py check:                  PASSED
  makemigrations --check:           No drift
  pytest:                           <N>/<M> passed

Commits:
  <sha1>  Wire <dist-name> as a dependency
  <sha2>  Remove <app-name>/ — now provided by <dist-name>

Next steps (you):
  1. Push the monolith branch and open a PR.
  2. <If PyPI placeholder:> Publish <dist-name> to PyPI, then run
     `uv sync` (or `pip install -r requirements.txt`) to install the
     published version.
  3. <If editable install:> Anyone else working in the monolith needs
     <local-path> on their machine, or you should switch to PyPI/git URL
     before merging.
```

---

## Common Mistakes

| Mistake | Prevention |
|---|---|
| Deleting `<app-path>/` before verifying installed package's import works | Step 2c verifies. If skipped, you may delete the only working copy. |
| Skipping `makemigrations --check --dry-run` | This is the #1 indicator of drift. Always run it after deletion. |
| Forgetting the AppConfig label invariant | If the package's AppConfig declares a different `label` than the original app, Django won't recognize existing migration history. Verify in Step 3b. |
| `git rm -r` while working tree is dirty | The dirty changes get bundled into the same commit. Always start with a clean tree. |
| Running cleanup before publishing to PyPI (when wiring strategy = PyPI released) | Cleanup will install-fail at `uv sync`. Use the placeholder strategy or publish first. |
| Trying to fix migration drift by re-running `makemigrations` | NO. If `--check` reports drift, the packaged source and monolith source actually differ. Find the source-of-truth difference and align — do not paper over with a new migration that the package won't have. |
| Auto-deleting `<app-path>` without showing the file list | Iron Law #2. Always show contents and confirm. |

## Red Flags — STOP

- "I'll just commit the deletion and the dependency together for one clean commit" — **NO.** Iron Law #3. Two commits.
- "`makemigrations --check` says there's drift but it's minor, I'll add a migration" — **NO.** That migration won't exist in the packaged version next time someone installs. Find the source mismatch.
- "The monolith doesn't have pytest configured — I'll skip that verification" — **NO.** Use whatever test runner the monolith has. If literally none, surface that to the user and confirm they're OK proceeding without test verification.
- "The user said `dist-name` is `django-foo` but the importable is `foo` — INSTALLED_APPS has `foo`, that's correct, I'll just check it once" — verify by importing first. Don't assume the package was installed correctly.
- "The monolith's working tree has uncommitted changes but they're unrelated to this app" — **NO.** Always require a clean tree. The user can stash or branch.
