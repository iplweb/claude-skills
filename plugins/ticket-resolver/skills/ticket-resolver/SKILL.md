---
name: ticket-resolver
description: >-
  Obsługa POJEDYNCZEGO zgłoszenia end-to-end: pobiera jedno zgłoszenie z
  Freshdeska (konto iplweb) LUB z GitHub Issues (repo iplweb/bpp) po numerze,
  osobie albo pilności, analizuje je i klasyfikuje — czy wymaga WYJAŚNIENIA
  (klient nie wie jak coś działa) czy NAPRAWY (realny bug). Dla wyjaśnienia
  redaguje odpowiedź jako DRAFT do akceptacji (prywatna notatka w FD + link).
  Dla naprawy zakłada gałąź z numerem zgłoszenia (np. fix-fd344-...) ORAZ
  worktree, pisze repro-test (TDD), naprawia i otwiera PR z odniesieniem do
  zgłoszenia, plus newsfragment towncriera. Po wystawieniu PR dopisuje do FD
  prywatną notatkę z lokalizacją gałęzi, a gdy gałąź zostaje zmergowana —
  notatkę zwrotną „zmergowano wtedy i wtedy" (tryb /ticket-resolver merged
  <fdNNN|PR#|gałąź>). Użyj ZAWSZE, gdy user mówi „obsłuż zgłoszenie", „napraw
  ticket", „weź to zgłoszenie", „przeanalizuj i napraw FD344 / #123", „ta
  poprawka poszła do maina / zmergowana", podaje numer zgłoszenia z intencją
  działania, albo prosi o draft odpowiedzi / poprawkę pod konkretne zgłoszenie.
  Wywołanie: /ticket-resolver <numer | osoba | pilność> albo /ticket-resolver merged
  <ref>. To NIE jest przegląd wielu zgłoszeń — do listy „co wisi" użyj
  /freshdesk.
---

# Zgłoszenie — analiza i autonaprawa pojedynczego zgłoszenia

Bierze **jedno** zgłoszenie i prowadzi je do końca: analiza → klasyfikacja →
albo **draft wyjaśnienia** do klienta, albo **pełna naprawa** (gałąź + worktree
+ repro-test + fix + newsfragment + PR). Odróżnij od `/freshdesk`, który jest
**przeglądem wielu** wiszących zgłoszeń — tu pracujemy nad konkretnym.

Źródła:
- **Freshdesk** — MCP `freshdesk-mcp`, konto **iplweb**, panel:
  `https://iplweb.freshdesk.com/a/tickets/<id>`.
- **GitHub Issues** — repo **`iplweb/bpp`**, przez `gh` CLI.

## Zasada bezpieczeństwa (jak /freshdesk)

Granica jest **klient vs reszta**:

- **Wobec klienta — zawsze za „tak":** odpowiedź do klienta (FD reply, komentarz
  na GH issue) i zmiana statusu ticketu. Nic z tego nie wychodzi bez wyraźnego
  potwierdzenia treści.
- **Na ścieżce kodu — jedna bramka (po triażu):** po „tak" przy klasyfikacji
  skill działa autonomicznie aż do **otwartego PR** — w tym worktree, fix, push
  i `gh pr create`. PR to artefakt do review (nie merge), a push idzie na własną
  gałąź `fix-…`, więc nie wymaga osobnego potwierdzenia. Wyjątki bezpieczeństwa
  (np. fix wymagałby migracji) zatrzymują bieg i pytają — patrz niżej.

Prywatna notatka w FD (ślad wewnętrzny, niewidoczny dla klienta) też nie wymaga
bramki.

## Słownik kodów Freshdesk (do interpretacji danych)

- **status**: `2` = Open, `3` = Pending, `4` = Resolved, `5` = Closed.
- **priority**: `1` = Low, `2` = Medium, `3` = High, `4` = Urgent (na tym koncie
  prawie wszystko ma `1` — patrz scoring w `/freshdesk`).
- **terminy SLA**: `fr_due_by` = pierwsza odpowiedź, `due_by` = rozwiązanie.
- **requester_id** → kontakt zgłaszającego (`get_contact` / `search_contacts`).
- **cf_adres_url** (`custom_fields.cf_adres_url`): URL klienta (np.
  `bpp.klienta.example.org`) — zdradza instytucję. **Zapamiętaj go** — przyszły skill #2
  użyje go do sprawdzenia, czy fix jest już wgrany u tego klienta.

---

## Krok 0 — rozpoznaj źródło i pobierz zgłoszenie

Sparsuj argument `/ticket-resolver <arg>`:

- `fdNNN`, `FD#NNN`, `fd NNN`, „freshdesk NNN" → **Freshdesk**:
  `get_ticket(ticket_id=NNN)` + `get_ticket_conversation(ticket_id=NNN)`.
  Rozwiń zgłaszającego (`get_contact`) gdy potrzebna nazwa/instytucja.
- `#NNN`, `gh NNN`, „issue NNN", „github NNN" → **GitHub**:
  `gh issue view NNN --repo iplweb/bpp --comments`.
- **goła liczba bez kontekstu** (`/ticket-resolver 344`) → **dopytaj**: „FD#344 czy
  GitHub issue #344?". Nie zgaduj — numeracje się nakładają.
- **osoba / pilność / projekt** (`/ticket-resolver KLIENTB`, `/ticket-resolver pilne`,
  `/ticket-resolver BPP`) → użyj logiki `/freshdesk` (scoring SLA→termin→priorytet→
  wiek; filtr po temacie + `cf_adres_url` + nazwie zgłaszającego), pokaż
  **krótką listę kandydatów** (max ~8, jako tabela z linkami) i poproś o wybór
  **jednego**. Po wyborze wróć do tego kroku z konkretnym id.

Zbierz do analizy: temat, treść pierwszej wiadomości, całą konwersację,
instytucję/`cf_adres_url`, datę, status. To materiał dla triażu.

---

## Krok 1 — TRIAGE (klasyfikacja) — **BRAMKA**

Przeczytaj zgłoszenie i konwersację. Sklasyfikuj do jednej z trzech kategorii:

- **WYJAŚNIENIE** — system działa zgodnie z projektem; klient nie wie, jak coś
  działa, pyta o sposób użycia, myli funkcję z błędem. Sygnały: „jak zrobić…",
  „czy da się…", „nie widzę opcji…", a zachowanie jest poprawne.
- **NAPRAWA** — realny defekt: błąd 500, traceback, złe dane, regresja, krzyk
  „nie działa" z konkretnym, odtwarzalnym objawem. Sygnały: stacktrace, „było
  dobrze, teraz źle", liczby się nie zgadzają, eksport pusty itd.
- **NIEJASNE** — za mało informacji, by rozstrzygnąć. Wtedy zaproponuj **draft
  pytania zwrotnego** do klienta (ścieżką jak WYJAŚNIENIE) — nie wybieraj na siłę.

Jeśli zgłoszenie miesza oba (pytanie + bug) — rozdziel: nazwij obie części i
**zaproponuj kolejność** (zwykle najpierw naprawa, potem informacja zwrotna).

Pokaż użytkownikowi **werdykt + uzasadnienie** (2–4 zdania) i — dla naprawy —
**wstępną hipotezę** (gdzie w kodzie leży problem, jeśli widać). Format:

```
Triage FD#344 — [klient: bpp.klientb.example.org]
Werdykt: NAPRAWA
Powód: import BibTeX z wieloautorowym cytowaniem rzuca 500 (traceback w
  konwersacji wskazuje na parser strony). Reprodukowalne.
Hipoteza: importer_publikacji, parsowanie pól autorów / page-range.
→ Wejść w naprawę? [tak / popraw klasyfikację / pokaż więcej]
```

**Czekaj na potwierdzenie.** To jedyna bramka. Dopiero po „tak" rusza ścieżka.

---

## Podpis (stopka) w odpowiedziach do klienta — OBOWIĄZKOWY

**Każda** treść wychodząca do klienta (FD `create_ticket_reply`, komentarz na
GH issue) — oraz jej wersja w drafcie — kończy się stopką:

```
Pozdrawiamy,
Zespół <PROJEKT> — iplweb

---
Tę odpowiedź przygotował agent sztucznej inteligencji (Claude) wspierający
nasz zespół wsparcia. Jeśli coś w tej wiadomości wymaga sprostowania,
zauważą Państwo pomyłkę albo wolą Państwo porozmawiać bezpośrednio
z człowiekiem — prosimy o odpowiedź na tego maila lub kontakt z zespołem;
chętnie się tym zajmiemy.
```

`<PROJEKT>` dobierz do zgłoszenia (np. `BPP`, `PRODX`, `KLIENTA-PRODX`) na
podstawie kontekstu ticketu — `product_id`, `cf_adres_url`, temat. **Nie
wstawiaj na sztywno „BPP"** — skill obsługuje różne projekty. Gdy projektu
nie da się jednoznacznie ustalić, użyj neutralnego „Zespół wsparcia iplweb".

To świadoma transparentność: klient od razu widzi, że odpowiedź redagował
agent AI, i wie, jak trafić do człowieka. Nie wysyłaj odpowiedzi bez tej
stopki. Reguła dotyczy WYŁĄCZNIE komunikacji do klienta — prywatne notatki
wewnętrzne (`create_ticket_note`) i opisy PR-ów stopki nie wymagają.

---

## Formatowanie odpowiedzi do klienta — HTML (Freshdesk) / Markdown (GitHub)

**Freshdesk renderuje treść jako HTML** — gołe `\n` i myślniki `- ` zlewają
się w jedną ścianę tekstu (FD opakowuje body w `<div>`, ale nie zamienia
znaków nowej linii na `<br>`). Dlatego **odpowiedzi do klienta na FD pisz
poprawnym HTML-em**, a nie plain-textem:

- akapity w `<p>…</p>` (nie puste linie),
- listy w `<ul><li>…</li></ul>` (nie `- ` ani `•`),
- wyróżnienia `<strong>…</strong>`, linki `<a href="…">…</a>`,
- separator stopki przez `<hr>`, a disclaimer w osobnym `<p>`.

Stopka/podpis z sekcji wyżej jest częścią tego HTML-a (np. `<p>Pozdrawiamy,<br>
Zespół …</p><hr><p style="font-size:smaller;color:#666">Tę odpowiedź…</p>`).

**GitHub Issues** renderują **Markdown** — tam pisz Markdownem (nagłówki,
listy `-`, **bold**), NIE HTML-em.

**Prywatne notatki wewnętrzne (`create_ticket_note`) też renderują HTML** —
formatuj je HTML-em, gdy zyskują na czytelności, zwłaszcza notatki-ślady
(„gdzie naprawione") z listą PR-ów i linkami. Przykład notatki HTML:

```html
<p><strong>[fix · zmergowano]</strong> FD#NNN — krótki opis.</p>
<ul>
  <li>PR <a href="https://github.com/iplweb/bpp/pull/NN">#NN</a> — co zrobił;
      squash do <code>dev</code>: <code>&lt;sha&gt;</code>.</li>
</ul>
<p>Wejdzie w wydaniu &gt; v&lt;bieżąca&gt;.</p>
```

Marker statusu (`[fix · PR wystawiony]`, `[fix · zmergowano]`) zostaw jako
zwykły tekst w `<strong>`, żeby dało się go znaleźć grepem w konwersacji.

---

## Krok 2a — ścieżka WYJAŚNIENIE (draft, nic do klienta bez „tak")

1. Zredaguj odpowiedź **po polsku**, uprzejmym, konkretnym tonem (jak w
   `/freshdesk`). Tłumacz **jak to działa**, podaj kroki / gdzie kliknąć,
   ewentualnie link do odpowiedniej części UI. Bez żargonu deweloperskiego.
2. **Zapisz jako DRAFT — nie wysyłaj:**
   - **Freshdesk**: `create_ticket_note(ticket_id=NNN, private=true, …)` z
     treścią poprzedzoną `[DRAFT do akceptacji — nie wysłane do klienta]`.
     Prywatna notatka jest widoczna tylko dla agenta. **Notatki FD nie mają
     własnego, samodzielnego URL-a** — żyją w konwersacji ticketu, więc do
     podglądu zawsze linkuj sam ticket (ewentualnie podaj `note id` z odpowiedzi
     API do referencji): `https://iplweb.freshdesk.com/a/tickets/NNN`.
   - **GitHub**: zapisz draft do pliku `drafts/gh-NNN-reply.md` (w katalogu
     roboczym; jeśli go nie ma — utwórz, jest ulotny/roboczy) i pokaż ścieżkę
     **oraz** wariant `file://` (reguła z CLAUDE.md), plus URL issue.
3. Pokaż treść draftu w odpowiedzi i zapytaj: „Wysłać do klienta tak jak jest,
   poprawić, czy zostawić jako draft?".
4. **Dopiero po „tak"** wyślij realnie:
   - FD: `create_ticket_reply(ticket_id=NNN, …)`,
   - GH: `gh issue comment NNN --repo iplweb/bpp --body-file drafts/gh-NNN-reply.md`.
   Status FD zwykle zostaje bez zmian (chyba że user poprosi o Pending/Closed —
   wtedy `update_ticket` po potwierdzeniu).

---

## Krok 2b — ścieżka NAPRAWA (po bramce — autonomicznie aż do PR)

Wszystkie polecenia Pythona przez **`uv run`**. Reużyj skilli:
`superpowers:systematic-debugging`, `superpowers:test-driven-development`,
`superpowers:using-git-worktrees` — orkiestruj je, nie wymyślaj od nowa.

### 2b.1 — slug i gałąź

Ustal **krótki slug** (kebab-case, ~2–5 słów, ASCII) z istoty buga, np.
`bibtex-import-500`. Złóż identyfikator zgłoszenia:
- FD → `fdNNN` (np. `fd344`),
- GH → `NNN` (czysty numer; w treści PR użyjesz `#NNN`).

Nazwa gałęzi: **`fix-<id>-<slug>`** → `fix-fd344-bibtex-import-500`.
Numer zgłoszenia w nazwie gałęzi jest **obowiązkowy**.

### 2b.2 — worktree (TWARDA reguła z CLAUDE.md)

Worktree **NIGDY** w repo ani w `.claude/worktrees/`. Zawsze jako siostrzany
katalog w `~/Programowanie/`:

```bash
git worktree add ~/Programowanie/bpp-fix-fd344-bibtex-import-500 \
    -b fix-fd344-bibtex-import-500
```

Następnie wejdź w już-istniejący worktree (`EnterWorktree path=~/Programowanie/
bpp-fix-fd344-bibtex-import-500`, albo pracuj z tej ścieżki). Twórz gałąź z
aktualnego `dev` (lub bieżącego maina repo).

### 2b.3 — repro-test NAJPIERW (TDD + systematic-debugging)

Zanim cokolwiek naprawisz: napisz **test odtwarzający błąd** i potwierdź, że
**pada** (czerwony). Wzorzec w repo: pliki `test_repro_<NNN>.py` w katalogu
`tests/` odpowiedniej aplikacji (np. `src/importer_publikacji/tests/`). Nazwij
test referencją do zgłoszenia, np. `test_repro_fd344.py` / `test_repro_344.py`.
Konwencje testów z CLAUDE.md: pytest (bez klas), `@pytest.mark.django_db`,
`model_bakery.baker.make`.

```bash
uv run pytest src/<app>/tests/test_repro_<id>.py  # ma PAŚĆ (czerwony)
```

Jeśli nie umiesz odtworzyć — **nie zgaduj fixu**. Wróć do użytkownika z tym, co
ustaliłeś, i poproś o brakujące dane (wersja, dane wejściowe, kroki). To zgodne
z `systematic-debugging`: najpierw rzetelna reprodukcja, potem naprawa.

### 2b.4 — naprawa

Napraw przyczynę (nie objaw). Po fixie test repro **przechodzi** (zielony),
a istniejące testy dotkniętej aplikacji nadal przechodzą:

```bash
uv run pytest src/<app>/tests/test_repro_<id>.py   # zielony
uv run pytest src/<app>/                            # bez regresji
```

Trzymaj minimalny, czytelny diff. Max 88 znaków/linia. Jeśli fix **wymagałby
migracji** — **zatrzymaj się i zapytaj** (osobna, ostrożna operacja; pamiętaj o
zakazie modyfikacji istniejących migracji i o `make baseline-update` przy
scalaniu). Większość bugfixów obejdzie się bez migracji.

### 2b.5 — newsfragment (towncrier)

Towncrier jest skonfigurowany (`[tool.towncrier]`, `package_dir = "src"`,
fragmenty w `src/bpp/newsfragments/`, typy: `bugfix`/`feature`/`doc`/`removal`).

- **FD** (nie jest GitHub issue): użyj **orphan fragment** — nazwa zaczyna się
  od `+`, więc towncrier **nie** wygeneruje martwego linku do GH:
  `src/bpp/newsfragments/+fd344.bugfix.md`. W treści wpisz `FD#344` jawnie.
- **GH issue**: nazwa **numeryczna** → towncrier auto-linkuje do issue:
  `src/bpp/newsfragments/123.bugfix.md`.

Treść (po polsku, z perspektywy użytkownika — co teraz działa, nie jak
naprawiono). Zanotuj też ślad wersji — CalVer gwarantuje, że fix wejdzie w
wydaniu **późniejszym niż bieżące** (`> v<bieżąca>`; bieżącą odczytasz z
`src/django_bpp/version.py`, np. `202606.1390`). Przykład `+fd344.bugfix.md`:

```markdown
Import BibTeX z wieloautorowym cytowaniem nie kończy się już błędem 500 —
parser poprawnie rozdziela autorów i zakres stron (FD#344).
```

### 2b.6 — ślad FORWARD w Freshdesku (notatka „gdzie naprawione")

**Obowiązkowo:** gdy dla zgłoszenia **FD** wyszedł PR (krok 2b.7 zakończony),
dodaj **prywatną notatkę** (private, niewidoczna dla klienta) z **jawną
lokalizacją gałęzi**, gdzie bug jest naprawiony. To ślad forward — dla przyszłego
skilla #2 oraz dla noty zwrotnej po merge (Krok 3). Każde w-miarę-naprawione
FD-zgłoszenie z PR-em **musi** taką notatkę dostać.

```
create_ticket_note(ticket_id=344, private=true, body=
  "[fix · PR wystawiony] Naprawione — gałąź: fix-fd344-bibtex-import-500
   PR: https://github.com/iplweb/bpp/pull/<N>  (status: open, do review)
   Worktree: ~/Programowanie/bpp-fix-fd344-bibtex-import-500
   Wejdzie w wydaniu > v202606.1390.
   Status u klienta (bpp.klientb.example.org) i zamknięcie — osobny krok (skill #2).")
```

Notatkę dodaj **bez bramki** (jest wewnętrzna, nie dotyka klienta). Nie zmieniaj
statusu ticketu ani nie odpisuj klientowi — to robi skill #2. Dla **GH issue**
nie trzeba notatki: `Closes #NNN` w PR sam wiąże i auto-zamknie issue po merge.

### 2b.7 — jakość, push, PR

```bash
ruff format .
ruff check .          # błędy naprawiaj RĘCZNIE (Edit), bez --fix
pre-commit            # NIGDY z argumentami; problemy fiksuj per-issue ręcznie
```

Po zielonych testach i czystym pre-commit — **push** gałęzi i **`gh pr
create`**. Tytuł i treść PR **MUSZĄ** referować zgłoszenie:

- **FD**: w tytule/treści `Fixes Freshdesk FD#344` + link panelu
  `https://iplweb.freshdesk.com/a/tickets/344`. (FD-tickety nie auto-zamykają
  się z GitHuba — to świadome; domyka skill #2.)
- **GH issue**: `Closes #123` (auto-zamknie issue po merge).

Commit message też zawiera ref (`FD#344` / `#123`). Stopki commitów/PR wg reguł
repo (Co-Authored-By dla commitów, znacznik Claude Code dla treści PR).

Po otwarciu PR pokaż użytkownikowi: link do PR, nazwę gałęzi/worktree, podsumowanie
diffu i wynik testów. **Zatrzymaj się tutaj** — merge i sprzątanie worktree to
decyzja użytkownika (lub `superpowers:finishing-a-development-branch`).

---

## Krok 3 — nota ZWROTNA po merge gałęzi („zmergowano wtedy i wtedy")

Domknięcie obiegu wewnętrznego: gdy gałąź `fix-fdNNN-…` zostaje **zmergowana**
(zwykle później, często w innej sesji), do powiązanego FD-zgłoszenia ma trafić
**druga prywatna notatka** z datą/godziną merge. To wciąż ślad wewnętrzny —
**nie** zamyka ticketu i **nie** odpisuje klientowi (to skill #2).

### Wyzwalacze

- **Jawny tryb:** `/ticket-resolver merged <fdNNN | PR# | nazwa-gałęzi>` — użytkownik
  wprost mówi „ta poprawka poszła do maina".
- **Okazjonalnie:** ilekroć skill pracuje nad FD-zgłoszeniem, które ma już
  notatkę `[fix · PR wystawiony]`, a nie ma jeszcze `[fix · zmergowano]` —
  sprawdź stan PR-a i jeśli zmergowany, dołóż notę zwrotną.

### Procedura

1. **Ustal PR/gałąź → FD.** Mapowanie po nazwie gałęzi `fix-fd(\d+)-…` albo po
   treści PR (`Fixes Freshdesk FD#NNN`). Z gołego `fdNNN` znajdź PR po gałęzi:
   `gh pr list --repo iplweb/bpp --head fix-fdNNN-… --state all --json
   number,state,mergedAt,mergeCommit,headRefName`.
2. **Sprawdź stan merge:**
   `gh pr view <PR#> --repo iplweb/bpp --json state,mergedAt,mergeCommit,headRefName,baseRefName`.
   - `state != "MERGED"` → jeszcze nie scalone; nie dodawaj noty (ewentualnie
     powiedz „PR #N nadal open/closed-bez-merge").
   - `state == "MERGED"` → weź `mergedAt` (to „wtedy i wtedy"), `baseRefName`
     (gałąź docelowa, zwykle `dev`), `mergeCommit.oid`.
3. **Dodaj notę zwrotną** (private, bez bramki — wewnętrzna):

```
create_ticket_note(ticket_id=344, private=true, body=
  "[fix · zmergowano] Gałąź fix-fd344-bibtex-import-500 scalona do dev
   dnia <mergedAt> (PR #<N>, commit <merge-sha-7>).
   Wejdzie w najbliższym wydaniu > v202606.1390.
   Wgranie u klienta i zamknięcie zgłoszenia — osobny krok (skill #2).")
```

4. **Idempotencja:** jeśli nota `[fix · zmergowano]` dla tej gałęzi już jest w
   konwersacji — nie duplikuj. Dla **GH issue** nota zwrotna jest zbędna: merge
   z `Closes #NNN` sam zamyka issue (możesz tylko potwierdzić użytkownikowi, że
   issue zamknięte).

Po zmergowaniu możesz też zaproponować sprzątnięcie worktree gałęzi
(`git worktree remove`) — ale tylko na wyraźną prośbę, bo merge ≠ wdrożenie.

---

## Czego ten skill świadomie NIE robi (to skill #2)

- Nie **zamyka** ticketów FD ani nie wysyła „naprawione, wgrane na serwer".
- Nie sprawdza, **jaką wersję BPP ma dany klient** (brak czystego endpointu —
  `/health/` nie wystawia wersji; wersja przecieka tylko do HTML jako
  `CACHE-<wersja>`, co jest kruche).
- Nie domyka pętli release → deploy → notyfikacja. Zostawia tylko **ślad
  wewnętrzny**: newsfragment (→ trafi do `HISTORY.md` przy cięciu wydania) +
  dwie prywatne notatki FD — forward `[fix · PR wystawiony]` (lokalizacja
  gałęzi) i zwrotna `[fix · zmergowano]` (data merge). Te notatki **należą do
  skilla #1** (Krok 2b.6 i Krok 3) — są wewnętrzne, nie dotykają klienta.
  Granica wobec skilla #2 to **strona klienta**: to skill #2 połączy changelog z
  narzędziem „kto ma jaką wersję", odpisze klientowi i zamknie zgłoszenie.

## Kruchość i pułapki

- **Nie zgaduj źródła** dla gołej liczby — FD i GH mają niezależną numerację.
- **Nie zgaduj fixu bez reprodukcji** — `systematic-debugging` najpierw.
- **Worktree poza repo** — twarda reguła; sprawdź, że ścieżka to
  `~/Programowanie/bpp-...`, nie cokolwiek w drzewie repo.
- **Orphan `+` w newsfragmencie FD** — bez `+` towncrier zrobi martwy link
  `…/issues/fd344`.
- **`uv run`** dla każdego Pythona; `pre-commit` bez argumentów; ruff bez
  `--fix`.
- **Migracja w fixie** → stop i zapytaj (baseline, zakaz edycji starych migracji).
- **Daty** licz względem czasu sesji, nie zaszywaj.
- **MCP FD**: `search_tickets` zwraca tylko pierwszą stronę; `get_ticket_fields`
  bywa zepsute — kody statusów masz w słowniku wyżej (szczegóły w `/freshdesk`).
