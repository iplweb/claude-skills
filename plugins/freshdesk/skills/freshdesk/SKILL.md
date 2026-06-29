---
name: freshdesk
description: >-
  Przegląd wiszących zgłoszeń w Freshdesku (konto iplweb): pobiera otwarte
  zgłoszenia, sortuje wg złożonego priorytetu (SLA → termin → priorytet → wiek),
  pokazuje czytelną listę i prowadzi do działania (otwórz w panelu, pokaż
  konwersację, zmień status/priorytet, zaproponuj odpowiedź). Druga sekcja to
  pending wymagające przypomnienia lub zamknięcia. Można zawęzić parametrem do
  projektu lub osoby (np. "BPP", "PRODX", "KLIENTA-PRODX", nazwisko klienta). Użyj
  ZAWSZE, gdy user pyta o zgłoszenia, tickety, support, "co wisi", "co pilnego",
  "czym się zająć", przegląd Freshdeska albo wymienia projekt z kontekstem
  zgłoszeń. Wywołanie: /freshdesk [filtr].
---

# Freshdesk — przegląd wiszących zgłoszeń

Pomaga ustalić, **czym realnie trzeba się zająć** w Freshdesku: pobiera otwarte
zgłoszenia, układa je wg pilności, pokazuje zwięzłą listę i prowadzi do akcji.
Opcjonalny argument zawęża widok do projektu lub osoby.

Wszystkie operacje przez serwer MCP `freshdesk-mcp`. Konto: **iplweb**, panel:
`https://iplweb.freshdesk.com/a/tickets/<id>`.

## Zasada bezpieczeństwa (read-only domyślnie)

Domyślnie skill **tylko czyta**. Żadna zmiana w Freshdesku (zmiana statusu,
priorytetu, przypisania, wysłanie odpowiedzi czy notatki) **nie następuje bez
wyraźnego potwierdzenia użytkownika w danym kroku**. Najpierw pokaż, co
zamierzasz wysłać/zmienić, dopiero po „tak" wywołaj narzędzie zapisujące.

## Słownik kodów Freshdesk (potrzebny do interpretacji danych)

Te liczby zwraca API i trzeba je tłumaczyć na ludzki język:

- **status**: `2` = Open, `3` = Pending, `4` = Resolved, `5` = Closed.
  Skill zajmuje się **tylko `2` i `3`**. Resolved/Closed ignoruj.
- **priority**: `1` = Low, `2` = Medium, `3` = High, `4` = Urgent.
  Uwaga: na tym koncie prawie wszystko ma `1` (Low) — dlatego samo to pole
  słabo różnicuje i potrzebny jest scoring złożony (niżej).
- **source** (informacyjnie): `1` = email, `2` = portal, `3` = telefon,
  `9` = feedback/widget. Nie wpływa na priorytet.
- **terminy SLA**: `fr_due_by` = termin pierwszej odpowiedzi,
  `due_by` = termin rozwiązania. To **główny realny sygnał pilności** tutaj.
- **responder_id**: agent przypisany (zwykle `null` — jest jeden agent, Ty).
- **requester_id**: kontakt zgłaszającego (trzeba rozwinąć przez `get_contact`
  lub `search_contacts`, jeśli potrzebna nazwa/e-mail).
- **cf_adres_url** (`custom_fields.cf_adres_url`): URL klienta, np.
  `bpp.klientc.example.org`, `bpp.klienta.example.org`, `publikacje.klientb.example.org`. Domena
  zdradza instytucję — używana w filtrze projektu.

## Jak rozpoznawany jest projekt/osoba (na tym koncie)

Projekt **nie jest osobnym polem**. Kryje się w:
- **temacie** zgłoszenia: prefiksy/słowa `[BPP]`, `BPP —`, `[PRODX]`,
  `PRODX ...`, `!!! PRODX`,
- **`cf_adres_url`**: domena instytucji.

Osoba = **zgłaszający** (`requester_id` → kontakt). Agentem jesteś tylko Ty,
więc „osoba" nigdy nie oznacza tu przypisanego agenta.

## Procedura

### Krok 0 — odczytaj argument

`/freshdesk [filtr]`. Argument jest opcjonalny i traktowany jako **jeden
uniwersalny filtr tekstowy**, bez trybu „osoba vs projekt":

- Rozbij argument na **tokeny** po znakach niealfanumerycznych
  (`KLIENTA-PRODX` → `["KLIENTA", "PRODX"]`).
- Zgłoszenie pasuje, gdy **każdy token** występuje (case-insensitive) w
  połączonym „sianie" = `temat` + `cf_adres_url` + nazwa/e-mail zgłaszającego.
  - `BPP` → łapie `[BPP]`, `BPP —`, domenę `bpp.*`.
  - `KLIENTA-PRODX` → wymaga `PRODX` (temat) i `KLIENTA` (np. URL `bpp.klienta.example.org`).
  - nazwisko → najpierw `search_contacts(query="nazwisko")`, zbierz `id`
    kontaktów, dopasuj po `requester_id` (i tak po sianie tematu/URL).
- Brak argumentu → bez filtra (wszystko otwarte/pending).

Dopasowanie po nazwie zgłaszającego wymaga rozwinięcia kontaktów. Żeby nie
rozwijać wszystkich: jeśli argument **nie** trafia w żaden temat/URL, potraktuj
go jako możliwe nazwisko i spróbuj `search_contacts`. Jeśli trafia w tematy —
nie musisz rozwijać kontaktów do samego filtrowania (rozwiniesz lazy w
szczegółach).

### Krok 1 — pobierz zgłoszenia

Pobierz **osobno** open i pending (sekcje mają różną logikę):

- Open: `search_tickets(query="\"status:2\"")`
- Pending: `search_tickets(query="\"status:3\"")`

**Uwaga o składni (zweryfikowane na żywo):** wartość `query` musi być
**owinięta w cudzysłowy** — przekazuje się literalnie `"status:2"` (z
cudzysłowami), inaczej API zwraca „Given query is invalid". Składnia filtra
Freshdesk obsługuje pola `status`, `priority`, `tag`, `due_by`, `fr_due_by`,
`cf_*` itd., łączone operatorami `AND`/`OR` (spacja wokół operatora obowiązkowa).

**Uwaga o rozmiarze odpowiedzi (zweryfikowane na żywo):** open potrafi zwrócić
duży JSON, który harness **zapisuje do pliku** zamiast wstawić do kontekstu
(komunikat „exceeds maximum allowed tokens … saved to …"). Wtedy **nie czytaj
całego pliku** — wyciągnij tylko potrzebne pola przez `jq`:

```bash
jq -c '.result.results[] | {id, subject, pr:.priority, st:.status,
  created:.created_at, due:.due_by, fr:.fr_due_by,
  resp:.responder_id, req:.requester_id, url:.custom_fields.cf_adres_url}' <plik>
jq '.result.total' <plik>   # ile faktycznie pasuje
```

**Uwaga o paginacji (ważne ograniczenie):** ten MCP **nie udostępnia `page`**
dla `search_tickets`, więc dostajesz tylko **pierwszą stronę (~30 najnowszych)**.
Porównaj liczbę zwróconych z `total`:

- jeśli `zwrócone ≥ total` → masz komplet,
- jeśli `total > zwrócone` → **zeskanowałeś tylko najnowsze ~30**. Przy filtrze
  na konkretny projekt/osobę to zwykle wystarcza (sprawy są świeże), ale
  **powiedz to wprost w nagłówku** (np. „skan: 30 najnowszych z N open"). Gdy
  potrzebne pełne pokrycie (brak filtra albo stare sprawy) — **fallback**:
  `get_tickets(page=1,2,…)` (zwraca wszystkie statusy, malejąco po `id`) i
  odfiltruj `status` po stronie klienta, aż zbierzesz dość / zejdziesz poniżej
  interesującego zakresu dat.

Następnie zastosuj filtr z Kroku 0.

### Krok 2 — policz scoring (sekcja OPEN)

Sortowanie ma odzwierciedlać realną pilność, a nie samo pole `priority`.
Policz dla każdego open zgłoszenia **score** (wyżej = pilniejsze) wg poniższej
hierarchii. Liczby to wagi pomocnicze do porządkowania i remisów — stosuj je
z głową, nie mechanicznie:

| Czynnik | Warunek | Waga |
|---|---|---|
| SLA pierwszej odpowiedzi przekroczone | `fr_due_by` < teraz i brak odpowiedzi agenta | **+100** |
| SLA rozwiązania przekroczone | `due_by` < teraz | **+80** |
| Termin bardzo blisko | dowolne SLA w ciągu 24 h | +40 |
| Termin blisko | dowolne SLA w ciągu 48 h | +20 |
| Klient właśnie odpisał (piłka po Twojej stronie) | ostatnia wiadomość od zgłaszającego | +25 |
| Priorytet | Urgent +30 · High +20 · Medium +10 · Low +0 | wg pola |
| Wiek | +1 za każdy dzień od `created_at`, maks. +30 | do +30 |

„Teraz" = aktualna data/godzina (z kontekstu sesji). Wykrycie „klient właśnie
odpisał" wymaga konwersacji — dla listy open **nie** dociągaj jej masowo; status
Open sam w sobie znaczy zwykle „po Twojej stronie". Sygnał `+25` stosuj, gdy i
tak otwierasz konwersację, albo gdy temat wskazuje świeżą odpowiedź. Nie blokuj
listy na masowym pobieraniu konwersacji.

Posortuj malejąco po score. Przy remisie — starsze wyżej.

### Krok 3 — sekcja PENDING (follow-up / przypominajki)

Pending na tym koncie zwykle znaczy „już odpisałem, czekam na klienta". Dla
każdego pending ustal stan na podstawie wieku (`updated_at`) i — dla pending
jest ich zwykle mało — **konwersacji** (`get_ticket_conversation`), by poznać
kierunek ostatniej wiadomości:

- **📨 Klient odpisał, czeka na Ciebie** — ostatnia wiadomość od zgłaszającego.
  To realnie „po Twojej stronie" → **przenieś do sekcji OPEN** (z odpowiednim
  score), nie trzymaj w pending.
- **🔔 Przypominajka należna** — bez ruchu > ~5 dni i nie wysłano jeszcze
  przypomnienia → zaproponuj wysłanie nudge'a do klienta.
- **🗑 Kandydat do zamknięcia** — przypomnienie już było, dalej cisza
  > ~10 dni od ostatniego ruchu → zaproponuj zamknięcie (status Closed).
- W przeciwnym razie: po prostu „czeka, świeże" — pokaż, nic nie sugeruj.

Progi `5` i `10` dni to rozsądne domyślne — jeśli user chce inne, dostosuj w
locie. „Czy wysłano już przypomnienie" rozpoznasz po Twoich wcześniejszych
odpowiedziach/notatkach w konwersacji (np. krótka prośba o potwierdzenie).

### Krok 4 — pokaż listę

Najpierw **nagłówek-podsumowanie**, np.:

```
Freshdesk — przegląd [filtr: BPP]   (stan: 2026-06-20 14:10)
🔴 7 open (2 po SLA) · 🟡 5 pending (1 do przypomnienia, 2 do zamknięcia)
```

Potem **sekcja A (OPEN)** — posortowana score'em, jako **tabela Markdown**.
Kolumnę `id` renderuj jako **klikalny link** do panelu, żeby dało się wejść w
zgłoszenie wprost z listy:

```
| # | id | flagi | temat | wiek | SLA |
|---|----|-------|-------|------|-----|
| 1 | [#376](https://iplweb.freshdesk.com/a/tickets/376) | ⏰SLA 📨klient | Fwd: ODP: funkcjonalności BPP – uwaga | 4 dni | fr po terminie |
| 2 | [#385](https://iplweb.freshdesk.com/a/tickets/385) | 🔴Urgent | [BPP] Rozdział: brak wymuszenia wydawcy | 1 dz. | rozw. za 6 dni |
```

Wzór linku: `[#<id>](https://iplweb.freshdesk.com/a/tickets/<id>)`.
Flagi (dobierz pasujące): `⏰SLA` (po terminie), `⌛<24h` / `⌛<48h` (blisko),
`🔴Urgent`/`🟠High`/`🟡Medium`, `📨klient` (czeka na Ciebie), `🕸stare`. Temat
skróć do ~60 znaków. Wiek licz od `created_at`. `id` zawsze jako link — to klucz
do akcji i zarazem gotowe „otwórz w przeglądarce".

Potem **sekcja B (PENDING)** — pogrupowana wg stanu (🔔 do przypomnienia,
🗑 do zamknięcia, reszta zwinięta lub pominięta), z `id` (też jako link
`[#<id>](…/a/tickets/<id>)`) i wiekiem od `updated_at`.

Jeśli po filtrze nic nie ma — powiedz to wprost (np. „Brak otwartych zgłoszeń
dla filtra »KLIENTA-PRODX«").

### Krok 5 — „co dalej"

Po liście zapytaj, co zrobić. Użytkownik wskazuje **numer lub `id`** + akcję.
Dostępne akcje:

1. **Otwórz w przeglądarce** — link jest już na liście przy `id`
   (`https://iplweb.freshdesk.com/a/tickets/<id>`); w razie potrzeby podaj go
   ponownie wprost.
2. **Szczegóły / konwersacja** — `get_ticket(ticket_id)` +
   `get_ticket_conversation(ticket_id)`; streść wątek (kto, o co chodzi, ostatni
   ruch, czego oczekuje klient). Rozwiń zgłaszającego przez `get_contact`, jeśli
   przydatne.
3. **Zmień status / priorytet / przypisz** — `update_ticket`. **Najpierw pokaż,
   co zmienisz** (np. „status → Pending, priority → High"), wykonaj po „tak".
4. **Zaproponuj odpowiedź / notatkę** — zredaguj treść i **pokaż ją do
   akceptacji**. Dopiero po „tak":
   - odpowiedź do klienta → `create_ticket_reply`,
   - notatka wewnętrzna → `create_ticket_note` (parametr private).
   Przy „przypominajce" z sekcji B użyj tej samej ścieżki (krótki, uprzejmy
   nudge), a przy „kandydacie do zamknięcia" — zaproponuj `update_ticket`
   status → Closed (po potwierdzeniu).

Po akcji zaproponuj powrót do listy (kolejne zgłoszenie) — typowo przerabia się
ich kilka z rzędu.

## Wydajność i kruchość — o czym pamiętać

- **Nie dociągaj konwersacji masowo.** Pełna treść/wątek tylko dla pending
  (mało ich) oraz na żądanie w „szczegółach". Lista open opiera się na tanich
  polach (status, SLA, priorytet, wiek).
- **Rozwijanie kontaktów lazy.** Nazwę zgłaszającego pobieraj tylko, gdy jest
  potrzebna (filtr po osobie, widok szczegółów), nie dla całej listy.
- **Daty.** Zawsze licz względem aktualnego czasu sesji, nie zaszywaj dat.
- **Fallback wyszukiwania.** Gdy `search_tickets` zawiedzie — `get_tickets`
  + filtr po stronie klienta.
- **Znane ograniczenie MCP:** `get_ticket_fields` bywa zepsute (zwraca listę
  zamiast słownika i rzuca błędem walidacji) — nie polegaj na nim; kody
  statusów/priorytetów masz w słowniku wyżej.

## Automatyzacja (opcjonalnie)

Sam skill jest uruchamiany ręcznie. Jeśli chcesz cyklicznego przeglądu (np.
„pending do przypomnienia" co rano), sparuj go z `/schedule` (cloud-cron) lub
`/loop` — to jest poza skillem, ale skill świadomie produkuje sekcję B właśnie
pod taki nawyk.
