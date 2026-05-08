# Dyrektywa zapisu (artifact-file pattern)

Wspólna instrukcja "zapisz finalny premortem do pliku przez write tool" dla wszystkich trzech narzędzi (codex, opencode, claude subagent). Każdy leaf wstawia poniższy blok jako `<DYREKTYWA ZAPISU>` w prompcie do swojego CLI / subagenta.

**Cel:** narzędzie pisze czysty markdown raport wprost do `${OUT}` przez swój write tool, zamiast wyrzucać go na stdout (gdzie tonąłby w bannerach, reasoning, exec logach). Wrapper czyta tylko `${OUT}` i dostaje 2-5 KB czystego markdownu zamiast 30-50 KB szumu.

## Treść do wklejenia (1:1)

```
WAŻNE — gdzie zwracasz premortem:

Twój **jedyny deliverable** to plik markdown pod ścieżką:
**${OUT}**

Zapisz finalny raport premortem wprost do tego pliku, używając
swojego write tool. Plik ma zawierać:
- WYŁĄCZNIE ustrukturyzowany markdown wg formatu w prompcie premortem,
- BEZ preambuły typu "OK, zaczynam premortem...",
- BEZ podsumowania "Skończyłem analizę",
- BEZ powtarzania raportu na stdout (stdout idzie tylko do
  loga debugowego, nie do usera).

Pierwsza linia pliku ma być nagłówkiem `## Premortem ...`.

Stdout nie idzie do usera, więc nie tracz energii na ładne
formatowanie tam. Tylko `write` na plik ${OUT}.
```

## Specyficzne dla narzędzia

- **codex** (`codex exec`): dyrektywa wystarcza. Codex ma write tool jako built-in.
- **opencode**: dodaj **dopisek o ograniczonych permissions**. Premortem-opencode jest agresywnie restrictive (`read/glob/grep/bash` wszystkie deny) — opencode dostaje tylko prompt i może pisać do `/tmp/premortem-*`. Wstawiaj inline w `premortem-opencode/SKILL.md`.
- **claude subagent** (przez `Agent` tool, `general-purpose`): subagent ma `Write` tool z domyślnej allowlisty. Dyrektywa wystarcza, subagent zapisze do pliku zamiast zwracać tekst. **Pamiętaj: main agent musi przed-podstawić aktualną wartość `${OUT}` w prompt string** zanim wywoła `Agent` — subagent nie wykrywa zmiennej sam.
