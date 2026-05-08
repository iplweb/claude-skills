---
name: code-review-codex
description: Użyj, gdy user chce wygenerować zewnętrzne code review za pomocą `codex` (OpenAI Codex CLI). Skill auto-wykrywa cel z argumentu - brak argumentu = niezacommitowane zmiany, SHA/HEAD~N/branch = pojedynczy commit, ścieżka pliku = review pliku, ścieżka katalogu = review katalogu, dowolny inny tekst = free-form wskazówka dla codexa (np. "całe repo", "security audit src/auth/", "ostatnie 3 commity z focus na perf"). Codex pisze finalne review przez swój write tool do `/tmp/code-review-codex-<timestamp>.md` (czysty markdown), a verbose log idzie do `.log`. Wywołuj zawsze, gdy user prosi o "code review codexem", "codex review", "/code-review-codex" albo wprost wymienia codex jako external reviewer.
---

# Code review przez codex (artifact-file pattern)

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
5. **W przeciwnym razie → `free`** (free-form hint). Argument jest
   wolnym tekstem od usera (np. "całe repo", "audyt security w
   `src/auth/`", "sprawdź czy nowe API jest backward compatible") —
   przekazujemy go jako wskazówkę do codexa, on sam decyduje co i jak
   zreviewować w kontekście tego repo.

Sprawdzenia rób przez `Bash` jednym wywołaniem, np.:

```bash
ARG="..."  # to co user podał
if [ -z "$ARG" ]; then echo "uncommitted"
elif [ -f "$ARG" ]; then echo "file"
elif [ -d "$ARG" ]; then echo "dir"
elif git rev-parse --verify "$ARG^{commit}" >/dev/null 2>&1; then echo "commit"
else echo "free"
fi
```

Po detekcji **zawsze ogłoś userowi co wykryłeś** jednym zdaniem
("Tryb: free-form, wskazówka: ‘…’"), żeby mógł przerwać jeśli to
pomyłka (np. typo w ścieżce pliku spadł na `free`).

## Strategia output: artifact file zamiast tee

Stary wzorzec (`2>&1 | tee "$OUT"`) wciągał do kontekstu Claude'a
cały verbose dump codexa: echoed prompt, exec calls, file listings,
reasoning steps — review pojawiał się dopiero na końcu i tonęło
w 60+ KB szumu. Empirycznie potwierdzone na konkretnym runie.

Nowy wzorzec:
1. **Codex sam pisze finalne review do pliku** przez swój `write` tool
   (codex ma write/bash/read jako built-in tools).
2. Wskazujemy mu konkretną ścieżkę `$OUT` w prompcie.
3. Stdout/stderr lecą do **osobnego** `$RUN_LOG` (do debugowania
   gdyby coś padło — nie do czytania na co dzień).
4. Po wykonaniu czytamy **tylko** `$OUT` przez `Read` — kontekst
   Claude'a dostaje czyste 1-3 KB markdown zamiast 60 KB śmietnika.

## Komendy per tryb

Zawsze:
- `TS=${TS:-$(date +%Y%m%d-%H%M%S)}` — jeśli wrapper podał `TS`,
  użyj go (parowanie trójki plików tego samego runa).
- `OUT=/tmp/code-review-codex-$TS.md` — czysty markdown review.
- `RUN_LOG=/tmp/code-review-codex-$TS.log` — verbose codex stdout/stderr.
- Output **przekierowany do RUN_LOG** (`> "$RUN_LOG" 2>&1`), bez `tee`.
- Timeout `Bash` ustaw na **600000** ms (10 min).

Każda komenda kończy `bash`-em pojedynczego HEREDOC z promptem
zawierającym **dyrektywę zapisu** + standardowy prompt review.

> **WAŻNE — flagi `--uncommitted` / `--commit` są wzajemnie wykluczające
> z `[PROMPT]`** (codex ≥ 0.129 odrzuca je z błędem
> `the argument '--uncommitted' cannot be used with '[PROMPT]'`).
> Nie używamy więc tych flag — zamiast tego dajemy codexowi własny
> prompt, który mówi co ma zreviewować, a codex sam robi `git diff` /
> `git show` przez swój bash tool. Dzięki temu możemy też wkleić
> dyrektywę zapisu do pliku.

### `uncommitted`

```bash
codex review "$(cat <<PROMPT
Zrób code review **niezakomitowanych zmian** w tym repo
(staged + unstaged + untracked). Najpierw uruchom \`git status\`
i \`git diff HEAD\` żeby zobaczyć diff, oraz przeczytaj nowe pliki
untracked w całości. Dopiero potem oceniaj.

<DYREKTYWA ZAPISU - patrz niżej>
<TUTAJ STANDARDOWY PROMPT - patrz sekcja "Prompt review">
PROMPT
)" > "$RUN_LOG" 2>&1
```

### `commit`

```bash
codex review "$(cat <<PROMPT
Zrób code review zmian wprowadzonych przez commit **${ARG}**.
Najpierw uruchom \`git show --stat ${ARG}\` i \`git show ${ARG}\`
żeby zobaczyć diff oraz kontekst zmian. Jeśli commit dotyka nowych
plików, przeczytaj je w całości. Oceniaj **tylko** zmiany w tym
commicie, nie cały stan repo.

<DYREKTYWA ZAPISU>
<TUTAJ STANDARDOWY PROMPT>
PROMPT
)" > "$RUN_LOG" 2>&1
```

### `file`

`codex review` nie ma flagi do pojedynczego pliku — używamy `codex review`
z custom promptem, codex sam czyta plik:

```bash
codex review "$(cat <<PROMPT
Zrób code review pliku **${ARG}**. Przeczytaj go w całości i oceń
jakość kodu, nie tylko ostatnich zmian.

<DYREKTYWA ZAPISU>
<TUTAJ STANDARDOWY PROMPT>
PROMPT
)" > "$RUN_LOG" 2>&1
```

(HEREDOC bez cudzysłowów wokół `PROMPT` — wtedy `${ARG}` i `${OUT}`
są interpolowane przez shell.)

### `dir`

```bash
codex review "$(cat <<PROMPT
Zrób code review wszystkich plików źródłowych w katalogu
**${ARG}**. Najpierw wylistuj zawartość, potem przejrzyj
najważniejsze pliki. Pomiń pliki testowe chyba że widzisz w nich
problemy.

<DYREKTYWA ZAPISU>
<TUTAJ STANDARDOWY PROMPT>
PROMPT
)" > "$RUN_LOG" 2>&1
```

### `free`

Argument jest wolną wskazówką od usera — wkleić go dosłownie.
Codex sam orientuje się jakie pliki wziąć, jakie diff-y wywołać,
itd. To jest tryb dla "całe repo", "audyt security", "ostatnie
3 commity z focus na perf" i podobnych pytań które nie pasują do
auto-detekcji.

```bash
codex review "$(cat <<PROMPT
User prosi o następujące code review tego repo:

  ${ARG}

Sam zorientuj się co dokładnie zreviewować i jak (które pliki,
które komendy git, ewentualnie cały repo). Trzymaj się tematu
i scope-u który user wskazał — jeśli mówi "security audit", nie
rób ogólnego review; jeśli mówi "całe repo", przejrzyj ważne
moduły, nie tylko ostatnie zmiany.

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
- BEZ powtarzania review na stdout (stdout idzie tylko do
  loga debugowego, nie do usera).

Pierwsza linia pliku ma być nagłówkiem `## Podsumowanie`.

Możesz swobodnie używać bash/read/grep do nawigacji po repo —
to są twoje narzędzia robocze, ale ich output NIE idzie do
deliverable. Tylko `write` na plik ${OUT}.

Jeśli skończysz analizę bez znalezienia problemów score ≥ 80 —
zapisz plik z sekcjami pustymi i jednym zdaniem
"Nie znalazłem realnych problemów score ≥ 80." pod podsumowaniem.
NIE pomijaj zapisu, NIE wymyślaj uwag żeby coś wpisać.
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

FORMAT PLIKU `${OUT}` (markdown, po polsku):

## Podsumowanie
2-3 zdania: ogólna ocena + verdykt
(gotowe do merge / wymaga drobnych zmian / blokery).

## Uwagi (tylko score ≥ 80)

### 🔴 CRITICAL (blokery, score 100)
### 🟠 HIGH (fix przed merge, score 90-99)
### 🟡 MEDIUM (warto poprawić, score 80-89)

W każdej sekcji lista, każda uwaga w formacie wyżej.
Sekcja pusta → "brak".
```

## Po wykonaniu

1. Sprawdź czy `$OUT` istnieje i ma >100 B (`wc -c "$OUT"`). Jeśli
   pusty/nieistniejący → coś poszło nie tak, zerknij na `tail -50
   "$RUN_LOG"` i pokaż userowi.
2. Jeśli `$OUT` ma sensowną zawartość — przeczytaj go przez `Read`
   i tyle (bez parsowania `$RUN_LOG`).
3. Powiedz userowi krótko: "Codex review w `$OUT`, verbose log
   w `$RUN_LOG`."
4. Jeśli skill wywołany przez `code-review-external` — wrapper
   sam czyta `$OUT`, nie drukuj zawartości ponownie.
5. Standalone — pokaż userowi zawartość pliku `$OUT` raz (Read +
   wstaw do odpowiedzi).

## Częste pomyłki

- **Stary wzorzec `tee` + `2>&1`** — wciąga 50+ KB śmieci do
  kontekstu Claude'a. Już nie używamy. Stdout idzie do `$RUN_LOG`,
  review do `$OUT`.
- **Pominięcie dyrektywy zapisu w prompcie** — bez niej codex
  wyrzuci review na stdout, plik `$OUT` nie powstanie. Dyrektywa
  zapisu jest **obowiązkowa**, nie opcjonalna.
- **HEREDOC z `'PROMPT'` (z apostrofami)** — blokuje interpolację,
  więc `${OUT}` i `${ARG}` lecą jako literały do codexa. Używaj
  HEREDOC bez apostrofów żeby shell zinterpolował zmienne ZANIM
  prompt trafi do codexa.
- **Krótki timeout** — codex review na większym diff-ie potrafi
  iść 5-8 minut. Domyślne 120s = false negative.
- **Cisze przy detekcji trybu** — zawsze ogłoś userowi jeden zdanie
  co wykryłeś ("Tryb: free, wskazówka: ‘…’"). Dzięki temu jak user
  zrobił typo w ścieżce pliku i argument spadł na `free`, ma szansę
  przerwać przed odpaleniem codexa.
- **Użycie flagi `--uncommitted` lub `--commit <SHA>` razem z PROMPT** —
  codex (≥ 0.129) odrzuca to z błędem `the argument '--uncommitted'
  cannot be used with '[PROMPT]'`. Te flagi są **wykluczające** z
  custom promptem, a my potrzebujemy promptu (dyrektywa zapisu).
  Dlatego w trybach `uncommitted` i `commit` NIE używamy tych flag —
  dajemy codexowi prompt który każe mu samemu zrobić `git diff HEAD`
  / `git show <sha>` przez jego bash tool.
- **Wklejanie sekretów do promptu** — codex i tak ma dostęp do FS,
  niech czyta sam.
- **Nie sprawdzanie czy plik powstał** — czasem codex zignoruje
  dyrektywę albo padnie. Zawsze `wc -c "$OUT"` przed Read.
