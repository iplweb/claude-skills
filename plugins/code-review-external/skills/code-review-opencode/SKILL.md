---
name: code-review-opencode
description: Użyj, gdy user chce wygenerować zewnętrzne code review za pomocą `opencode` (opencode CLI). Skill auto-wykrywa cel z argumentu - brak argumentu = niezacommitowane zmiany, SHA/HEAD~N = pojedynczy commit, ścieżka pliku = review pliku, ścieżka katalogu = review katalogu. Opencode pisze finalne review przez swój write tool do `/tmp/code-review-opencode-<timestamp>.md` (czysty markdown), verbose log do `.log`. Uruchamiany z tymczasowym project-local config (`.opencode/opencode.json`) który blokuje wszystkie modyfikacje poza zapisem review do `/tmp/`. Wywołuj zawsze, gdy user prosi o "code review przez opencode", "opencode run", "/code-review-opencode" albo wprost wymienia opencode jako external reviewer.
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

Identycznie jak w `code-review-codex`:

1. **Brak argumentu** → `uncommitted` (staged + unstaged + untracked).
2. **`test -f "$ARG"`** → `file`.
3. **`test -d "$ARG"`** → `dir`.
4. **`git rev-parse --verify "$ARG^{commit}"`** zwraca 0 → `commit`.
5. W przeciwnym razie → zatrzymaj się i zapytaj usera (nie zgaduj).

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

## Dyrektywa zapisu (do wklejenia jako `<DYREKTYWA ZAPISU>`)

```
WAŻNE — gdzie zwracasz review:

Twój **jedyny deliverable** to plik markdown pod ścieżką:
**${OUT}**

Zapisz finalne review wprost do tego pliku, używając swojego
`write` tool. Plik ma zawierać:
- WYŁĄCZNIE ustrukturyzowany markdown wg formatu poniżej,
- BEZ preambuły typu "OK, zaczynam review...",
- BEZ podsumowania "Skończyłem review",
- BEZ powtarzania review na stdout.

Pierwsza linia pliku ma być nagłówkiem `## Podsumowanie`.

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

Jeśli skończysz analizę bez znalezienia problemów score ≥ 80 —
zapisz plik z sekcjami pustymi i jednym zdaniem
"Nie znalazłem realnych problemów score ≥ 80." pod podsumowaniem.
NIE pomijaj zapisu, NIE wymyślaj uwag żeby coś wpisać.
```

## Prompt review (standardowy blok do wklejenia)

```
Pisz po polsku. Senior reviewer, konkret nie ogólnik.

KONTEKST PROJEKTU:
- **NAJPIERW** zorientuj się jaki to projekt: jakim językiem pisany,
  jakim frameworkiem, gdzie testy. Wykryj sam (po plikach typu
  `pyproject.toml`, `package.json`, `Cargo.toml`, `go.mod`).
- **POTEM przeczytaj `CLAUDE.md` w korzeniu repo** oraz każdy inny
  `CLAUDE.md` znaleziony w katalogach zmienionych w tym diff/commit/
  pliku/katalogu (twarde reguły konkretnego projektu - zakazy
  formatowania, wymagania exception handling, zakaz modyfikowania
  migracji, wymagane prefiksy komend, itp.).
- Złamanie reguły z CLAUDE.md → automatycznie score ≥ 75 i cytuj
  którą regułę złamano.
- Spójność z konwencjami sąsiedniego kodu liczy się tak samo jak
  reguły explicit.

CO ZGŁOSIĆ (tylko realne problemy):
- Bugi i błędy logiczne (off-by-one, błędne warunki, race conditions,
  leak zasobów, zły lifecycle).
- Luki bezpieczeństwa: SQL injection, XSS, CSRF, command injection,
  path traversal, IDOR, niebezpieczne deserializacje, brakujące
  permissions, sekrety w logach/responsach, GET-y mutujące stan.
- Złamanie konkretnej reguły z CLAUDE.md (cytuj którą).
- Połknięte wyjątki bez logu/re-raise (`except: pass`,
  `catch (e) {}`, etc.) - prawie zawsze błąd.
- Brakujące walidacje input-u na granicy systemu.
- Framework-specific anti-patterny (np. Django: N+1, brak
  `select_related`, niezweryfikowane permissions; React: brak
  deps w `useEffect`, mutacja state - dobierz wg języka).
- Brak testów dla **nowej** krytycznej ścieżki, jeśli reszta repo
  testy pisze.

CO BEZWZGLĘDNIE POMIJAĆ (false positives - score 0):
- Pre-existing issues (problem był przed tą zmianą).
- Problemy na liniach **nie zmodyfikowanych** w tym diff/commit
  (NIE dotyczy trybu file/dir - tam review całości jest sensem).
- Cokolwiek co łapie linter/typechecker/CI: formatowanie, długość
  linii, importy, type errors, broken tests.
- Subiektywne preferencje stylu nie wymienione w CLAUDE.md.
- "Dodaj docstring/type hints" jeśli reszta repo ich nie ma.
- Issue explicit-em wyciszony w kodzie (`# noqa`, `# type: ignore`,
  `eslint-disable`).
- Zmiany funkcjonalności intencjonalne / część szerszej zmiany.
- Generic "lack of test coverage / poor documentation" - tylko
  jeśli CLAUDE.md tego wymaga.

CONFIDENCE SCORING (0-100), ZGŁASZAJ TYLKO ≥ 80:
- 0: FP, nie wytrzyma lekkiej krytyki, lub pre-existing.
- 25: może realny, może FP - nie potwierdzony.
- 50: potwierdzony, ale nitpick / rzadki w praktyce.
- 75: ważny, na pewno wystąpi w praktyce, lub explicit w CLAUDE.md.
- 100: pewny, częsty, dowody wprost w kodzie.

Każda zgłoszona uwaga MUSI mieć:
- **`<plik>:<linia>`** - bez tego nie zgłaszaj.
- Cytat fragmentu (max 5 linii) jeśli pomaga.
- Sugestia naprawy w 1-2 zdaniach.
- Cytat reguły z CLAUDE.md jeśli to compliance issue.

FORMAT PLIKU `${OUT}` (markdown, po polsku):

## Podsumowanie
2-3 zdania: ogólna ocena + verdykt
(gotowe do merge / wymaga drobnych zmian / blokery).

## Uwagi (tylko score ≥ 80)

### 🔴 CRITICAL (blokery, score 100)
### 🟠 HIGH (fix przed merge, score 90-99)
### 🟡 MEDIUM (warto poprawić, score 80-89)

Sekcja pusta → "brak".
```

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
