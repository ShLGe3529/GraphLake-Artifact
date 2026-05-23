#!/usr/bin/env bash
# Run Trino BI SQL against Iceberg on MinIO.
# Usage: ./run_query.sh <namespace> <query_name>
#   namespace: mydb (only; partitioning is internal to Iceberg)
#   query_name: bi-2 | bi-5 | bi-8 | bi-13 | bi-16
set -ex

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER="${TRINO_CONTAINER:-trino-baseline}"
RESULT_DIR="${RESULT_DIR:-${SCRIPT_DIR}/results}"
mkdir -p "$RESULT_DIR"

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <namespace> <bi-2|bi-5|bi-8|bi-13|bi-16>" >&2
  exit 1
fi

NAMESPACE="$1"
QUERY="$2"
SQL_FILE="/query/$(echo "$QUERY" | tr '[:lower:]' '[:upper:]').sql"
OUT="${RESULT_DIR}/${NAMESPACE}_${QUERY}_result.csv"
TIME="${RESULT_DIR}/${NAMESPACE}_${QUERY}_time.txt"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "Container ${CONTAINER} not running." >&2
  exit 1
fi

echo "Running ${QUERY} on iceberg.${NAMESPACE} ..."
/usr/bin/time -f 'elapsed_sec=%e' -o "$TIME" \
  docker exec -i "$CONTAINER" trino \
    --catalog iceberg \
    --schema "$NAMESPACE" \
    --output-format CSV_HEADER \
    -f "$SQL_FILE" \
  > "$OUT"

echo "Wrote ${OUT} and ${TIME}"
