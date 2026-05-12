# Django × Python compatibility matrix (canonical reference)

**Owner:** `readme-guardian` skill. Other skills that need this data (e.g., `python-upgrade-package` Step 2b) reference this file rather than duplicating the table.

**Snapshot date:** 2026-05-08

**Authoritative upstream:**
- <https://docs.djangoproject.com/en/dev/faq/install/#what-python-version-can-i-use-with-django>
- <https://www.djangoproject.com/download/#supported-versions>

## Freshness rule

Before emitting any per-project Django matrix into a README, the consuming skill must:

1. Compute `days_since = today - snapshot_date` above.
2. If `days_since > 90`, run the **Regenerating this file** procedure at the bottom of this document and update the snapshot before continuing.
3. If `days_since <= 90`, the snapshot is fresh enough — use it directly.

A skill that emits a stale matrix into a user's README has failed its job. Re-deriving from upstream is cheap; shipping wrong compatibility data is not.

## Matrix

| Django  | 3.10 | 3.11 | 3.12 | 3.13 | 3.14 | Status                                  |
|---------|------|------|------|------|------|-----------------------------------------|
| 4.2 LTS | ✓    | ✓    | ✓    | —    | —    | EOL Apr 2026                            |
| 5.0     | ✓    | ✓    | ✓    | —    | —    | EOL Apr 2025                            |
| 5.1     | ✓    | ✓    | ✓    | ✓    | —    | EOL Dec 2025                            |
| 5.2 LTS | ✓    | ✓    | ✓    | ✓    | ✓    | Active LTS (extended support Apr 2028)  |
| 6.0     | —    | —    | ✓    | ✓    | ✓    | Mainstream Aug 2026, extended Apr 2027  |

**Currently supported series (as of snapshot):** 5.2 LTS and 6.0. Everything else is kept for historical reference and to inform floor-bump decisions — drop EOL rows when generating a per-project matrix unless the project's constraint genuinely demands them.

**Pre-3.10 columns omitted.** Python 3.8 and 3.9 are EOL; the modern `requires-python` floor is `>=3.10`. Add older columns only if a project explicitly supports them.

## Regenerating this file

When the freshness rule fires, or when Django ships a new release / a Python version reaches EOL:

1. WebFetch <https://docs.djangoproject.com/en/dev/faq/install/#what-python-version-can-i-use-with-django>. Extract the "What Python version can I use with Django?" table — each row is `Django release → list of supported Python versions`.
2. WebFetch <https://www.djangoproject.com/download/#supported-versions>. Extract LTS designation and mainstream/extended/EOL dates per release.
3. Rebuild the matrix above:
   - One row per Django series still relevant (see drop rule below).
   - Columns cover every Python version supported by any in-scope Django series.
   - `✓` where the Django × Python pair is supported upstream; `—` otherwise.
4. Update the **Status** column from step 2 data.
5. Refresh the "Currently supported series" line to whatever Django currently calls "supported" on the downloads page.
6. **Drop rule:** remove any Django series that reached EOL more than 12 months before today. Keep recent EOLs (within 12 months) so projects mid-migration still see them.
7. Update the **Snapshot date** at the top to today.
8. Commit with a message like `Refresh Django × Python matrix snapshot to YYYY-MM-DD`.

The matrix is small enough that a manual rebuild from the two upstream pages takes 2–3 minutes and is more reliable than parsing HTML programmatically.
