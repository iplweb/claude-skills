#!/usr/bin/env python3
"""Scaffold a new plugin in the iplweb-claude-skills marketplace.

Creates:
  plugins/<name>/.claude-plugin/plugin.json
  plugins/<name>/skills/<name>/SKILL.md   (stub with front matter)
and registers the plugin in .claude-plugin/marketplace.json at the marketplace
version (lockstep). Idempotent-safe: refuses to overwrite an existing plugin.

Usage:
  python3 scripts/new-plugin.py <name> "<one-line description>"

After scaffolding: flesh out SKILL.md, then run `python3 scripts/validate.py`.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")


def die(msg: str) -> None:
    print(f"error: {msg}")
    sys.exit(1)


def main() -> int:
    if len(sys.argv) != 3:
        die('użycie: new-plugin.py <name> "<description>"')
    name, description = sys.argv[1], sys.argv[2].strip()
    if not NAME_RE.match(name):
        die(f"name '{name}' musi być kebab-case (a-z, 0-9, myślniki)")
    if not description:
        die("description nie może być puste")

    pdir = ROOT / "plugins" / name
    if pdir.exists():
        die(f"plugins/{name} już istnieje")

    mk_path = ROOT / ".claude-plugin" / "marketplace.json"
    mk = json.loads(mk_path.read_text(encoding="utf-8"))
    version = mk["version"]
    if any(p.get("name") == name for p in mk["plugins"]):
        die(f"'{name}' już jest w marketplace.json")

    # plugin.json
    (pdir / ".claude-plugin").mkdir(parents=True)
    plugin_json = {
        "name": name,
        "description": description,
        "version": version,
        "author": mk.get("owner", {"name": "Michal Pasternak"}),
        "repository": "https://github.com/iplweb/claude-skills",
        "license": "MIT",
        "keywords": [],
    }
    (pdir / ".claude-plugin" / "plugin.json").write_text(
        json.dumps(plugin_json, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    # SKILL.md stub
    skill_dir = pdir / "skills" / name
    skill_dir.mkdir(parents=True)
    (skill_dir / "SKILL.md").write_text(
        f"---\nname: {name}\ndescription: >-\n  {description}\n---\n\n"
        f"# {name}\n\nTODO: opisz krok po kroku, co robi ten skill.\n",
        encoding="utf-8",
    )

    # register in marketplace (lockstep version), keep file 2-space JSON
    mk["plugins"].append(
        {
            "name": name,
            "source": f"./plugins/{name}",
            "description": description,
            "version": version,
            "author": mk.get("owner", {"name": "Michal Pasternak"}),
        }
    )
    mk_path.write_text(
        json.dumps(mk, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    print(f"✓ utworzono plugin '{name}' (wersja {version})")
    print(f"  - plugins/{name}/.claude-plugin/plugin.json")
    print(f"  - plugins/{name}/skills/{name}/SKILL.md  (uzupełnij treść)")
    print("  - wpis dodany do .claude-plugin/marketplace.json")
    print("Następnie: uzupełnij SKILL.md i odpal `python3 scripts/validate.py`.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
