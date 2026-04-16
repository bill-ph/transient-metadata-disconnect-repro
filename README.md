# Transient Metadata Disconnect Repro

Minimal reproduction for intermittent DuckLake write failures caused by a short-lived disconnect to the PostgreSQL metadata catalog.

This repro uses:

- base `duckdb` CLI
- the published `ducklake` extension
- a local PostgreSQL container as the DuckLake metadata catalog
- a tiny TCP proxy that can drop active metadata connections for a very short blackout window

## What It Reproduces

A write transaction where:

1. `BEGIN` succeeds
2. the `INSERT` may succeed
3. a short metadata disconnect occurs during the transaction
4. the failure surfaces at transaction end as a commit-style error such as:

- `Failed to commit`
- `TransactionContext Error`
- `no transaction is active`

The exact message is timing-sensitive and may vary by DuckDB/DuckLake version and machine speed.

## Prerequisites

- Docker with Compose v2
- `duckdb` on your `PATH`
- `python3` on your `PATH`

The first run may download the `ducklake` extension via `INSTALL ducklake;`.

## Validated Environment

This repro was confirmed on:

- macOS
- DuckDB `v1.5.2`
- DuckLake `v1.0` (extension_version `415a9ebd`, installed from `core`)
- Docker Compose `v2.40.3`
- Python `3.9.6`

## Run

```bash
./run.sh
```

The script will:

1. start PostgreSQL on `127.0.0.1:55432`
2. start a TCP blackout proxy on `127.0.0.1:55433`
3. initialize a DuckLake catalog using PostgreSQL metadata and local filesystem data files
4. loop transaction attempts until it reproduces a commit-style failure or exhausts the configured attempts

Logs are written under `./logs/<timestamp>/`.

## Expected Failure

The repro is successful if you see a commit-stage failure such as:

```text
TransactionContext Error: Failed to commit: Failed to execute query "ROLLBACK":
```

You may also see an earlier metadata attach failure on some attempts while the blackout lands too early:

```text
IO Error: Failed to attach DuckLake MetaData ...
Unable to connect to Postgres ...
server closed the connection unexpectedly
```

The attach-time error is useful signal, but the main target is the commit-stage failure after the disconnect occurs during an in-flight write transaction.

## Cleanup

```bash
./cleanup.sh
```

## Tuning Knobs

If the failure does not reproduce on your machine, increase one or more of:

```bash
ATTEMPTS=100 ./run.sh
BLACKOUT_MS=125 ./run.sh
ROW_COUNT=20000000 ./run.sh
BLACKOUT_DELAY_MS=300 ./run.sh
```

Available environment variables:

- `ATTEMPTS` default `25`
- `ROW_COUNT` default `10000000`
- `BLACKOUT_MS` default `75`
- `BLACKOUT_DELAY_MS` default `200`
- `METADATA_PORT` default `55432`
- `PROXY_PORT` default `55433`
- `LOG_DIR` default `./logs/<timestamp>`

## Notes

- This repro intentionally simulates a transient network problem; it does not require Duckgres.
- The PostgreSQL metadata catalog is local only because it makes the disconnect timing reproducible.
- The data path uses local files to keep the setup small and avoid adding object storage to the repro.
- If you mostly see failures during `ATTACH` instead of `COMMIT`, increase `BLACKOUT_DELAY_MS` so the blackout lands later in the transaction.

## Sharing This Repro

The cleanest way to report this upstream is:

1. put this directory in a small public GitHub repo
2. link that repo from the DuckLake issue
3. paste the contents of `ISSUE_DRAFT.md` into the issue body
4. include one or two short log excerpts showing the exact failure you hit

Keep generated artifacts like `logs/` and `lake/data/` out of the repo.
