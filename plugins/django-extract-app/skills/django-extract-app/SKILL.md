---
name: django-extract-app
description: Use when a Django app inside a larger project should be extracted into a standalone reusable Django package — runs an 8-point extractability audit (cross-app FKs, imports, settings usage, migration deps, URL/reverse coupling, template extends, signals, admin), then scaffolds a new package with pyproject.toml + uv, TDD test stubs, GitHub Actions matrix (Python × Django, optionally pytest-testcontainers-django for Postgres), pre-commit, optional example/demo Django project, and chains into readme-guardian + oss-github-publisher
---

# Django Extract App

## Overview

Extracts a Django app from a monolithic project into a standalone reusable package. The output is a new git repository containing the app's source plus a full reusable-package shell: `pyproject.toml`, tests, CI, pre-commit, license, README, optional example project. The skill **does not modify the monolith** — wiring the new package back in (and removing the old app directory) is the job of the companion sub-skill `django-extract-app-cleanup`, which runs as a separate step after the new package is published or installed editable.

## When to Use

- A Django app inside a project has matured and is reusable across other projects
- An app needs to be open-sourced as a standalone package
- An app's logic should be isolated for independent testing and CI
- Before publishing — the package shell created here is verified by `/readme-guardian:readme-guardian` and `/oss-github-publisher:oss-github-publisher` as the last two steps

**Not for:** Brand-new apps (just create them as packages from the start), apps that are tightly coupled across many models with the rest of the project (the Step 1 audit will block — refactor the coupling first), non-Django code.

## Iron Laws

1. **Never modify the monolith in this skill.** That's the companion sub-skill's job. This skill only reads the monolith.
2. **One commit per step in the new repo.** Each step below produces exactly one commit. Reviewers can revert any single step independently.
3. **Every decision goes through `AskUserQuestion`.** No silent defaults — package naming, location, history strategy, DB engine, license, all explicit.
4. **Audit blockers stop the workflow.** If the Step 1 audit finds ≥1 BLOCK-level issue, the skill explicitly asks the user whether to abort or continue. Never proceed silently past a BLOCK.

---

## Step 0: Reconnaissance

Before any work, identify the target app and confirm it's actually a Django app.

### 0a. Identify the app

Ask the user for the app name (or path) inside the current project. Accept either `myapp` (relative to project root) or a full path. Resolve to an absolute directory.

### 0b. Confirm it's a Django app

The directory must contain ALL of:
- `apps.py` with an `AppConfig` subclass — OR a registration in `INSTALLED_APPS` of the project
- `__init__.py`
- At minimum one of: `models.py`, `views.py`, `urls.py`, `admin.py`, `management/commands/`, `templatetags/`

Find the project's settings module — typically detect via:
- `manage.py` at project root → `os.environ.setdefault("DJANGO_SETTINGS_MODULE", "<dotted>")`
- `pyproject.toml` `[tool.pytest.ini_options]` `DJANGO_SETTINGS_MODULE`
- `setup.cfg` `[tool:pytest]` `DJANGO_SETTINGS_MODULE`

Confirm the app appears in `INSTALLED_APPS` of the detected settings module.

If any of the above fails, report what's missing and stop. Do not proceed to audit.

### 0c. Inventory app contents

Build a manifest of what's in the app (used in later steps for test scaffolding and CI matrix):

```bash
find <app-path> -type f \( -name "*.py" -o -name "*.html" -o -name "*.txt" -o -name "*.md" \) | sort
```

Specifically note presence/absence of:
- `models.py` and `migrations/` (count of migration files)
- `views.py` / `views/` package
- `admin.py`
- `urls.py`
- `signals.py` and registrations of `@receiver`
- `forms.py`
- `serializers.py` (DRF detection)
- `management/commands/*.py`
- `templatetags/*.py`
- `templates/<app>/*.html` (must be namespaced under `<app>/` — note if NOT)
- `static/<app>/*` (same — should be namespaced)
- `tests/` or `test_*.py` (existing tests get migrated)
- `apps.py` `AppConfig` — note any `ready()` overrides (signals registration)

Report the manifest as a table. This is the basis for both the audit (Step 1) and the test scaffolding (Step 5).

---

## Step 1: Extractability Audit (8 checks)

Run all 8 checks. Each produces one of three statuses:

- **OK** — nothing to do
- **WARN** — the package can ship, but the user should know
- **BLOCK** — extraction will produce a broken package unless this is resolved first

Present results as a single table at the end. If any row is BLOCK, ask the user explicitly: *"Found N blocking issues. Resolve in the monolith first (recommended) or continue anyway and ship a known-broken package?"*

### 1.1 Cross-app FKs + dynamic refs (often BLOCK)

```bash
# ForeignKey/OneToOneField/ManyToManyField pointing to other local apps
grep -rEn "(ForeignKey|OneToOneField|ManyToManyField)\s*\(\s*['\"]([^'\"]+)['\"]" <app-path>
```

For each match, parse the referenced model. Three categories:
- **Built-in / external** (`auth.User`, `contenttypes.ContentType`, `django.contrib.*`, models from packages already in `[project.dependencies]` — once we build pyproject in Step 4) → OK
- **`settings.AUTH_USER_MODEL`** → OK (swappable)
- **Other local app in this project** → **BLOCK** unless the model is also being extracted, OR the user wires it as a swappable reference (`settings.MYAPP_FOO_MODEL`)

Also grep for dynamic references:

```bash
grep -rEn "apps\.get_model\(['\"]([^'\"]+)['\"]" <app-path>
grep -rEn "apps\.get_app_config\(['\"]([^'\"]+)['\"]" <app-path>
```

Same classification as above.

### 1.2 Cross-app imports (often BLOCK)

```bash
# All Python imports in the app
grep -rEn "^(from|import)\s+[a-zA-Z_]" <app-path> --include="*.py"
```

For each import, classify:
- Standard library / third-party (installable) → OK
- `django.*` → OK
- Same-app imports (`from .models import X`, `from <app>.foo import Y`) → OK
- **Other local app** (`from <other_local_app> import ...` where `<other_local_app>` is in `INSTALLED_APPS` of the monolith but NOT a package on PyPI) → **BLOCK**

Report each blocking import with its file:line so the user can decide whether to:
- Pull the helper into the extracted app (copy + adapt)
- Refactor the helper into a shared package first
- Abandon extraction

### 1.3 `settings.X` usages (WARN — becomes the package's settings contract)

```bash
grep -rEn "from django\.conf import settings" <app-path>
grep -rEn "settings\.[A-Z_]+" <app-path>
```

Collect every distinct `settings.X` accessed. These become the **package's settings contract**:
- For each setting, determine if it's a Django built-in (`DEBUG`, `MEDIA_ROOT`, `AUTH_USER_MODEL`, etc.) → OK to keep as-is
- For each project-specific setting (e.g., `MY_PROJECT_API_KEY`) → must become a prefixed package setting in Step 7, with a documented default

Status: WARN if any project-specific settings are found (handled in Step 7's README). BLOCK only if a setting has no obvious default and is required for the app to function (e.g., import-time access).

### 1.4 Migration cross-app dependencies (often BLOCK or WARN)

```bash
grep -rEn "dependencies\s*=\s*\[" <app-path>/migrations/
```

Read every `migrations/*.py` and extract `dependencies = [...]`. Each entry is `(app_label, migration_name)`. Classify each `app_label`:
- The app itself → OK
- Django built-ins (`auth`, `contenttypes`, `sessions`, `admin`, `sites`) → OK
- External packages (e.g., `taggit`) → OK if `[project.dependencies]` will include them
- **Other local app** → **BLOCK** unless that app is also being extracted

Status: BLOCK if any cross-app local dep exists.

### 1.5 `reverse()` / `{% url %}` cross-app coupling (WARN)

```bash
grep -rEn "reverse\(['\"]([^'\"]+):" <app-path> --include="*.py"
grep -rEn "\{%\s*url\s+['\"]([^'\"]+):" <app-path> --include="*.html"
```

For each URL namespace referenced:
- The app's own namespace → OK
- Other local app namespace → **WARN** (package will fail with `NoReverseMatch` unless the consumer wires the other app). Document in README's "requirements" section.
- Built-in (`admin:index`) → OK

### 1.6 Cross-app template extends/includes (WARN)

```bash
grep -rEn "\{%\s*(extends|include)\s+['\"]([^'\"]+)['\"]" <app-path>/templates/
```

For each `extends` / `include` target:
- Path under `<app>/...` → OK (templates are namespaced)
- Path with no namespace (e.g., `base.html`) → **WARN** — the package assumes the consumer provides this template. Document in README.
- Path under another local app namespace (e.g., `other_app/foo.html`) → **WARN** with stronger guidance.

### 1.7 Cross-app signals (WARN or BLOCK)

```bash
grep -rEn "@receiver\(" <app-path>
grep -rEn "\.connect\(" <app-path>
```

For each `@receiver(SIGNAL, sender=X)`:
- `sender` is from same app → OK
- `sender` is Django built-in (`User`, `Group`) → OK
- `sender` is another local app's model → **BLOCK** (creates a hard runtime dependency on a model that isn't installed when the package is)

For `Signal.connect()` calls, same classification.

### 1.8 Cross-app admin registrations (WARN)

```bash
grep -rEn "admin\.site\.register\(" <app-path>/admin.py
```

For each `admin.site.register(Model, ...)`:
- `Model` is defined in the app → OK
- `Model` is imported from another local app → **WARN** — the package will register an admin for something it doesn't own. Usually means the registration should live in the OTHER app or be removed.

### Audit summary table

Present the table like:

| # | Check | Status | Details |
|---|-------|--------|---------|
| 1.1 | Cross-app FKs + dynamic refs | OK / WARN / BLOCK | `<app>/models.py:42` → `accounts.Profile` |
| 1.2 | Cross-app imports | OK / WARN / BLOCK | `<app>/views.py:7`: `from billing.utils import compute_tax` |
| ... | ... | ... | ... |

If any BLOCK: `AskUserQuestion` — *"Continue with N blocking issues (package will be broken until resolved) or abort to refactor in the monolith first?"*. Default = abort.

---

## Step 2: Decisions (ask each via AskUserQuestion, one at a time)

### 2a. OSS or internal?

`AskUserQuestion`: "Will this package be published as OSS (PyPI), or kept internal (editable install / private index)?"

- **OSS**: package is built assuming PyPI publication. README contains install via `pip install <pypi-name>`. The cleanup sub-skill will wire the monolith with a regular dependency line (consumer waits for PyPI release before installing).
- **Internal**: same scaffold, but cleanup sub-skill uses `uv add --editable <path>` or a private index URL.

### 2b. PyPI distribution name (only if OSS)

Suggest `django-<app_name>` if the app doesn't already start with `django-` or `django_`. Show the proposed name and ask confirm. Validate format: lowercase, hyphens not underscores (PEP 503 normalization), no leading digit.

If OSS: also recommend (don't enforce) running `pip index versions <name>` to check PyPI availability — flag as a TODO for the user (the actual PyPI check is in `oss-github-publisher`'s scope, not here).

### 2c. Importable Python name

Suggest the original app name (e.g., if the app was `<monolith>/blog/`, suggest `blog`). This is what goes in `INSTALLED_APPS` of the consuming project. Validate: a valid Python identifier (snake_case, no hyphens).

Show the user the mapping clearly:

```
PyPI dist name:    django-blog
pip install:       pip install django-blog
import / app:      import blog  |  INSTALLED_APPS = [..., "blog"]
```

### 2d. New package location

Ask for an absolute path. Default suggestion: `../<importable-name>/` (sibling to the monolith). Confirm the path does not already exist, OR if it does, that it's empty.

### 2e. Git history strategy

`AskUserQuestion`:

- **Clean `git init`** (default) — new repo, first commit "Initial extraction from `<monolith>` @ `<sha>`". History of the app's files is lost; SHAs are clean.
- **Preserve history via `git filter-repo`** — runs `git filter-repo --subdirectory-filter <app-path>` on a fresh clone of the monolith. Preflight: `command -v git-filter-repo` must succeed. If missing, print the install hint (`brew install git-filter-repo` or `pipx install git-filter-repo`) and ask again (clean init or abort to install).

### 2f. Database engine in tests

Auto-detect Postgres-bound features:

```bash
# Postgres-specific signals
grep -rEn "(ArrayField|HStoreField|JSONField.*postgres|django\.contrib\.postgres|TrigramSimilarity|SearchVector|pg_trgm|pgcrypto|CITEXT)" <app-path>
# Raw SQL with PG dialect (heuristic: RETURNING, ON CONFLICT, ::cast, ILIKE)
grep -rEn "(RETURNING|ON CONFLICT|::int|::text|ILIKE\s)" <app-path> --include="*.py"
```

Present detection results:
- If ANY Postgres signals found → `AskUserQuestion`: *"Detected Postgres-specific features (`<list>`). Recommend `pytest-testcontainers-django` + Postgres in CI. Use Postgres testcontainers, or override to SQLite?"* — default Postgres.
- If NONE found → default SQLite in-memory; ask for confirm.

The choice drives Step 6 (CI workflow shape) and Step 5 (conftest fixtures).

### 2g. Example/demo project

`AskUserQuestion`: "Generate an `example/` Django project demonstrating package usage?" (default Yes for apps with views/urls/admin/templates; default No for utility-only packages with just models or template tags). The example/ project is also used as a CI smoke test (`./manage.py check`, `migrate --run-syncdb`).

### 2h. License

`AskUserQuestion`: MIT (default) / BSD-3-Clause / Apache-2.0 / GPL-3.0 / proprietary. Choice drives `LICENSE` file and `pyproject.toml` `license = "..."` and the classifier.

Save all decisions to a single context dict — they are referenced by every later step.

---

## Step 3: Create the new repo and copy source (commit #1)

1. `mkdir -p <package-path>` and `cd <package-path>`.

2. If **Clean init** (chosen in 2e):
   ```bash
   git init
   git checkout -b main
   ```

3. If **filter-repo** (chosen in 2e):
   ```bash
   # Make sure the monolith's working tree is clean first
   cd <monolith-path> && git status --porcelain
   # Should be empty. If not, abort and ask user to commit/stash.

   git clone <monolith-path> <package-path>
   cd <package-path>
   git filter-repo --subdirectory-filter <app-relative-path>
   git remote remove origin || true
   ```
   After filter-repo, the worktree contains only the app's files at the repo root.

4. **For clean init only**: copy source from monolith into `src/<importable-name>/`:
   ```bash
   mkdir -p src/<importable-name>
   cp -r <monolith>/<app-path>/* src/<importable-name>/
   # Then sanity-check no .pyc / __pycache__ / .DS_Store got copied
   find src/ -name '__pycache__' -o -name '*.pyc' -o -name '.DS_Store' | xargs -r rm -rf
   ```

5. **For filter-repo**: move app contents into `src/<importable-name>/` layout:
   ```bash
   mkdir -p src/<importable-name>
   # Move every top-level file/dir except .git into the src/ subdir
   shopt -s extglob
   git mv !(.git|src) src/<importable-name>/
   ```
   Commit this rearrangement on top of the filter-repo history (so the layout matches what pyproject.toml expects).

6. **Commit** (clean init):
   ```
   Initial extraction from <monolith-name> @ <short-sha>

   Imported <app-name> from <monolith-name> at <short-sha>.
   Source placed in src/<importable-name>/.
   ```

   For filter-repo, the commit message for the rearrangement step:
   ```
   Move filter-repo contents into src/<importable-name>/ layout
   ```

---

## Step 4: `pyproject.toml` + uv (commit #2)

Build `pyproject.toml` derived from the decisions and the monolith's metadata.

### 4a. Detect dependencies

The package depends on:
- `django>=X.Y` — pick the floor as the lowest currently-supported Django series (cross-reference `readme-guardian` SKILL.md's Django × Python matrix; as of 2026-05-08 that's `>=5.2`)
- Anything imported from third-party packages in the app's source (e.g., `import requests` → `requests`)

Detect third-party imports:

```bash
# Strip stdlib, django.*, same-package imports — what's left is third-party
grep -rEh "^(from|import)\s+([a-zA-Z_][a-zA-Z0-9_]*)" src/<importable-name>/ --include="*.py" \
  | awk '{ if ($1 == "from") print $2; else print $2 }' \
  | awk -F. '{print $1}' \
  | sort -u
```

Filter against:
- Stdlib (compare with `python -c "import sys; print(sys.stdlib_module_names)"`)
- `django`, the importable name itself
- Common false-positives: `tests`, `conftest`

What remains is the third-party dependency list. Ask the user to confirm version constraints (`>=2,<3`) for each; offer to leave unpinned for everything.

### 4b. Generate pyproject.toml

```toml
[build-system]
requires = ["setuptools>=75.0"]
build-backend = "setuptools.build_meta"

[project]
name = "<pypi-dist-name>"  # from 2b
version = "0.1.0"           # initial extraction = pre-release
description = "<one-line description; ask user>"
readme = "README.md"
requires-python = ">=3.10"  # ask user — default 3.10
license = "<from 2h>"
authors = [{name = "<from git config user.name>", email = "<from git config user.email>"}]
keywords = ["django", "<derive from app contents>"]
classifiers = [
    "Development Status :: 3 - Alpha",
    "Framework :: Django",
    "Framework :: Django :: 5.2",
    "Framework :: Django :: 6.0",
    "License :: OSI Approved :: <license>",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
    "Programming Language :: Python :: 3.13",
    "Programming Language :: Python :: 3.14",
]
dependencies = [
    "django>=5.2",
    # ... detected third-party deps with constraints
]

[project.optional-dependencies]
test = [
    "pytest>=8",
    "pytest-django>=4.8",
    # If 2f chose Postgres:
    "pytest-testcontainers>=0.4",
    "pytest-testcontainers-django>=0.2",
]
dev = [
    "pre-commit",
    "ruff",
]

[project.urls]
# Filled in later when GitHub remote is added — leave commented placeholders
# Homepage = "https://github.com/<owner>/<repo>"
# Repository = "https://github.com/<owner>/<repo>"
# Issues = "https://github.com/<owner>/<repo>/issues"

[tool.setuptools.packages.find]
where = ["src"]

[tool.setuptools.package-data]
"<importable-name>" = ["templates/**/*", "static/**/*", "locale/**/*"]

[tool.ruff]
target-version = "py310"  # matches requires-python floor

[tool.ruff.lint]
select = ["E", "F", "W"]

[tool.pytest.ini_options]
DJANGO_SETTINGS_MODULE = "tests.settings"
python_files = ["test_*.py", "tests.py"]
addopts = "-ra"
```

**Important:** Cross-reference `readme-guardian` for the Django × Python matrix. Do not hardcode dates — recheck every run.

### 4c. Initialize uv

```bash
uv sync --all-extras
```

Creates `uv.lock`. Decide based on package type — for a library, add `uv.lock` to `.gitignore` (Step 7 generates it). Don't commit `uv.lock` yet.

### 4d. Commit

```
Add pyproject.toml and uv configuration

- name: <pypi-dist-name>
- importable: <importable-name>
- requires-python: >=3.10
- Django constraint: >=5.2 (5.2 LTS + 6.0 supported)
- Dependencies detected from source: <list>
```

---

## Step 5: pytest scaffolding with TDD test stubs (commit #3)

### 5a. Test directory layout

```
tests/
├── __init__.py
├── conftest.py
├── settings.py            # Django settings for tests
├── urls.py                # if app has urls.py — wires <importable>.urls into a tiny test URLconf
├── test_apps.py           # smoke: import the app, AppConfig loads
├── test_models.py         # per-model stub (5b)
├── test_views.py          # per-view stub (5c)
├── test_admin.py          # per-admin stub (5d)
├── test_signals.py        # per-signal stub (5e)
├── test_commands.py       # per-management-command stub (5f)
└── test_templatetags.py   # per-templatetag stub (5g)
```

### 5b. `tests/settings.py`

For **SQLite** (decision 2f):

```python
SECRET_KEY = "test-secret-key-not-for-production"
DEBUG = False

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": ":memory:",
    }
}

INSTALLED_APPS = [
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.admin",
    "django.contrib.staticfiles",
    "<importable-name>",
]

MIDDLEWARE = [
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
]

ROOT_URLCONF = "tests.urls"  # only if app has urls.py

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

STATIC_URL = "/static/"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

USE_TZ = True
```

For **Postgres via testcontainers** (decision 2f):

```python
# Same as SQLite version, but DATABASES is set by conftest.py at test-collection time
# via the testcontainers fixture. Leave a placeholder here.
DATABASES = {}  # populated by conftest.py
```

### 5c. `tests/conftest.py`

For SQLite — minimal:

```python
import os
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "tests.settings")
```

For Postgres testcontainers:

```python
import os
import pytest
from testcontainers.postgres import PostgresContainer

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "tests.settings")


@pytest.fixture(scope="session", autouse=True)
def postgres_container(django_db_setup):
    with PostgresContainer("postgres:16-alpine") as pg:
        os.environ["DB_HOST"] = pg.get_container_host_ip()
        os.environ["DB_PORT"] = str(pg.get_exposed_port(5432))
        os.environ["DB_NAME"] = pg.dbname
        os.environ["DB_USER"] = pg.username
        os.environ["DB_PASS"] = pg.password
        from django.conf import settings as django_settings
        django_settings.DATABASES["default"] = {
            "ENGINE": "django.db.backends.postgresql",
            "NAME": pg.dbname,
            "USER": pg.username,
            "PASSWORD": pg.password,
            "HOST": pg.get_container_host_ip(),
            "PORT": pg.get_exposed_port(5432),
        }
        yield pg
```

### 5d. `tests/urls.py` (only if app has `urls.py`)

```python
from django.urls import include, path

urlpatterns = [
    path("", include("<importable-name>.urls")),
]
```

### 5e. Per-construct test stubs (TDD scaffolding)

For each construct inspected in Step 0c, generate a failing-but-meaningful test stub. The intent: developer fills in the body, removes the `pytest.skip()` marker, runs the test.

**Models** (`tests/test_models.py`) — one test per model class found in `models.py`:

```python
import pytest
from django.db import models
from <importable-name>.models import <ModelName>


@pytest.mark.django_db
def test_<modelname_snake>_can_be_created():
    """Smoke: instance can be created with required fields populated."""
    pytest.skip("TODO: provide required field values and assert .pk")
    obj = <ModelName>(...)
    obj.save()
    assert obj.pk is not None


@pytest.mark.django_db
def test_<modelname_snake>_str_repr():
    """The __str__ method returns a meaningful representation."""
    pytest.skip("TODO: instantiate model and check str() result")
    obj = <ModelName>(...)
    assert str(obj)
```

**Views** (`tests/test_views.py`) — for each view in `views.py` or `views/`:

```python
import pytest
from django.test import Client
from django.urls import reverse


@pytest.fixture
def client():
    return Client()


def test_<view_snake>_url_resolves():
    """The view's URL pattern exists in the URLconf."""
    pytest.skip("TODO: assert reverse('<namespace>:<name>') returns a path")
    # url = reverse("<importable-name>:<view-name>")
    # assert url


@pytest.mark.django_db
def test_<view_snake>_get_anonymous(client):
    """GET as anonymous user — expected status code."""
    pytest.skip("TODO: choose expected status (200 / 302 / 403) and assert")
    # response = client.get(reverse("<importable-name>:<view-name>"))
    # assert response.status_code in (200, 302, 403)
```

**Admin** (`tests/test_admin.py`) — for each `admin.site.register(Model, ...)` call:

```python
import pytest
from django.contrib.auth import get_user_model
from django.test import Client
from django.urls import reverse


@pytest.fixture
def admin_client(db):
    User = get_user_model()
    admin = User.objects.create_superuser("admin", "admin@example.com", "pw")
    c = Client()
    c.force_login(admin)
    return c


@pytest.mark.django_db
def test_<modelname_snake>_admin_changelist(admin_client):
    """The admin changelist loads without 500."""
    pytest.skip("TODO: verify the URL and assert 200")
    # url = reverse("admin:<importable-name>_<modelname-lower>_changelist")
    # response = admin_client.get(url)
    # assert response.status_code == 200
```

**Signals** (`tests/test_signals.py`) — for each `@receiver(...)`:

```python
import pytest


@pytest.mark.django_db
def test_<signal_handler_snake>_fires_on_<event>():
    """The receiver runs when its signal fires."""
    pytest.skip("TODO: trigger the signal source and assert the side-effect")
```

**Management commands** (`tests/test_commands.py`) — for each `management/commands/<name>.py`:

```python
import pytest
from django.core.management import call_command


@pytest.mark.django_db
def test_<command_snake>_runs():
    """The management command completes without exception."""
    pytest.skip("TODO: provide required args and assert side-effects")
    # call_command("<command-name>", ...)
```

**Template tags** (`tests/test_templatetags.py`) — for each registered tag/filter:

```python
import pytest
from django.template import Context, Template


def test_<tag_snake>_renders():
    """The template tag renders without error."""
    pytest.skip("TODO: provide a template using the tag and assert rendered output")
    # tmpl = Template("{% load <library-name> %}{% <tagname> %}")
    # rendered = tmpl.render(Context({...}))
    # assert rendered
```

**Apps** (`tests/test_apps.py`) — always:

```python
def test_app_imports():
    import <importable-name>
    assert <importable-name>


def test_appconfig_loads():
    from django.apps import apps
    config = apps.get_app_config("<importable-name>")
    assert config.name == "<importable-name>"
```

### 5f. Migrate existing tests (if any)

If the monolith's app contained `tests/` or `test_*.py` files, copy them into `tests/`, replacing only imports:
- `from <monolith>.<app>.X` → `from <importable-name>.X`
- Path imports that referenced other local apps → flag as TODO comment at the top of the file (couldn't auto-resolve; user must decide)

Do NOT rewrite test bodies. Do NOT convert `unittest.TestCase` to pytest functions.

### 5g. Run tests locally

```bash
uv run pytest -v
```

Expected: every stub `SKIP`s with the TODO message; `test_app_imports`, `test_appconfig_loads`, and any migrated tests run for real. If migrated tests fail, that's diagnostic — surface the failure to the user, do not silently fix.

### 5h. Commit

```
Add pytest scaffolding with TDD test stubs

- tests/settings.py for <sqlite | postgres-testcontainers>
- conftest.py with <minimal | postgres fixture>
- One stub per: model, view, admin, signal, command, templatetag
- Apps smoke test (test_apps.py)
- Existing tests (if any) migrated with import paths rewritten
```

---

## Step 6: GitHub Actions CI (commit #4)

Create `.github/workflows/tests.yml`.

### 6a. Derive the matrix

Same logic as `python-upgrade-package` Step 4 — cross-reference `readme-guardian`'s canonical Django × Python compatibility table. As of 2026-05-08: 5.2 LTS (3.10–3.14) and 6.0 (3.12–3.14).

### 6b. Workflow for SQLite

```yaml
name: Tests

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        include:
          # Django 5.2 LTS
          - { python-version: "3.10", django-version: "5.2" }
          - { python-version: "3.11", django-version: "5.2" }
          - { python-version: "3.12", django-version: "5.2" }
          - { python-version: "3.13", django-version: "5.2" }
          - { python-version: "3.14", django-version: "5.2" }
          # Django 6.0
          - { python-version: "3.12", django-version: "6.0" }
          - { python-version: "3.13", django-version: "6.0" }
          - { python-version: "3.14", django-version: "6.0" }
    steps:
      - uses: actions/checkout@v4
      - name: Install uv
        uses: astral-sh/setup-uv@v5
      - name: Set up Python ${{ matrix.python-version }}
        run: uv python install ${{ matrix.python-version }}
      - name: Install dependencies
        run: |
          uv sync --all-extras
          uv pip install "django~=${{ matrix.django-version }}.0"
      - name: Run tests
        run: uv run pytest -v
```

### 6c. Workflow for Postgres testcontainers (decision 2f)

Testcontainers manages its own Docker container — no need for `services:` block. But the runner needs Docker, which ubuntu-latest provides. Add a smoke step:

```yaml
      - name: Verify Docker available (testcontainers)
        run: docker info
```

The test step is unchanged — pytest-testcontainers-django spins up Postgres at session-scope.

### 6d. Lint job (informational only)

```yaml
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install uv
        uses: astral-sh/setup-uv@v5
      - name: Set up Python
        run: uv python install 3.13
      - name: Install dependencies
        run: uv sync --all-extras
      - name: Lint with ruff
        run: uv run ruff check . || true
      - name: Check formatting with ruff
        run: uv run ruff format --check . || true
```

### 6e. Example project smoke test (only if decision 2g = Yes)

Append after the lint job:

```yaml
  example-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install uv
        uses: astral-sh/setup-uv@v5
      - name: Set up Python
        run: uv python install 3.13
      - name: Install dependencies
        run: uv sync --all-extras
      - name: Django check on example project
        run: |
          cd example
          uv run python manage.py check
          uv run python manage.py migrate --run-syncdb --no-input
```

### 6f. Commit

```
Add GitHub Actions test workflow

- Matrix: Python 3.10–3.14 × Django 5.2/6.0 (5.2 LTS + 6.0 latest)
- Database: <SQLite | Postgres via testcontainers>
- Lint job: ruff check + format (informational)
<- Example project: ./manage.py check + migrate --run-syncdb (if 2g=Yes)>
```

---

## Step 7: Tooling — pre-commit, license, gitignore, README (commit #5)

### 7a. `.pre-commit-config.yaml`

Same template as `python-upgrade-package` Step 3. Derive `pyupgrade --pyXY-plus` and `django-upgrade --target-version` from `requires-python` and Django floor respectively.

```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
      - id: detect-private-key

  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.11.0
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format

  - repo: https://github.com/asottile/pyupgrade
    rev: v3.20.0
    hooks:
      - id: pyupgrade
        args: [--py310-plus]   # derived from requires-python

  - repo: https://github.com/adamchainz/django-upgrade
    rev: 1.22.2
    hooks:
      - id: django-upgrade
        args: [--target-version, "5.2"]   # derived from Django floor
```

### 7b. `LICENSE`

Write the chosen license (2h). Templates:
- MIT: `https://opensource.org/licenses/MIT`
- BSD-3-Clause, Apache-2.0, GPL-3.0: standard SPDX templates.
- Year = current year (from `date +%Y`). Holder = git config user.name.

### 7c. `.gitignore`

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

# Virtual envs
.venv/
venv/

# IDE
.idea/
.vscode/
*.swp

# Testing
.pytest_cache/
.coverage
htmlcov/
.tox/

# uv (library — do not commit lockfile)
uv.lock

# Local DBs / artifacts
*.sqlite3
*.sqlite3-journal

# OS
.DS_Store
```

### 7d. `README.md` — minimal-but-correct

Generate a starter README. `readme-guardian` (Step 10 chaining) will polish it.

```markdown
# <pypi-dist-name>

<one-line description from pyproject.toml>

## Installation

```bash
pip install <pypi-dist-name>
```

Add to your Django project's `INSTALLED_APPS`:

```python
INSTALLED_APPS = [
    # ...
    "<importable-name>",
]
```

<If app has urls.py:>

Include the URLs in your project's `urls.py`:

```python
urlpatterns = [
    # ...
    path("<importable-name>/", include("<importable-name>.urls")),
]
```

## Requirements

- Python ≥ 3.10
- Django ≥ 5.2

## Settings

<For each project-specific setting found in Step 1.3, list with default and description.
 Mark as TODO if no default was derivable.>

## Development

```bash
git clone <repo>
cd <repo>
uv sync --all-extras
uv run pytest
```

## License

<License name> — see [LICENSE](./LICENSE).
```

### 7e. `CHANGELOG.md`

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial extraction from `<monolith-name>` @ `<sha>`.
```

### 7f. Commit

```
Add pre-commit, license, gitignore, README, CHANGELOG

- .pre-commit-config.yaml: ruff + pyupgrade --py310-plus + django-upgrade --target-version 5.2
- LICENSE: <chosen license>
- .gitignore: Python + Django + uv
- README.md: install instructions, settings contract, dev setup
- CHANGELOG.md: Keep a Changelog format
```

---

## Step 8: Example/demo project (commit #6, only if decision 2g = Yes)

### 8a. Layout

```
example/
├── manage.py
├── example_project/
│   ├── __init__.py
│   ├── settings.py
│   ├── urls.py
│   └── wsgi.py
└── README.md
```

### 8b. `example/example_project/settings.py`

Mirror `tests/settings.py` but with file-backed SQLite (`db.sqlite3` next to manage.py) and DEBUG=True:

```python
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
SECRET_KEY = "example-not-for-production"
DEBUG = True
ALLOWED_HOSTS = ["*"]

INSTALLED_APPS = [
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.admin",
    "django.contrib.staticfiles",
    "<importable-name>",
]

MIDDLEWARE = [
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
]

ROOT_URLCONF = "example_project.urls"

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": BASE_DIR / "db.sqlite3",
    }
}

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

STATIC_URL = "/static/"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
USE_TZ = True
```

### 8c. `example/example_project/urls.py`

```python
from django.contrib import admin
from django.urls import include, path

urlpatterns = [
    path("admin/", admin.site.urls),
]

# Only if package has urls.py:
# urlpatterns += [path("<importable-name>/", include("<importable-name>.urls"))]
```

### 8d. `manage.py`

Standard Django manage.py template.

### 8e. `example/README.md`

```markdown
# Example project for `<pypi-dist-name>`

Quick demo of the package in a minimal Django project.

```bash
cd example
uv run python manage.py migrate
uv run python manage.py runserver
```

Then visit http://127.0.0.1:8000/admin/ (create a superuser first with `createsuperuser`).
```

### 8f. Commit

```
Add example/ project demonstrating package usage
```

---

## Step 9: Local verification (no commit)

Before chaining into the polish skills, verify the package builds and tests pass.

```bash
uv sync --all-extras
uv run pytest -v
uv run pre-commit run --all-files     # this is the new package, formatting it is OK
uv build
uv run --with twine twine check dist/*
rm -rf dist/  # don't commit build artifacts
```

Each command's expected result:
- `pytest`: every TODO test SKIPs (intentional — developer fills in), real tests (app smoke, migrated tests) pass
- `pre-commit run --all-files`: passes after possible auto-fixes (ruff format, end-of-file-fixer)
- `uv build`: produces both sdist (`*.tar.gz`) and wheel (`*.whl`)
- `twine check dist/*`: every line `PASSED`

If pre-commit makes changes, commit them as:

```
Apply pre-commit auto-formatting to extracted source
```

If any verification step fails, **stop** and report the failure to the user. Do not auto-fix package metadata (e.g., classifier typos) — surface the actual error so the user can decide.

---

## Step 10: Chaining + final report

### 10a. Run `readme-guardian` (after AskUserQuestion)

`AskUserQuestion`: *"Run `/readme-guardian:readme-guardian` on the new package's README to polish it (badges, install instructions, Django × Python matrix table)?"*. Default Yes.

If Yes, invoke via the `Skill` tool:

```
Skill: readme-guardian:readme-guardian
args: (none — it auto-detects from pwd; ensure we're cd'd into <package-path>)
```

### 10b. Run `oss-github-publisher` (after AskUserQuestion)

`AskUserQuestion`: *"Run `/oss-github-publisher:oss-github-publisher` for the full pre-publication audit (LICENSE, secrets, PII, hostnames, GH Actions security, PyPI metadata)?"*. Default Yes.

Invoke via the `Skill` tool:

```
Skill: oss-github-publisher:oss-github-publisher
```

### 10c. Final report

```
Django Reusable App Extraction Summary — <pypi-dist-name>
=========================================================

Source app:        <monolith-name>/<app-path>
Target package:    <package-path>
PyPI dist name:    <pypi-dist-name>
Importable name:   <importable-name>
License:           <license>
DB in tests:       <SQLite | Postgres testcontainers>
Example project:   <Yes | No>
History strategy:  <clean init | filter-repo>

Commits in new repo:
  <list each commit one-liner>

Audit findings (Step 1):
  <repeat the table>

Verification (Step 9):
  uv build:    PASSED
  twine check: PASSED
  pytest:      <N> passed, <N> skipped (TDD stubs)
  pre-commit:  PASSED

Chained skills:
  readme-guardian:        <ran | skipped>
  oss-github-publisher:   <ran | skipped>

Next steps (you):
  1. Add a GitHub remote and push:
     cd <package-path>
     git remote add origin git@github.com:<owner>/<repo>.git
     git push -u origin main
  2. <If OSS:> Publish to PyPI when ready (TestPyPI first).
  3. Run `/django-extract-app:django-extract-app-cleanup` in the monolith
     to wire in the package as a dependency and remove the original app/.
  4. Fill in TDD test stubs in tests/test_*.py — each currently SKIPs with
     a TODO message describing what to assert.
```

---

## Common Mistakes

| Mistake | Prevention |
|---|---|
| Modifying the monolith during extraction | Iron Law #1. Only the cleanup sub-skill touches the monolith. |
| Skipping the Step 1 audit because the app "looks simple" | Always run all 8 checks. Hidden cross-app deps are common in even small apps. |
| Hardcoding the Python × Django matrix | Always derive from `requires-python` + `readme-guardian` canonical table. |
| Copying tests verbatim without rewriting imports | Imports MUST be rewritten — `from <monolith>.<app>.X` → `from <importable>.X`. Other monolith imports get flagged as TODO. |
| Generating test stubs that pass trivially | Stubs MUST `pytest.skip("TODO: ...")` so failure to fill them in is visible. Stubs passing silently is worse than nothing. |
| Committing `uv.lock` for a library | This is a library — `uv.lock` belongs in `.gitignore`. |
| Running `git filter-repo` without a clean monolith working tree | Filter-repo on a dirty tree silently drops uncommitted changes. Always check `git status --porcelain` is empty first. |
| Generating an empty `templates/<app>/` placeholder | Only copy template directories that actually have files. Empty dirs confuse `package-data`. |
| Forgetting `ROOT_URLCONF` in tests/settings.py when app has urls.py | `pytest.mark.django_db` views tests will 404 if URL config is unset. Detect presence of `urls.py` in Step 0c and set `ROOT_URLCONF` accordingly. |
| Auto-converting cross-app FKs to swappable | Don't try. The user decides whether to make it swappable (with the `settings.MYAPP_FOO_MODEL` pattern) or refactor the coupling. The audit flags, the user decides. |
| Treating WARN as BLOCK | WARN is informational — package ships, README documents the requirement. BLOCK means the package will be broken. Only BLOCK triggers the abort prompt. |
| Running `oss-github-publisher` before the new repo has any commits | The skill needs commits to audit. Step 3–8 must have run first. |
| Forgetting to chain `readme-guardian` BEFORE `oss-github-publisher` | `oss-github-publisher` audits README content quality — running it first means readme-guardian's improvements aren't audited. Order matters: readme-guardian → oss-github-publisher. |

## Red Flags — STOP

- "I'll silently fix the cross-app import by copying the helper" — **NO.** The audit flags it; the user decides whether to copy/refactor/abort. Never silently rewrite imports.
- "I'll fix the FK by changing it to `settings.AUTH_USER_MODEL`" — **NO.** Even if it IS `auth.User`, the user must confirm. Never auto-swappable.
- "I'll delete the source app from the monolith too while I'm at it" — **NO.** That's the cleanup sub-skill's job, separate confirmation.
- "I'll skip the audit, the user said extract this app" — **NO.** Always audit. The user may not know about a cross-app FK they wrote 3 years ago.
- "The example project is just boilerplate, I'll skip the AskUserQuestion" — **NO.** Every decision goes through AskUserQuestion (Iron Law #3).
- "I'll generate `os.environ['DJANGO_SETTINGS_MODULE'] = ...`" — **NO.** Use `setdefault()`. Direct assignment overwrites consumer-set values.
- "Tests are failing after migration — I'll fix them" — **NO.** Migrated tests failing is a diagnostic signal. Surface to user, don't fix.
- "I'll run `pyupgrade` / `django-upgrade` on the whole extracted source to modernize it" — **NO.** Minimal-diff principle. The pre-commit hooks only fire on staged files; bulk runs defeat that.
- "PyPI name `django-foo` is probably available, I'll skip the check" — **NO.** Flag the name check as a TODO; the `oss-github-publisher` chain does the actual PyPI availability check.
