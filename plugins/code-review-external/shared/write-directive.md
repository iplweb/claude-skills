# Dyrektywa zapisu (artifact-file pattern)

Wspólna instrukcja "zapisz finalne review do pliku przez write tool" dla wszystkich trzech narzędzi (codex, opencode, claude subagent). Każdy leaf wstawia poniższy blok jako `<DYREKTYWA ZAPISU>` w prompcie do swojego CLI / subagenta. Edytuj raz; leafy go referują.

**Cel:** narzędzie pisze czyste markdown review wprost do `${OUT}` przez swój write tool, zamiast wyrzucać je na stdout (gdzie tonęłoby w bannerach, reasoning steps, exec logach). Wrapper czyta tylko `${OUT}` i dostaje 1-3 KB czystego markdownu zamiast 50 KB szumu.

## Treść do wklejenia (1:1)

```
WAŻNE — gdzie zwracasz review:

Twój **jedyny deliverable** to plik markdown pod ścieżką:
**${OUT}**

Zapisz finalne review wprost do tego pliku, używając swojego
write tool. Plik ma zawierać:
- WYŁĄCZNIE ustrukturyzowany markdown wg formatu w prompcie review,
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

## Specyficzne dla narzędzia

- **codex**: dyrektywa wystarcza. Codex ma write tool jako built-in, użyje go.
- **opencode**: dodaj **doprawce o ograniczonych permissions** (read all, edit tylko `/tmp/code-review-*`, bash zawężony do read-only). Wstawiaj inline w `code-review-opencode/SKILL.md`, nie w shared — jest specyficzne dla opencode setupu.
- **claude (subagent przez `Agent` tool)**: subagent dispatchowany z `general-purpose` ma `Write` tool. Dyrektywa wystarcza, subagent zapisze do pliku zamiast zwracać tekst.
