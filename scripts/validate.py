#!/usr/bin/env python3
"""Validate the iplweb-claude-skills marketplace invariants.

Checks (the things easy to break when editing by hand):
  - marketplace.json is valid JSON and has name/version/plugins
  - every marketplace entry: source == ./plugins/<name>, dir exists, version
    matches the marketplace version (lockstep)
  - every plugins/<dir> is registered in marketplace.json (no orphans)
  - each plugin has a valid .claude-plugin/plugin.json with name == dir,
    version == marketplace version, and a non-empty description
  - each plugin ships at least one skills/<x>/SKILL.md, and every SKILL.md has
    YAML front matter with `name` (== its directory) and `description`

Usage: python3 scripts/validate.py   (exit 0 = OK, 1 = problems found)
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ERRORS: list[str] = []


def err(msg: str) -> None:
    ERRORS.append(msg)


FRONT = re.compile(r"^---\s*\n(.*?)\n---", re.S)


def front_matter(text: str) -> dict | None:
    m = FRONT.match(text)
    if not m:
        return None
    data: dict[str, str] = {}
    for line in m.group(1).splitlines():
        mm = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", line)
        if mm:
            data[mm.group(1)] = mm.group(2).strip()
    return data


def main() -> int:
    mk_path = ROOT / ".claude-plugin" / "marketplace.json"
    try:
        mk = json.loads(mk_path.read_text(encoding="utf-8"))
    except Exception as e:  # noqa: BLE001 - report any JSON/IO problem
        print(f"FATAL: nie można wczytać marketplace.json: {e}")
        return 1

    version = mk.get("version")
    if not version:
        err("marketplace.json: brak 'version'")
    if not mk.get("name"):
        err("marketplace.json: brak 'name'")

    listed = {}
    for entry in mk.get("plugins", []):
        name = entry.get("name")
        if not name:
            err("marketplace.json: wpis pluginu bez 'name'")
            continue
        listed[name] = entry
        src = entry.get("source")
        if src != f"./plugins/{name}":
            err(f"{name}: source '{src}' != './plugins/{name}'")
        if entry.get("version") != version:
            err(
                f"{name}: wersja w marketplace ({entry.get('version')}) "
                f"!= {version} (lockstep)"
            )
        if not entry.get("description"):
            err(f"{name}: brak 'description' w marketplace.json")

    plugins_dir = ROOT / "plugins"
    ondisk = {p.name for p in plugins_dir.iterdir() if p.is_dir()}

    for name in listed:
        if name not in ondisk:
            err(f"{name}: w marketplace, brak katalogu plugins/{name}")
    for d in sorted(ondisk - set(listed)):
        err(f"{d}: katalog plugins/{d} istnieje, brak wpisu w marketplace.json")

    for name in sorted(set(listed) & ondisk):
        pdir = plugins_dir / name
        pj = pdir / ".claude-plugin" / "plugin.json"
        if not pj.exists():
            err(f"{name}: brak {pj.relative_to(ROOT)}")
        else:
            try:
                pjd = json.loads(pj.read_text(encoding="utf-8"))
                if pjd.get("name") != name:
                    err(
                        f"{name}: plugin.json name '{pjd.get('name')}' "
                        f"!= katalog '{name}'"
                    )
                if pjd.get("version") != version:
                    err(
                        f"{name}: plugin.json version "
                        f"{pjd.get('version')} != {version}"
                    )
                if not pjd.get("description"):
                    err(f"{name}: plugin.json bez 'description'")
            except Exception as e:  # noqa: BLE001
                err(f"{name}: plugin.json niepoprawny JSON: {e}")

        skill_files = sorted(pdir.glob("skills/*/SKILL.md"))
        if not skill_files:
            err(f"{name}: brak żadnego skills/*/SKILL.md")
        for sf in skill_files:
            rel = sf.relative_to(ROOT)
            fm = front_matter(sf.read_text(encoding="utf-8"))
            if fm is None:
                err(f"{rel}: brak front mattera (--- ... ---)")
                continue
            if not fm.get("name"):
                err(f"{rel}: front matter bez 'name'")
            elif fm["name"] != sf.parent.name:
                err(
                    f"{rel}: name '{fm['name']}' != katalog skilla "
                    f"'{sf.parent.name}'"
                )
            if "description" not in fm:
                err(f"{rel}: front matter bez 'description'")

    if ERRORS:
        print(f"✗ marketplace NIEspójny — {len(ERRORS)} problem(ów):")
        for e in ERRORS:
            print(f"  - {e}")
        return 1

    n = len(listed)
    print(f"✓ marketplace OK — {n} pluginów, wszystkie na wersji {version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
