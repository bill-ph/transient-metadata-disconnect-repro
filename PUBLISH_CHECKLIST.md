# Publish Checklist

Before opening the upstream issue:

1. Put this directory in a small GitHub repo.
2. Make sure generated artifacts stay uncommitted.
3. Add a license file for the repo.
4. Replace `<REPO URL>` in `ISSUE_DRAFT.md`.
5. Open a DuckLake issue and paste in `ISSUE_DRAFT.md`.
6. Include one short excerpt from the commit-stage failure log.

Suggested log excerpt:

```text
TransactionContext Error: Failed to commit: Failed to execute query "ROLLBACK":
```

Suggested upstream issue location:

- https://github.com/duckdb/ducklake/issues
