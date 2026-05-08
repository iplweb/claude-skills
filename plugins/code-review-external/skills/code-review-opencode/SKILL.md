---
name: code-review-opencode
description: Użyj, gdy user chce wygenerować zewnętrzne code review za pomocą `opencode` (opencode CLI). Skill auto-wykrywa cel z argumentu - brak argumentu = niezacommitowane zmiany, SHA/HEAD~N/branch = pojedynczy commit, ścieżka pliku = review pliku, ścieżka katalogu = review katalogu, dowolny inny tekst = free-form wskazówka dla opencode (np. "całe repo", "security audit src/auth/", "ostatnie 3 commity z focus na perf"). Opencode pisze finalne review przez swój write tool do `/tmp/code-review-opencode-<timestamp>.md` (czysty markdown), verbose log do `.log`. Uruchamiany z tymczasowym project-local config (`.opencode/opencode.json`) który blokuje wszystkie modyfikacje poza zapisem review do `/tmp/`. Wywołuj zawsze, gdy user prosi o "code review przez opencode", "opencode run", "/code-review-opencode" albo wprost wymienia opencode jako external reviewer.
---

# Code review przez opencode (artifact-file pattern + ograniczone permissions)

## Kiedy używać

- User wprost prosi o review przez opencode.
- User uruchamia `/code-review-opencode [target]`.
- W ramach skilla `code-review-external` (uruchamia ten skill równolegle z `code-review-codex`).

NIE używaj, gdy user chce review zrobione przez Ciebie (Claude'a).
Sens jest taki, że `opencode` ma podać niezależną drugą opinię.

## Wymagania

- `opencode` w `$PATH` (sprawdź: `which opencode`). Jeśli nie ma -
  zatrzymaj się i powiedz userowi że trzeba zainstalować
  (https://opencode.ai), nie próbuj instalować sam.
- Skonfigurowany provider (`opencode auth list` żeby sprawdzić).
- Działa w katalogu repo (`opencode run` używa cwd jako kontekstu).

## Auto-detekcja celu (z argumentu usera)

Wspólna logika 5 trybów (`uncommitted` / `file` / `dir` / `commit` / `free`) — czytaj **`../../shared/target-detection.md`**. Zastosuj wzór i **zawsze ogłoś userowi** wykryty tryb zanim odpalisz opencode.

## Strategia output i permissions: dwa problemy, dwa rozwiązania

Stary wzorzec (`2>&1 | tee "$OUT"`) miał **dwa rozłączne problemy**:

1. **Stdout dump opencode (banner ASCII + reasoning + status bary)
   wciągał >50 KB szumu do kontekstu Claude'a.** Review tonął.
2. **Opencode w trybie `run` (non-TTY) blokuje się na pierwszym
   permission ask** (`external_directory`, `bash`, `edit` poza
   wzorcami allow) — nie ma jak odpowiedzieć, proces wisi
   w nieskończoność. Empirycznie potwierdzone: 60+ min bez
   output, CPU 1.6s, w logach `service=permission ... asking`.

Rozwiązania (każde adresuje jeden problem):

### 1) Artifact file zamiast tee

- Opencode pisze finalne review do pliku przez swój `write` tool.
  Wskazujemy mu ścieżkę `$OUT` w prompcie.
- Stdout/stderr lecą do `$RUN_LOG` (debug only).
- Po wykonaniu czytamy **tylko** `$OUT` przez `Read`.

### 2) Tymczasowy project-local config zamiast `--dangerously-skip-permissions`

- Opencode ładuje config z `<cwd>/.opencode/opencode.json` (jeśli
  istnieje) i mergeuje z user-level configami. Project-local
  ma najwyższy priorytet.
- Skill **tymczasowo** zapisuje `.opencode/opencode.json` z
  konkretnymi rulami: read całego projektu allow, edit tylko do
  `/tmp/code-review-*`, bash zawężony do safe read commands,
  external_directory deny, task/webfetch/websearch deny.
- Trap na EXIT/INT/TERM przywraca poprzedni config (jeśli był)
  albo usuwa nasz plik. Skill **nigdy** nie zostawia trwałych
  zmian w repo usera.

To jest dużo bezpieczniejsze niż `--dangerously-skip-permissions`,
bo:
- Czytanie wszystko w projekcie OK (i tak default).
- Pisanie ZABLOKOWANE wszędzie poza `/tmp/code-review-*`.
- Bash zawężony do `git/ls/find/cat/head/tail/wc/rg/grep` —
  nie ma jak odpalić destrukcyjnego polecenia.
- External_directory deny — opencode nie wyjedzie poza projekt.
- Task deny — żadnych subagentów (deterministyczne zachowanie).
- Webfetch/websearch deny — analiza tylko offline z plików.

## Polityka opencode (zapisywana tymczasowo do `.opencode/opencode.json`)

```json
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "read": {
      "*": "allow",
      "*.env": "deny",
      "*.env.*": "deny",
      "*.env.example": "allow"
    },
    "glob": "allow",
    "grep": "allow",
    "bash": {
      "*": "deny",
      "git *": "allow",
      "ls *": "allow",
      "find *": "allow",
      "wc *": "allow",
      "cat *": "allow",
      "head *": "allow",
      "tail *": "allow",
      "rg *": "allow",
      "grep *": "allow"
    },
    "edit": {
      "*": "deny",
      "/tmp/code-review-*": "allow",
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

`edit` covers `edit`, `write`, `patch`. Allowed only dla `/tmp/code-review-*`
i `/tmp/premortem-*` (drugi żeby ten sam mechanizm działał dla
`premortem-opencode`). Wszystko inne → deny → opencode dostaje
"permission denied" i nie ma jak coś zepsuć ani się zawiesić.

## Wrapper bash (do każdej komendy)

Każdy z czterech trybów (`uncommitted`/`commit`/`file`/`dir`) zawija
samo wywołanie `opencode run` w setup config + trap cleanup.
Najprostszy szablon — wstaw konkretną komendę opencode w `<OPENCODE_RUN>`:

```bash
TS=${TS:-$(date +%Y%m%d-%H%M%S)}
OUT=/tmp/code-review-opencode-$TS.md
RUN_LOG=/tmp/code-review-opencode-$TS.log

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CFG_DIR="$PROJECT_ROOT/.opencode"
CFG_PATH="$CFG_DIR/opencode.json"
CFG_BACKUP=""
CFG_DIR_CREATED=""

# Backup existing config if any
if [ -f "$CFG_PATH" ]; then
  CFG_BACKUP="$CFG_PATH.code-review-backup-$$"
  cp "$CFG_PATH" "$CFG_BACKUP"
fi
[ ! -d "$CFG_DIR" ] && CFG_DIR_CREATED=1
mkdir -p "$CFG_DIR"

# Write restrictive config (here-doc treated as literal — note 'OPENCODE_CFG' in quotes)
cat > "$CFG_PATH" <<'OPENCODE_CFG'
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "read": {
      "*": "allow",
      "*.env": "deny",
      "*.env.*": "deny",
      "*.env.example": "allow"
    },
    "glob": "allow",
    "grep": "allow",
    "bash": {
      "*": "deny",
      "git *": "allow",
      "ls *": "allow",
      "find *": "allow",
      "wc *": "allow",
      "cat *": "allow",
      "head *": "allow",
      "tail *": "allow",
      "rg *": "allow",
      "grep *": "allow"
    },
    "edit": {
      "*": "deny",
      "/tmp/code-review-*": "allow",
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

# Cleanup trap — runs on normal exit, Ctrl-C, kill
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

# Then run opencode (one of four mode-specific invocations below):
<OPENCODE_RUN>
```

## Komendy per tryb

W każdym trybie podstaw konkretne wywołanie `opencode run` w miejsce
`<OPENCODE_RUN>` w wrapperze powyżej. Wszystkie używają `--dir` żeby
zafiksować cwd opencode na project root (inaczej opencode mógłby
attach do innego runninga TUI i traktować nasz projekt jako
external_directory):

### `uncommitted`

Diff może być duży — jeśli `git diff HEAD --stat` pokazuje >50
plików, ostrzeż usera w jednym zdaniu, ale wykonaj.

```bash
DIFF=$(git diff HEAD; git ls-files --others --exclude-standard \
  | xargs -I {} sh -c 'echo "=== UNTRACKED: {} ==="; cat {}')
opencode run --dir "$PROJECT_ROOT" "$(cat <<PROMPT
Poniżej diff niezacommitowanych zmian. Zrób code review.

<DYREKTYWA ZAPISU>
<TUTAJ STANDARDOWY PROMPT>

\`\`\`diff
${DIFF}
\`\`\`
PROMPT
)" > "$RUN_LOG" 2>&1
```

### `commit`

```bash
SHOW=$(git show "$ARG")
opencode run --dir "$PROJECT_ROOT" "$(cat <<PROMPT
Poniżej commit ${ARG}. Zrób code review tej konkretnej zmiany.

<DYREKTYWA ZAPISU>
<TUTAJ STANDARDOWY PROMPT>

\`\`\`
${SHOW}
\`\`\`
PROMPT
)" > "$RUN_LOG" 2>&1
```

### `file`

```bash
opencode run --dir "$PROJECT_ROOT" -f "$ARG" "$(cat <<PROMPT
Zrób code review załączonego pliku **${ARG}**. Oceń całość, nie
tylko ostatnie zmiany.

<DYREKTYWA ZAPISU>
<TUTAJ STANDARDOWY PROMPT>
PROMPT
)" > "$RUN_LOG" 2>&1
```

### `dir`

```bash
FILES=$(git ls-files "$ARG" 2>/dev/null || find "$ARG" -type f \
  -not -path '*/\.*' -not -name '*.pyc' | head -50)
opencode run --dir "$PROJECT_ROOT" "$(cat <<PROMPT
Zrób code review katalogu **${ARG}**. Lista najważniejszych plików:

${FILES}

Przeczytaj te pliki (masz dostęp do FS przez swoje narzędzia)
i zgłoś problemy. Pomiń testy, chyba że widzisz w nich błędy.

<DYREKTYWA ZAPISU>
<TUTAJ STANDARDOWY PROMPT>
PROMPT
)" > "$RUN_LOG" 2>&1
```

### `free`

Argument jest wolną wskazówką od usera — wkleić go dosłownie.
Opencode sam orientuje się jakie pliki przejrzeć, jakie diff-y
wywołać. Tryb dla "całe repo", "audyt security w X", "ostatnie
3 commity z focus na perf" itp.

Nie pre-computujemy `git diff` ani listy plików (jak w trybach
uncommitted/dir) — opencode ma w swoim sandbox-ie git/ls/find/cat
i sam zdecyduje czego potrzebuje. Project root mu narzucamy przez
`--dir` jak zawsze.

```bash
opencode run --dir "$PROJECT_ROOT" "$(cat <<PROMPT
User prosi o następujące code review tego repo:

  ${ARG}

Sam zorientuj się co dokładnie zreviewować i jak (które pliki,
które komendy git, ewentualnie cały repo). Trzymaj się tematu
i scope-u który user wskazał — jeśli mówi "security audit", nie
rób ogólnego review; jeśli mówi "całe repo", przejrzyj ważne
moduły, nie tylko ostatnie zmiany.

Masz dostęp do read-only komend: \`git status\`, \`git log\`,
\`git diff\`, \`ls\`, \`find\`, \`cat\`, \`grep\`, \`rg\` —
używaj ich do nawigacji.

<DYREKTYWA ZAPISU>
<TUTAJ STANDARDOWY PROMPT>
PROMPT
)" > "$RUN_LOG" 2>&1
```

## Dyrektywa zapisu (do wklejenia jako `<DYREKTYWA ZAPISU>`)

Czytaj **`../../shared/write-directive.md`** — wstaw zawartość bloku 1:1 jako `<DYREKTYWA ZAPISU>` w komendach opencode powyżej.

**Dodatkowo dla opencode** dopisz na końcu (specyficzne dla restrictive config tej sesji):

```
UWAGA dotycząca permissions w tej sesji:
- read: cały projekt OK, .env zablokowane.
- glob/grep: cały projekt OK.
- bash: tylko polecenia read-only (git/ls/find/cat/head/tail/wc/rg/grep).
  Każda inna komenda → permission denied. NIE próbuj `rm`, `mv`,
  `chmod`, `npm install`, niczego co modyfikuje.
- write/edit: TYLKO ścieżki `/tmp/code-review-*` i `/tmp/premortem-*`.
  Nigdzie indziej. Nie próbuj zapisać niczego w projekcie.
- external_directory: deny — nie wyjdziesz poza project root.

Te ograniczenia są intencjonalne: skill ma być read-only review,
nie modyfikować repo. Jedyny output to plik review.
```

Reszta dyrektywy (deliverable jako plik, brak preambuły, brak echo na stdout, jak postępować przy braku znalezisk) — w shared file.

## Prompt review (standardowy blok do wklejenia)

Czytaj **`../../shared/standard-review-prompt.md`** — wstaw zawartość bloku 1:1 jako `<TUTAJ STANDARDOWY PROMPT>` w komendach opencode powyżej.

Edytujesz wspólne pliki raz — trzy leaf skille (codex/opencode/claude) i wrapper używają tej samej wersji prompta. Zmiana wytycznych review = zmiana w jednym miejscu.

## Po wykonaniu

1. Sprawdź `wc -c "$OUT"`. Pusty (0 B) lub nie istnieje → coś
   padło, zerknij na `tail -50 "$RUN_LOG"` i pokaż userowi.
2. Jeśli sensowny rozmiar — `Read "$OUT"`.
3. Powiedz userowi krótko: "Opencode review w `$OUT`, verbose log
   w `$RUN_LOG`."
4. Wywołane przez `code-review-external` → wrapper sam czyta.
5. Standalone → pokaż zawartość `$OUT` raz.

## Co jeśli config trap nie zadziałał

Jeśli skrypt został zabity SIGKILL (kill -9), trap się nie wykona
i `.opencode/opencode.json` zostanie w projekcie. Pokaż userowi
co zostało:

```bash
ls -la "$PROJECT_ROOT/.opencode/" 2>/dev/null
ls "$PROJECT_ROOT"/.opencode/opencode.json.code-review-backup-* 2>/dev/null
```

Zapytaj usera czy ręcznie sprzątnąć (`rm` lub przywrócić backup).
Nie ruszaj sam — może user ma własny `.opencode/opencode.json`
od poprzedniego runa.

## Częste pomyłki

- **Pominięcie wrappera config + trap** — opencode wisi na
  permission ask, 60+ min bez output.
- **Użycie `--dangerously-skip-permissions` zamiast project-local
  config** — działa, ale obchodzi cały model bezpieczeństwa
  opencode. Project-local config jest precyzyjny.
- **Pominięcie `--dir "$PROJECT_ROOT"`** — opencode może
  attach do innego TUI z innym cwd, traktować projekt jako
  external_directory, blok permission. `--dir` fiksuje cwd.
- **Stary wzorzec `tee`** — wciąga ASCII banner i reasoning do
  kontekstu Claude'a. Stdout do `$RUN_LOG`, review do `$OUT`.
- **Pominięcie dyrektywy zapisu w prompcie** — opencode zwraca
  review na stdout, plik `$OUT` nie powstanie.
- **HEREDOC z `'PROMPT'`** — blokuje interpolację `${OUT}`/`${ARG}`.
  Bez apostrofów dla głównego promptu (z apostrofami tylko dla
  config który ma `$` literałowe).
- **Krótki timeout** — duży diff + powolny model = łatwo >5 min.
  600000 ms minimum.
- **Wklejanie tajnych danych do promptu** — jeśli `git diff`
  zahacza o `.env`, sekrety, klucze - obetnij ręcznie albo
  pomiń te pliki przez `git diff -- ':!.env'`.
- **Trap który nie restoruje backupu** — jeśli user miał
  istniejący `.opencode/opencode.json`, MUSISZ go przywrócić.
  Test: zrobić plik, odpalić skill, sprawdzić że plik wraca 1:1.
