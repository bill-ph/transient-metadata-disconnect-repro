#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METADATA_PORT="${METADATA_PORT:-55432}"
PROXY_PORT="${PROXY_PORT:-55433}"
BLACKOUT_MS="${BLACKOUT_MS:-75}"
BLACKOUT_DELAY_MS="${BLACKOUT_DELAY_MS:-200}"
ATTEMPTS="${ATTEMPTS:-25}"
ROW_COUNT="${ROW_COUNT:-10000000}"
LOG_DIR="${LOG_DIR:-$ROOT/logs/$(date +%Y%m%d-%H%M%S)}"
DATA_PATH="$ROOT/lake/data"
PROXY_LOG="$LOG_DIR/proxy.log"

mkdir -p "$DATA_PATH" "$LOG_DIR"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 2
  }
}

need_cmd docker
need_cmd duckdb
need_cmd python3

echo "repro root: $ROOT"
echo "logs: $LOG_DIR"
echo "attempts=$ATTEMPTS row_count=$ROW_COUNT blackout_ms=$BLACKOUT_MS blackout_delay_ms=$BLACKOUT_DELAY_MS"

cleanup() {
  if [[ -n "${proxy_pid:-}" ]]; then
    kill "$proxy_pid" >/dev/null 2>&1 || true
    wait "$proxy_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

docker compose -f "$ROOT/docker-compose.yml" up -d --wait

python3 "$ROOT/tcp_blackout_proxy.py" "$PROXY_PORT" 127.0.0.1 "$METADATA_PORT" "$BLACKOUT_MS" >"$PROXY_LOG" 2>&1 &
proxy_pid=$!

METADATA_STORE="postgres:host=127.0.0.1 port=${PROXY_PORT} user=ducklake password=ducklake dbname=ducklake"

init_sql="
INSTALL ducklake;
LOAD ducklake;
ATTACH 'ducklake:${METADATA_STORE}' AS dl (DATA_PATH '${DATA_PATH}');
USE dl;
CREATE TABLE IF NOT EXISTS repro_commit(id BIGINT);
"
duckdb :memory: -c "$init_sql" >"$LOG_DIR/init.log" 2>&1

target_reproduced=0

for attempt in $(seq 1 "$ATTEMPTS"); do
  log_file="$LOG_DIR/attempt-$(printf '%02d' "$attempt").log"

  (
    sleep "$(awk "BEGIN { printf \"%.3f\", ${BLACKOUT_DELAY_MS} / 1000 }")"
    kill -USR1 "$proxy_pid" >/dev/null 2>&1 || true
  ) &

  attempt_sql="
LOAD ducklake;
ATTACH 'ducklake:${METADATA_STORE}' AS dl (DATA_PATH '${DATA_PATH}');
USE dl;
DELETE FROM repro_commit;
BEGIN;
INSERT INTO repro_commit SELECT i FROM range(${ROW_COUNT}) t(i);
COMMIT;
"

  if duckdb :memory: -c "$attempt_sql" >"$log_file" 2>&1; then
    printf 'attempt=%02d outcome=success\n' "$attempt"
    continue
  fi

  first_line="$(sed -n '1p' "$log_file")"
  printf 'attempt=%02d outcome=failure first_line=%s\n' "$attempt" "$first_line"

  if grep -Eq 'no transaction is active|Failed to commit|TransactionContext Error' "$log_file"; then
    target_reproduced=1
    echo "reproduced target failure on attempt $attempt"
    echo "full log: $log_file"
    break
  fi
done

if [[ "$target_reproduced" -eq 1 ]]; then
  exit 0
fi

echo "did not reproduce target failure in $ATTEMPTS attempts"
echo "try increasing ATTEMPTS, BLACKOUT_MS, or ROW_COUNT"
exit 1
