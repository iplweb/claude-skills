# Tmux runner pattern (wspólny dla premortem-codex / premortem-opencode)

Oba external CLI premortem (`codex`, `opencode`) uruchamiają się **w tmux session** zamiast bezpośrednio w pipe. Edytuj ten plik raz; leafy go referują. Wzorzec analogiczny do `code-review-external/shared/tmux-runner.md` — adaptowany na premortem (inne prefiksy nazw plików / sesji).

## Sens

- **Real TTY** dla narzędzi które buforują stdout w pipe-mode. Opencode w pipe-mode wisi 15+ min na bootstrap (potwierdzone empirycznie); w tmux od razu widać czy się rozkręca, czy stuck na auth/sieci.
- **Live observability** — `tmux attach -t $SESSION` pokazuje aktualny stan, `tmux capture-pane -p -t $SESSION` daje screenshot bez podpinania.
- **Czysty kill** — `tmux kill-session -t $SESSION` zamiast `pkill -9 -f opencode`.
- **Stuck detector** — log nie urośnie przez 90s + brak OUT → abortujemy zamiast wisieć w nieskończoność.

## Wymóg: tmux musi być w `$PATH`

Każdy leaf w preflight sprawdza `which tmux`. Brak → zatrzymaj się i powiedz userowi żeby zainstalował (`brew install tmux` na macOS, `apt install tmux` na Debian/Ubuntu). Nie próbuj fallbacku do starego pipe pattern.

## Konwencja nazewnictwa

| Element | Wzór | Przykład |
|---|---|---|
| Session | `pm-{tool}-{TS}` | `pm-codex-20260508-122145` |
| OUT | `/tmp/premortem-{tool}-{TS}.md` | `/tmp/premortem-codex-20260508-122145.md` |
| RUN_LOG | `/tmp/premortem-{tool}-{TS}.log` | `/tmp/premortem-codex-20260508-122145.log` |
| RUNNER | `/tmp/pm-{tool}-runner-{TS}.sh` | `/tmp/pm-codex-runner-20260508-122145.sh` |

`tool` ∈ `{codex, opencode}`. `TS` = `YYYYMMDD-HHMMSS`. W jednym runie `premortem-multiple` wszystkie leafy dzielą **ten sam TS** (wrapper eksportuje `PREMORTEM_TS=$TS` przed dispatchem).

## Wzorzec startu

Każdy leaf realizuje cztery kroki: (1) preflight, (2) build prompt, (3) write runner script, (4) launch tmux session. Polling jest wspólny — patrz "Wzorzec polling".

```bash
# === KROK 1: preflight ===
which tmux >/dev/null || { echo "ERR: brak tmux w PATH"; exit 1; }

TS=${PREMORTEM_TS:-$(date +%Y%m%d-%H%M%S)}
TOOL=codex   # leaf ustawia: codex | opencode
SESSION="pm-$TOOL-$TS"
OUT="/tmp/premortem-$TOOL-$TS.md"
RUN_LOG="/tmp/premortem-$TOOL-$TS.log"
RUNNER="/tmp/pm-$TOOL-runner-$TS.sh"

# Sanity: czy session już nie istnieje (kolizja TS)
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "ERR: sesja $SESSION już istnieje"
  exit 1
fi

# === KROK 2: zbuduj prompt (leaf-specific) ===
# HEREDOC bez apostrofów wokół delimitera — interpolacja ${OUT} zachodzi
# tu, w shellu głównej komendy bash, ZANIM trafia do runnera.
PROMPT_TEXT=$(cat <<PROMPT
…leaf-specific prompt body…
<DYREKTYWA ZAPISU - z shared/write-directive.md>
<STANDARDOWY PROMPT PREMORTEM - z shared/standard-premortem-prompt.md>
PROMPT
)

# === KROK 3: napisz runner script ===
# `printf %q` shell-quote'uje PROMPT_TEXT bezpiecznie. Leaf wstawia
# tu jedną linię specyficzną dla swojego CLI (codex / opencode).
{
  printf '%s\n' '#!/bin/bash'
  printf '%s\n' 'set -o pipefail'
  printf '%s\n' 'export NO_COLOR=1'
  # === LEAF-SPECIFIC LINE === (wybierz wg leaf):
  # codex:
  #   printf 'codex exec --skip-git-repo-check --sandbox workspace-write %q </dev/null\n' "$PROMPT_TEXT"
  # opencode (po setupie restrictive config):
  #   printf 'opencode run --dir %q --print-logs %q </dev/null\n' "$PROJECT_ROOT" "$PROMPT_TEXT"
  printf '%s\n' 'EXIT=$?'
  printf '%s\n' 'echo'
  printf '%s\n' 'echo "===EXIT=$EXIT==="'
  printf '%s\n' 'sleep 2'
} > "$RUNNER"
chmod +x "$RUNNER"

# === KROK 4: odpal tmux session ===
tmux new-session -d -s "$SESSION" -x 220 -y 50 "bash '$RUNNER'"
tmux pipe-pane -t "$SESSION" "cat > '$RUN_LOG'"

cat <<INFO

▶ $TOOL premortem startuje w tmux:
    Attach (live):   tmux attach -t $SESSION
    Detach (w tmux): Ctrl-B D
    Output:          $OUT
    Log:             $RUN_LOG

INFO
```

## Wzorzec polling

Po dispatchu agent wraca do shella i czeka aż sesja skończy się. Polling odbywa się w tej samej komendzie Bash co dispatch (timeout `600000` ms na całość):

```bash
DEADLINE=$(($(date +%s) + 600))
LAST_LOG_SIZE=0
LAST_GROWTH_AT=$(date +%s)
STUCK_THRESHOLD=90    # sekund bez wzrostu logu → abort (jeśli brak OUT)

while tmux has-session -t "$SESSION" 2>/dev/null; do
  NOW=$(date +%s)

  # Hard timeout (10 min)
  if [ "$NOW" -ge "$DEADLINE" ]; then
    echo "⚠ Timeout 10 min — zabijam $SESSION"
    tmux kill-session -t "$SESSION" 2>/dev/null
    break
  fi

  # Stuck detector
  CUR_SIZE=$(wc -c < "$RUN_LOG" 2>/dev/null || echo 0)
  if [ "$CUR_SIZE" -gt "$LAST_LOG_SIZE" ]; then
    LAST_LOG_SIZE=$CUR_SIZE
    LAST_GROWTH_AT=$NOW
  elif [ $((NOW - LAST_GROWTH_AT)) -ge "$STUCK_THRESHOLD" ] && [ ! -s "$OUT" ]; then
    echo "⚠ $SESSION stuck (log nie rośnie ${STUCK_THRESHOLD}s, brak OUT) — zabijam"
    tmux kill-session -t "$SESSION" 2>/dev/null
    break
  fi

  sleep 5
done

# Sesja skończona (sama lub zabita). Sprawdź wynik.
if [ -s "$OUT" ]; then
  echo "✓ $TOOL premortem zapisany: $OUT ($(wc -c < "$OUT") B)"
else
  echo "✗ $TOOL: brak premortem w $OUT. Tail RUN_LOG:"
  tail -30 "$RUN_LOG" 2>/dev/null || echo "(log pusty lub brak)"
fi
```

## Cleanup

- **Sesja kończy się sama** gdy CLI zwróci.
- **Timeout / stuck** → `tmux kill-session` zabija sesję i CLI w niej.
- **User Ctrl-C w attached tmux** → CLI dostaje SIGINT, kończy, sesja zamyka się.
- **RUNNER script i RUN_LOG zostają w `/tmp`** dla debug.
- **Konfigi narzędzi** (`opencode` zostawia `.opencode/opencode.json` w project root) — leaf ma swój trap cleanup, patrz `premortem-opencode/SKILL.md`.

## Częste błędy

- **Brak `pipe-pane` po `new-session`** — RUN_LOG pusty, stuck-detector myśli że proces nie postępuje (false-abort po 90s).
- **`pipe-pane` PRZED `new-session`** — race; pipe-pane wymaga istniejącej sesji.
- **`-x` / `-y` za małe** — domyślne 80×24 łamie banner-y. `-x 220 -y 50` minimum.
- **`new-session` bez `-d`** — agent wisi w `tmux attach` zamiast detachować.
- **Pominięcie `printf %q`** — prompt z apostrofami / cudzysłowami / backslashami się rozjedzie.
- **Brak `set -o pipefail` w runnerze** — `EXIT=$?` daje 0 nawet gdy CLI padło.
- **Polling z `sleep 1`** — niepotrzebne CPU. `sleep 5` wystarczy.
- **Stuck threshold 30s** — za krótkie. **90s** to dobre minimum.
- **Czytanie OUT zanim sesja się skończyła** — premortem może być niekompletny. ZAWSZE czekaj aż `tmux has-session` zwróci false.
- **Kolizja TS** — sanity check `tmux has-session` na starcie i abort jeśli kolizja.
