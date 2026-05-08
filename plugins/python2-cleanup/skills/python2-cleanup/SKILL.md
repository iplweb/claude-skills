---
name: python2-cleanup
description: Use when a Python codebase has been nominally migrated to Python 3 but still contains Python 2 compatibility cruft — `from __future__` imports, the `six` library, `unicode()`/`basestring`/`xrange`/`long`, `python_2_unicode_compatible` decorator, `iteritems`/`iterkeys`/`itervalues`, `dict.has_key()`, `u'..'` string prefixes, custom `s2u`/`u2s`/`to_text` helpers, `__metaclass__`, `cStringIO`/`urllib2`/`ConfigParser`/`Queue` stdlib names, `__nonzero__`/`__div__`/`__cmp__` dunders. Cleanup is category-by-category, one commit per category, with grep-first detection, user confirmation, and tests run after every change.
---

# Python 2 Cleanup

## Overview

Hunts down and removes Python 2 compatibility cruft from a codebase that already runs on Python 3. Each category has a detection grep, a confirmation step, and a targeted edit. **One commit per category. Tests run after each.**

This skill modifies source code — unlike `python-upgrade-package` (which only touches tooling). The complement, not a replacement: run `python-upgrade-package` first to modernize packaging and CI; then run this skill to clean up the source.

## When to Use

- Project's `requires-python` is `>=3.x` (no Py2 in scope) but the source still imports `six`, calls `unicode()`, or has `from __future__ import ...`
- Audit before dropping the `six` dependency from `pyproject.toml`
- After a 2to3-style migration where the runtime now passes but the cruft remains
- When `ruff` rule `UP` (pyupgrade) flags many violations and you want to fix them deliberately, category by category, instead of a giant auto-fix

**Not for:**
- Projects that still need to support Python 2 (you do not — confirm before starting)
- Initial 2 → 3 syntax migration (`print` statement, `except Exception, e:` syntax). Use `2to3` or `python-modernize` first; this skill assumes Py3 already runs
- General style cleanup unrelated to Py2 cruft (use ruff for that)
- Speculative "it might still work on Py2" code in libraries — if `requires-python` says Py3-only, the cruft is dead weight

## Iron Law

**Touch only Py2 cruft. Never refactor surrounding code. Never reformat.** Every diff line must be explainable as "removed Py2 cruft" — never "while I was here, I also…". One category per commit.

## Pre-flight Check

Before starting:

1. **Confirm Py3-only.** Read `requires-python` in `pyproject.toml`. If it allows Py2 (`>=2.7`, no constraint, etc.), STOP and ask the user. Do not proceed unless the project is Py3-only.
2. **Confirm tests pass.** Run `uv run pytest` (or whatever the project uses). If tests are red before cleanup starts, fix them first or ask the user — you need a green baseline to detect regressions.
3. **Confirm a clean working tree.** `git status` should show no uncommitted changes. If there are, commit or stash them first — each cleanup category needs its own commit.

## Execution Model

```
For each category (in the order listed below):
  1. Detect with ripgrep — list every file/line with the cruft
  2. Show findings to the user (count by file, sample lines)
  3. Ask for confirmation via AskUserQuestion (skip / proceed / partial)
  4. Apply targeted edits — only the matched lines, no reformatting
  5. Run tests — if red, revert and investigate
  6. Commit with a category-specific message
  7. Move to next category
```

**Categories are independent — if the user skips one, continue to the next.**

---

## Category 1: `from __future__` imports

In Py3 these are all no-ops. Safe to remove globally, but **always one file at a time**, because some files may have ordering quirks (e.g., `from __future__` must be the first non-docstring statement).

### Detection

```bash
rg --type py '^from __future__ import' -n
```

Common imports (all no-ops in Py3):
- `from __future__ import absolute_import`
- `from __future__ import division`
- `from __future__ import print_function`
- `from __future__ import unicode_literals`
- `from __future__ import generator_stop` (was a no-op since 3.7)
- `from __future__ import nested_scopes`, `with_statement`, `generators`

### Procedure

1. List all `__future__` imports per file
2. Confirm with user
3. For each file: delete the line(s). If the import was the only line in its block (followed by a blank line before the next import), also delete the trailing blank line — but don't reorder anything else
4. Run tests
5. Commit:
   ```
   Remove obsolete __future__ imports

   All __future__ imports are no-ops on Python 3. Removed from <N> files.
   ```

### Edge cases

- A file's only top-level statement is `from __future__ import ...` — leave the file with just its module docstring. Don't add `pass`.
- File has `__future__` imports inside a `try/except` block (defensive Py2/Py3 compat) — STOP, flag for user. This is intentional compat code that needs more thought.
- File has `from __future__ import barry_as_FLUFL` — keep it. It's a joke (Easter egg) and harmless. Mention it to the user.

---

## Category 2: `six` library

Once `six` calls are gone, also remove `six` from `pyproject.toml` dependencies.

### Detection

```bash
rg --type py 'import six|from six' -n
rg --type py '\bsix\.' -n
```

Common patterns and their Py3 replacements:

| `six` API | Py3 replacement |
|---|---|
| `six.string_types` | `str` |
| `six.text_type` | `str` |
| `six.binary_type` | `bytes` |
| `six.integer_types` | `int` |
| `six.class_types` | `type` |
| `six.PY2` | `False` (always) — usually means the surrounding `if`/`else` block needs simplification |
| `six.PY3` | `True` (always) — same |
| `six.iteritems(d)` | `d.items()` |
| `six.iterkeys(d)` | `d.keys()` |
| `six.itervalues(d)` | `d.values()` |
| `six.viewitems(d)` | `d.items()` |
| `six.unichr(n)` | `chr(n)` |
| `six.b("...")` | `b"..."` |
| `six.u("...")` | `"..."` |
| `six.print_(...)` | `print(...)` |
| `six.next(it)` | `next(it)` |
| `six.moves.range` | `range` |
| `six.moves.urllib.parse` | `urllib.parse` |
| `six.moves.urllib.request` | `urllib.request` |
| `six.moves.queue` | `queue` |
| `six.moves.cStringIO` / `six.moves.StringIO` | `io.StringIO` (text) or `io.BytesIO` (bytes) |
| `six.moves.input` | `input` |
| `six.moves.zip` | `zip` |
| `six.moves.map` | `map` |
| `six.moves.filter` | `filter` |
| `@six.add_metaclass(Meta)` | `class Foo(Bar, metaclass=Meta):` (handle in Category 9) |
| `@six.python_2_unicode_compatible` | (handle in Category 6) |
| `six.with_metaclass(Meta, Base)` | `class Foo(Base, metaclass=Meta):` (handle in Category 9) |
| `six.raise_from(exc, cause)` | `raise exc from cause` |
| `six.reraise(tp, val, tb)` | `raise val.with_traceback(tb)` |

### Procedure

1. List every `six` reference grouped by API used
2. Confirm with user — for each API category, explain the replacement
3. **Replace API by API**, not file by file. Easier to verify each pattern.
4. Then remove `import six` / `from six import ...` lines that are no longer used (use a Python AST check or `ruff check --select F401` to detect unused imports — but ONLY on changed files, never `--all`)
5. Remove `six` from `pyproject.toml` `dependencies`
6. Run tests
7. Commit:
   ```
   Drop the six library, replace with Py3 builtins

   - Replaced six.string_types/text_type/binary_type/integer_types with str/bytes/int
   - Replaced six.iteritems/iterkeys/itervalues with dict methods
   - Replaced six.moves.* with stdlib equivalents
   - Removed six from dependencies
   ```

### Edge cases

- `if six.PY2:` / `if six.PY3:` blocks: the dead branch must be removed. Be careful — sometimes the code is structured `if six.PY2: foo() else: bar()`. Replace the whole `if/else` with just `bar()`. Show the user the before/after for each occurrence.
- `from six.moves import urllib` when the code does `urllib.request.urlopen(...)` — `urllib` in Py3 is a package, but you can keep `import urllib.request` and the access pattern works identically.
- `six.string_types` used in `isinstance(x, six.string_types)` — replace with `isinstance(x, str)`. Don't simplify to `type(x) is str` (different semantics).
- Subclassing `six.with_metaclass(...)` — see Category 9 for the careful conversion.

---

## Category 3: `unicode()` / `basestring` / `xrange` / `long` / `unichr`

### Detection

```bash
rg --type py '\bunicode\(' -n
rg --type py '\bbasestring\b' -n
rg --type py '\bxrange\b' -n
rg --type py '\blong\(' -n
rg --type py '\bunichr\(' -n
```

### Procedure

| Py2 builtin | Py3 replacement | Note |
|---|---|---|
| `unicode(x)` | `str(x)` | Identical for non-bytes inputs in Py3. **Verify** that callers aren't relying on Py2 behavior with bytes — `unicode(b"x")` was different from `str(b"x")` in Py2. |
| `unicode` (as type, e.g. `isinstance(x, unicode)`) | `str` | |
| `basestring` (as type, e.g. `isinstance(x, basestring)`) | `str` | In Py2 it covered both `str` and `unicode`; in Py3 there's no separate `unicode` type, so `str` is correct |
| `xrange(n)` | `range(n)` | `range` in Py3 is already a generator-like iterator |
| `long(x)` | `int(x)` | Py3 has unbounded ints |
| `long` (as type) | `int` | |
| `unichr(n)` | `chr(n)` | |

For each: replace the call/reference. Do NOT change surrounding code structure.

### Edge cases

- `unicode(x, encoding="utf-8")` — this was a common way to decode bytes. Replace with `x.decode("utf-8")` — but this changes semantics if `x` was already `str`. Show the user every occurrence and confirm. If unsure, keep `str(x, encoding="utf-8")` (works in Py3).
- `isinstance(x, (str, unicode))` — replace with `isinstance(x, str)`. The redundant `(str,)` tuple isn't needed.
- A custom `unicode = str` shim at module top — delete the shim and any related compat lines.

### Commit

```
Replace Py2 builtins with Py3 equivalents

- unicode() → str()
- basestring → str
- xrange → range
- long() → int(); long → int
- unichr() → chr()
```

---

## Category 4: dict `iteritems` / `iterkeys` / `itervalues` / `viewitems` / `viewkeys` / `viewvalues`

### Detection

```bash
rg --type py '\.iter(items|keys|values)\(\)' -n
rg --type py '\.view(items|keys|values)\(\)' -n
```

### Procedure

| Py2 method | Py3 replacement |
|---|---|
| `d.iteritems()` | `d.items()` |
| `d.iterkeys()` | `d.keys()` |
| `d.itervalues()` | `d.values()` |
| `d.viewitems()` | `d.items()` |
| `d.viewkeys()` | `d.keys()` |
| `d.viewvalues()` | `d.values()` |

In Py3 these all return view objects, which is the behavior `iter*`/`view*` provided in Py2. Performance is equivalent.

### Commit

```
Replace dict iter*/view* methods with Py3 equivalents

iteritems/iterkeys/itervalues and viewitems/viewkeys/viewvalues
all return views in Py3 already.
```

---

## Category 5: `dict.has_key()`

### Detection

```bash
rg --type py '\.has_key\(' -n
```

### Procedure

Replace `d.has_key(k)` with `k in d`. **Watch for line wrapping** — a long `has_key` call may have arguments on the next line, and `in` reads differently. Don't blindly substitute; review each diff.

```python
# Before
if my_dict.has_key("foo"):
    ...

# After
if "foo" in my_dict:
    ...
```

### Commit

```
Replace dict.has_key() with `in` operator

dict.has_key() was removed in Py3. The `in` operator is idiomatic and faster.
```

---

## Category 6: `python_2_unicode_compatible` (Django)

The `@python_2_unicode_compatible` decorator from Django was used to make a model's `__str__` work on both Py2 and Py3. In Py3-only code it's a no-op and should be removed.

### Detection

```bash
rg --type py 'python_2_unicode_compatible' -n
rg --type py 'from django\.utils\.encoding import .*python_2_unicode_compatible' -n
```

### Procedure

For each occurrence:
1. Remove the `@python_2_unicode_compatible` decorator line
2. Remove the import (`from django.utils.encoding import python_2_unicode_compatible`) — but only if no other symbols are imported from the same line. If it's `from django.utils.encoding import smart_str, python_2_unicode_compatible`, just remove `python_2_unicode_compatible` from the list.
3. Leave the `__str__` method completely untouched. It already works in Py3.

### Edge cases

- Some projects re-export the decorator from a `compat.py`. Find the re-export and remove it too.
- `@six.python_2_unicode_compatible` (the `six` version) — same treatment, but remove via Category 2 instead.

### Commit

```
Remove @python_2_unicode_compatible decorators

The decorator was a Py2 compat shim; in Py3-only code it's a no-op.
```

---

## Category 7: `u'..'` string prefix (optional, opt-in)

PEP 414 made `u''` a no-op in Python 3.3+. Removing the prefix is purely cosmetic.

### When to do this

Only if the user explicitly opts in. Removing `u''` prefixes touches a LOT of lines for zero functional change. Many users prefer to leave them.

### Detection

```bash
rg --type py "\bu'[^']*'|\bu\"[^\"]*\"" -n
```

### Procedure

Replace `u"..."` with `"..."` and `u'...'` with `'...'`. Watch for:
- Don't touch byte strings (`b"..."`)
- Don't touch raw strings (`r"..."`) — those don't have a `u` prefix anyway, but check
- Don't touch f-strings (no `u` prefix issue there)

### Commit

```
Remove u'...' string prefix (no-op in Py3.3+)

Cosmetic cleanup. PEP 414 made u'' a no-op.
```

---

## Category 8: Custom `s2u`/`u2s`/`to_text`/`to_bytes` helpers, `compat.py` modules

Many projects defined their own Py2/Py3 string-conversion helpers, often in a `compat.py` module:

```python
# compat.py
def s2u(s):
    if isinstance(s, bytes):
        return s.decode("utf-8")
    return s

def u2s(s):
    if isinstance(s, str):
        return s.encode("utf-8")
    return s
```

In Py3-only code, `s2u(x)` is usually equivalent to `x` (because everything is already `str`), or `x.decode("utf-8")` if `x` is bytes.

### Detection

```bash
rg --type py 'def (s2u|u2s|to_text|to_bytes|to_unicode|to_str|smart_text|force_text)' -n
rg --type py '\b(s2u|u2s|to_text|to_bytes|to_unicode)\(' -n
```

Also look for project-specific `compat.py` / `_compat.py` / `compat/__init__.py`:

```bash
find . -name 'compat.py' -o -name '_compat.py'
```

### Procedure

This category requires the most care. **Do not blindly remove helpers** — read each helper and decide:

1. **Trivial helpers** (the body is `return x` after a Py2 branch is dropped) — replace every call site with the argument directly, then delete the helper
2. **Decode-on-bytes helpers** (the body decodes if input is bytes, returns unchanged if str) — keep the helper, OR replace each call site with the appropriate `.decode("utf-8")` / `.encode("utf-8")`. Prefer keeping the helper if it's used in many places.
3. **Helpers from Django** — `force_text`/`force_str`/`smart_text`/`smart_str`: in modern Django (3.0+), these have been renamed and the `*_text` variants are deprecated aliases for `*_str`. Replace `force_text` with `force_str`, `smart_text` with `smart_str`. Don't remove the calls — they still do useful work (lazy string handling).
4. **`compat.py` module** — once all imports from it are gone, delete the module. Check with `rg "from .* import .* (compat|_compat)"` and `rg "import .*compat"` first.

### Edge cases

- A helper is referenced from a string (e.g., `getattr(mod, "s2u")`) — grep finds it but rg may miss it. Search for the name as a string too.
- A helper is exported via `__all__` — update the `__all__` list when removing.

### Commit

This is one commit per helper or one commit per `compat.py` removal. Don't bundle.

```
Remove obsolete <helper-name> Py2/Py3 compat helper

The helper was a no-op in Py3 (or trivial); replaced N call sites with direct usage.
```

---

## Category 9: `__metaclass__` attribute and `with_metaclass` / `add_metaclass`

Py2 metaclass syntax (`class Foo(Bar): __metaclass__ = Meta`) doesn't work in Py3. If the project ran on Py3, it was likely already converted to `six.with_metaclass(Meta, Bar)` or `@six.add_metaclass(Meta)`. Now it's time to use the native `metaclass=` keyword.

### Detection

```bash
rg --type py '__metaclass__' -n
rg --type py 'with_metaclass|add_metaclass' -n
```

### Procedure

| Pattern | Py3 native |
|---|---|
| `class Foo(Bar):\n    __metaclass__ = Meta` | `class Foo(Bar, metaclass=Meta):` |
| `class Foo(six.with_metaclass(Meta, Bar)):` | `class Foo(Bar, metaclass=Meta):` |
| `@six.add_metaclass(Meta)\nclass Foo(Bar):` | `class Foo(Bar, metaclass=Meta):` |

If `__metaclass__ = Meta` appears at module level (not inside a class), it sets the default metaclass for all classes in the module — Py3 has no equivalent, so each class needs `metaclass=Meta` explicitly. Show the user before refactoring.

### Edge cases

- `with_metaclass(Meta, Base1, Base2)` (multiple bases) — `class Foo(Base1, Base2, metaclass=Meta):`
- Tests for the metaclass behavior — verify they still pass

### Commit

```
Convert metaclass syntax to Py3 native (metaclass=...)

- __metaclass__ attribute → class definition keyword
- six.with_metaclass / six.add_metaclass → metaclass= keyword
```

---

## Category 10: stdlib renames

Py3 reorganized many stdlib modules. Imports may still be using Py2 names if they were behind `try/except ImportError` shims.

### Detection

```bash
rg --type py '\bimport (urllib2|urlparse|cStringIO|StringIO|Queue|ConfigParser|HTMLParser|httplib|cookielib|BaseHTTPServer|SimpleHTTPServer|CGIHTTPServer|xmlrpclib|SocketServer|Tkinter|tkFileDialog|repr|copy_reg|copyreg|__builtin__)\b' -n
rg --type py '\bfrom (urllib2|urlparse|cStringIO|StringIO|Queue|ConfigParser|HTMLParser|httplib|cookielib|BaseHTTPServer|SimpleHTTPServer|CGIHTTPServer|xmlrpclib|SocketServer|Tkinter|tkFileDialog|repr|copy_reg|__builtin__) import' -n
```

### Procedure

| Py2 name | Py3 name |
|---|---|
| `urllib2` | `urllib.request` (most uses) — note `urlopen`, `Request`, `urlencode` are split across `urllib.request` and `urllib.parse` |
| `urlparse` | `urllib.parse` |
| `urllib.urlencode` | `urllib.parse.urlencode` |
| `urllib.urlopen` | `urllib.request.urlopen` |
| `cStringIO.StringIO` | `io.StringIO` (text) / `io.BytesIO` (bytes) |
| `StringIO.StringIO` | `io.StringIO` (text) / `io.BytesIO` (bytes) |
| `Queue` | `queue` |
| `Queue.Queue` | `queue.Queue` |
| `ConfigParser` | `configparser` |
| `ConfigParser.SafeConfigParser` | `configparser.ConfigParser` (the `Safe` prefix is deprecated) |
| `HTMLParser` | `html.parser` |
| `HTMLParser.HTMLParser` | `html.parser.HTMLParser` |
| `httplib` | `http.client` |
| `cookielib` | `http.cookiejar` |
| `Cookie` | `http.cookies` |
| `BaseHTTPServer` | `http.server` |
| `SimpleHTTPServer` | `http.server` |
| `CGIHTTPServer` | `http.server` |
| `xmlrpclib` | `xmlrpc.client` |
| `SocketServer` | `socketserver` |
| `Tkinter` | `tkinter` |
| `tkFileDialog` | `tkinter.filedialog` |
| `__builtin__` | `builtins` |
| `copy_reg` | `copyreg` |
| `repr` (module) | `reprlib` |

There are a few other Py2 → Py3 stdlib renames (e.g., the C-accelerated `cPickle` → unified `p`+`ickle` module, the `commands` module → `subprocess`). Handle them the same way — verify with the official porting guide: <https://docs.python.org/3/whatsnew/3.0.html#library-changes>.

**`StringIO` vs `BytesIO`:** Look at what's written to the buffer. If it's `str` → `io.StringIO`. If it's `bytes` → `io.BytesIO`. Don't guess.

### Procedure per occurrence

1. Show the user the import line and a few usages
2. Confirm the replacement (especially for `StringIO` → text vs bytes)
3. Update the import
4. Update any qualified usages that need namespace adjustment (e.g., `urllib2.urlopen` → `urllib.request.urlopen`)

### Commit

One commit per stdlib module replaced — easier to revert if a specific replacement causes issues.

```
Replace Py2 <module> with Py3 <new-module>

<short list of file changes>
```

---

## Category 11: `__nonzero__` / `__div__` / `__cmp__` / `__hex__` / `__oct__`

Py3 renamed several dunder methods.

### Detection

```bash
rg --type py 'def __(nonzero|div|cmp|hex|oct|coerce|long|getslice|setslice|delslice|unicode)__' -n
```

### Procedure

| Py2 dunder | Py3 dunder |
|---|---|
| `__nonzero__` | `__bool__` |
| `__div__` | `__truediv__` (and consider `__floordiv__` if needed) |
| `__cmp__` | (no direct equivalent) — implement `__eq__`, `__lt__`, etc., or use `functools.total_ordering` |
| `__hex__` | `__index__` (used by `hex()` via `__index__`) |
| `__oct__` | `__index__` |
| `__coerce__` | (gone — Py3 doesn't have numeric coercion) — usually safe to remove |
| `__long__` | `__int__` (Py3 has only `int`) |
| `__getslice__` / `__setslice__` / `__delslice__` | `__getitem__` / `__setitem__` / `__delitem__` (with slice objects — usually already implemented) |
| `__unicode__` | `__str__` (Py3 has no separate unicode type) |

**`__cmp__` is the tricky one.** It returned -1/0/1. To replace it, you need to define `__eq__` and `__lt__` (at minimum). Use `@functools.total_ordering` to derive the rest. Show the user the original `__cmp__` and propose the replacement; don't auto-convert.

### Commit

```
Rename Py2 dunder methods to Py3 equivalents

- __nonzero__ → __bool__
- __div__ → __truediv__
<...>
```

---

## Category 12: `super(Class, self)` → `super()` (optional, opt-in)

In Py3, `super()` (no arguments) works inside methods. `super(Class, self)` still works but is verbose.

### When to do this

**Only if the user opts in.** This is purely cosmetic. It also has a subtle gotcha:

- `super(SomeOtherClass, self)` (intentionally referring to a different class than the enclosing one) is **NOT** equivalent to `super()` — leave it alone.
- Inside metaclass `__init_subclass__` or other unusual contexts, the no-arg `super()` may not work correctly — leave those alone too.

### Detection

```bash
rg --type py 'super\([A-Za-z_][A-Za-z0-9_]*,\s*self\)' -n
```

### Procedure

For each occurrence:
1. Verify the class name in `super(<ClassName>, self)` matches the enclosing class
2. If yes, replace with `super()`
3. If no (intentional MRO manipulation), leave it

### Commit

```
Simplify super() calls (Py3 no-arg form)
```

---

## After all categories: final cleanup

1. **Remove `six` from `pyproject.toml`** dependencies if not already done (Category 2)
2. **Delete `compat.py` / `_compat.py`** if empty after Category 8
3. **Run full test suite once more:**
   ```bash
   uv run pytest
   ```
4. **Run ruff check on changed files** (informational):
   ```bash
   uv run ruff check $(git diff --name-only main -- '*.py')
   ```
5. **Final commit (if anything left):**
   ```
   Remove leftover Py2 compat scaffolding (compat.py, six dependency)
   ```

---

## Summary Report

After all categories, present:

```
Python 2 Cleanup Summary — <package-name>
=========================================

Category  1: __future__ imports         [DONE / SKIPPED]   N occurrences in M files
Category  2: six library                [DONE / SKIPPED]   N occurrences
Category  3: Py2 builtins (unicode/…)   [DONE / SKIPPED]   N occurrences
Category  4: dict iter/view methods     [DONE / SKIPPED]   N occurrences
Category  5: dict.has_key()             [DONE / SKIPPED]   N occurrences
Category  6: python_2_unicode_compatible [DONE / SKIPPED]  N occurrences
Category  7: u'…' prefix                [DONE / SKIPPED]   N occurrences
Category  8: compat helpers / compat.py [DONE / SKIPPED]   N helpers
Category  9: metaclass syntax           [DONE / SKIPPED]   N classes
Category 10: stdlib renames             [DONE / SKIPPED]   N imports
Category 11: dunder renames             [DONE / SKIPPED]   N methods
Category 12: super() simplification     [DONE / SKIPPED]   N call sites

Files modified: <count>
Commits created: <count>
Tests: <green / red>

⚠ Manual follow-up needed:
  - <items where user needs to verify behavior, e.g. unicode(x, encoding) calls>
  - <__cmp__ replacements requiring careful __eq__/__lt__ design>
  - <if six.PY2/six.PY3 conditionals where dead branch removal needs review>
```

---

## Common Mistakes

| Mistake | Prevention |
|---|---|
| Bulk `unicode → str` substitution without reviewing each call | `unicode(x, "utf-8")` and `str(x, "utf-8")` differ if `x` is `str` — review every occurrence |
| Combining categories in one commit | One per commit — easier to revert if a specific category breaks tests |
| Reformatting code while editing Py2 cruft | Iron Law: only Py2 cruft, never reformat |
| Removing `six` dependency before all `six` calls are gone | Always remove the dep last — verify with `rg 'six\.'` returns nothing |
| Auto-removing `u''` prefixes without user opt-in | Cosmetic, touches huge number of lines — always ask |
| Converting `super(Class, self)` to `super()` blindly | The class name might intentionally differ; check each |
| Replacing `force_text` → `force_str` in old Django (<3.0) | `force_str` only exists in Django 3.0+ — check Django version first |
| Replacing `StringIO` → `io.StringIO` when buffer holds bytes | Use `io.BytesIO` for bytes buffers — check what's written to the buffer |
| Removing `if six.PY2:` block but leaving the indentation of `else:` stale | After removing the dead branch, dedent the kept branch and remove the `if/else` skeleton |
| Treating `from __future__ import` as cruft when it's inside a `try:` block | Defensive Py2/Py3 compat code — flag for user, don't auto-remove |
| Running `2to3` instead of this skill | `2to3` makes a single huge diff with no human review — defeats the per-category review model |

## Red Flags — STOP

- "I'll just run `pyupgrade --py3-plus` on everything" — **NO.** That's a bulk auto-fix with no review. Use the per-category model.
- "These categories are independent, let me batch them in one commit" — **NO.** One commit per category.
- "While I'm fixing `unicode()`, I'll also rename this variable" — **NO.** Iron Law: only Py2 cruft.
- "The test suite is too slow, I'll skip running it after each category" — **NO.** Tests run after every category. If slow, run only the relevant test module.
- "This `if six.PY2:` block is obviously dead, I'll just remove the whole `if`" — **OK, but** verify the kept (`else:`) branch is syntactically correct after dedent.
- "This compat.py only has 3 helpers, I'll inline them all in one commit" — **NO.** One helper per commit.
- "The user said 'go ahead', so I'll just do all categories without confirming each" — **NO.** Each category is a separate confirmation.
- "I'll convert `__cmp__` to `__eq__` myself — it's obvious from the comparison" — **NO.** `__cmp__` returns -1/0/1; correctly translating to `__eq__`/`__lt__` is non-trivial. Show the user, propose, confirm.

## Tooling Notes

- **`pyupgrade`** (https://github.com/asottile/pyupgrade) automates many of these but in bulk — use it as a *detection aid* (run with `--py310-plus` and review the diff), not as the executor
- **`ruff`** with rule set `UP` (pyupgrade) does the same — useful for detection. Do NOT run `ruff --fix --select UP` on the whole codebase. If used for detection, run on changed files only.
- **`pylint`** has rule `useless-super-delegation` which catches some related issues
- **`vulture`** can find unused `compat.py` helpers after their callers are migrated
