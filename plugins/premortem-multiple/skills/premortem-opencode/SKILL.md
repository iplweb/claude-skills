---
name: premortem-opencode
description: Użyj, gdy user chce premortem na plan/launch/decyzję wykonany przez `opencode` (opencode CLI). Skill zakłada, że plan padł 6 miesięcy w przyszłości i każe opencode wstecznie znaleźć powody śmierci, zrobić deep-dive na każdy, i zsyntezować rewizję. Opencode pisze finalny raport przez swój write tool do `/tmp/premortem-opencode-<timestamp>.md` (czysty markdown), verbose log do `.log`. Uruchamiany z tymczasowym project-local config (`.opencode/opencode.json`) który blokuje wszystkie modyfikacje poza zapisem do `/tmp/premortem-*`. Wywołuj zawsze, gdy user prosi o "premortem przez opencode", "opencode premortem", "/premortem-opencode" albo wskazuje opencode jako narzędzie do stress-testu planu. Sens: jedna z trzech niezależnych opinii w `premortem-multiple`, albo standalone gdy user chce tylko opencode.
---

# Premortem przez opencode (artifact-file pattern + ograniczone permissions)

## Kiedy używać

- User uruchamia `/premortem-opencode [plan-description]`.
- User wprost prosi o "premortem przez opencode".
- W ramach `premortem-multiple` (równolegle do codex + claude).

NIE używaj, gdy:
- User chce review kodu → to `code-review-opencode`.
- User chce trzy opinie premortem naraz → użyj `premortem-multiple`.

## Wymagania

- `opencode` w `$PATH` (`which opencode`).
- `tmux` w `$PATH` (`which tmux`). Brak → stop, instalacja
  (`brew install tmux` / `apt install tmux`). Cały skill jedzie przez
  tmux — patrz `../../shared/tmux-runner.md`.
- Skonfigurowany provider (`opencode auth list`).
- Brak narzędzia → zatrzymaj się, powiedz userowi co zainstalować
  (https://opencode.ai). Nie instaluj sam.

## Co dostaje skill

Identycznie jak `premortem-codex` — trzy elementy minimalne planu
(CO / KTO / SUKCES). Brak któregoś → zadaj **jedno** pytanie zanim
ruszysz. Premortem bez kontekstu = bezwartościowy.

## Strategia: tmux + restrictive config + artifact file

Trzy problemy, trzy rozwiązania:

### 1) Tmux session — observability + stuck detection

Opencode w pipe-mode potrafi wisieć 15+ min na bootstrap (potwierdzone
empirycznie w `code-review-opencode`). W tmux user może `tmux attach
-t pm-opencode-$TS` i zobaczyć co się dzieje. Plus stuck detector
w polling-u abortuje po 90s braku progresu zamiast wisieć w
nieskończoność. Wzorzec w `../../shared/tmux-runner.md`.

### 2) Artifact file zamiast tee

Opencode pisze finalny raport przez swój `write` tool do `$OUT`. Pane
output (verbose: banner ASCII, reasoning steps) capture'owany przez
`tmux pipe-pane` do `$RUN_LOG` (debug only). Po zakończeniu czytamy
**tylko** `$OUT` przez `Read`.

### 3) Tymczasowy project-local config (restrictive permissions)

Premortem nie potrzebuje czytać projektu — wszystko co potrzebne
jest w prompcie. Tylko musi zapisać raport do `/tmp/premortem-*`.
Więc config jest **bardzo restrykcyjny**:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "read": "deny",
    "glob": "deny",
    "grep": "deny",
    "bash": {"*": "deny"},
    "edit": {
      "*": "deny",
      "/tmp/premortem-*": "allow"
    },
    "external_directory": "deny",
    "task": "deny",
    "webfetch": "deny",
    "websearch": "deny",
    "doom_loop": "deny"
  }
}
```

Wszystko `deny` poza zapisem do `/tmp/premortem-*`. Opencode nie
ma żadnego sensownego powodu żeby chcieć czytać projekt do analizy
biznesowo-produktowego planu — jeśli próbuje, dostaje
"permission denied" i musi się zorientować że ma użyć tego co jest
w prompcie.

Trap przywraca poprzedni `.opencode/opencode.json` (jeśli był) lub
usuwa nasz plik.

> **WAŻNE — kolejność operacji:** config setup + trap registration
> MUSI być w **tej samej** komendzie bash co tmux launch + polling.
> Trap fires dopiero gdy ta komenda kończy się — czyli po polling-u,
> czyli po zakończeniu sesji opencode. Jeśli rozdzielisz na dwie
> komendy bash, trap z pierwszej komendy odpali zanim opencode skończy.

## Pełny wrapper bash (config + trap + tmux + polling)

Wszystko w **jednej** komendzie bash (timeout `600000` ms). Trap odpala
się dopiero gdy bash zwróci, czyli po polling-u, czyli po zamknięciu
sesji opencode → restrictive config czyszczony jest dopiero gdy
naprawdę nie jest już potrzebny.

```bash
which opencode tmux >/dev/null || { echo "ERR: brak opencode lub tmux"; exit 1; }

TS=${PREMORTEM_TS:-$(date +%Y%m%d-%H%M%S)}
TOOL=opencode
SESSION="pm-$TOOL-$TS"
OUT="/tmp/premortem-$TOOL-$TS.md"
RUN_LOG="/tmp/premortem-$TOOL-$TS.log"
RUNNER="/tmp/pm-$TOOL-runner-$TS.sh"
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# === 1. Restrictive config + trap ===
CFG_DIR="$PROJECT_ROOT/.opencode"
CFG_PATH="$CFG_DIR/opencode.json"
CFG_BACKUP=""
CFG_DIR_CREATED=""

if [ -f "$CFG_PATH" ]; then
  CFG_BACKUP="$CFG_PATH.premortem-backup-$$"
  cp "$CFG_PATH" "$CFG_BACKUP"
fi
[ ! -d "$CFG_DIR" ] && CFG_DIR_CREATED=1
mkdir -p "$CFG_DIR"

cat > "$CFG_PATH" <<'OPENCODE_CFG'
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "read": "deny",
    "glob": "deny",
    "grep": "deny",
    "bash": {"*": "deny"},
    "edit": {
      "*": "deny",
      "/tmp/premortem-*": "allow"
    },
    "external_directory": "deny",
    "task": "deny",
    "webfetch": "deny",
    "websearch": "deny",
    "doom_loop": "deny"
  }
}
OPENCODE_CFG

cleanup() {
  tmux kill-session -t "$SESSION" 2>/dev/null
  if [ -n "$CFG_BACKUP" ] && [ -f "$CFG_BACKUP" ]; then
    mv "$CFG_BACKUP" "$CFG_PATH"
  else
    rm -f "$CFG_PATH"
  fi
  if [ -n "$CFG_DIR_CREATED" ]; then
    rmdir "$CFG_DIR" 2>/dev/null
  fi
}
trap cleanup EXIT INT TERM

# === 2. Build prompt + runner ===
PROMPT_TEXT=$(cat <<PROMPT
<DYREKTYWA ZAPISU>
<TUTAJ STANDARDOWY PROMPT PREMORTEM>
PROMPT
)

{
  printf '%s\n' '#!/bin/bash'
  printf '%s\n' 'set -o pipefail'
  printf '%s\n' 'export NO_COLOR=1'
  printf 'opencode run --dir %q --print-logs %q </dev/null\n' "$PROJECT_ROOT" "$PROMPT_TEXT"
  printf '%s\n' 'EXIT=$?'
  printf '%s\n' 'echo'
  printf '%s\n' 'echo "===EXIT=$EXIT==="'
  printf '%s\n' 'sleep 2'
} > "$RUNNER"
chmod +x "$RUNNER"

# === 3. tmux launch ===
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "ERR: sesja $SESSION już istnieje"
  exit 1
fi
tmux new-session -d -s "$SESSION" -x 220 -y 50 "bash '$RUNNER'"
tmux pipe-pane -t "$SESSION" "cat > '$RUN_LOG'"

cat <<INFO

▶ Opencode premortem startuje w tmux:
    Attach (live):  tmux attach -t $SESSION
    Detach (w tmux): Ctrl-B D
    Output:         $OUT
    Log:            $RUN_LOG

INFO

# === 4. Polling — patrz shared/tmux-runner.md, sekcja "Wzorzec polling" ===
# (skopiuj wzorzec 1:1, używa $SESSION / $OUT / $RUN_LOG ustawionych wyżej)
```

- Timeout `Bash` na **600000** ms (10 min).
- `--dir "$PROJECT_ROOT"` żeby zafiksować cwd opencode.
- `--print-logs` daje real-time INFO logi — gdy opencode się zawiesi
  na bootstrapie, widać to w pane'u i w RUN_LOG; stuck detector
  aborduje po 90s.
- HEREDOC bez apostrofów wokół `PROMPT` — żeby `${OUT}` interpolowało.
- HEREDOC z apostrofami `'OPENCODE_CFG'` żeby `$schema` w JSON
  został literałem.

## Dyrektywa zapisu (do wklejenia jako `<DYREKTYWA ZAPISU>`)

Czytaj **`../../shared/write-directive.md`** — wstaw zawartość bloku 1:1.

**Dodatkowo dla opencode** dopisz na końcu (specyficzne dla restrictive config tej sesji):

```
UWAGA dotycząca permissions w tej sesji:
- read/glob/grep: deny — analizujesz plan tylko z tego co masz
  w prompcie. Nie próbuj otwierać żadnych plików w projekcie.
- bash: deny — żadnych shell commands.
- write/edit: TYLKO `/tmp/premortem-*`. Nigdzie indziej.
- external_directory/task/webfetch/websearch: deny.

Te ograniczenia są intencjonalne: premortem to czysta analiza
plan w prompcie, niczego nie modyfikujesz w projekcie usera,
żadnych zewnętrznych źródeł. Tylko jeden plik wyjścia.

(Sekcja "ZANIM RUSZYSZ — opcjonalnie zorientuj się w workspace"
z prompta premortem NIE dotyczy ciebie — sandbox tej sesji ma
read=deny. Pomiń krok i jedź dalej z tym co masz w prompcie.)
```

## Standardowy prompt premortem (do wklejenia)

Czytaj **`../../shared/standard-premortem-prompt.md`** — wstaw zawartość bloku 1:1 jako `<TUTAJ STANDARDOWY PROMPT PREMORTEM>` w komendzie opencode powyżej.

Edytujesz wspólne pliki raz — trzy leaf skille (codex/opencode/claude) i wrapper używają tej samej wersji prompta.

## Po wykonaniu

1. Sesja `pm-opencode-$TS` zamyka się sama gdy opencode zwróci albo
   gdy stuck-detector ją zabije. Polling z `tmux-runner.md` wykrywa to.
2. `wc -c "$OUT"` — sprawdź czy nie pusty (>200 B).
3. Pusty / brak → `tail -30 "$RUN_LOG"`, pokaż userowi (zwykle: auth
   error, model API timeout, permission denied).
4. Sensowny → `Read "$OUT"`.
5. "Opencode premortem w `$OUT`. Sesja zakończona, log w `$RUN_LOG`."
6. Wywołane przez `premortem-multiple` → nie drukuj ponownie.
7. Standalone → pokaż zawartość raz.

## Co jeśli config trap nie zadziałał

Trap fire'uje na EXIT/INT/TERM, ale NIE na SIGKILL (kill -9). Jeśli
ktoś zabije główny proces bash przez kill -9, `.opencode/opencode.json`
zostanie w projekcie. Tmux sesja może też zostać orphaned. Pokaż
userowi co zostało:

```bash
ls -la "$PROJECT_ROOT/.opencode/" 2>/dev/null
ls "$PROJECT_ROOT"/.opencode/opencode.json.premortem-backup-* 2>/dev/null
tmux ls 2>/dev/null | grep '^pm-opencode-'
```

Zapytaj usera czy ręcznie sprzątnąć / przywrócić backup
(`tmux kill-session -t NAME`, `rm` lub `mv` configu z backupu). Nie
ruszaj sam — może user ma własny config z poprzedniego runa.

## Częste pomyłki

- **Pominięcie tmux** — uruchamianie `opencode run` bezpośrednio
  (`> $RUN_LOG 2>&1`). Opencode w pipe-mode wisi 15+ min na bootstrap.
  W tmux user widzi co się dzieje przez `tmux attach`, stuck detector
  aborduje po 90s. To nie jest opcja — to wymóg architektury.
- **Pominięcie wrappera config + trap** — bez restrictive permissions
  opencode wisi na permission ask 60+ min, w pipe-mode niewidzialny.
- **Użycie `--dangerously-skip-permissions`** — działa, ale obchodzi
  cały model bezpieczeństwa opencode. Project-local config jest
  precyzyjny.
- **Pominięcie `--dir "$PROJECT_ROOT"`** — opencode może attach do
  innego TUI, traktować projekt jako external_directory → permission
  denied.
- **Pominięcie `--print-logs`** — bez tego opencode w pipe-mode loguje
  minimalne rzeczy do stdout, trudniej zdiagnozować stuck. `--print-logs`
  daje INFO logi w real-time.
- **Pominięcie dyrektywy zapisu** — premortem leci na stdout, plik
  `$OUT` nie powstanie.
- **HEREDOC z `'PROMPT'`** — `${OUT}` literałowo, opencode nie wie
  gdzie pisać.
- **Tylko `printf %q` przy budowaniu runnera** — `PROMPT_TEXT` zawiera
  cudzysłowy / backticki / unicode, bez `%q` runner się rozjedzie.
- **Krótki timeout** — j.w., **600000 ms** minimum.
- **Mylenie z review kodu** — to NIE jest `code-review-opencode`.
  Tu opencode analizuje **plan**, nie kod. Bez `-f` na pliki, bez
  `git diff` w prompcie, ZE WSZYSTKIM `read/bash/grep` zablokowanymi
  na poziomie permissions.
- **Pominięcie kontekstu planu w prompcie** — opencode tu nie wie nic
  o planie poza tym co dostanie w prompcie. Brak kontekstu = generyczny
  output bez wartości.
- **Generowanie nowego `$TS` jeśli wrapper podał `PREMORTEM_TS`** —
  użyj env, inaczej trójka plików będzie miała różne stamps.
- **Nie sprawdzanie czy plik powstał** — `wc -c "$OUT"` przed Read,
  zawsze.
- **Trap który nie restoruje backupu** — jeśli user miał istniejący
  `.opencode/opencode.json`, MUSISZ go przywrócić. Test: zrób plik
  z dummy content, odpal skill, sprawdź że plik wraca 1:1.
- **Brak `tmux kill-session` w cleanup trap** — jeśli polling się
  przerwie (Ctrl-C w głównym agencie), tmux session żyje dalej
  z opencode w środku. Trap musi `tmux kill-session -t "$SESSION"
  2>/dev/null` zanim posprząta config.
- **Stuck threshold za krótki** — opencode boot 30-60s. **90s** to
  dobre minimum. Krócej → false-aborty na cold start.
