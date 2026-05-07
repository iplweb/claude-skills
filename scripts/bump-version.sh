#!/usr/bin/env bash
# Bump every "version" field across the repo to the supplied CalVer value.
#
# Usage:
#   scripts/bump-version.sh 2026.05.1
#   scripts/bump-version.sh --auto        # picks YYYY.0M.0 for current month, or YYYY.0M.<n+1> if that already exists
#
# Lockstep model: every plugin and the marketplace itself ship at the same version.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

current_version() {
  # Single source of truth: marketplace.json top-level version.
  python3 -c 'import json,sys; print(json.load(open(".claude-plugin/marketplace.json"))["version"])'
}

next_calver() {
  local ym today_year today_month base cur micro
  today_year=$(date +%Y)
  today_month=$(date +%m)
  base="${today_year}.${today_month}"
  cur=$(current_version)
  if [[ "$cur" == "${base}."* ]]; then
    micro="${cur##*.}"
    micro=$((micro + 1))
  else
    micro=0
  fi
  echo "${base}.${micro}"
}

if [[ "${1:-}" == "--auto" || $# -eq 0 ]]; then
  new_version="$(next_calver)"
elif [[ "${1:-}" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]+$ ]]; then
  new_version="$1"
else
  echo "error: version must match YYYY.0M.MICRO (e.g. 2026.05.0) or pass --auto" >&2
  exit 2
fi

old_version="$(current_version)"
echo "Bumping ${old_version} -> ${new_version}"

# Top-level marketplace version (single line).
python3 - <<PY
import json, pathlib
path = pathlib.Path(".claude-plugin/marketplace.json")
data = json.loads(path.read_text())
data["version"] = "$new_version"
for p in data.get("plugins", []):
    p["version"] = "$new_version"
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY

# Per-plugin manifests.
find plugins -maxdepth 3 -name plugin.json -print0 | while IFS= read -r -d '' f; do
  python3 - "$f" <<PY
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
data = json.loads(p.read_text())
data["version"] = "$new_version"
p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY
done

echo "Done. Next steps:"
echo "  1. Add a section to CHANGELOG.md for ${new_version}."
echo "  2. git add -A && git commit -m \"Release ${new_version}\""
echo "  3. git tag v${new_version} && git push --tags"
