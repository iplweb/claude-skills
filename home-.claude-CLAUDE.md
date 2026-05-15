# Claude Context

## General rule
If anything is unclear to you, ask the user for clarification. 

## Error Handling

NEVER write bare `except: pass`, `except Exception: pass`, or any exception handler that silently swallows errors.
Every except block MUST either:
- Log the exception (logger.exception / logger.error with exc_info)
- Re-raise it
- Raise a different exception
- Return a meaningful error response

If there is a legitimate reason to suppress a specific exception, use a narrow exception type and add a comment explaining WHY:
```python
# OK only with justification:
try:
    os.remove(tmp_file)
except FileNotFoundError:
    pass  # File already cleaned up, not an error
```

This rule applies to all languages, not just Python. No silent error swallowing.

## Git worktrees

Worktrees twórz **wyłącznie poza** drzewem roboczym repozytorium — nigdy
w `./.worktrees/` ani innym podkatalogu repo. Domyślna lokalizacja:
`~/Programowanie/<repo>-worktrees/<nazwa>` (albo `~/Programowanie/<nazwa>`
jeśli to jasne że to worktree konkretnego projektu).

**Why:** worktree wewnątrz drzewa roboczego psuje narzędzia, które mają
własny `conftest.py` / `pyproject.toml` / `.git` / pliki źródłowe i są
łapane jako część głównego repo:
- pytest — kolekcja wywala się na zagnieżdżonym `conftest.py`
  ("Defining 'pytest_plugins' in a non-top-level conftest is no longer
  supported")
- ripgrep / grep — duplikaty wyników, podwójne indeksowanie
- ruff / pre-commit `--all-files` — formatuje pliki z cudzego brancha
- IDE / LSP — indeksuje dwa razy, konflikty symboli
- buildy frontendu (grunt / make assets) — generują artefakty dla
  worktree zamiast głównego drzewa

**How to apply:**
- Tworząc worktree: `git worktree add ~/Programowanie/<repo>-worktrees/<nazwa> <branch>`
- Jeśli natrafisz na istniejący worktree wewnątrz repo:
  zaproponuj `git worktree move` poza repo — **nie kasuj**, może mieć
  niezacommitowaną pracę.
- Dotyczy też mechanizmów które same tworzą worktree (np. agenci
  z `isolation: "worktree"`, skille `superpowers:using-git-worktrees`,
  `EnterWorktree`) — jawnie kieruj je pod `~/Programowanie/<repo>-worktrees/`.
