#!/usr/bin/env bash
# Offline neo4j-admin import from projection-optimized CSV.
# Usage: ./run_import.sh [bi2|bi5|bi8|bi13|bi16|full]
# [NOTICE] Run dataset/run_ingest.sh neo4j first; import wipes and rebuilds neo4j/data.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="${1:-bi16}"

case "$SUITE" in
  bi2)  IMPORT_SCRIPT="import_ldbc-bi2.sh"
        CSV_SUBDIR="mydb_bi2" ;;
  bi5)  IMPORT_SCRIPT="import_ldbc-bi5.sh"
        CSV_SUBDIR="mydb_bi5" ;;
  bi8)  IMPORT_SCRIPT="import_ldbc-bi8.sh"
        CSV_SUBDIR="mydb_bi8" ;;
  bi13) IMPORT_SCRIPT="import_ldbc-bi13.sh"
        CSV_SUBDIR="mydb_bi13" ;;
  bi16) IMPORT_SCRIPT="import_ldbc-bi16.sh"
        CSV_SUBDIR="mydb_bi16" ;;
  full) IMPORT_SCRIPT="import_ldbc.sh"
        CSV_SUBDIR="mydb_full" ;;
  *)
    echo "Usage: $0 [bi2|bi5|bi8|bi13|bi16|full]" >&2
    exit 1
    ;;
esac

CSV_HOST="${NEO4J_CSV_DIR:-${SCRIPT_DIR}/../../dataset/exports/neo4j/${CSV_SUBDIR}}"
if [[ ! -d "$CSV_HOST" ]]; then
  echo "CSV directory not found: ${CSV_HOST}" >&2
  echo "Run dataset/export_neo4j_csv.py first (set NEO4J_EXPORT_DIR)." >&2
  exit 1
fi

mkdir -p "${SCRIPT_DIR}/data"

echo "Importing Neo4j from ${CSV_HOST} using ${IMPORT_SCRIPT} ..."
docker run --rm \
  --network lakehouse-net \
  --entrypoint bash \
  -v "${SCRIPT_DIR}/data:/data" \
  -v "${CSV_HOST}:/import/csv:ro" \
  -v "${SCRIPT_DIR}/import/${IMPORT_SCRIPT}:/import_ldbc.sh:ro" \
  neo4j:latest \
  /import_ldbc.sh

echo "Import finished. Start Neo4j with: docker compose -f ${SCRIPT_DIR}/docker-compose.yml up -d"
