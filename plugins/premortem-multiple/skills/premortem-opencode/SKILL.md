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
- Skonfigurowany provider (`opencode auth list`).
- Brak narzędzia → zatrzymaj się, powiedz userowi co zainstalować
  (https://opencode.ai). Nie instaluj sam.

## Co dostaje skill

Identycznie jak `premortem-codex` — trzy elementy minimalne planu
(CO / KTO / SUKCES). Brak któregoś → zadaj **jedno** pytanie zanim
ruszysz. Premortem bez kontekstu = bezwartościowy.

## Strategia output i permissions

Stary wzorzec (`2>&1 | tee "$OUT"`) miał **dwa rozłączne problemy**:

1. **Stdout dump opencode** wciągał banner ASCII + reasoning do
   kontekstu Claude'a, raport tonął.
2. **Opencode w trybie `run` blokuje się na permission ask**
   (`bash`, `edit`, `external_directory`) — w non-TTY nie ma jak
   odpowiedzieć, proces wisi w nieskończoność.

Rozwiązania:

### 1) Artifact file zamiast tee

- Opencode pisze finalny raport przez swój `write` tool do `$OUT`.
- Stdout/stderr do `$RUN_LOG` (debug only).
- Po wykonaniu czytamy **tylko** `$OUT` przez `Read`.

### 2) Tymczasowy project-local config (zamiast skip-permissions)

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

## Wrapper bash

```bash
TS=${PREMORTEM_TS:-$(date +%Y%m%d-%H%M%S)}
OUT=/tmp/premortem-opencode-$TS.md
RUN_LOG=/tmp/premortem-opencode-$TS.log

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
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

opencode run --dir "$PROJECT_ROOT" "$(cat <<PROMPT
<DYREKTYWA ZAPISU>
<TUTAJ STANDARDOWY PROMPT PREMORTEM>
PROMPT
)" > "$RUN_LOG" 2>&1
```

- Timeout `Bash` na **600000** ms (10 min).
- `--dir "$PROJECT_ROOT"` żeby zafiksować cwd opencode.
- HEREDOC bez apostrofów wokół `PROMPT` — żeby `${OUT}` interpolowało.
- HEREDOC z apostrofami `'OPENCODE_CFG'` żeby `$schema` w JSON
  został literałem.

## Dyrektywa zapisu (do wklejenia jako `<DYREKTYWA ZAPISU>`)

```
WAŻNE — gdzie zwracasz premortem:

Twój **jedyny deliverable** to plik markdown pod ścieżką:
**${OUT}**

Zapisz finalny raport premortem wprost do tego pliku, używając
swojego `write` tool. Plik ma zawierać:
- WYŁĄCZNIE ustrukturyzowany markdown wg formatu poniżej,
- BEZ preambuły, BEZ podsumowania.
- BEZ powtarzania raportu na stdout.

Pierwsza linia pliku ma być nagłówkiem `## Premortem ...`.

UWAGA dotycząca permissions w tej sesji:
- read/glob/grep: deny — analizujesz plan tylko z tego co masz
  w prompcie. Nie próbuj otwierać żadnych plików w projekcie.
- bash: deny — żadnych shell commands.
- write/edit: TYLKO `/tmp/premortem-*`. Nigdzie indziej.
- external_directory/task/webfetch/websearch: deny.

Te ograniczenia są intencjonalne: premortem to czysta analiza
plan w prompcie, niczego nie modyfikujesz w projekcie usera,
żadnych zewnętrznych źródeł. Tylko jeden plik wyjścia.
```

## Standardowy prompt premortem (do wklejenia)

Identyczny jak w `premortem-codex` — patrz tam, sekcja "Standardowy
prompt premortem (do wklejenia)". Skopiuj 1:1.

Krótkie przypomnienie struktury:
1. Przesłanka: plan **już padł** 6 miesięcy w przyszłości.
2. Krok 1: lista wszystkich realnych przyczyn śmierci (specyficznych,
   ugruntowanych, niewymyślonych do liczby).
3. Krok 2: per-przyczyna deep-dive (historia + ukryte założenie +
   wczesne sygnały).
4. Krok 3: synteza (najbardziej prawdopodobna / najbardziej groźna /
   najgłębsze ukryte założenie / rewizja planu / checklist).
5. Format markdown po polsku, bez preambuły, bez podsumowań na koniec.
6. Wynik zapisany do pliku `$OUT`, nie na stdout.

## Po wykonaniu

1. `wc -c "$OUT"` — sprawdź czy nie pusty.
2. Pusty / brak → `tail -50 "$RUN_LOG"`, pokaż userowi.
3. Sensowny → `Read "$OUT"`.
4. "Opencode premortem w `$OUT`, verbose log w `$RUN_LOG`."
5. Wywołane przez `premortem-multiple` → nie drukuj ponownie.
6. Standalone → pokaż zawartość raz.

## Co jeśli config trap nie zadziałał

`SIGKILL` ubije skrypt bez wykonania trap. Pokaż userowi co
zostało:

```bash
ls -la "$PROJECT_ROOT/.opencode/" 2>/dev/null
ls "$PROJECT_ROOT"/.opencode/opencode.json.premortem-backup-* 2>/dev/null
```

Zapytaj usera czy ręcznie sprzątnąć / przywrócić backup. Nie ruszaj
sam — może user ma własny config z poprzedniego runa.

## Częste pomyłki

- **Pominięcie wrappera config + trap** — opencode wisi na
  permission ask, 60+ min bez output.
- **Użycie `--dangerously-skip-permissions`** — działa, ale obchodzi
  cały model bezpieczeństwa opencode. Project-local config jest
  precyzyjny.
- **Pominięcie `--dir "$PROJECT_ROOT"`** — opencode może attach do
  innego TUI, traktować projekt jako external_directory.
- **Stary wzorzec `tee`** — wciąga banner i reasoning do kontekstu.
- **Pominięcie dyrektywy zapisu** — premortem leci na stdout, plik
  `$OUT` nie powstanie.
- **HEREDOC z `'PROMPT'`** — `${OUT}` literałowo, codex/opencode
  nie wie gdzie pisać.
- **Krótki timeout** — j.w., 600000 ms minimum.
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
  `.opencode/opencode.json`, MUSISZ go przywrócić.
