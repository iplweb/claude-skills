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

## Co dostaje skill

Wrapper (`premortem-multiple`) podaje skillowi **gotowy kontekst planu**:
trzy elementy minimalne (CO, KTO, SUKCES). Standalone — user opisuje plan
w wiadomości; jeśli któreś z trzech brakuje → zadaj **jedno** pytanie
o najważniejszą lukę, nie kontynuuj z generycznym premortem.

Premortem bez kontekstu = generyczny premortem = bezwartościowy.

## Strategia output: artifact file zamiast tee

Stary wzorzec (`2>&1 | tee "$OUT"`) wciągał do kontekstu Claude'a
cały verbose dump codexa: echoed prompt, reasoning steps, exec
calls — sam premortem pojawiał się dopiero na końcu i tonął
w 50+ KB szumu.

Nowy wzorzec:
1. **Codex sam pisze finalny premortem do pliku** przez swój
   `write` tool (codex ma write/bash/read jako built-in).
2. Wskazujemy mu konkretną ścieżkę `$OUT` w prompcie.
3. Stdout/stderr lecą do **osobnego** `$RUN_LOG` (debug only).
4. Po wykonaniu czytamy **tylko** `$OUT` przez `Read` — czyste
   kilka KB markdown zamiast 50+ KB śmietnika.

## Komenda

```bash
TS=${PREMORTEM_TS:-$(date +%Y%m%d-%H%M%S)}
OUT=/tmp/premortem-codex-$TS.md
RUN_LOG=/tmp/premortem-codex-$TS.log

codex exec "$(cat <<PROMPT
<DYREKTYWA ZAPISU - patrz niżej>
<TUTAJ STANDARDOWY PROMPT PREMORTEM - patrz dalej>
PROMPT
)" > "$RUN_LOG" 2>&1
```

- `codex exec` (non-interactive) zamiast `codex review` — tu nie chodzi
  o kod, tylko o analizę planu.
- `> "$RUN_LOG" 2>&1` — verbose codex idzie tylko do logu.
- `PREMORTEM_TS` — jeśli wrapper wywołał z konkretnym timestampem,
  używamy go, inaczej generujemy nowy. Pozwala wrapperowi sparować
  trójkę plików tego samego runa.
- Timeout `Bash` ustaw na **600000** ms (10 min) — premortem deep-dive
  potrafi długo myśleć.
- HEREDOC bez apostrofów wokół `PROMPT` — żeby `${OUT}` interpolowało
  się przez shell ZANIM prompt trafi do codexa.

## Dyrektywa zapisu (do wklejenia jako `<DYREKTYWA ZAPISU>`)

Czytaj **`../../shared/write-directive.md`** — wstaw zawartość bloku 1:1 jako `<DYREKTYWA ZAPISU>` w komendzie codex powyżej. Zmienna `${OUT}` w prompcie zinterpolowana przez shell przed wysłaniem do codexa (HEREDOC bez apostrofów wokół `PROMPT`).

## Standardowy prompt premortem (do wklejenia)

Czytaj **`../../shared/standard-premortem-prompt.md`** — wstaw zawartość bloku 1:1 jako `<TUTAJ STANDARDOWY PROMPT PREMORTEM>` w komendzie codex powyżej.

Edytujesz wspólne pliki raz — trzy leaf skille (codex/opencode/claude) i wrapper używają tej samej wersji prompta. Zmiana metodologii premortemu = zmiana w jednym miejscu.

## Po wykonaniu

1. Sprawdź `wc -c "$OUT"`. Pusty / nie istnieje → coś poszło nie
   tak, zerknij na `tail -50 "$RUN_LOG"` i pokaż userowi.
2. Jeśli sensowna zawartość — `Read "$OUT"`.
3. Powiedz userowi krótko: "Codex premortem w `$OUT`, verbose log
   w `$RUN_LOG`."
4. Wywołane przez `premortem-multiple` → wrapper sam czyta `$OUT`,
   nie drukuj zawartości ponownie.
5. Standalone → pokaż userowi zawartość pliku raz.

## Częste pomyłki

- **Stary wzorzec `tee`** — wciąga 30-50 KB śmieci do kontekstu
  Claude'a, premortem ginie. Stdout do `$RUN_LOG`, raport do `$OUT`.
- **Pominięcie dyrektywy zapisu w prompcie** — codex wyrzuci
  premortem na stdout, plik `$OUT` nie powstanie.
- **HEREDOC z `'PROMPT'` (apostrofami)** — `${OUT}` leci jako
  literał. Bez apostrofów żeby shell zinterpolował.
- **Krótki timeout** — premortem z deep-dive'ami na 7 punktów potrafi
  iść 5-8 minut. Default 120s = false negative.
- **Generyczny prompt bez kontekstu planu** — premortem bez detali
  produkuje pustosłowie. Jeśli wrapper nie podał kontekstu albo user
  dał jednozdaniowy plan, zatrzymaj się i zapytaj o brakującą część
  (CO / KTO / SUKCES).
- **Mieszanie z code review** — to NIE jest review kodu. Codex tu nie
  ma czytać `git diff`, ma analizować plan biznesowy/produktowy.
  Używamy `codex exec`, nie `codex review`.
- **Generowanie różnego timestampu niż wrapper** — jeśli wrapper
  ustawił `PREMORTEM_TS` w env, użyj go. Inaczej trudno sparować
  trójkę plików.
- **Nie sprawdzanie czy plik powstał** — `wc -c "$OUT"` przed Read,
  zawsze.
