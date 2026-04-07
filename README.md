# claude-skills

A collection of [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skills for Python and DevOps workflows.

## Available Skills

| Skill | Description |
|-------|-------------|
| [github-build-fixer](skills/github-build-fixer/) | Diagnoses and fixes failing GitHub Actions CI builds — reads logs, proposes fixes, pushes, polls until green |
| [oss-github-publisher](skills/oss-github-publisher/) | Pre-flight audit before publishing a repo as open source — checks LICENSE, CI, pre-commit, scans for secrets and PII |
| [python-upgrade-package](skills/python-upgrade-package/) | Modernizes legacy Python packages step-by-step — setup.py to uv + pyproject.toml, Travis to GitHub Actions, pytest migration |
| [readme-guardian](skills/readme-guardian/) | Analyzes and improves Python project READMEs — badges, install instructions, version support matrix |

## Installation

### Option 1: Symlink (recommended)

Clone the repo and symlink individual skills you want into your Claude Code skills directory:

```bash
git clone https://github.com/iplweb/claude-skills.git
ln -s "$(pwd)/claude-skills/skills/github-build-fixer" ~/.claude/skills/github-build-fixer
ln -s "$(pwd)/claude-skills/skills/oss-github-publisher" ~/.claude/skills/oss-github-publisher
ln -s "$(pwd)/claude-skills/skills/python-upgrade-package" ~/.claude/skills/python-upgrade-package
ln -s "$(pwd)/claude-skills/skills/readme-guardian" ~/.claude/skills/readme-guardian
```

To update, just `git pull` inside the cloned repo.

### Option 2: Copy

Copy individual skill directories directly into `~/.claude/skills/`:

```bash
cp -r skills/github-build-fixer ~/.claude/skills/
```

### Option 3: Project-local

Copy a skill into your project's `.claude/skills/` directory to make it available only within that project:

```bash
mkdir -p .claude/skills
cp -r /path/to/claude-skills/skills/readme-guardian .claude/skills/
```

## Usage

Once installed, skills are automatically available in Claude Code. They activate based on context, or you can invoke them explicitly with `/skill-name` (e.g., `/github-build-fixer`).

## License

MIT — see [LICENSE](LICENSE) for details.
