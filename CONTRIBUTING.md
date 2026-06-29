# Contributing

This repo is a **Claude Code plugin marketplace**. Each plugin is a directory
under `plugins/` and is registered in `.claude-plugin/marketplace.json`.

## Layout of a plugin

```
plugins/<name>/
├── .claude-plugin/
│   └── plugin.json          # name, description, version, author, keywords
└── skills/
    └── <skill>/
        └── SKILL.md         # YAML front matter (name + description) + body
```

Invariants the tooling enforces (see `scripts/validate.py`):

- plugin **name == directory name == marketplace entry name**,
- marketplace `source` is `./plugins/<name>`,
- **lockstep versioning**: every `plugin.json` and every marketplace entry use
  the same `version` as the marketplace itself,
- every `plugins/<dir>` is registered (no orphans) and vice-versa,
- every `skills/<x>/SKILL.md` has front matter with `name` (matching its
  directory) and `description`.

## Add a plugin

```bash
python3 scripts/new-plugin.py my-plugin "One-line description of what it does."
# edit plugins/my-plugin/skills/my-plugin/SKILL.md
python3 scripts/validate.py        # must pass
```

`new-plugin.py` scaffolds the directory, the `plugin.json`, a `SKILL.md` stub,
and the marketplace entry at the current marketplace version.

## Validate

```bash
python3 scripts/validate.py        # checks all invariants above
pre-commit run --all-files         # check-json, eof, whitespace, validate
```

CI (`.github/workflows/validate.yml`) runs `validate.py` on every push and PR.

## Release

All plugins ship in **lockstep** — a release re-tags every plugin and the
marketplace with the same version:

```bash
scripts/bump-version.sh <YYYY.0M.MICRO>   # or --auto for the next value
```

## Notes

- Some plugins are **iplweb/BPP-specific** (e.g. `ticket-resolver`, `freshdesk`
  hardcode the iplweb Freshdesk account and the `iplweb/bpp` repo). They live
  here for versioning and reuse across the author's machines, not as general
  reusable tools — keep that in mind before depending on them elsewhere.
- `statusline/` is an **extra**, not a plugin (a `statusLine` script), so it is
  not part of the marketplace and not checked by `validate.py`.
