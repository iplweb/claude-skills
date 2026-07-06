---
name: django-run-site
description: Use when working in a Django project that may have a dev stack started by run-site (django-run-site) and/or django-dev-helpers — to tell whether the dev server is running, find its web URL/port, locate the Postgres/Redis/SQLite endpoints and credentials, make an authenticated request via autologin, understand the .run-site-config sidecar and .dev_helpers_* dotfiles, or know what run-site can do. Also when a background run-site process needs inspecting, stopping, or restarting.
---

# django-run-site & django-dev-helpers

## Overview

Two cooperating tools for local Django development. Either works standalone;
neither imports the other — they communicate through env vars and files.

- **run-site** (PyPI `django-run-site`, command `run-site`) — a pure CLI
  orchestrator. Starts Postgres/Redis containers, picks free ports, runs
  `migrate` + `createsuperuser`, then launches `manage.py runserver` and
  multiplexes its logs. Does **not** import Django.
- **django-dev-helpers** — a Django app added to the project's
  `INSTALLED_APPS`. Adds token-based **autologin**, writes convenience
  **dotfiles**, and prints an "agent help" banner.

**Mental model:** run-site writes ONE authoritative file
`.run-site-config` (all endpoints, including the DB password). dev-helpers
writes several tiny single-value `.dev_helpers_*` dotfiles plus an autologin
token. **Their presence signals a running stack** — but confirm with a quick
probe (an unclean shutdown can leave them behind; see below).

## Recognizing a run-site project

Even with nothing running:
- `runsite.toml` at or above the project root, **or** a `[tool.run-site]`
  table in `pyproject.toml`. run-site walks parent dirs to find it.

A stack is **running right now** when these appear at the project root:
- `.run-site-config` → a run-site stack is up (removed on clean shutdown).
- `.dev_helpers_*` dotfiles → django-dev-helpers is active in that server.
- A missing file means the server isn't running **or** that service isn't
  used (a SQLite project has no `.dev_helpers_pg_*`).

**These files are a strong hint, not proof.** An unclean shutdown can leave
them behind. Confirm the server is actually up before trusting them:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' --max-time 4 "$(python3 -c 'import tomllib;print(tomllib.load(open(".run-site-config","rb"))["web"]["url"])')"
# connection refused / 000 → the files are stale leftovers, not a live server
```

## File map (all at the project root)

| File | Writer | Contents | Perms |
|---|---|---|---|
| `.run-site-config` | run-site | TOML: `project_slug`, `generated_at`, `[web]` host/port/url, `[postgres]` host/port/db/user/password/url, `[sqlite]` path/url/ephemeral, `[redis]` host/port/db/url, `[celery]` enabled/app. Section omitted when its service is off. | 0600 (plaintext DB password) |
| `.dev_helpers_token` | dev-helpers | autologin token (opaque string) | 0600 |
| `.dev_helpers_port` | dev-helpers | runserver port | 0644 |
| `.dev_helpers_pg_host` / `.dev_helpers_pg_port` | dev-helpers | Postgres host / host-side port | 0644 |
| `.dev_helpers_redis_host` / `.dev_helpers_redis_port` | dev-helpers | Redis host / host-side port | 0644 |

Ports are **dynamic** — run-site maps containers to random free host ports
and picks a free web port. **Never assume 8000 / 5432 / 6379; read the
actual value from the file.**

## Reading the endpoints

Prefer `.run-site-config` when present — it is authoritative and ships
ready-made connection URLs (and the DB password). Fall back to `.dev_helpers_*`.

```bash
# Web URL
python3 -c 'import tomllib;print(tomllib.load(open(".run-site-config","rb"))["web"]["url"])'
echo "http://localhost:$(cat .dev_helpers_port)/"          # dev-helpers fallback

# Postgres — full DSN incl. password (sidecar only)
python3 -c 'import tomllib;print(tomllib.load(open(".run-site-config","rb"))["postgres"]["url"])'
psql "$(python3 -c 'import tomllib;print(tomllib.load(open(".run-site-config","rb"))["postgres"]["url"])')"
psql -h "$(cat .dev_helpers_pg_host)" -p "$(cat .dev_helpers_pg_port)" -U <user> -d <db>   # dotfiles = host/port only; user/db/password come from .run-site-config [postgres]

# Redis
redis-cli -h "$(cat .dev_helpers_redis_host)" -p "$(cat .dev_helpers_redis_port)"
```

Prefer the sidecar `url` fields — they already embed the real host and port
(the `127.0.0.1`/`localhost` fallbacks assume runserver bound to localhost,
the default). SQLite projects have `[sqlite] path` in the sidecar instead of
`[postgres]` — a local file, no host/port. `[celery]` records only
`enabled`/`app`, **not** a broker URL — Celery's broker is usually this same
Redis, but confirm in the project's settings before assuming.

## Authenticated HTTP request (autologin — needs django-dev-helpers)

dev-helpers exposes a token-gated autologin endpoint (default
`/__autologin__/`, default user `admin`, `DEBUG=True` only). Exchange the
token for a session cookie, then reuse the cookie jar:

```bash
TOKEN=$(cat .dev_helpers_token)
PORT=$(cat .dev_helpers_port)
JAR=$(mktemp)
curl -sc "$JAR" -L "http://localhost:$PORT/__autologin__/?token=$TOKEN" >/dev/null
curl -sb "$JAR" "http://localhost:$PORT/<path>"     # now authenticated as admin
rm "$JAR"
```

Without dev-helpers there is no autologin — you only reach the public site
(run-site opens the browser on the homepage, not a login).

dev-helpers may also inject a static help block into `CLAUDE.md` / `AGENTS.md`
between `<!-- django-dev-helpers:agent-help -->` markers, and ships
`manage.py dev_helpers_doctor` / `dev_helpers_print_help` for on-demand info.

## What run-site can do

`run-site <cmd>`; run `run-site <cmd> --help` for the full flag list.

- `run-site run` — spin up the dev stack (default). Short form:
  `run-site path/to/manage.py`.
- `run-site init` — generate a starter `runsite.toml`.
- `run-site doctor` — sanity-check config + tooling (Docker, manage.py, ports).
- `run-site --version`.

Useful `run` flags: `--from-git URL` / `--from-path` (+ `--branch/--commit/--tag`)
run a repo checkout; `--reuse` / `--no-reuse` keep containers warm between runs;
`--no-postgres` / `--no-redis` / `--sqlite` choose backing services;
`--from-dump PATH` load a DB dump; `--port` / `--bind` control runserver;
`--no-migrate` / `--no-superuser`; `--with-celery` / `--with-celery-beat`;
`--no-browser`; `--print-env` (`--print-secrets` to unredact); `--dry-run`;
`-y` for CI.

## A run-site started in the background

run-site runs in the foreground and streams runserver logs to stdout; an agent
usually launches it as a background task. **There is no control socket or IPC**
— use these primitives:

- **Ready?** No explicit "ready" marker exists. Poll for `.run-site-config`
  (or `.dev_helpers_port`) to appear, then `curl` the web URL until it answers.
  Containers + `migrate` take time — don't assume it's up the instant you launch it.
- **Logs:** read the background task's stdout. The `web`, `postgres`, migrate,
  and hook streams are multiplexed and labeled.
- **Endpoints:** read the files above — don't scrape the logs.
- **Stop:** send SIGINT/SIGTERM (Ctrl-C equivalent), or kill the background
  task that owns it. run-site shuts down gracefully — stops/removes its
  containers, removes `.run-site-config`, and prints a report of what it removed.
- **Restart:** stop, then launch again; `--reuse` keeps containers warm so it's fast.
- **Stale files:** a leftover `.run-site-config` whose web URL doesn't answer
  means a dead/crashed run, not a live server. Verify by probing the URL.

## Common mistakes

- Assuming default ports — they're random; read the files.
- Committing these files — they're per-run runtime state and the sidecar
  holds a plaintext password. They belong in `.gitignore`.
- Expecting autologin without django-dev-helpers installed — it's a separate
  package; check `INSTALLED_APPS` or the presence of `.dev_helpers_token`.
- Trying to "contact" run-site over a port/socket for control — there's no IPC;
  use signals + the files + the task's stdout.
