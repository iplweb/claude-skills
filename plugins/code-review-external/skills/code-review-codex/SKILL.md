---
name: code-review-codex
description: Użyj, gdy user chce wygenerować zewnętrzne code review za pomocą `codex` (OpenAI Codex CLI). Skill auto-wykrywa cel z argumentu - brak argumentu = niezacommitowane zmiany, SHA/HEAD~N = pojedynczy commit, ścieżka pliku = review pliku, ścieżka katalogu = review katalogu. Generuje review po polsku, drukuje wynik i zapisuje do `/tmp/code-review-codex-<timestamp>.md`. Wywołuj zawsze, gdy user prosi o "code review codexem", "codex review", "/code-review-codex" albo wprost wymienia codex jako external reviewer.
---

# Code review przez codex

## Kiedy używać

- User wprost prosi o review przez codex (`codex review`, "codexem", "codex CLI").
- User uruchamia `/code-review-codex [target]`.
- W ramach skilla `code-review-external` (uruchamia ten skill równolegle z `code-review-opencode`).

NIE używaj, gdy user chce review zrobione przez Ciebie (Claude'a) -
to oddzielne narzędzie `codex` ma podać drugą opinię.

## Wymagania

- `codex` w `$PATH` (sprawdź: `which codex`). Jeśli nie ma -
  zatrzymaj się, powiedz userowi że trzeba zainstalować Codex CLI
  (https://github.com/openai/codex), nie próbuj instalować sam.
- Działa w katalogu repo (codex sam wykrywa git context).

## Auto-detekcja celu (z argumentu usera)

Argument przychodzi w wiadomości usera po nazwie skilla. Wykryj typ
**w tej kolejności** (pierwszy match wygrywa):

1. **Brak argumentu** → `uncommitted` (staged + unstaged + untracked).
2. **`test -f "$ARG"`** zwraca true → `file`.
3. **`test -d "$ARG"`** zwraca true → `dir`.
4. **`git rev-parse --verify "$ARG^{commit}"`** zwraca 0 → `commit`
   (działa dla SHA, `HEAD`, `HEAD~3`, nazw branchy, tagów).
5. W przeciwnym razie → zatrzymaj się i zapytaj usera co miał na
   myśli (nie zgaduj).

Sprawdzenia rób przez `Bash` jednym wywołaniem, np.:

```bash
ARG="..."  # to co user podał
if [ -z "$ARG" ]; then echo "uncommitted"
elif [ -f "$ARG" ]; then echo "file"
elif [ -d "$ARG" ]; then echo "dir"
elif git rev-parse --verify "$ARG^{commit}" >/dev/null 2>&1; then echo "commit"
else echo "unknown"
fi
```

## Komendy per tryb

Zawsze:
- `OUT=/tmp/code-review-codex-$(date +%Y%m%d-%H%M%S).md`
- Output łapiesz przez `2>&1 | tee "$OUT"` żeby user widział
  na żywo i miał plik.
- Timeout `Bash` ustaw na **600000** ms (10 min) - codex review
  potrafi długo myśleć.

### `uncommitted`

```bash
codex review --uncommitted "$(cat <<'PROMPT'
<TUTAJ STANDARDOWY PROMPT - patrz sekcja "Prompt review" niżej>
PROMPT
)" 2>&1 | tee "$OUT"
```

### `commit`

```bash
codex review --commit "$ARG" "$(cat <<'PROMPT'
<TUTAJ STANDARDOWY PROMPT>
PROMPT
)" 2>&1 | tee "$OUT"
```

### `file`

`codex review` nie ma flagi do pojedynczego pliku, ale akceptuje
custom prompt jako jedyny argument - i codex sam czyta pliki przez
swoje narzędzia. Daj mu konkretną ścieżkę:

```bash
codex review "$(cat <<PROMPT
Zrób code review pliku **${ARG}**. Przeczytaj go w całości i oceń
jakość kodu, nie tylko ostatnich zmian.

<TUTAJ STANDARDOWY PROMPT>
PROMPT
)" 2>&1 | tee "$OUT"
```

(zwróć uwagę: HEREDOC bez cudzysłowów wokół `PROMPT` - wtedy
`${ARG}` jest interpolowane przez shell)

### `dir`

```bash
codex review "$(cat <<PROMPT
Zrób code review wszystkich plików źródłowych w katalogu
**${ARG}**. Najpierw wylistuj zawartość, potem przejrzyj
najważniejsze pliki. Pomiń pliki testowe chyba że widzisz w nich
problemy.

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
  pliku/katalogu (to są twarde reguły konkretnego projektu - mogą
  zawierać zakazy formatowania, wymagania exception handling, zakaz
  modyfikowania migracji, wymagane prefiksy komend, itp.).
- Złamanie reguły z CLAUDE.md → automatycznie score ≥ 75 i cytuj
  którą regułę złamano.
- Spójność z konwencjami sąsiedniego kodu liczy się tak samo jak
  reguły explicit z CLAUDE.md.

CO ZGŁOSIĆ (tylko realne problemy):
- Bugi i błędy logiczne (off-by-one, błędne warunki, race conditions,
  leak zasobów, zły lifecycle obiektów).
- Luki bezpieczeństwa: SQL injection, XSS, CSRF, command injection,
  path traversal, IDOR, niebezpieczne deserializacje, brakujące
  permissions, sekrety w logach/responsach, GET-y mutujące stan.
- Złamanie konkretnej reguły z CLAUDE.md (cytuj którą).
- Połknięte wyjątki bez logu / re-raise (`except: pass`,
  `catch (e) {}`, etc.) - prawie zawsze błąd.
- Brakujące walidacje input-u na granicy systemu.
- Framework-specific anti-patterny (np. dla Django: N+1, brak
  `select_related`, niezweryfikowane permissions w widokach;
  dla React: brak deps w `useEffect`; itd. - dobierz wg języka).
- Brak testów dla **nowej** krytycznej ścieżki, jeśli reszta repo
  testy pisze.

CO BEZWZGLĘDNIE POMIJAĆ (false positives - score 0):
- Pre-existing issues (problem był przed tą zmianą).
- Problemy na liniach **nie zmodyfikowanych** w tym diff/commit
  (NIE dotyczy trybu file/dir - tam review całości jest sensem).
- Cokolwiek co łapie linter/typechecker/CI: formatowanie, długość
  linii, importy, type errors, broken tests, ruff/isort.
- Subiektywne preferencje stylu nie wymienione w CLAUDE.md.
- "Dodaj docstring/type hints" jeśli reszta repo ich nie ma.
- Issue explicit-em wyciszony w kodzie (`# noqa`, `# type: ignore`).
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
problemów score ≥ 80." Nie dorabiaj uwag żeby coś zgłosić - cisza
też jest cennym sygnałem.
```

## Po wykonaniu

1. Powiedz userowi krótko (1 zdanie): "Codex review zapisany w
   `$OUT`."
2. Jeśli skill został wywołany przez `code-review-external` -
   nie drukuj ponownie zawartości; wrapper sam ją odczyta.
3. Jeśli wywołany standalone - tee już pokazał wynik na żywo,
   nie powtarzaj.

## Częste pomyłki

- **Pomijanie `2>&1` przy tee** - błędy z codexa lecą na stderr
  i nie wpadają do pliku. Zawsze `2>&1 | tee`.
- **Krótki timeout** - codex review na większym diff-ie potrafi
  iść 5-8 minut. Domyślne 120s = false negative.
- **Zgadywanie typu argumentu** - jeśli nie pasuje do żadnego
  z czterech wzorców, zapytaj usera; nie wybieraj losowo.
- **Próba użycia `--uncommitted` razem z `--commit`** - codex review
  bierze TYLKO jeden tryb. Auto-detekcja musi wybrać dokładnie jeden.
- **Wklejanie sekretów do promptu** - jeśli `git diff` zahacza
  o `.env`, klucze, hasła w fixtures, obetnij ręcznie albo użyj
  `git diff -- ':!.env' ':!**/secrets/*'`. Codex i tak ma dostęp
  do FS, niech czyta sam.
