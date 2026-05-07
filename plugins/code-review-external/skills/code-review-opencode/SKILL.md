---
name: code-review-opencode
description: Użyj, gdy user chce wygenerować zewnętrzne code review za pomocą `opencode` (opencode CLI). Skill auto-wykrywa cel z argumentu - brak argumentu = niezacommitowane zmiany, SHA/HEAD~N = pojedynczy commit, ścieżka pliku = review pliku, ścieżka katalogu = review katalogu. Generuje review po polsku, drukuje wynik i zapisuje do `/tmp/code-review-opencode-<timestamp>.md`. Wywołuj zawsze, gdy user prosi o "code review przez opencode", "opencode run", "/code-review-opencode" albo wprost wymienia opencode jako external reviewer.
---

# Code review przez opencode

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

Argument przychodzi w wiadomości usera po nazwie skilla. Wykryj typ
**w tej kolejności** (pierwszy match wygrywa):

1. **Brak argumentu** → `uncommitted` (staged + unstaged + untracked).
2. **`test -f "$ARG"`** zwraca true → `file`.
3. **`test -d "$ARG"`** zwraca true → `dir`.
4. **`git rev-parse --verify "$ARG^{commit}"`** zwraca 0 → `commit`.
5. W przeciwnym razie → zatrzymaj się i zapytaj usera (nie zgaduj).

Jednolity oneliner do auto-detekcji - patrz `code-review-codex`,
ta sama logika.

## Kluczowa różnica vs codex

`opencode` **nie ma** dedykowanego trybu code review ani flag
`--uncommitted`/`--commit`. Cały kontekst musisz wstrzyknąć
przez prompt:

- Dla zmian: zrób `git diff` / `git show` i wklej do promptu.
- Dla pliku: `opencode run -f <path> "<prompt>"` (flaga `-f`
  attache plik do kontekstu).
- Dla katalogu: prompt wskazujący ścieżkę - opencode uruchamia
  się w cwd i sam czyta pliki przez tools.

## Komendy per tryb

Zawsze:
- `OUT=/tmp/code-review-opencode-$(date +%Y%m%d-%H%M%S).md`
- Output łapiesz przez `2>&1 | tee "$OUT"`.
- Timeout `Bash` ustaw na **600000** ms (10 min).
- Używaj `--print-logs` tylko jeśli debugujesz; do review tylko
  szumi.

### `uncommitted`

Diff może być duży - jeśli `git diff HEAD --stat` pokazuje >50
plików, ostrzeż usera w jednym zdaniu, ale wykonaj.

```bash
DIFF=$(git diff HEAD; git ls-files --others --exclude-standard \
  | xargs -I {} sh -c 'echo "=== UNTRACKED: {} ==="; cat {}')
opencode run "$(cat <<PROMPT
Poniżej diff niezacommitowanych zmian. Zrób code review.

<TUTAJ STANDARDOWY PROMPT>

\`\`\`diff
${DIFF}
\`\`\`
PROMPT
)" 2>&1 | tee "$OUT"
```

### `commit`

```bash
SHOW=$(git show "$ARG")
opencode run "$(cat <<PROMPT
Poniżej commit ${ARG}. Zrób code review tej konkretnej zmiany.

<TUTAJ STANDARDOWY PROMPT>

\`\`\`
${SHOW}
\`\`\`
PROMPT
)" 2>&1 | tee "$OUT"
```

### `file`

Użyj `-f` żeby attache plik do kontekstu - opencode wtedy widzi
go jako oddzielny artefakt zamiast wklejki w prompcie.

```bash
opencode run -f "$ARG" "$(cat <<PROMPT
Zrób code review załączonego pliku **${ARG}**. Oceń całość, nie
tylko ostatnie zmiany.

<TUTAJ STANDARDOWY PROMPT>
PROMPT
)" 2>&1 | tee "$OUT"
```

### `dir`

```bash
FILES=$(git ls-files "$ARG" 2>/dev/null || find "$ARG" -type f \
  -not -path '*/\.*' -not -name '*.pyc' | head -50)
opencode run "$(cat <<PROMPT
Zrób code review katalogu **${ARG}**. Lista najważniejszych plików:

${FILES}

Przeczytaj te pliki (masz dostęp do FS przez swoje narzędzia)
i zgłoś problemy. Pomiń testy, chyba że widzisz w nich błędy.

<TUTAJ STANDARDOWY PROMPT>
PROMPT
)" 2>&1 | tee "$OUT"
```

## Prompt review (standardowy blok do wklejenia)

Wklej **ten blok** w miejsce `<TUTAJ STANDARDOWY PROMPT>`:

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

FORMAT ODPOWIEDZI (markdown, po polsku):

## Podsumowanie
2-3 zdania: ogólna ocena + verdykt
(gotowe do merge / wymaga drobnych zmian / blokery).

## Uwagi (tylko score ≥ 80)

### 🔴 CRITICAL (blokery, score 100)
### 🟠 HIGH (fix przed merge, score 90-99)
### 🟡 MEDIUM (warto poprawić, score 80-89)

W każdej sekcji lista, każda uwaga w formacie wyżej.
Sekcja pusta → "brak".

Jeśli wszystkie sekcje puste → napisz wprost: "Nie znalazłem realnych
problemów score ≥ 80." Nie dorabiaj uwag żeby coś zgłosić.
```

## Po wykonaniu

1. Powiedz userowi krótko: "Opencode review zapisany w `$OUT`."
2. Jeśli wywołany przez `code-review-external` - nie drukuj
   ponownie zawartości.
3. Jeśli standalone - tee już pokazał wynik na żywo, nie powtarzaj.

## Częste pomyłki

- **Wyjście opencode ma sporo "ozdóbek"** (banner ASCII, status
  bary). Nie filtruj ich - zaśmiecanie regexem łatwo gubi
  zawartość review. Po prostu zapisz całość do pliku.
- **Pomijanie `2>&1` przy tee** - błędy lecą na stderr i znikają.
- **Krótki timeout** - duży diff + powolny model = łatwo >5 minut.
  Default 120s będzie killował. Zawsze 600000 ms.
- **Próba użycia `--quiet`/`-q`** - opencode `run` nie ma flagi
  cichej, nie wymyślaj.
- **Wklejanie tajnych danych do promptu** - jeśli `git diff`
  zahacza o `.env`, sekrety, klucze - obetnij ręcznie albo
  pomiń te pliki przez `git diff -- ':!.env'`.
- **Zgadywanie typu argumentu** - patrz `code-review-codex`,
  ta sama reguła: niejednoznaczność = pytanie do usera.
