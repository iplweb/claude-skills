# Auto-detekcja celu review (5 trybów)

Wspólna logika wykrywania trybu z argumentu usera. Używana przez wszystkie 4 skille pluginu — `code-review-codex`, `code-review-opencode`, `code-review-claude`, `code-review-external`. Edytuj ten plik raz; leafy go referują.

## Tryby (pierwszy match wygrywa)

Argument przychodzi w wiadomości usera po nazwie skilla. Wykryj typ **w tej kolejności**:

1. **Brak argumentu** → `uncommitted` (staged + unstaged + untracked).
2. **`test -f "$ARG"`** zwraca true → `file`.
3. **`test -d "$ARG"`** zwraca true → `dir`.
4. **`git rev-parse --verify "$ARG^{commit}"`** zwraca 0 → `commit` (działa dla SHA, `HEAD`, `HEAD~3`, nazw branchy, tagów).
5. **W przeciwnym razie → `free`** (free-form hint). Argument jest wolnym tekstem od usera (np. "całe repo", "audyt security w `src/auth/`", "sprawdź czy nowe API jest backward compatible") — przekazujemy go jako wskazówkę do narzędzia, ono samo decyduje co zreviewować.

## Bash one-liner

```bash
ARG="..."  # to co user podał
if [ -z "$ARG" ]; then echo "uncommitted"
elif [ -f "$ARG" ]; then echo "file"
elif [ -d "$ARG" ]; then echo "dir"
elif git rev-parse --verify "$ARG^{commit}" >/dev/null 2>&1; then echo "commit"
else echo "free"
fi
```

## Ogłaszanie wykrytego trybu

Po detekcji **zawsze ogłoś userowi co wykryłeś** jednym zdaniem, np.:

- "Tryb: `uncommitted` (review niezacommitowanych zmian)."
- "Tryb: `file`, ścieżka: `src/auth/views.py`."
- "Tryb: `dir`, ścieżka: `tests/integration/`."
- "Tryb: `commit`, SHA: `abc1234`."
- "Tryb: `free`, wskazówka: ‘…’."

Sens — jeśli user zrobił typo w ścieżce pliku i argument spadł na `free`, ma szansę przerwać zanim odpalimy CLI / dispatchujemy subagenta.

## W trybie `free`

Argument trafia do prompta narzędzia dosłownie. Narzędzie samo orientuje się jakie pliki przejrzeć, jakie diff-y wywołać. To jest tryb dla "całe repo", "audyt security", "ostatnie 3 commity z focus na perf" i podobnych pytań, które nie pasują do auto-detekcji 1-4.

Nie pre-computuj `git diff` ani listy plików — narzędzie ma w swoim sandbox-ie git/ls/find/cat i samo zdecyduje czego potrzebuje. Project root narzucamy zwykle przez `--dir "$PROJECT_ROOT"` (opencode) lub przez cwd (codex).
