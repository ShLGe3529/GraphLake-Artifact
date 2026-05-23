#!/usr/bin/env bash
# POST PuppyGraph schema mapping Iceberg demo.mydb.
# Usage: ./load_schema.sh [full|bi16]
set -ex

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="${1:-full}"
HOST="${PUPPYGRAPH_HOST:-http://localhost:8081}"
USER="${PUPPYGRAPH_USER:-puppygraph}"
PASS="${PUPPYGRAPH_PASSWORD:-puppygraph123}"

case "$PROFILE" in
  full) SCHEMA_FILE="${SCRIPT_DIR}/schema.json" ;;
  bi16) SCHEMA_FILE="${SCRIPT_DIR}/schema_bi16.json" ;;
  *)
    echo "Usage: $0 [full|bi16]" >&2
    exit 1
    ;;
esac

if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "Schema file missing: ${SCHEMA_FILE}" >&2
  exit 1
fi

echo "Loading PuppyGraph schema profile=${PROFILE} (demo.mydb) ..."
curl -sf -X POST \
  -H "content-type: application/json" \
  --data-binary "@${SCHEMA_FILE}" \
  --user "${USER}:${PASS}" \
  "${HOST}/schema"
echo
echo "Schema ${PROFILE} loaded."
