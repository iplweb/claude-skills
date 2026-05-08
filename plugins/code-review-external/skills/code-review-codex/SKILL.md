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

- `codex` w `$PATH` (sprawdź: `which codex`). Brak → stop, powiedz userowi
  żeby zainstalował Codex CLI (https://github.com/openai/codex).
- `tmux` w `$PATH` (sprawdź: `which tmux`). Brak → stop, powiedz userowi
  żeby zainstalował tmux (`brew install tmux` / `apt install tmux`).
  Cały skill jedzie przez tmux — patrz `../../shared/tmux-runner.md`.
- Działa w git repo **i poza git repo** — używamy `codex exec
  --skip-git-repo-check`, więc katalog nie musi być pod kontrolą
  gita (np. review samego `SPEC.md` w świeżym katalogu projektu).
- Tryby `uncommitted` i `commit` wymagają git repo (codex robi
  `git diff` / `git show`). Tryby `file` / `dir` / `free` działają
  w obu kontekstach.

## Auto-detekcja celu (z argumentu usera)

Wspólna logika 5 trybów (`uncommitted` / `file` / `dir` / `commit` / `free`) — czytaj **`../../shared/target-detection.md`** (dwa poziomy w górę z tego SKILL.md do plugin root, potem `shared/`). Zastosuj wzór i **zawsze ogłoś userowi** wykryty tryb jednym zdaniem zanim odpalisz codexa.

Wspólny plik aktualizujesz raz — wszystkie 4 skille pluginu (codex/opencode/claude/external) używają tej samej detekcji.

## Strategia: tmux + artifact file

Wszystkie 5 trybów uruchamia codex **wewnątrz tmux session** (`cr-codex-$TS`).
User może w dowolnym momencie podpiąć się: `tmux attach -t cr-codex-$TS`.

Codex sam pisze finalne review do **pliku** przez swój `write` tool
(czysty markdown, ~1-3 KB). Pane output (verbose: reasoning steps, tool
calls, banner-y) capture'owany jest do **osobnego** RUN_LOG przez
`tmux pipe-pane`. Po zakończeniu czytamy tylko OUT przez `Read` — kontekst
Claude'a dostaje czyste review zamiast 60 KB szumu.

Pełny wzorzec (preflight, runner script, launch, polling, stuck detector,
combined polling dla external) — czytaj **`../../shared/tmux-runner.md`**.
Tu opisuję tylko **codex-specific wycinek**.

> **WAŻNE — czemu `codex exec`, nie `codex review`:**
> 1. `codex review` nie ma `--skip-git-repo-check` (ma je tylko
>    `codex exec`). W nie-git katalogu wybucha `Not inside a trusted directory`.
> 2. Flagi `--uncommitted` / `--commit` w `codex review` są wzajemnie
>    wykluczające z `[PROMPT]` (codex ≥ 0.129), a my potrzebujemy promptu.
>
> `codex exec` z naszym promptem rozwiązuje obie sprawy: codex sam
> wywołuje `git diff` / `git show` przez swój bash tool.

## Codex-specific runner line

Linia w runner script (KROK 3 wzorca z `tmux-runner.md`) dla codexa:

```bash
printf 'codex exec --skip-git-repo-check --sandbox workspace-write %q </dev/null\n' "$PROMPT_TEXT"
```

`workspace-write` daje codexowi prawo zapisu do `${OUT}` w `/tmp/` oraz
do cwd; `read-only` zablokowałby zapis review. `</dev/null` zamyka stdin
żeby codex nie wisiał na `Reading additional input from stdin...`.

## Tryb-specyficzny prompt body (5 wariantów)

Reszta (dyrektywa zapisu, standardowy prompt review) jest dla wszystkich
trybów identyczna — czytaj `../../shared/write-directive.md` i
`../../shared/standard-review-prompt.md`. Różni się tylko **pierwsza
sekcja prompta** (mówi codexowi co dokładnie zreviewować).

### `uncommitted` (wymaga git repo)

Preflight: `git rev-parse --is-inside-work-tree >/dev/null 2>&1`. Brak →
**zatrzymaj się** i powiedz userowi że ten tryb wymaga repo (zaproponuj
`file` / `dir` / `free`). Body promptu:

```
Zrób code review **niezakomitowanych zmian** w tym repo
(staged + unstaged + untracked). Najpierw uruchom `git status`
i `git diff HEAD` żeby zobaczyć diff, oraz przeczytaj nowe pliki
untracked w całości. Dopiero potem oceniaj.
```

### `commit` (wymaga git repo)

Detekcja sama wymaga `git rev-parse --verify`, więc tryb commit nie
zostanie wykryty poza git repo. Body:

```
Zrób code review zmian wprowadzonych przez commit **${ARG}**.
Najpierw uruchom `git show --stat ${ARG}` i `git show ${ARG}`
żeby zobaczyć diff oraz kontekst zmian. Jeśli commit dotyka nowych
plików, przeczytaj je w całości. Oceniaj **tylko** zmiany w tym
commicie, nie cały stan repo.
```

### `file` (działa w git i nie-git)

Body:

```
Zrób code review pliku **${ARG}**. Przeczytaj go w całości i oceń
jakość kodu, nie tylko ostatnich zmian.
```

### `dir` (działa w git i nie-git)

Body:

```
Zrób code review wszystkich plików źródłowych w katalogu
**${ARG}**. Najpierw wylistuj zawartość, potem przejrzyj
najważniejsze pliki. Pomiń pliki testowe chyba że widzisz w nich
problemy.
```

### `free` (działa w git i nie-git)

Argument jest wolną wskazówką od usera — wkleić go dosłownie. Tryb dla
"całe repo", "audyt security", "ostatnie 3 commity z focus na perf",
"przejrzyj SPEC.md" itp. Body:

```
User prosi o następujące code review tego repo:

  ${ARG}

Sam zorientuj się co dokładnie zreviewować i jak (które pliki,
które komendy git jeśli to git repo, ewentualnie cały katalog).
Trzymaj się tematu i scope-u który user wskazał — jeśli mówi
"security audit", nie rób ogólnego review; jeśli mówi
"przejrzyj SPEC.md", oceniaj ten dokument jak design doc
(spójność, kompletność, dziury w wymaganiach), nie kod.
```

## Złożenie pełnego prompta

Pełny `PROMPT_TEXT` w runnerze to konkatenacja:

1. **Tryb-specyficzne body** (z sekcji wyżej, z interpolacją `${ARG}`).
2. **Dyrektywa zapisu** — czytaj `../../shared/write-directive.md`, wstaw 1:1.
   Zmienna `${OUT}` w treści dyrektywy musi być zinterpolowana przez
   shell przed wysłaniem do codexa (HEREDOC bez apostrofów wokół delimitera).
3. **Standardowy prompt review** — czytaj `../../shared/standard-review-prompt.md`,
   wstaw 1:1.

Edytujesz wspólne pliki raz — trzy leafy + wrapper używają tej samej
wersji.

## Po wykonaniu

1. Sesja `cr-codex-$TS` zamyka się sama gdy codex zwróci. Polling
   z `tmux-runner.md` wykrywa to (`tmux has-session` zwraca false).
2. Sprawdź `wc -c "$OUT"`. Brak / pusty → tail RUN_LOG (`tail -30 "$RUN_LOG"`)
   pokaże dlaczego (auth error, sandbox denial, etc.).
3. Jeśli `$OUT` ma sensowną zawartość — `Read "$OUT"` i tyle (bez
   parsowania RUN_LOG).
4. Powiedz userowi krótko: "Codex review w `$OUT`. Sesja zakończona
   (`tmux ls` żeby sprawdzić). Log: `$RUN_LOG`."
5. Wywołane przez `code-review-external` → wrapper sam czyta OUT.
6. Standalone → pokaż zawartość OUT raz.

## Częste pomyłki

- **Pominięcie tmux** — uruchamianie codexa bezpośrednio (`codex exec ... > $RUN_LOG 2>&1`)
  zamiast w sesji tmux. Tracimy live-attach UX, codex może buforować w pipe-mode
  (mniej niż opencode, ale potrafi). ZAWSZE przez tmux, patrz `../../shared/tmux-runner.md`.
- **Użycie `codex review` zamiast `codex exec`** — `codex review` NIE ma flagi
  `--skip-git-repo-check`, w nie-git katalogu wybucha `Not inside a trusted directory`.
  Używaj `codex exec --skip-git-repo-check --sandbox workspace-write`.
- **Pominięcie `--sandbox workspace-write`** — `read-only` zablokuje codexowi zapis OUT.
  `workspace-write` daje prawo zapisu do cwd i `/tmp/`. Nie używaj `danger-full-access`.
- **Pominięcie `</dev/null` w runnerze** — codex w tmux ma TTY (lepiej), ale dla pewności
  zamykaj stdin redirectem żeby nie wisiał na `Reading additional input from stdin...`.
- **Tryb `uncommitted` w nie-git katalogu** — preflight `git rev-parse --is-inside-work-tree`,
  jak fail → "tu nie ma git repo, użyj `file`/`dir`/`free`". Bez tego codex zwróci śmieci.
- **Pominięcie dyrektywy zapisu w prompcie** — codex wyrzuci review na stdout, plik OUT
  nie powstanie. Dyrektywa zapisu jest **obowiązkowa**.
- **HEREDOC z `'PROMPT'` (apostrofy)** — blokuje interpolację `${OUT}` / `${ARG}` w prompcie.
  Bez apostrofów wokół delimitera HEREDOC.
- **Krótki timeout** — codex na większym diff / dłuższym SPEC.md potrafi 5-8 min.
  Domyślne 120s = false negative. **600000 ms** (10 min) na całość bash polling-a.
- **Cisza przy detekcji trybu** — zawsze ogłoś userowi jednym zdaniem co wykryłeś
  ("Tryb: free, wskazówka: ‘…’"). Typo w ścieżce → user widzi że poszło na `free`,
  może przerwać.
- **Stuck threshold za krótki** — codex grzeje model 30-60s na cold start. **90s** to
  dobre minimum. Krócej → false-aborty.
- **Czytanie OUT przed zakończeniem sesji** — review może być niekompletny. ZAWSZE
  czekaj aż `tmux has-session` zwróci false (patrz polling z `tmux-runner.md`).
- **Pominięcie ogłoszenia `tmux attach -t cr-codex-$TS` userowi** — sens refactora to
  observability. Drukuj attach command **przed** rozpoczęciem polling-u, żeby user
  miał szansę zajrzeć do sesji w trakcie.
