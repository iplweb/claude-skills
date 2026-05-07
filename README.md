# claude-skills

A collection of [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skills for Python, DevOps, code review, and decision-making workflows, distributed as a plugin marketplace.

## Available Plugins

| Plugin | Description |
|--------|-------------|
| [code-review-external](plugins/code-review-external/) | Parallel external code review with codex, opencode, and a Claude subagent — runs all three reviewers concurrently on a diff, commit, file, or directory and surfaces three independent opinions side-by-side |
| [github-build-fixer](plugins/github-build-fixer/) | Diagnoses and fixes failing GitHub Actions CI builds — reads logs, proposes fixes, pushes, polls until green |
| [oss-github-publisher](plugins/oss-github-publisher/) | Pre-flight audit before publishing a repo as open source — checks LICENSE, CI, pre-commit, scans for secrets and PII |
| [premortem](plugins/premortem/) | Klein-style premortem on plans, launches, hires, pricing, or strategy — assumes failure 6 months out and works backward to expose blind spots |
| [premortem-multiple](plugins/premortem-multiple/) | Three parallel premortems (codex + opencode + Claude subagent) on the same plan, synthesized into one unified document — consensus failures, divergent blind spots, hidden assumptions, combined revised plan |
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
/plugin install premortem-multiple@iplweb-claude-skills
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
- `/premortem-multiple:premortem-multiple` — three parallel premortems (codex + opencode + Claude subagent) on the same plan, synthesized into a single unified document
  - `/premortem-multiple:premortem-codex` — only codex
  - `/premortem-multiple:premortem-opencode` — only opencode
  - `/premortem-multiple:premortem-claude` — only a Claude subagent
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

## Using with Codex

These skill folders can be used directly with Codex because each one contains a `SKILL.md` file. Codex discovers user-installed skills from `$CODEX_HOME/skills`; if `CODEX_HOME` is not set, that defaults to `~/.codex/skills`.

Symlink the skill you want into Codex's skills directory:

```bash
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"
ln -s "$(pwd)/plugins/<plugin>/skills/<skill-name>" \
  "${CODEX_HOME:-$HOME/.codex}/skills/<skill-name>"
```

For example:

```bash
ln -s "$(pwd)/plugins/readme-guardian/skills/readme-guardian" \
  "${CODEX_HOME:-$HOME/.codex}/skills/readme-guardian"
```

### Quick setup (all skills, global)

```bash
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"
for dir in plugins/*/skills/*/; do
  skill=$(basename "$dir")
  ln -sfn "$(pwd)/$dir" "${CODEX_HOME:-$HOME/.codex}/skills/$skill"
done
```

Restart Codex after linking so it reloads the skill metadata.

Once installed, invoke a skill by naming it in your prompt, for example:

```text
Use the readme-guardian skill to improve this project's README.
Use the python-upgrade-package skill to modernize this package.
```

In Codex interfaces that support explicit skill mentions, you can also reference the skill directly, for example `$readme-guardian`.

The Claude Code slash-command forms above, such as `/readme-guardian:readme-guardian`, are Claude Code commands. In Codex, use natural-language skill names or explicit skill mentions instead.

## Using with OpenCode

These skills also work with [OpenCode](https://opencode.ai). OpenCode discovers skills from specific directories — symlink each skill folder into a discoverable location:

```bash
# Global (available in all projects)
ln -s "$(pwd)/plugins/<plugin>/skills/<skill-name>" \
  ~/.config/opencode/skills/<skill-name>

# Or per-project
ln -s "$(pwd)/plugins/<plugin>/skills/<skill-name>" \
  .opencode/skills/<skill-name>
```

OpenCode scans these paths for `SKILL.md` files:

| Location | Scope |
|----------|-------|
| `.opencode/skills/<name>/SKILL.md` | Project |
| `~/.config/opencode/skills/<name>/SKILL.md` | Global |
| `.claude/skills/<name>/SKILL.md` | Project (Claude-compatible) |
| `~/.claude/skills/<name>/SKILL.md` | Global (Claude-compatible) |
| `.agents/skills/<name>/SKILL.md` | Project |
| `~/.agents/skills/<name>/SKILL.md` | Global |

### Quick setup (all skills, global)

```bash
mkdir -p ~/.config/opencode/skills
for dir in plugins/*/skills/*/; do
  skill=$(basename "$dir")
  ln -sf "$(pwd)/$dir" ~/.config/opencode/skills/"$skill"
done
```

After linking, OpenCode will list the skills in the `skill` tool and agents can load them on demand. See the [OpenCode skills docs](https://opencode.ai/docs/skills/) for details.

## Versioning

This marketplace uses [CalVer](https://calver.org/) — `YYYY.0M.MICRO` (e.g. `2026.05.0`, `2026.05.1`, `2026.06.0`).

- `YYYY` — full year
- `0M` — zero-padded month (01–12)
- `MICRO` — release counter within the month, starting at 0

All plugins ship in **lockstep**: every release re-tags every plugin and the marketplace itself with the same version. There are no per-plugin version trains — if any plugin changes, the next release bumps everything.

Current version: see [`CHANGELOG.md`](CHANGELOG.md) for the release history. To cut a release run `scripts/bump-version.sh <YYYY.0M.MICRO>` (or `--auto` for the next sensible value).

## License

MIT — see [LICENSE](LICENSE) for details.
