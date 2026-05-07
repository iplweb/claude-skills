---
name: premortem-codex
description: Użyj, gdy user chce premortem na plan/launch/decyzję wykonany przez `codex` (OpenAI Codex CLI). Skill zakłada, że plan już padł 6 miesięcy w przyszłości i każe codexowi wstecznie znaleźć wszystkie powody śmierci, zrobić deep-dive na każdy, i zsyntezować rewizję. Zwraca raport po polsku i zapisuje do `/tmp/premortem-codex-<timestamp>.md`. Wywołuj zawsze, gdy user prosi o "premortem przez codexa", "codex premortem", "/premortem-codex", albo wskazuje codexa jako narzędzie do stress-testu planu. Sens: jedna z trzech niezależnych opinii w `premortem-multiple`, albo standalone gdy user chce tylko codexa.
---

# Premortem przez codex

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

## Komenda

```bash
TS=${PREMORTEM_TS:-$(date +%Y%m%d-%H%M%S)}
OUT=/tmp/premortem-codex-$TS.md

codex exec "$(cat <<'PROMPT'
<TUTAJ STANDARDOWY PROMPT PREMORTEM - patrz niżej>
PROMPT
)" 2>&1 | tee "$OUT"
```

- `codex exec` (non-interactive) zamiast `codex review` — tu nie chodzi
  o kod, tylko o analizę planu.
- `2>&1 | tee "$OUT"` — błędy ze stderr trafiają do pliku.
- Timeout `Bash` ustaw na **600000** ms (10 min) — premortem deep-dive
  potrafi długo myśleć.
- `PREMORTEM_TS` — jeśli wrapper wywołał z konkretnym timestampem,
  używamy go, inaczej generujemy nowy. Pozwala wrapperowi sparować
  trójkę plików tego samego runa.

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

FORMAT ODPOWIEDZI (markdown, po polsku):

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

NIE pisz preambuły o tym co zaraz zrobisz. NIE podsumowuj na koniec
"zakończyłem premortem". Main agent czyta twój output 1:1.
```

## Po wykonaniu

1. Powiedz userowi krótko (1 zdanie): "Codex premortem zapisany w
   `$OUT`."
2. Jeśli wywołany przez `premortem-multiple` — nie drukuj zawartości
   ponownie; wrapper sam ją odczyta i zsyntezuje.
3. Standalone → tee już pokazał wynik na żywo, nie powtarzaj.

## Częste pomyłki

- **Pominięcie `2>&1` przy tee** — błędy z codexa lecą na stderr
  i nie wpadają do pliku.
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
