# claude-skills

A collection of [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skills for Python, DevOps, code review, and decision-making workflows, distributed as a plugin marketplace.

## Available Plugins

| Plugin | Description |
|--------|-------------|
| [code-review-external](plugins/code-review-external/) | Parallel external code review with codex, opencode, and a Claude subagent — runs all three reviewers concurrently on a diff, commit, file, or directory and surfaces three independent opinions side-by-side |
| [github-build-fixer](plugins/github-build-fixer/) | Diagnoses and fixes failing GitHub Actions CI builds — reads logs, proposes fixes, pushes, polls until green |
| [oss-github-publisher](plugins/oss-github-publisher/) | Pre-flight audit before publishing a repo as open source — checks LICENSE, CI, pre-commit, scans for secrets and PII |
| [premortem](plugins/premortem/) | Klein-style premortem on plans, launches, hires, pricing, or strategy — assumes failure 6 months out and works backward to expose blind spots |
| [python-upgrade-package](plugins/python-upgrade-package/) | Modernizes legacy Python packages step-by-step — setup.py to uv + pyproject.toml, Travis to GitHub Actions, pytest migration |
| [readme-guardian](plugins/readme-guardian/) | Analyzes and improves Python project READMEs — badges, install instructions, version support matrix |

## Installation

### Step 1: Add the marketplace

In Claude Code, run:

```
/plugin marketplace add iplweb/claude-skills
```

### Step 2: Install the plugins you want

```
/plugin install code-review-external@iplweb-claude-skills
/plugin install github-build-fixer@iplweb-claude-skills
/plugin install oss-github-publisher@iplweb-claude-skills
/plugin install premortem@iplweb-claude-skills
/plugin install python-upgrade-package@iplweb-claude-skills
/plugin install readme-guardian@iplweb-claude-skills
```

Install only the ones you need — each plugin is independent.

## Usage

Once installed, skills activate automatically based on context, or you can invoke them explicitly:

- `/code-review-external:code-review-external` — three parallel reviews (codex + opencode + Claude subagent) of a diff, commit, file, or directory
  - `/code-review-external:code-review-codex` — only codex
  - `/code-review-external:code-review-opencode` — only opencode
  - `/code-review-external:code-review-claude` — only a Claude subagent
- `/github-build-fixer:github-build-fixer` — when CI is failing on your branch
- `/oss-github-publisher:oss-github-publisher` — before publishing a repo as open source
- `/premortem:premortem` — to stress-test a plan, launch, or decision by imagining it has already failed
- `/python-upgrade-package:python-upgrade-package` — to modernize a legacy Python package
- `/readme-guardian:readme-guardian` — to improve a project's README

### code-review-external — argument forms

All four `code-review-external` skills accept the same positional argument and auto-detect the target type:

| Argument | Target |
|----------|--------|
| _(none)_ | Uncommitted changes (staged + unstaged + untracked) |
| `HEAD~3`, `<sha>`, branch name | A single commit (`git rev-parse` resolvable) |
| `path/to/file.py` | A single file (review the whole file) |
| `path/to/dir/` | A directory (review key files in it) |

Reviews are saved to `/tmp/code-review-{codex,opencode,claude}-<timestamp>.md` and printed side-by-side. The `code-review-external` wrapper requires both `codex` and `opencode` CLIs on `$PATH`; the individual sub-skills only require their own tool. For GitHub PR review use the official `/code-review:code-review` skill instead — it has a multi-agent pipeline with confidence scoring and posts the comment back to the PR.

## Versioning

This marketplace uses [CalVer](https://calver.org/) — `YYYY.0M.MICRO` (e.g. `2026.05.0`, `2026.05.1`, `2026.06.0`).

- `YYYY` — full year
- `0M` — zero-padded month (01–12)
- `MICRO` — release counter within the month, starting at 0

All plugins ship in **lockstep**: every release re-tags every plugin and the marketplace itself with the same version. There are no per-plugin version trains — if any plugin changes, the next release bumps everything.

Current version: see [`CHANGELOG.md`](CHANGELOG.md) for the release history. To cut a release run `scripts/bump-version.sh <YYYY.0M.MICRO>` (or `--auto` for the next sensible value).

## License

MIT — see [LICENSE](LICENSE) for details.
