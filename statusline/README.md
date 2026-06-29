# Claude Code statusline

A `statusLine` script for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows:

- `user@host` — shell identity
- `~/path` — current working directory (home collapsed to `~`)
- `‹branch›` — current git branch (if any)
- `🕐 NN%` — % of historical-max usage in the active 5-hour billing block, plus minutes remaining
- `📅 NN%` — % of weekly token budget used, plus raw token count

Example:

```
mpasternak@Mac-mini ~/Programowanie/bobik-2 ‹master› │ 🕐 38% (3h45m left) │ 📅 57% (2.8B)
```

Colors are tuned for **light terminal themes** (256-color dark palette — `dark green` / `dark amber` / `dark red` thresholds at 50% / 80%). If you use a dark theme, edit the `color_for_pct` function and the static `printf` codes at the bottom of the script.

## Requirements

- [`ccusage`](https://github.com/ryoppippi/ccusage) — reads `~/.claude/projects/**/*.jsonl` to compute 5h-block + weekly usage. Install via `npm install -g ccusage` or Homebrew (`brew install ccusage`).
- `jq` — JSON parsing. Pre-installed on most systems; `brew install jq` otherwise.
- A terminal that supports 256-color escape codes (any modern one does).

## Install

1. Copy the script to your Claude Code config directory:

   ```sh
   mkdir -p ~/.claude
   cp statusline-command.sh ~/.claude/statusline-command.sh
   ```

2. Add a `statusLine` block to `~/.claude/settings.json` (top-level, alongside `theme`, `permissions`, etc.):

   ```json
   "statusLine": {
     "type": "command",
     "command": "sh /Users/<you>/.claude/statusline-command.sh"
   }
   ```

   Replace `<you>` with your username — `~` is not reliably expanded when the harness spawns the command via `sh -c`.

3. Restart Claude Code (`/exit` then re-launch). The status line appears at the bottom of every session.

## Configuration

### Weekly token budget

The script defaults to `5_000_000_000` tokens/week — a rough estimate for an Anthropic **Max 20x** plan, including cache reads (which dominate raw token counts). Override per your plan:

```sh
export CC_WEEKLY_TOKEN_LIMIT=3000000000   # ~Max 5x estimate
```

Or set it in `~/.claude/settings.json` under the top-level `env` block (Claude Code propagates it to all hooks):

```json
"env": {
  "CC_WEEKLY_TOKEN_LIMIT": "3000000000"
}
```

**Calibration tip:** Anthropic doesn't publish a token cap, only "Sonnet/Opus hours per week". The right way to tune `CC_WEEKLY_TOKEN_LIMIT` is empirical — when you actually hit a weekly rate limit, note the `%` the status line shows, and divide your current budget by that fraction. Example: limited at 70% → new budget = `5_000_000_000 / 0.7 ≈ 7_100_000_000`.

Set `CC_WEEKLY_TOKEN_LIMIT=0` to disable the percentage and show raw tokens only (`📅 2.8B tok`).

### Color thresholds

Edit `color_for_pct` in the script. Default:
- `<50%` → dark green (256-color index `28`)
- `50–80%` → dark amber (`130`)
- `≥80%` → dark red (`124`)

Lower index = darker (`28 → 22 → 17` for greens). [256-color reference](https://www.ditig.com/256-colors-cheat-sheet).

### Week-start day

The script computes the weekly bucket from **last Monday** (`date -v-mon +%Y%m%d` on macOS, `date -d "last monday"` on Linux), matching ISO 8601. Anthropic's rate-limit window may reset on a different day (e.g. your subscription anniversary), so the percentage is a trend indicator, not a 1:1 mirror of Anthropic's internal counter.

## How it works

Claude Code spawns the `command` configured in `statusLine` on every UI update (capped at ~300 ms) and passes a JSON blob on stdin describing the current session (`workspace.current_dir`, `model.id`, `session_id`, `transcript_path`, etc.). The script:

1. Parses the JSON for `cwd` + git branch.
2. Calls `ccusage blocks --active --json --token-limit max --offline` to get the current 5h block, including a `percentUsed` field relative to the user's historical max.
3. Calls `ccusage weekly --json --since <last-monday>` to sum tokens for the current ISO week.
4. Prints a single ANSI-coloured line to stdout, which Claude Code renders as the status line.

`--offline` flag on `ccusage` avoids a model-pricing fetch on every tick (cached pricing is fine for percentage math).

## Troubleshooting

- **`printf: ...: invalid number`** — your shell's `LC_NUMERIC` uses `,` as decimal separator (common on European systems). The script forces `LC_ALL=C` at the top to prevent this; if you removed that line, restore it.
- **Status line is empty** — check `jq` is installed and `ccusage` is in `$PATH` when Claude Code spawns the script. Run it manually with a fake input to test:
  ```sh
  echo '{"cwd":"'"$PWD"'","workspace":{"current_dir":"'"$PWD"'","project_dir":"'"$PWD"'"},"model":{"id":"claude-opus-4-7"},"session_id":"t","transcript_path":""}' | sh ~/.claude/statusline-command.sh
  ```
- **`ccusage` rejects input with "Invalid input format"** — Claude Code passes the right schema at runtime; if you're testing manually, make sure the JSON has `cwd`, `model.id`, and `workspace.project_dir`.
- **Slow status line** — make sure `ccusage` is installed globally (`npm install -g ccusage` or `brew install ccusage`), not invoked via `npx -y` on every tick.

## License

MIT — same as the parent repo.
