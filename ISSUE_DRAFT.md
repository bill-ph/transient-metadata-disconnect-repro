# DuckLake commit failure after transient metadata disconnect

## What happens?

When a short-lived network disconnect hits the PostgreSQL metadata catalog during a write transaction, DuckLake can fail at transaction end with a commit-style error instead of completing cleanly or failing in a more direct way.

This report is based on the latest stable DuckLake path using DuckDB `v1.5.2` with DuckLake `v1.0` (installed extension version `415a9ebd` from `core`).

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

- `https://github.com/bill-ph/transient-metadata-disconnect-repro`

Steps:

```bash
git clone https://github.com/bill-ph/transient-metadata-disconnect-repro
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

- DuckDB `v1.5.2`
- DuckLake `v1.0` (installed extension version `415a9ebd` from `core`)
- local PostgreSQL metadata catalog behind the blackout proxy

I reproduced:

```text
attempt=04 outcome=failure first_line=TransactionContext Error: Failed to commit: Failed to execute query "ROLLBACK":
```

I also saw:

```text
attempt=02 outcome=failure first_line=IO Error: Failed to attach DuckLake MetaData ...
```

## Expected behavior

A short-lived transient metadata disconnect should not fail an otherwise valid transaction.

DuckLake should be robust to brief metadata-store transport interruptions and self-heal across them, especially when the metadata store is a remote PostgreSQL/RDS deployment in the normal production architecture.

## Environment

- OS: macOS
- DuckDB: `v1.5.2`
- DuckLake: `v1.0` (installed extension version `415a9ebd`, `core`)
- Metadata catalog: PostgreSQL
- Data path: local filesystem
- Docker Compose: v2
- Python: Python 3

## Notes

- The repro intentionally uses a local TCP proxy to force a very short network blackout against the metadata store.
- If needed, the repro exposes tuning knobs such as `ATTEMPTS`, `BLACKOUT_MS`, `BLACKOUT_DELAY_MS`, and `ROW_COUNT`.
- Logs are written under `./logs/<timestamp>/`.
