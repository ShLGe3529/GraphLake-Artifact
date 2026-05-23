#!/usr/bin/env bash
# Run Iceberg ingest inside the spark-iceberg container.
# Usage: ./run_ingest.sh [standard|partitioned|partitioned-exp0|neo4j]
#
# Scale: set LDBC_SCALE=sf30 or run ./generate_ldbc.sh sf30 (writes .ldbc_scale).
# All modes write to demo.mydb.<lowercase_table>; each table is DROP + overwrite (all SF share mydb).
# [NOTICE] Start storage (docker compose up -d) and Spark stack first; large SF ingest takes hours.

set -ex

MODE="${1:-standard}"
CONTAINER="${SPARK_CONTAINER:-spark-iceberg}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Scale from env, or last ./generate_ldbc.sh run
if [[ -z "${LDBC_SCALE:-}" && -f "${SCRIPT_DIR}/.ldbc_scale" ]]; then
  LDBC_SCALE="$(tr -d '[:space:]' < "${SCRIPT_DIR}/.ldbc_scale")"
fi
LDBC_SCALE="${LDBC_SCALE:-sf1}"
export LDBC_SCALE

case "$MODE" in
  standard)
    SCRIPT="/data/dataset/ingest_to_iceberg.py"
    export ICEBERG_NAMESPACE="${ICEBERG_NAMESPACE:-mydb}"
    export PARTITION_BY_CREATION_DATE="${PARTITION_BY_CREATION_DATE:-false}"
    unset PARTITION_TABLES 2>/dev/null || true
    echo "[INFO] Ingest target: demo.${ICEBERG_NAMESPACE}.<table>  LDBC_SCALE=${LDBC_SCALE}"
    echo "[NOTICE] Each table is DROP + overwrite; re-run standard after changing SF." >&2
    ;;
  partitioned)
    SCRIPT="/data/dataset/ingest_partitioned.py"
    export ICEBERG_NAMESPACE="${ICEBERG_NAMESPACE:-mydb}"
    export PARTITION_BY_CREATION_DATE="${PARTITION_BY_CREATION_DATE:-true}"
    export PARTITION_TABLES="${PARTITION_TABLES:-comment}"
    export PARTITION_GRANULARITY="${PARTITION_GRANULARITY:-month}"
    unset INGEST_ONLY_TYPES 2>/dev/null || true
    echo "[INFO] Ingest target: demo.mydb.<table> (comment month partitions)  LDBC_SCALE=${LDBC_SCALE}"
    echo "[NOTICE] DROP + overwrite; comment uses months(creation_date). Filter env: ISO timestamp." >&2
    ;;
  partitioned-exp0)
    SCRIPT="/data/dataset/ingest_exp0_partitioned.py"
    export ICEBERG_NAMESPACE="${ICEBERG_NAMESPACE:-mydb}"
    export INGEST_ONLY_TYPES="comment,person,comment_hascreator_person"
    export PARTITION_BY_CREATION_DATE="${PARTITION_BY_CREATION_DATE:-true}"
    export PARTITION_TABLES="${PARTITION_TABLES:-comment_hascreator_person}"
    export PARTITION_GRANULARITY="${PARTITION_GRANULARITY:-month}"
    echo "[INFO] exp0 ingest: comment, person, comment_hascreator_person  LDBC_SCALE=${LDBC_SCALE}"
    echo "[NOTICE] Month partition on comment_hascreator_person only." >&2
    ;;
  neo4j)
    SCRIPT="/data/dataset/export_neo4j_csv.py"
    export ICEBERG_NAMESPACE="${ICEBERG_NAMESPACE:-mydb}"
    unset PARTITION_BY_CREATION_DATE PARTITION_TABLES 2>/dev/null || true
    echo "[INFO] Neo4j export from demo.${ICEBERG_NAMESPACE}.*  LDBC_SCALE=${LDBC_SCALE}"
    ;;
  *)
    echo "Usage: $0 [standard|partitioned|partitioned-exp0|neo4j]" >&2
    exit 1
    ;;
esac

SPARK_MEM_OPTS=(
  --conf "spark.driver.memory=${SPARK_DRIVER_MEMORY:-24g}"
  --conf "spark.executor.memory=${SPARK_EXECUTOR_MEMORY:-24g}"
  --conf "spark.sql.iceberg.write.target-file-size-bytes=134217728"
  --conf "spark.sql.iceberg.write.parquet.row-group-size-bytes=16777216"
)

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "Container '${CONTAINER}' is not running. Start storage and Spark first:" >&2
  echo "  docker compose -f ${REPO_ROOT}/docker-compose.yml up -d" >&2
  echo "  docker compose -f ${REPO_ROOT}/systems/spark/docker-compose.yml up -d" >&2
  exit 1
fi

DATASET_DIR="bi-${LDBC_SCALE}-composite-projected-fk"
if ! docker exec "$CONTAINER" test -d "/data/dataset/raw/ldbc-snb/${DATASET_DIR}" 2>/dev/null; then
  echo "[WARN] CSV not found in container: /data/dataset/raw/ldbc-snb/${DATASET_DIR}" >&2
  echo "[WARN] Run: ./generate_ldbc.sh ${LDBC_SCALE}" >&2
fi

echo "Running ${SCRIPT} in ${CONTAINER} (LDBC_SCALE=${LDBC_SCALE}) ..."
# spark-submit (not pyspark -c): in this image -c means --conf, not Python code.
EXEC_ENV=(
  -e "LDBC_SCALE=${LDBC_SCALE}"
  -e "ICEBERG_CATALOG=${ICEBERG_CATALOG:-demo}"
  -e "ICEBERG_NAMESPACE=${ICEBERG_NAMESPACE}"
  -e "ICEBERG_DROP_BEFORE_WRITE=${ICEBERG_DROP_BEFORE_WRITE:-true}"
)
if [[ -n "${PARTITION_BY_CREATION_DATE:-}" ]]; then
  EXEC_ENV+=(-e "PARTITION_BY_CREATION_DATE=${PARTITION_BY_CREATION_DATE}")
fi
if [[ -n "${PARTITION_TABLES:-}" ]]; then
  EXEC_ENV+=(-e "PARTITION_TABLES=${PARTITION_TABLES}")
fi
if [[ -n "${PARTITION_GRANULARITY:-}" ]]; then
  EXEC_ENV+=(-e "PARTITION_GRANULARITY=${PARTITION_GRANULARITY}")
fi
if [[ -n "${INGEST_ONLY_TYPES:-}" ]]; then
  EXEC_ENV+=(-e "INGEST_ONLY_TYPES=${INGEST_ONLY_TYPES}")
fi

docker exec -i "${EXEC_ENV[@]}" "$CONTAINER" \
  spark-submit \
    --master 'local[*]' \
    "${SPARK_MEM_OPTS[@]}" \
    "$SCRIPT"
