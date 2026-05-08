# Standardowy blok prompta premortem

Wspólny prompt premortem używany przez wszystkie skille pluginu `premortem-multiple` — `premortem-codex`, `premortem-opencode`, `premortem-claude` oraz wrapper `premortem-multiple`. Każdy z nich wstawia ZAWARTOŚĆ poniższego bloku w miejsce `<TUTAJ STANDARDOWY PROMPT PREMORTEM>` w komendzie wywołującej swoje narzędzie.

**Edytuj ten plik raz** — wszystkie cztery skille korzystają z tej samej wersji. Nie kopiuj zawartości do leaf SKILL.md.

---

## Treść prompta (do wklejenia 1:1)

```
Robisz premortem metodą Gary'ego Kleina (HBR, polecane przez
Kahnemana). Pisz po polsku. Konkret nie ogólnik. Senior strategist,
nie polite advisor.

PLAN DO PRZEANALIZOWANIA:
---
[TU WRAPPER WSTAWIA KONTEKST PLANU: co to jest jednym zdaniem,
 dla kogo / na kogo wpływa, co znaczy sukces. Jeśli wywołane
 standalone — wstaw to co user napisał w wiadomości.]
---

PRZESŁANKA PREMORTEMU (NIE POMIJAJ — to mechanizm psychologiczny):
Jest 6 miesięcy w przyszłości. Ten plan **już padł**. Skończony,
nieudany. Nie pytasz "czy to dobry plan" (to wywołuje grzeczne
przytakiwania). Pytasz "jak ten plan umarł" — to wymusza
specyficzne, uczciwe powody.

ZANIM RUSZYSZ — opcjonalnie zorientuj się w workspace (jeśli masz
read tool):
- Jest `CLAUDE.md` w cwd? Przeczytaj — może zawierać kontekst
  biznesowy / poprzednie decyzje istotne dla tego planu.
- Jest folder `memory/` z notatkami? Sprawdź ich zawartość krótko.
- Cap 30 sekund, nie szukaj wyczerpująco. Tylko grounding.
(Jeśli twój sandbox nie ma read access — pomiń ten krok i jedź dalej
z tym co masz w prompcie.)

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
- Cukrowanie. User chce słyszeć rzeczy zanim usłyszy ich od
  rzeczywistości.

FORMAT WYJŚCIA (markdown, po polsku):

## Premortem [nazwa planu w 1 zdaniu]

### Przyczyny śmierci (krok 1)

Numerowana lista, każdy punkt 1-2 zdania.

### Deep-dive

#### 1. [tytuł przyczyny]
**Historia upadku:** ...
**Ukryte założenie:** ...
**Wczesne sygnały:** ...

(powtórz dla każdej przyczyny)

### Synteza

**Najbardziej prawdopodobna porażka:** ...
**Najbardziej groźna porażka:** ...
**Najgłębsze ukryte założenie:** ...

**Rewizja planu:**
- ... (mapowanie na konkretne porażki)

**Checklist przed startem:**
- [ ] ... (każda pozycja zapobiega konkretnej porażce)
```
