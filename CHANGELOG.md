# Changelog

All releases follow [CalVer](https://calver.org/) — `YYYY.0M.MICRO`. The marketplace and all plugins ship in lockstep: every release re-tags every plugin with the same version.

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
