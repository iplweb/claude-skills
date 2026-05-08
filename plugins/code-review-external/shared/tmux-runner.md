# Tmux runner pattern (wspólny dla codex/opencode/claude)

Wszystkie trzy leaf skille (`code-review-codex`, `code-review-opencode`, `code-review-claude`) uruchamiają swój CLI **w tmux session** zamiast bezpośrednio w pipe. User może w dowolnym momencie podpiąć się i zobaczyć na żywo, co reviewer robi. Edytuj ten plik raz; leafy go referują.

## Sens

- **Real TTY** dla narzędzi które buforują stdout gdy nie ma TTY. Opencode w pipe-mode wisi 15+ min na bootstrap (potwierdzone empirycznie); w tmux od razu widać czy się rozkręca, czy stuck na auth/sieci.
- **Live observability** — `tmux attach -t $SESSION` pokazuje aktualny stan, `tmux capture-pane -p -t $SESSION` daje screenshot bez podpinania.
- **Czysty kill** — `tmux kill-session -t $SESSION` zamiast `pkill -9 -f opencode` + ręczne sprzątanie.
- **Survivability** — jeśli twoja konwersacja Claude padnie, sesje tmux żyją dalej (`tmux ls` żeby je znaleźć potem).
- **Stuck detector** — log nie urośnie przez 90s + brak OUT → abortujemy zamiast wisieć 15 min.

## Wymóg: tmux musi być w `$PATH`

Każdy leaf skill **w preflight** sprawdza `which tmux`. Brak → zatrzymaj się i powiedz userowi że trzeba zainstalować tmux (`brew install tmux` na macOS, `apt install tmux` na Debian/Ubuntu). Nie próbuj fallbacku do starego pipe pattern — bug-prone, gubimy observability dla której robimy refactor.

## Konwencja nazewnictwa

| Element | Wzór | Przykład |
|---|---|---|
| Session | `cr-{tool}-{TS}` | `cr-codex-20260508-122145` |
| OUT | `/tmp/code-review-{tool}-{TS}.md` | `/tmp/code-review-codex-20260508-122145.md` |
| RUN_LOG | `/tmp/code-review-{tool}-{TS}.log` | `/tmp/code-review-codex-20260508-122145.log` |
| RUNNER | `/tmp/cr-{tool}-runner-{TS}.sh` | `/tmp/cr-codex-runner-20260508-122145.sh` |

`tool` ∈ `{codex, opencode, claude}`. `TS` = `YYYYMMDD-HHMMSS`. Wszystkie trzy leafy w jednym runie `code-review-external` dzielą **ten sam TS** (wrapper exportuje go przed dispatchem).

## Wzorzec startu

Każdy leaf skill realizuje cztery kroki: (1) preflight, (2) build prompt, (3) write runner script, (4) launch tmux session. Polling jest wspólny — patrz "Wzorzec polling" niżej.

```bash
# === KROK 1: preflight ===
which tmux >/dev/null || { echo "ERR: brak tmux w PATH"; exit 1; }

TS=${TS:-$(date +%Y%m%d-%H%M%S)}
TOOL=codex   # leaf skill ustawia: codex|opencode|claude
SESSION="cr-$TOOL-$TS"
OUT="/tmp/code-review-$TOOL-$TS.md"
RUN_LOG="/tmp/code-review-$TOOL-$TS.log"
RUNNER="/tmp/cr-$TOOL-runner-$TS.sh"

# Sanity: czy session już nie istnieje (kolizja TS)
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "ERR: sesja $SESSION już istnieje — to nie powinno się zdarzyć"
  exit 1
fi

# === KROK 2: zbuduj prompt (leaf-specific) ===
# Standardowy heredoc bez apostrofów wokół PROMPT — interpolacja ${OUT} / ${ARG}
# zachodzi tu, w shellu główncj komendy bash, ZANIM trafia do runnera.
PROMPT_TEXT=$(cat <<PROMPT
…leaf-specific prompt body…
<DYREKTYWA ZAPISU - z shared/write-directive.md>
<STANDARDOWY PROMPT - z shared/standard-review-prompt.md>
PROMPT
)

# === KROK 3: napisz runner script ===
# `printf %q` shell-quote'uje PROMPT_TEXT bezpiecznie (cudzysłowy, backticki,
# unicode, nowe linie). Runner jest tylko cienką nakładką która wywołuje
# konkretny CLI z tym promptem.
{
  printf '%s\n' '#!/bin/bash'
  printf '%s\n' 'set -o pipefail'
  printf '%s\n' 'export NO_COLOR=1'   # mniej śmieci ANSI w RUN_LOG
  # === LEAF-SPECIFIC LINE === (jedna z trzech, wg leaf skilla):
  # codex:
  #   printf 'codex exec --skip-git-repo-check --sandbox workspace-write %q </dev/null\n' "$PROMPT_TEXT"
  # opencode (after restrictive config setup):
  #   printf 'opencode run --dir %q --print-logs %q </dev/null\n' "$PROJECT_ROOT" "$PROMPT_TEXT"
  # claude:
  #   printf 'claude -p %q --permission-mode auto --add-dir /tmp --allowedTools %q </dev/null\n' "$PROMPT_TEXT" "Read Grep Glob Bash Write Edit"
  printf '%s\n' 'EXIT=$?'
  printf '%s\n' 'echo'
  printf '%s\n' 'echo "===EXIT=$EXIT==="'
  printf '%s\n' 'sleep 2   # daj userowi szansę zobaczyć wynik przed zamknięciem sesji'
} > "$RUNNER"
chmod +x "$RUNNER"

# === KROK 4: odpal tmux session ===
# `-d` = detached (nie blokuj agenta). `-x 220 -y 50` = wymiary panela
# (domyślne 80×24 łamie banner-y i reasoning).
tmux new-session -d -s "$SESSION" -x 220 -y 50 "bash '$RUNNER'"

# Capture pane output do RUN_LOG (real-time, niezależne od bufferingu CLI).
# `pipe-pane` musi być PO `new-session` (sesja musi istnieć).
tmux pipe-pane -t "$SESSION" "cat > '$RUN_LOG'"

# Komunikat dla usera (drukuj zawsze, nawet jeśli to dispatch z external):
cat <<INFO

▶ $TOOL review startuje w tmux:
    Attach (live):  tmux attach -t $SESSION
    Detach (w tmux): Ctrl-B D
    Output:         $OUT
    Log:            $RUN_LOG

INFO
```

## Wzorzec polling

Po dispatchu agent wraca do shella i czeka aż sesja skończy się (CLI zwróci → bash runner zwróci → tmux session zamyka się automatycznie). Polling odbywa się w tej samej komendzie Bash co dispatch (timeout 600000 ms na całość):

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

  # Stuck detector: RUN_LOG nie rośnie przez STUCK_THRESHOLD sekund i nie ma
  # jeszcze pliku OUT — najpewniej CLI zawiesił się na bootstrap (auth, sieć,
  # API). Zabijamy zamiast wisieć w nieskończoność.
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
  echo "✓ $TOOL review zapisany: $OUT ($(wc -c < "$OUT") B)"
else
  echo "✗ $TOOL: brak review w $OUT. Tail RUN_LOG:"
  tail -30 "$RUN_LOG" 2>/dev/null || echo "(log pusty lub brak)"
fi
```

## Wzorzec polling dla `code-review-external` (3 sesje równolegle)

Wrapper dispatchuje 3 sesje (`cr-codex-$TS`, `cr-opencode-$TS`, `cr-claude-$TS`) i czeka aż wszystkie się skończą. Jedna pętla polluje wszystkie trzy:

```bash
TOOLS=(codex opencode claude)
DEADLINE=$(($(date +%s) + 600))
declare -A LAST_SIZE LAST_GROWTH
for t in "${TOOLS[@]}"; do
  LAST_SIZE[$t]=0
  LAST_GROWTH[$t]=$(date +%s)
done

while :; do
  NOW=$(date +%s)
  ALL_DONE=1
  for t in "${TOOLS[@]}"; do
    SESSION="cr-$t-$TS"
    OUT="/tmp/code-review-$t-$TS.md"
    LOG="/tmp/code-review-$t-$TS.log"

    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
      continue   # już skończona, pomiń
    fi
    ALL_DONE=0

    if [ "$NOW" -ge "$DEADLINE" ]; then
      echo "⚠ Timeout — zabijam $SESSION"
      tmux kill-session -t "$SESSION" 2>/dev/null
      continue
    fi

    CUR=$(wc -c < "$LOG" 2>/dev/null || echo 0)
    if [ "$CUR" -gt "${LAST_SIZE[$t]}" ]; then
      LAST_SIZE[$t]=$CUR
      LAST_GROWTH[$t]=$NOW
    elif [ $((NOW - ${LAST_GROWTH[$t]})) -ge 90 ] && [ ! -s "$OUT" ]; then
      echo "⚠ $SESSION stuck — zabijam"
      tmux kill-session -t "$SESSION" 2>/dev/null
    fi
  done

  [ "$ALL_DONE" -eq 1 ] && break
  sleep 5
done

# Pokaż wynik per tool
for t in "${TOOLS[@]}"; do
  OUT="/tmp/code-review-$t-$TS.md"
  if [ -s "$OUT" ]; then
    echo "✓ $t: $OUT ($(wc -c < "$OUT") B)"
  else
    echo "✗ $t: brak review (zobacz /tmp/code-review-$t-$TS.log)"
  fi
done
```

## User attach: co user widzi

`tmux attach -t cr-codex-20260508-122145` pokazuje pełny terminal CLI:
- Codex: progress bar, reasoning steps, tool calls (bash/read), final output.
- Opencode: ASCII banner, status bary, model output.
- Claude: prompt streaming + tool calls.

Detach: `Ctrl-B D` (CLI nadal działa). Kill-from-attached: `Ctrl-C` w panelu (CLI dostaje SIGINT, sesja zamyka się, polling agent wykrywa i kontynuuje).

`tmux ls` pokazuje wszystkie aktualnie żywe sesje review:
```
cr-codex-20260508-122145: 1 windows (created Fri May  8 12:21:45 2026)
cr-opencode-20260508-122145: 1 windows (created Fri May  8 12:21:45 2026)
cr-claude-20260508-122145: 1 windows (created Fri May  8 12:21:45 2026)
```

## Cleanup

- **Sesja kończy się sama** gdy CLI zwróci (runner script kończy → bash exit → tmux pane zamyka panel → sesja zamyka się).
- **Timeout / stuck** → `tmux kill-session` zabija sesję i CLI w niej.
- **User Ctrl-C w attached tmux** → CLI dostaje SIGINT, kończy, sesja zamyka się.
- **RUNNER script i RUN_LOG zostają w `/tmp`** dla debug. Nie sprzątamy automatycznie — `/tmp` czyszczony przez OS przy reboot. Jeśli ktoś codziennie odpala 100 review, periodicznie: `find /tmp -name 'cr-*-runner-*.sh' -mtime +1 -delete`.
- **Konfigi narzędzi** (`opencode` zostawia `.opencode/opencode.json` w project root) — leaf skill ma swój trap cleanup, patrz odpowiedni SKILL.md.

## Częste błędy

- **Brak `pipe-pane` po `new-session`** — RUN_LOG jest pusty, a polling stuck-detector myśli że proces nie postępuje (→ false-abort po 90s).
- **`pipe-pane` PRZED `new-session`** — race; pipe-pane wymaga istniejącej sesji i targetuje `-t SESSION`.
- **`-x` / `-y` za małe** — domyślne 80×24 łamie reasoning steps i banner-y. `-x 220 -y 50` to rozsądne minimum dla logów review.
- **`new-session` bez `-d`** — agent wisi w `tmux attach` ekranie zamiast detachować i wracać do shella.
- **Niesprawdzenie `which tmux`** — bez tmuxa cały refactor padnie z niejasnym error. Preflight check po stronie leaf skilla, czytelny komunikat.
- **Pominięcie `printf %q` przy budowaniu runnera** — prompt z apostrofami / cudzysłowami / backslashami się rozjedzie. `%q` to kanoniczny shell-safe quote.
- **Brak `set -o pipefail` w runnerze** — `EXIT=$?` daje 0 nawet gdy CLI padło, jeśli ostatnia komenda w pipe wyszła OK.
- **Polling z `sleep 1`** — niepotrzebne CPU + częste tool calls. `sleep 5` wystarczy.
- **Stuck threshold 30s** — za krótkie, opencode/codex potrafi grzać model przez 60s na cold start. **90s** to dobre minimum.
- **Czytanie OUT zanim sesja się skończyła** — review może być zapisany niekompletny (CLI nadal pisze). ZAWSZE czekaj aż `tmux has-session` zwróci false zanim Read OUT.
- **Forgotten kolizja TS** — dwa runy w tej samej sekundzie → konflikt session names. Sanity check `tmux has-session` na starcie i abort jeśli kolizja (rzadkie ale możliwe gdy user spammuje skill).
