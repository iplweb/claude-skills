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

- `opencode` w `$PATH` (sprawdź: `which opencode`). Brak → stop, powiedz
  userowi żeby zainstalował (https://opencode.ai).
- `tmux` w `$PATH` (sprawdź: `which tmux`). Brak → stop, instalacja
  (`brew install tmux` / `apt install tmux`). Cały skill jedzie przez tmux.
- Skonfigurowany provider (`opencode auth list` żeby sprawdzić).
- Działa w katalogu repo (`opencode run --dir` zafiksuje cwd).

## Auto-detekcja celu (z argumentu usera)

Wspólna logika 5 trybów (`uncommitted` / `file` / `dir` / `commit` / `free`) — czytaj **`../../shared/target-detection.md`**. Zastosuj wzór i **zawsze ogłoś userowi** wykryty tryb zanim odpalisz opencode.

## Strategia: tmux + restrictive config + artifact file

Trzy problemy, trzy rozwiązania:

### 1) Tmux session — observability + stuck detection

Opencode w pipe-mode potrafi wisieć 15+ min na bootstrap (potwierdzone
empirycznie: log z 1 linią `INFO ... service=default version=...` przez
cały czas). W tmux user może `tmux attach -t cr-opencode-$TS` i zobaczyć
co się dzieje. Plus stuck detector w polling-u abortuje po 90s braku
progresu zamiast wisieć w nieskończoność. Wzorzec w `../../shared/tmux-runner.md`.

### 2) Artifact file zamiast tee

Opencode sam pisze finalne review do pliku przez swój `write` tool
(wskazujemy ścieżkę `$OUT` w prompcie). Pane output capture'owany przez
`tmux pipe-pane` do RUN_LOG (debug). Po zakończeniu czytamy TYLKO OUT.

### 3) Tymczasowy project-local config (restrictive permissions)

Opencode ładuje config z `<cwd>/.opencode/opencode.json` (jeśli istnieje)
i mergeuje z user-level configami; project-local ma najwyższy priorytet.

Skill **tymczasowo** zapisuje `.opencode/opencode.json` z restrictive
permissions: read projektu allow, edit tylko do `/tmp/code-review-*` /
`/tmp/premortem-*`, bash zawężony do read-only komend, external_directory
deny, task/webfetch/websearch deny. Trap (EXIT/INT/TERM) przywraca
poprzedni config (jeśli był) albo usuwa nasz plik.

Dużo bezpieczniejsze niż `--dangerously-skip-permissions`:
- Read: cały projekt OK, ale denylista pokrywa root + dowolny podkatalog (`**/...`) dla: `.env*`, kluczy prywatnych (`*.pem`, `*.key`, `id_rsa*`, `id_dsa*`, `id_ed25519*`, `id_ecdsa*`), pakietów kluczy (`*.p12`, `*.pfx`, `*.keystore`, `*.jks`), credentiali (`credentials.json`, `*credentials*.json`, `service-account*.json`) i registry creds (`.npmrc`, `.pypirc`, `.netrc`). Każdy wzór jest dwa razy — raz bez `**/` (root), raz z `**/` (nested) — bo opencode pattern matching nie cross-slash-uje pojedynczym `*`. Pisanie ZABLOKOWANE poza `/tmp/code-review-*`.
- Bash zawężony do **wyłącznie read-only listujących** `git` verbs **bez wildcardów które puszczałyby `--output`**: `git status`/`git status *`, `git log` (no-args = ostatni commit), `git show` (no-args = HEAD), `git ls-files`/`git ls-files *`, `git rev-parse`/`git rev-parse *`, `git branch` (no-args = lista lokalnych), `git tag` (no-args = lista tagów), `ls`/`ls *`. Wszystko inne → permission denied. **Czemu `git log`/`git show` BEZ wildcardów?** Bo `git log --output=PATH` i `git show --output=PATH` zapisują plik (potwierdzone empirycznie) — to bypass `edit` policy poprzez bash. Bez argumentów oba listują (log = ostatni commit; show = HEAD), bezpieczne. **Czemu nie `git diff`?** Bo `git diff --no-index FILE1 FILE2` czyta DOWOLNY plik z systemu (potwierdzone: `git diff --no-index /etc/hosts /dev/null` dumpuje zawartość) — bypass `external_directory: deny`. Diff dla trybów `uncommitted`/`commit` pre-computuje wrapper. **Czemu `git branch`/`tag` bez argumentów?** Bo `git branch -D foo`, `git tag -d v1`, `git branch new` — wszystkie matchują `git branch *` / `git tag *` i mutują `.git/`. **Czemu nie `cat`/`find`/`grep`/`rg`/`head`/`tail`/`wc`?** Bo opencode ma natywne `read`/`glob`/`grep` tools, które respektują path policy (deny dla sekretów). Bash `cat .env` byłby out-of-band bypass-em — usunęliśmy go.
- External_directory deny — opencode nie wyjedzie poza projekt.
- Task deny — żadnych subagentów (deterministyczne zachowanie).
- Webfetch/websearch deny — analiza offline z plików.

> **WAŻNE — kolejność operacji:** config setup + trap registration MUSI
> być w **tej samej** komendzie bash co tmux launch + polling. Trap fires
> dopiero gdy ta komenda kończy się — czyli po polling-u, czyli po
> zakończeniu sesji opencode. Jeśli rozdzielisz na dwie komendy bash,
> trap z pierwszej komendy odpali zanim opencode skończy.

## Polityka opencode (zapisywana tymczasowo do `.opencode/opencode.json`)

```json
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "read": {
      "*": "allow",
      ".env": "deny",
      ".env.*": "deny",
      "**/.env": "deny",
      "**/.env.*": "deny",
      ".env.example": "allow",
      "**/.env.example": "allow",
      "*.pem": "deny",
      "**/*.pem": "deny",
      "*.key": "deny",
      "**/*.key": "deny",
      "*.p12": "deny",
      "**/*.p12": "deny",
      "*.pfx": "deny",
      "**/*.pfx": "deny",
      "*.keystore": "deny",
      "**/*.keystore": "deny",
      "*.jks": "deny",
      "**/*.jks": "deny",
      "id_rsa": "deny",
      "id_rsa.*": "deny",
      "**/id_rsa": "deny",
      "**/id_rsa.*": "deny",
      "id_dsa": "deny",
      "id_dsa.*": "deny",
      "**/id_dsa": "deny",
      "**/id_dsa.*": "deny",
      "id_ed25519": "deny",
      "id_ed25519.*": "deny",
      "**/id_ed25519": "deny",
      "**/id_ed25519.*": "deny",
      "id_ecdsa": "deny",
      "id_ecdsa.*": "deny",
      "**/id_ecdsa": "deny",
      "**/id_ecdsa.*": "deny",
      "credentials.json": "deny",
      "**/credentials.json": "deny",
      "*credentials*.json": "deny",
      "**/*credentials*.json": "deny",
      "service-account*.json": "deny",
      "**/service-account*.json": "deny",
      "*-service-account*.json": "deny",
      "**/*-service-account*.json": "deny",
      ".npmrc": "deny",
      "**/.npmrc": "deny",
      ".pypirc": "deny",
      "**/.pypirc": "deny",
      ".netrc": "deny",
      "**/.netrc": "deny"
    },
    "glob": "allow",
    "grep": "allow",
    "bash": {
      "*": "deny",
      "git status": "allow",
      "git status *": "allow",
      "git log": "allow",
      "git show": "allow",
      "git ls-files": "allow",
      "git ls-files *": "allow",
      "git rev-parse": "allow",
      "git rev-parse *": "allow",
      "git branch": "allow",
      "git tag": "allow",
      "ls": "allow",
      "ls *": "allow"
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

**Czemu `git *` jest rozbity na konkretne verby zamiast jednego wildcardu?**
Blanket `"git *": "allow"` puszczałby też `git checkout HEAD~5 -- /etc/passwd`,
`git clean -fdx`, `git reset --hard`, `git config user.email evil@x`, etc.
Whitelist konkretnych verbów domyka tę dziurę.

**Czemu `git log` / `git show` BEZ wildcardów?** Bo oba akceptują flagę
`--output=PATH` która zapisuje output do pliku (potwierdzone empirycznie:
`git log --output=/tmp/out.txt -1` tworzy plik). To bypass `edit` policy
przez bash — model mógłby napisać dowolny plik w cwd albo `/tmp`. Glob
nie pozwala wyrazić "any flag except `--output`", więc dropujemy
wildcardy. No-args formy są bezpieczne: `git log` = ostatni commit,
`git show` = HEAD jako patch.

**Czemu nie ma `git diff` / `git diff *`?** Bo `git diff --no-index FILE1 FILE2`
czyta dowolne pliki spoza repo (i poza `external_directory` policy):
`git diff --no-index /etc/hosts /dev/null` dumpuje zawartość `/etc/hosts`
do stdout. Glob nie pozwala wyrazić "any flag except `--no-index`",
więc dropujemy `git diff` w ogóle. Diff dla `uncommitted`/`commit` pre-computuje
wrapper; w `free` mode model czyta pliki przez natywny `read` tool (który
respektuje denylistę).

**Czemu `git branch` i `git tag` BEZ wildcardów?** Bo `git branch -D foo`,
`git branch new`, `git tag -d v1`, `git tag new` — wszystkie matchowałyby
`git branch *` / `git tag *` i mutują `.git/`. Bez argumentów obie komendy
listują (`git branch` → bieżąca + lokalne, `git tag` → wszystkie tagi). Jeśli
model potrzebuje więcej info, niech czyta `.git/refs/` przez `read` tool
(opencode-owy, z polityką ścieżki).

**Czemu read denylista ma każdy wzór dwa razy (raz bez `**/`, raz z `**/`)?**
Bo opencode pattern matching nie cross-slash-uje pojedynczym `*`. Wzór
`id_rsa` matchuje TYLKO root-level plik o tej nazwie; `secrets/id_rsa`
przepuści przez `"*": "allow"`. Żeby pokryć podkatalogi, dodatkowo wpisujemy
`**/id_rsa`. Tak samo dla każdej pozycji denylisty. Brak tej duplikacji w
poprzedniej iteracji oznaczał, że `secrets/.npmrc` albo `packages/app/.env`
przechodziły mimo `.npmrc` / `.env` deny.

**Czemu nie ma `cat`/`find`/`grep`/`rg`/`head`/`tail`/`wc`?** Bo opencode ma
natywne `read`/`glob`/`grep` tools, które respektują path policy (deny dla
sekretów). Bash `cat .env` byłby out-of-band bypass-em — usunęliśmy go. Jak
opencode chce odczytać plik, używa `read` (z denylistą); jak chce listę
plików, używa `glob`; jak chce search-a, `grep`.

## Pełny wrapper bash (config + trap + tmux + polling)

Wszystko w **jednej** komendzie bash (timeout 600000 ms). Trap odpala
się dopiero gdy bash zwróci, czyli po polling-u, czyli po zamknięciu
sesji opencode → restrictive config czyszczony jest dopiero gdy
naprawdę nie jest już potrzebny.

```bash
which opencode tmux >/dev/null || { echo "ERR: brak opencode lub tmux"; exit 1; }

TS=${TS:-$(date +%Y%m%d-%H%M%S)}
TOOL=opencode
SESSION="cr-$TOOL-$TS"
OUT="/tmp/code-review-$TOOL-$TS.md"
RUN_LOG="/tmp/code-review-$TOOL-$TS.log"
RUNNER="/tmp/cr-$TOOL-runner-$TS.sh"
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# === 1. Restrictive config + trap ===
CFG_DIR="$PROJECT_ROOT/.opencode"
CFG_PATH="$CFG_DIR/opencode.json"
CFG_BACKUP=""
CFG_DIR_CREATED=""

if [ -f "$CFG_PATH" ]; then
  CFG_BACKUP="$CFG_PATH.code-review-backup-$$"
  cp "$CFG_PATH" "$CFG_BACKUP"
fi
[ ! -d "$CFG_DIR" ] && CFG_DIR_CREATED=1
mkdir -p "$CFG_DIR"

cat > "$CFG_PATH" <<'OPENCODE_CFG'
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "read": {
      "*": "allow",
      ".env": "deny",
      ".env.*": "deny",
      "**/.env": "deny",
      "**/.env.*": "deny",
      ".env.example": "allow",
      "**/.env.example": "allow",
      "*.pem": "deny",
      "**/*.pem": "deny",
      "*.key": "deny",
      "**/*.key": "deny",
      "*.p12": "deny",
      "**/*.p12": "deny",
      "*.pfx": "deny",
      "**/*.pfx": "deny",
      "*.keystore": "deny",
      "**/*.keystore": "deny",
      "*.jks": "deny",
      "**/*.jks": "deny",
      "id_rsa": "deny",
      "id_rsa.*": "deny",
      "**/id_rsa": "deny",
      "**/id_rsa.*": "deny",
      "id_dsa": "deny",
      "id_dsa.*": "deny",
      "**/id_dsa": "deny",
      "**/id_dsa.*": "deny",
      "id_ed25519": "deny",
      "id_ed25519.*": "deny",
      "**/id_ed25519": "deny",
      "**/id_ed25519.*": "deny",
      "id_ecdsa": "deny",
      "id_ecdsa.*": "deny",
      "**/id_ecdsa": "deny",
      "**/id_ecdsa.*": "deny",
      "credentials.json": "deny",
      "**/credentials.json": "deny",
      "*credentials*.json": "deny",
      "**/*credentials*.json": "deny",
      "service-account*.json": "deny",
      "**/service-account*.json": "deny",
      "*-service-account*.json": "deny",
      "**/*-service-account*.json": "deny",
      ".npmrc": "deny",
      "**/.npmrc": "deny",
      ".pypirc": "deny",
      "**/.pypirc": "deny",
      ".netrc": "deny",
      "**/.netrc": "deny"
    },
    "glob": "allow",
    "grep": "allow",
    "bash": {
      "*": "deny",
      "git status": "allow",
      "git status *": "allow",
      "git log": "allow",
      "git show": "allow",
      "git ls-files": "allow",
      "git ls-files *": "allow",
      "git rev-parse": "allow",
      "git rev-parse *": "allow",
      "git branch": "allow",
      "git tag": "allow",
      "ls": "allow",
      "ls *": "allow"
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

cleanup() {
  # tmux session: zabij na wszelki wypadek (jeśli polling jeszcze biegnie
  # gdy user wciska Ctrl-C w głównym agencie)
  tmux kill-session -t "$SESSION" 2>/dev/null
  # Restore config:
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
…tryb-specyficzne body — patrz "Tryb-specyficzny prompt body" niżej…

<DYREKTYWA ZAPISU - z shared/write-directive.md + opencode-specific dopisek>
<STANDARDOWY PROMPT - z shared/standard-review-prompt.md>
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

▶ Opencode review startuje w tmux:
    Attach (live):  tmux attach -t $SESSION
    Detach (w tmux): Ctrl-B D
    Output:         $OUT
    Log:            $RUN_LOG

INFO

# === 4. Polling — patrz shared/tmux-runner.md, sekcja "Wzorzec polling" ===
# (skopiuj wzorzec 1:1, używa $SESSION / $OUT / $RUN_LOG ustawionych wyżej)
```

`--print-logs` daje real-time INFO logi — gdy opencode się zawiesi na
bootstrapie (auth/sieć), widać to natychmiast w pane'u i w RUN_LOG;
stuck detector aborduje po 90s.

## Tryb-specyficzny prompt body (5 wariantów)

Wstaw w `PROMPT_TEXT` w miejsce `…tryb-specyficzne body…`. Reszta
prompta (dyrektywa zapisu + standardowy prompt review) jest dla
wszystkich trybów identyczna.

### `uncommitted` (wymaga git repo)

Pre-compute diff i wklej do prompta — opencode w restrictive sandbox
może odpalić `git diff` sam, ale dawanie mu gotowego diff-u jest
tańsze (mniej tool calls). Diff może być duży — `git diff HEAD --stat`
>50 plików: ostrzeż userowi, ale wykonaj.

Przed dispatchem: `git rev-parse --is-inside-work-tree >/dev/null 2>&1`,
brak repo → stop.

**WAŻNE — nie zassij sekretów:** restrictive config opencode (sekcja
"Polityka opencode" niżej) blokuje read `.env*` i innych sekretów,
ale pre-compute jest wykonywany przez **głównego agenta zanim** ten
config w ogóle istnieje. Sygnał do prompta zaprojektuj tak, żeby:

1. **Tracked diff** — wykluczać `.env*` w każdym podkatalogu (bez
   `glob` `:(exclude).env` matchuje tylko `./env`, sub/.env wycieka).
2. **Untracked** — NIE wklejać zawartości plików do prompta. Wystarczy
   lista nazw; opencode sam je odczyta przez natywny `read` tool, który
   respektuje denylistę (`.env*`, `*.pem`, `*.key`, `id_rsa*`,
   `credentials.json`, etc.). Wcześniej snippet cat-ował każdy untracked
   plik filtrując tylko `.env*`, więc każdy `id_rsa`, `*.pem`,
   `service-account.json` itp. szedł 1:1 do API opencode.

```bash
# Wspólny zbiór pathspeców-wykluczeń dla tracked diff. Musi być spójny
# z read denylist w restrictive config (sekcja "Polityka opencode") —
# wszystko, co opencode ma zablokowane do odczytu, my też wykluczamy
# z pre-compute, bo ten pipeline biegnie zanim policy jest aktywne.
SECRET_EXCLUDES=(
  ':(exclude,glob).env'                  ':(exclude,glob)**/.env'
  ':(exclude,glob).env.*'                ':(exclude,glob)**/.env.*'
  ':(exclude,glob)*.pem'                 ':(exclude,glob)**/*.pem'
  ':(exclude,glob)*.key'                 ':(exclude,glob)**/*.key'
  ':(exclude,glob)*.p12'                 ':(exclude,glob)**/*.p12'
  ':(exclude,glob)*.pfx'                 ':(exclude,glob)**/*.pfx'
  ':(exclude,glob)*.keystore'            ':(exclude,glob)**/*.keystore'
  ':(exclude,glob)*.jks'                 ':(exclude,glob)**/*.jks'
  ':(exclude,glob)id_rsa'                ':(exclude,glob)**/id_rsa'
  ':(exclude,glob)id_rsa.*'              ':(exclude,glob)**/id_rsa.*'
  ':(exclude,glob)id_dsa'                ':(exclude,glob)**/id_dsa'
  ':(exclude,glob)id_dsa.*'              ':(exclude,glob)**/id_dsa.*'
  ':(exclude,glob)id_ed25519'            ':(exclude,glob)**/id_ed25519'
  ':(exclude,glob)id_ed25519.*'          ':(exclude,glob)**/id_ed25519.*'
  ':(exclude,glob)id_ecdsa'              ':(exclude,glob)**/id_ecdsa'
  ':(exclude,glob)id_ecdsa.*'            ':(exclude,glob)**/id_ecdsa.*'
  ':(exclude,glob)credentials.json'      ':(exclude,glob)**/credentials.json'
  ':(exclude,glob)*credentials*.json'    ':(exclude,glob)**/*credentials*.json'
  ':(exclude,glob)service-account*.json' ':(exclude,glob)**/service-account*.json'
  ':(exclude,glob).npmrc'                ':(exclude,glob)**/.npmrc'
  ':(exclude,glob).pypirc'               ':(exclude,glob)**/.pypirc'
  ':(exclude,glob).netrc'                ':(exclude,glob)**/.netrc'
)

TRACKED=$(git diff HEAD -- "${SECRET_EXCLUDES[@]}")

# Untracked: TYLKO lista nazw (przefiltrowana przez ten sam zbiór
# wzorców), BEZ zawartości. Opencode czyta każdy plik sam przez `read`
# tool — denylista w policy zapewnia, że sekrety które przeciekły z
# filtrowania (np. niestandardowa nazwa) i tak będą odrzucone.
# NUL-delimited iteration odporna na malicious filenames typu
# `$(touch evil)` (kontrast: `xargs -I {} sh -c '... {}'` — vulnerable).
UNTRACKED_LIST=$(
  while IFS= read -r -d '' f; do
    case "$f" in
      .env|.env.*|*/.env|*/.env.*) continue ;;
      *.pem|*/*.pem|*.key|*/*.key) continue ;;
      *.p12|*/*.p12|*.pfx|*/*.pfx|*.keystore|*/*.keystore|*.jks|*/*.jks) continue ;;
      id_rsa|id_rsa.*|*/id_rsa|*/id_rsa.*) continue ;;
      id_dsa|id_dsa.*|*/id_dsa|*/id_dsa.*) continue ;;
      id_ed25519|id_ed25519.*|*/id_ed25519|*/id_ed25519.*) continue ;;
      id_ecdsa|id_ecdsa.*|*/id_ecdsa|*/id_ecdsa.*) continue ;;
      credentials.json|*/credentials.json) continue ;;
      *credentials*.json|*/*credentials*.json) continue ;;
      service-account*.json|*/service-account*.json) continue ;;
      .npmrc|*/.npmrc|.pypirc|*/.pypirc|.netrc|*/.netrc) continue ;;
    esac
    printf '%s\n' "$f"
  done < <(git ls-files -z --others --exclude-standard)
)
```

Body promptu:

```
Poniżej diff zacommitowanych+staged zmian (tracked) oraz lista
untracked plików. Treść untracked czytaj sam przez `read` tool —
sekrety (`.env*`, `*.pem`, `id_rsa*`, etc.) są zablokowane przez
policy, dostaniesz permission denied i pomijasz dany plik.

Tracked diff:
```diff
${TRACKED}
```

Untracked (nazwy):
${UNTRACKED_LIST}
```

### `commit` (wymaga git repo)

Pre-compute `git show` i wklej. Body:

```
SHOW=$(git show "$ARG")
```

```
Poniżej commit ${ARG}. Zrób code review tej konkretnej zmiany.

```
${SHOW}
```
```

### `file` (działa w git i nie-git)

Body:

```
Zrób code review pliku **${ARG}**. Oceń całość, nie tylko ostatnie zmiany.
```

### `dir` (działa w git i nie-git)

Pre-compute listę plików:

```
FILES=$(git ls-files "$ARG" 2>/dev/null || find "$ARG" -type f \
  -not -path '*/\.*' -not -name '*.pyc' | head -50)
```

Body:

```
Zrób code review katalogu **${ARG}**. Lista najważniejszych plików:

${FILES}

Przeczytaj te pliki (masz dostęp do FS przez swoje narzędzia)
i zgłoś problemy. Pomiń testy, chyba że widzisz w nich błędy.
```

### `free` (działa w git i nie-git)

Argument jest wolną wskazówką od usera. Tryb dla "całe repo", "audyt
security", "przejrzyj SPEC.md" itp. Bez pre-computowania — opencode
ma w swoim sandboxie git/ls/find/cat i sam zdecyduje. Body:

```
User prosi o następujące code review tego repo:

  ${ARG}

Sam zorientuj się co dokładnie zreviewować i jak (które pliki,
które komendy git, ewentualnie cały repo). Trzymaj się tematu
i scope-u który user wskazał — jeśli mówi "security audit", nie
rób ogólnego review; jeśli mówi "całe repo", przejrzyj ważne
moduły, nie tylko ostatnie zmiany.

Masz dostęp do bash z bardzo wąską whitelistą: `git status`/`status *`,
`git log` (no-args), `git show` (no-args), `git ls-files`/`ls-files *`,
`git rev-parse`/`rev-parse *`, `git branch` (no-args), `git tag` (no-args),
`ls`/`ls *`. **`git diff`, `git log *`, `git show *`, `git branch *`,
`git tag *` są zablokowane** (przez `--no-index` / `--output=PATH` /
mutating verbs). Do czytania plików używaj narzędzia `read` (z denylistą
sekretów), do listowania `glob`, do search-a `grep` tool — bash-owe
`cat`/`find`/`grep`/`rg` są zablokowane (one obchodzą path policy).
```

## Dyrektywa zapisu (do wklejenia jako `<DYREKTYWA ZAPISU>`)

Czytaj **`../../shared/write-directive.md`** — wstaw zawartość bloku 1:1 jako `<DYREKTYWA ZAPISU>` w komendach opencode powyżej.

**Dodatkowo dla opencode** dopisz na końcu (specyficzne dla restrictive config tej sesji):

```
UWAGA dotycząca permissions w tej sesji:
- read: cały projekt OK z denylistą sekretów (root i każdy podkatalog
  przez `**/`): `.env*`, klucze prywatne `*.pem`/`*.key`/`id_rsa*`/
  `id_dsa*`/`id_ed25519*`/`id_ecdsa*`, pakiety kluczy `*.p12`/`*.pfx`/
  `*.keystore`/`*.jks`, credentiale `credentials.json`/`*credentials*.json`/
  `service-account*.json`, registry creds `.npmrc`/`.pypirc`/`.netrc`.
  Próba odczytu któregoś z tych → permission denied — to zamierzone.
- glob/grep: cały projekt OK.
- bash: TYLKO `git status`/`status *`, `git log` (no-args), `git show`
  (no-args), `git ls-files`/`ls-files *`, `git rev-parse`/`rev-parse *`,
  `git branch` (no-args), `git tag` (no-args), `ls`/`ls *`. Wszystko inne
  → permission denied. **NIE MA `git diff`** (bo `--no-index` czyta pliki
  spoza repo) ani `git log */git show *` (bo `--output=PATH` zapisuje plik).
  Też zablokowane: `git checkout/reset/clean/rm/push/commit/merge/rebase/
  stash/restore/switch/config`, `git branch *`, `git tag *`, `cat`, `find`,
  `grep`, `rg`, `head`, `tail`, `wc`, `rm`, `mv`, `chmod`, `npm`.
  **Do czytania plików używaj narzędzia `read` (NIE `cat`); do listowania
  `glob` (NIE `find`); do search-a `grep` tool (NIE bash-owy `grep`/`rg`).**
  Te tools respektują path policy (denylistę sekretów); bash-owe komendy
  by ją obeszły. Diffy dla bieżącego review są PRE-COMPUTOWANE w prompcie
  poniżej (jeśli tryb tego wymaga) — nie wywołuj `git diff` sam.
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

1. Sesja `cr-opencode-$TS` zamknęła się (sama lub przez stuck detector).
2. `wc -c "$OUT"`. Pusty (0 B) / brak → tail RUN_LOG (`tail -30 "$RUN_LOG"`)
   pokaże dlaczego (auth error, model API timeout, permission denied, etc.).
3. Sensowny rozmiar (>200 B) → `Read "$OUT"`.
4. Powiedz userowi krótko: "Opencode review w `$OUT`. Sesja zakończona,
   log: `$RUN_LOG`."
5. Wywołane przez `code-review-external` → wrapper sam czyta i renderuje.
6. Standalone → pokaż zawartość `$OUT` raz.

## Co jeśli config trap nie zadziałał

Trap firee na EXIT/INT/TERM, ale NIE na SIGKILL (kill -9). Jeśli ktoś
zabije główny proces bash przez kill -9, `.opencode/opencode.json`
zostanie w projekcie. Pokaż userowi co zostało:

```bash
ls -la "$PROJECT_ROOT/.opencode/" 2>/dev/null
ls "$PROJECT_ROOT"/.opencode/opencode.json.code-review-backup-* 2>/dev/null
```

Zapytaj czy ręcznie sprzątnąć (`rm` lub `mv` z backupu). Nie ruszaj sam —
user może mieć swój własny config od innego runa.

Tmux sesja może też zostać orphaned przy SIGKILL bash-a. `tmux ls`
pokaże ewentualne `cr-opencode-*` które nie zniknęły. `tmux kill-session
-t NAME` żeby posprzątać.

## Częste pomyłki

- **Pominięcie tmux** — uruchamianie `opencode run` bezpośrednio (`> $RUN_LOG 2>&1`).
  Opencode w pipe-mode wisi 15+ min na bootstrap (potwierdzone empirycznie).
  W tmux user widzi co się dzieje przez `tmux attach`, stuck detector aborduje
  po 90s. To nie jest opcja — to wymóg architektury.
- **Pominięcie wrappera config + trap** — bez restrictive permissions opencode
  wisi na permission ask 60+ min, w pipe-mode niewidzialny.
- **Użycie `--dangerously-skip-permissions` zamiast project-local config** —
  działa ale obchodzi cały model bezpieczeństwa opencode. Project-local config
  jest precyzyjny.
- **Pominięcie `--dir "$PROJECT_ROOT"`** — opencode może attach do innego TUI,
  traktować projekt jako external_directory → permission denied. `--dir` fiksuje cwd.
- **Pominięcie `--print-logs`** — bez tego opencode w pipe-mode loguje minimalne
  rzeczy do stdout, trudniej zdiagnozować stuck. `--print-logs` daje INFO logi
  w real-time, widać że bootstrap-uje albo gdzie wisi.
- **Pominięcie dyrektywy zapisu w prompcie** — opencode zwraca review na stdout,
  plik OUT nie powstanie. Wrapper czeka na plik, dostanie pusty.
- **HEREDOC z `'PROMPT'`** — blokuje interpolację `${OUT}` / `${ARG}`.
  Bez apostrofów wokół delimitera HEREDOC.
- **Tylko `printf %q` przy budowaniu runnera** — `PROMPT_TEXT` zawiera
  cudzysłowy / backticki / unicode, bez `%q` runner się rozjedzie.
- **Krótki timeout** — duży diff + powolny model = łatwo >5 min. **600000 ms**
  minimum w bash-u.
- **Wklejanie tajnych danych do promptu** — `git diff` może zahaczyć o `.env`,
  klucze. Restrictive config blokuje read `.env`, ale jak DIFF pre-computed
  przed config-em, pre-compute może go zassać. Bezpieczniej: `git diff -- ':!.env'`.
- **Trap który nie restoruje backupu** — jeśli user miał istniejący config,
  MUSISZ go przywrócić. Test: zrób plik z dummy content, odpal skill, sprawdź
  że plik wraca 1:1.
- **Brak `tmux kill-session` w cleanup trap** — jeśli polling się przerwie
  (Ctrl-C w głównym agencie), tmux session żyje dalej z opencode w środku.
  Trap musi `tmux kill-session -t "$SESSION" 2>/dev/null` zanim posprząta config.
- **Stuck threshold za krótki** — opencode boot 30-60s. **90s** to dobre minimum.
  Krócej → false-aborty na cold start.
