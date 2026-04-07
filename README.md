# claude-skills

A collection of [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skills for Python and DevOps workflows, distributed as a plugin marketplace.

## Available Plugins

| Plugin | Description |
|--------|-------------|
| [github-build-fixer](plugins/github-build-fixer/) | Diagnoses and fixes failing GitHub Actions CI builds — reads logs, proposes fixes, pushes, polls until green |
| [oss-github-publisher](plugins/oss-github-publisher/) | Pre-flight audit before publishing a repo as open source — checks LICENSE, CI, pre-commit, scans for secrets and PII |
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
/plugin install github-build-fixer@iplweb-claude-skills
/plugin install oss-github-publisher@iplweb-claude-skills
/plugin install python-upgrade-package@iplweb-claude-skills
/plugin install readme-guardian@iplweb-claude-skills
```

Install only the ones you need — each plugin is independent.

## Usage

Once installed, skills activate automatically based on context, or you can invoke them explicitly:

- `/github-build-fixer:github-build-fixer` — when CI is failing on your branch
- `/oss-github-publisher:oss-github-publisher` — before publishing a repo as open source
- `/python-upgrade-package:python-upgrade-package` — to modernize a legacy Python package
- `/readme-guardian:readme-guardian` — to improve a project's README

## License

MIT — see [LICENSE](LICENSE) for details.
