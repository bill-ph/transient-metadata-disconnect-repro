# DuckLake commit failure after transient metadata disconnect

## What happens?

When a short-lived network disconnect hits the PostgreSQL metadata catalog during a write transaction, DuckLake can fail at transaction end with a commit-style error instead of completing cleanly or failing in a more direct way.

In my local repro, the target failure was:

```text
TransactionContext Error: Failed to commit: Failed to execute query "ROLLBACK":
```

I also saw an earlier attach-time failure on another attempt:

```text
IO Error: Failed to attach DuckLake MetaData "__ducklake_metadata_dl" ...
Unable to connect to Postgres ...
server closed the connection unexpectedly
```

The important case is the commit-stage failure after a transient metadata disconnect during the transaction.

## To reproduce

Repro repo:

- `<REPO URL>`

Steps:

```bash
git clone <REPO URL>
cd transient-metadata-disconnect-repro
./run.sh
```

This starts:

1. a local PostgreSQL container for the DuckLake metadata catalog
2. a small TCP proxy in front of PostgreSQL
3. a blackout window that briefly drops active metadata connections mid-transaction

The default settings reproduced the problem for me without tuning.

## Observed result

With:

- DuckDB `v1.4.4`
- published `ducklake` extension installed via `INSTALL ducklake;`
- local PostgreSQL metadata catalog behind the blackout proxy

I reproduced:

```text
attempt=03 outcome=failure first_line=TransactionContext Error: Failed to commit: Failed to execute query "ROLLBACK":
```

I also saw:

```text
attempt=02 outcome=failure first_line=IO Error: Failed to attach DuckLake MetaData ...
```

## Expected behavior

A transient metadata disconnect should either:

- fail the transaction in a cleaner and more direct way, or
- recover predictably if retry/reconnect is expected to be supported

It should not leave the transaction ending in a commit/rollback error state like:

```text
TransactionContext Error: Failed to commit: Failed to execute query "ROLLBACK":
```

## Environment

- OS: macOS
- DuckDB: `v1.4.4`
- DuckLake: published extension
- Metadata catalog: PostgreSQL
- Data path: local filesystem
- Docker Compose: v2
- Python: Python 3

## Notes

- This repro does not require Duckgres.
- The repro intentionally uses a local TCP proxy to force a very short network blackout against the metadata store.
- If needed, the repro exposes tuning knobs such as `ATTEMPTS`, `BLACKOUT_MS`, `BLACKOUT_DELAY_MS`, and `ROW_COUNT`.
- Logs are written under `./logs/<timestamp>/`.
