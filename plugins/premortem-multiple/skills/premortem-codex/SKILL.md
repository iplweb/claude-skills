---
name: premortem-codex
description: Użyj, gdy user chce premortem na plan/launch/decyzję wykonany przez `codex` (OpenAI Codex CLI). Skill zakłada, że plan już padł 6 miesięcy w przyszłości i każe codexowi wstecznie znaleźć wszystkie powody śmierci, zrobić deep-dive na każdy, i zsyntezować rewizję. Codex pisze finalny raport przez swój write tool do `/tmp/premortem-codex-<timestamp>.md` (czysty markdown), verbose log do `.log`. Wywołuj zawsze, gdy user prosi o "premortem przez codexa", "codex premortem", "/premortem-codex", albo wskazuje codexa jako narzędzie do stress-testu planu. Sens: jedna z trzech niezależnych opinii w `premortem-multiple`, albo standalone gdy user chce tylko codexa.
---

# Premortem przez codex (artifact-file pattern)

## Kiedy używać

- User uruchamia `/premortem-codex [plan-description]`.
- User wprost prosi o "premortem przez codex", "codex premortem".
- W ramach `premortem-multiple` (równolegle do opencode + claude).

NIE używaj, gdy:
- User chce review kodu → to `code-review-codex`.
- User chce trzy opinie premortem naraz → użyj `premortem-multiple`.
- User chce review zrobione przez Ciebie (Claude'a) → `premortem-claude`.

## Wymagania

- `codex` w `$PATH` (`which codex`). Brak → zatrzymaj się i powiedz
  userowi że trzeba zainstalować Codex CLI
  (https://github.com/openai/codex). Nie próbuj instalować sam.
- `tmux` w `$PATH` (`which tmux`). Brak → stop, instalacja
  (`brew install tmux` / `apt install tmux`). Cały skill jedzie przez
  tmux — patrz `../../shared/tmux-runner.md`.

## Co dostaje skill

Wrapper (`premortem-multiple`) podaje skillowi **gotowy kontekst planu**:
trzy elementy minimalne (CO, KTO, SUKCES). Standalone — user opisuje plan
w wiadomości; jeśli któreś z trzech brakuje → zadaj **jedno** pytanie
o najważniejszą lukę, nie kontynuuj z generycznym premortem.

Premortem bez kontekstu = generyczny premortem = bezwartościowy.

## Strategia: tmux + artifact file

Codex uruchamia się **wewnątrz tmux session** (`pm-codex-$TS`). User
może w dowolnym momencie podpiąć się: `tmux attach -t pm-codex-$TS`.

Codex sam pisze finalny premortem do **pliku** przez swój `write` tool
(czysty markdown, ~2-5 KB). Pane output (verbose: reasoning steps, tool
calls, banner-y) capture'owany jest do **osobnego** RUN_LOG przez
`tmux pipe-pane`. Po zakończeniu czytamy tylko OUT przez `Read` — kontekst
Claude'a dostaje czysty premortem zamiast 50+ KB szumu.

Pełny wzorzec (preflight, runner script, launch, polling, stuck detector)
— czytaj **`../../shared/tmux-runner.md`**. Tu opisuję tylko
**codex-specific wycinek**.

> **WAŻNE — czemu `codex exec`, nie `codex review`:** premortem to
> analiza planu, nie kod. `codex exec` (non-interactive) z naszym
> promptem; codex sam wywołuje swój `write` tool na `$OUT`.

## Codex-specific runner line

Linia w runner script (KROK 3 wzorca z `tmux-runner.md`) dla codexa:

```bash
printf 'codex exec --skip-git-repo-check --sandbox workspace-write %q </dev/null\n' "$PROMPT_TEXT"
```

`workspace-write` daje codexowi prawo zapisu do `${OUT}` w `/tmp/`;
`read-only` zablokowałby zapis premortemu. `</dev/null` zamyka stdin
żeby codex nie wisiał na `Reading additional input from stdin...`.

`PREMORTEM_TS` — jeśli wrapper wywołał z konkretnym timestampem, leaf
go używa (przez `TS=${PREMORTEM_TS:-$(date +%Y%m%d-%H%M%S)}` w preflight),
inaczej generuje nowy. Pozwala wrapperowi sparować trójkę plików tego
samego runa.

## Dyrektywa zapisu (do wklejenia jako `<DYREKTYWA ZAPISU>`)

Czytaj **`../../shared/write-directive.md`** — wstaw zawartość bloku 1:1 jako `<DYREKTYWA ZAPISU>` w komendzie codex powyżej. Zmienna `${OUT}` w prompcie zinterpolowana przez shell przed wysłaniem do codexa (HEREDOC bez apostrofów wokół `PROMPT`).

## Standardowy prompt premortem (do wklejenia)

Czytaj **`../../shared/standard-premortem-prompt.md`** — wstaw zawartość bloku 1:1 jako `<TUTAJ STANDARDOWY PROMPT PREMORTEM>` w komendzie codex powyżej.

Edytujesz wspólne pliki raz — trzy leaf skille (codex/opencode/claude) i wrapper używają tej samej wersji prompta. Zmiana metodologii premortemu = zmiana w jednym miejscu.

## Po wykonaniu

1. Sesja `pm-codex-$TS` zamyka się sama gdy codex zwróci. Polling
   z `tmux-runner.md` wykrywa to (`tmux has-session` zwraca false).
2. Sprawdź `wc -c "$OUT"`. Brak / pusty → tail RUN_LOG (`tail -30 "$RUN_LOG"`)
   pokaże dlaczego (auth error, sandbox denial, etc.).
3. Jeśli `$OUT` ma sensowną zawartość — `Read "$OUT"` i tyle (bez
   parsowania RUN_LOG).
4. Powiedz userowi krótko: "Codex premortem w `$OUT`. Sesja zakończona
   (`tmux ls` żeby sprawdzić). Log: `$RUN_LOG`."
5. Wywołane przez `premortem-multiple` → wrapper sam czyta `$OUT`,
   nie drukuj zawartości ponownie.
6. Standalone → pokaż userowi zawartość pliku raz.

## Częste pomyłki

- **Pominięcie tmux** — uruchamianie `codex exec` bezpośrednio (`> $RUN_LOG 2>&1`)
  zamiast w sesji tmux. Tracimy live-attach UX i stuck-detection. ZAWSZE przez tmux,
  patrz `../../shared/tmux-runner.md`.
- **Pominięcie `--sandbox workspace-write`** — `read-only` zablokuje codexowi zapis OUT.
  `workspace-write` daje prawo zapisu do `/tmp/`. Nie używaj `danger-full-access`.
- **Pominięcie `</dev/null` w runnerze** — codex w tmux ma TTY (lepiej), ale dla pewności
  zamykaj stdin redirectem.
- **Pominięcie dyrektywy zapisu w prompcie** — codex wyrzuci premortem na stdout, plik
  `$OUT` nie powstanie. Dyrektywa zapisu jest **obowiązkowa**.
- **HEREDOC z `'PROMPT'` (apostrofami)** — `${OUT}` leci jako literał. Bez apostrofów
  żeby shell zinterpolował.
- **Krótki timeout** — premortem z deep-dive'ami na 7 punktów potrafi iść 5-8 minut.
  Default 120s = false negative. **600000 ms** (10 min) na całość bash polling-a.
- **Generyczny prompt bez kontekstu planu** — premortem bez detali produkuje pustosłowie.
  Jeśli wrapper nie podał kontekstu albo user dał jednozdaniowy plan, zatrzymaj się
  i zapytaj o brakującą część (CO / KTO / SUKCES).
- **Mieszanie z code review** — to NIE jest review kodu. Codex tu nie ma czytać `git diff`,
  ma analizować plan biznesowy/produktowy. Używamy `codex exec`, nie `codex review`.
- **Generowanie różnego timestampu niż wrapper** — jeśli wrapper ustawił `PREMORTEM_TS`
  w env, użyj go. Inaczej trudno sparować trójkę plików.
- **Stuck threshold za krótki** — codex grzeje model 30-60s na cold start. **90s** to
  dobre minimum. Krócej → false-aborty.
- **Czytanie OUT przed zakończeniem sesji** — premortem może być niekompletny. ZAWSZE
  czekaj aż `tmux has-session` zwróci false (patrz polling z `tmux-runner.md`).
- **Pominięcie ogłoszenia `tmux attach -t pm-codex-$TS` userowi** — sens refactora to
  observability. Drukuj attach command **przed** rozpoczęciem polling-u.
