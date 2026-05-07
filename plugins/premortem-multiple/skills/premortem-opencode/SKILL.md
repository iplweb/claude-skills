---
name: premortem-opencode
description: Użyj, gdy user chce premortem na plan/launch/decyzję wykonany przez `opencode` (opencode CLI). Skill zakłada, że plan padł 6 miesięcy w przyszłości i każe opencode wstecznie znaleźć powody śmierci, zrobić deep-dive na każdy, i zsyntezować rewizję. Zwraca raport po polsku i zapisuje do `/tmp/premortem-opencode-<timestamp>.md`. Wywołuj zawsze, gdy user prosi o "premortem przez opencode", "opencode premortem", "/premortem-opencode" albo wskazuje opencode jako narzędzie do stress-testu planu. Sens: jedna z trzech niezależnych opinii w `premortem-multiple`, albo standalone gdy user chce tylko opencode.
---

# Premortem przez opencode

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

## Komenda

```bash
TS=${PREMORTEM_TS:-$(date +%Y%m%d-%H%M%S)}
OUT=/tmp/premortem-opencode-$TS.md

opencode run "$(cat <<'PROMPT'
<TUTAJ STANDARDOWY PROMPT PREMORTEM - patrz niżej>
PROMPT
)" 2>&1 | tee "$OUT"
```

- `2>&1 | tee` — j.w.
- Timeout **600000** ms.
- Bez `--print-logs` (tylko szumi).
- Output opencode ma ASCII banner / status bary — nie filtruj regexem,
  zaśmiecanie łatwo gubi treść. Po prostu zapisz całość; wrapper
  i tak czyta od pierwszego `##` markdown nagłówka.

## Standardowy prompt premortem

Identyczny jak w `premortem-codex` — patrz tam, sekcja "Standardowy
prompt premortem (do wklejenia)". Skopiuj 1:1.

Krótkie przypomnienie struktury (pełny tekst w `premortem-codex`):
1. Przesłanka: plan **już padł** 6 miesięcy w przyszłości.
2. Krok 1: lista wszystkich realnych przyczyn śmierci (specyficznych,
   ugruntowanych, niewymyślonych do liczby).
3. Krok 2: per-przyczyna deep-dive (historia + ukryte założenie +
   wczesne sygnały).
4. Krok 3: synteza (najbardziej prawdopodobna / najbardziej groźna /
   najgłębsze ukryte założenie / rewizja planu / checklist).
5. Format markdown po polsku, bez preambuły, bez podsumowań na koniec.

## Po wykonaniu

1. "Opencode premortem zapisany w `$OUT`."
2. Wywołane przez `premortem-multiple` → nie drukuj ponownie.
3. Standalone → tee pokazał wynik, nie powtarzaj.

## Częste pomyłki

- **Filtrowanie ASCII bannera regexem** — łatwo zjeść kawałek treści.
  Zostaw raw, wrapper sam wytnie banner.
- **Krótki timeout** — j.w., 600000 ms minimum.
- **Pomijanie `2>&1`** — błędy znikają.
- **Próba `--quiet`** — opencode `run` nie ma flagi cichej.
- **Mylenie z review kodu** — to NIE jest `code-review-opencode`.
  Tu opencode analizuje **plan**, nie kod. Bez `-f` na pliki, bez
  `git diff` w prompcie.
- **Pominięcie kontekstu planu w prompcie** — opencode tu nie wie nic
  o planie poza tym co dostanie w prompcie. Brak kontekstu = generyczny
  output bez wartości.
- **Generowanie nowego `$TS` jeśli wrapper podał `PREMORTEM_TS`** —
  użyj env, inaczej trójka plików będzie miała różne stamps.
