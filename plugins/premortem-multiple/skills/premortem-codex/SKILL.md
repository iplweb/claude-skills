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

```
WAŻNE — gdzie zwracasz premortem:

Twój **jedyny deliverable** to plik markdown pod ścieżką:
**${OUT}**

Zapisz finalny raport premortem wprost do tego pliku, używając
swojego `write` tool. Plik ma zawierać:
- WYŁĄCZNIE ustrukturyzowany markdown wg formatu poniżej,
- BEZ preambuły typu "OK, zaczynam premortem...",
- BEZ podsumowania "Skończyłem".
- BEZ powtarzania raportu na stdout.

Pierwsza linia pliku ma być nagłówkiem `## Premortem ...`.

Stdout idzie tylko do loga debugowego, nie do usera. Nie tracz
energii na ładne formatowanie stdout.
```

## Standardowy prompt premortem (do wklejenia)

Wklej **ten blok** w miejsce `<TUTAJ STANDARDOWY PROMPT PREMORTEM>`:

```
Pisz po polsku. Robisz premortem metodą Gary'ego Kleina, nie ogólne
risk assessment.

PLAN DO PRZEANALIZOWANIA:
---
[TU WRAPPER WSTAWIA KONTEKST PLANU: co to jest jednym zdaniem,
 dla kogo / na kogo wpływa, co znaczy sukces. Jeśli wywołane
 standalone — wstaw to co user napisał w wiadomości.]
---

PRZESŁANKA PREMORTEMU:
Jest 6 miesięcy w przyszłości. Ten plan **już padł**. Skończony,
nieudany. Nie pytasz "czy to dobry plan" (to wywołuje grzeczne
przytakiwania). Pytasz "jak ten plan umarł" — i to wymusza
specyficzne, uczciwe powody.

KROK 1 — Lista przyczyn śmierci:
Wygeneruj WSZYSTKIE realne powody, dla których ten plan padł. Każdy
powód musi być:
- specyficzny dla TEGO planu (nie generyczny "ryzyko rynku"),
- ugruntowany w detalach, które dostałeś (nazwij konkretną cenę,
  konkretną grupę, konkretną decyzję),
- realnym zagrożeniem (nie edge case ani niewygoda).
Liczba: tyle ile faktycznie istnieje. Mogą być 4, mogą być 9. Nie
wymyślaj 7-go żeby zapełnić listę. Nie zatrzymuj się na 3 jeśli jest
ich więcej.

KROK 2 — Deep-dive na każdą przyczynę:
Dla KAŻDEJ przyczyny z kroku 1 napisz:
1. **Historia upadku** (2-3 akapity) — narracja jak to się rozegrało.
   Konkretne momenty, konkretne reakcje. Niech brzmi jak case study
   czegoś, co naprawdę się stało.
2. **Ukryte założenie** (1 zdanie) — to JEDNO, co user wziął za
   pewnik, a co umożliwiło tę porażkę.
3. **Wczesne sygnały ostrzegawcze** (1-2 obserwowalne sygnały) —
   coś co da się zobaczyć lub zmierzyć, nie ogólne przeczucia.

KROK 3 — Synteza:
Po deep-dive'ach napisz:
1. **Najbardziej prawdopodobna porażka** — który scenariusz jest
   najbardziej prawdopodobny i dlaczego. Tu user powinien skupić
   wysiłek najpierw.
2. **Najbardziej groźna porażka** — który scenariusz robi największe
   szkody, nawet jeśli mniej prawdopodobny. Warto się asekurować.
3. **Najbardziej ukryte założenie** — z całej analizy: jedna rzecz,
   którą user bierze za pewnik najmocniej. Tu często leży prawdziwa
   wartość premortemu.
4. **Rewizja planu** — KONKRETNE zmiany przypisane do konkretnych
   scenariuszy porażki. NIE "przemyśl strategię". TAK "przetestuj
   cenę 47$ z 20 osobami przed publicznym committem do 297$".
   Każda rewizja ma być wykonalna w tym tygodniu.
5. **Checklist przed startem** — 3-5 konkretnych rzeczy do
   zweryfikowania / zrobić zanim user pociągnie spust. Każda pozycja
   zapobiega konkretnej porażce z listy.

CO POMIJAĆ (false positives):
- "Ryzyko rynkowe", "ryzyko egzekucyjne" — generyki bez wartości.
- Edge case'y które się nie wydarzą w praktyce.
- Doradcze "warto rozważyć X" — premortem produkuje konkrety, nie
  watery porady.
- Pochwały planu i "z tym może być problem ale nie jest aż taki zły"
  — jesteś po stronie znalezienia śmierci, nie balansu opinii.

FORMAT PLIKU `${OUT}` (markdown, po polsku):

## Premortem [nazwa planu w 1 zdaniu]

### Przyczyny śmierci (krok 1)

Lista numerowana, każdy punkt 1-2 zdania.

### Deep-dive

#### 1. [tytuł przyczyny]
**Historia upadku:** ...
**Ukryte założenie:** ...
**Wczesne sygnały:** ...

(powtórz dla każdej przyczyny)

### Synteza

**Najbardziej prawdopodobna porażka:** ...
**Najbardziej groźna porażka:** ...
**Najbardziej ukryte założenie:** ...

**Rewizja planu:**
- ... (mapowanie na konkretne porażki)

**Checklist przed startem:**
- [ ] ... (każda pozycja zapobiega konkretnej porażce)
```

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
