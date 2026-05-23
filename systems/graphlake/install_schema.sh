#!/usr/bin/env bash
# Install GraphLake GSQL schema. Usage: ./install_schema.sh [full|bi16]
# Manual helper only — experiment scripts call docker cp / gsql directly.
set -ex

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="${1:-full}"
CONTAINER="${GRAPHLAKE_CONTAINER:-graphlakeproto}"
GRAPH="${GRAPHLAKE_GRAPH:-ldbc_snb}"

case "$PROFILE" in
  full) GSQL_FILE="${SCRIPT_DIR}/conf/schema_full.gsql" ;;
  bi16) GSQL_FILE="${SCRIPT_DIR}/conf/schema_bi16.gsql" ;;
  *) echo "Usage: $0 [full|bi16]" >&2; exit 1 ;;
esac

docker ps --format '{{.Names}}' | grep -x "${CONTAINER}"
docker cp "${GSQL_FILE}" "${CONTAINER}:/tmp/schema_${PROFILE}.gsql"
docker exec -u tigergraph "${CONTAINER}" gsql -g "${GRAPH}" "/tmp/schema_${PROFILE}.gsql"
echo "Schema ${PROFILE} installed on ${CONTAINER} graph ${GRAPH}."
