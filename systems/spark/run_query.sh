#!/usr/bin/env bash
# Run Spark SQL BI query via spark-iceberg container.
# Usage: ./run_query.sh <namespace> <query_name>
set -ex

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER="${SPARK_CONTAINER:-spark-iceberg}"
RESULT_DIR="${RESULT_DIR:-${SCRIPT_DIR}/results}"
mkdir -p "$RESULT_DIR"

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <namespace> <bi-2|bi-5|bi-8|bi-13|bi-16>" >&2
  exit 1
fi

NAMESPACE="$1"
QUERY="$2"
QUERY_UPPER=$(echo "$QUERY" | tr '[:lower:]' '[:upper:]')
SQL_HOST="${SCRIPT_DIR}/queries/${QUERY_UPPER}.sql"
SQL_CONTAINER="/data/queries/${QUERY_UPPER}.sql"
OUT="${RESULT_DIR}/${NAMESPACE}_${QUERY}_result.tsv"
TIME="${RESULT_DIR}/${NAMESPACE}_${QUERY}_time.txt"

if [[ ! -f "$SQL_HOST" ]]; then
  echo "SQL not found: ${SQL_HOST}" >&2
  exit 1
fi

# Namespace-specific SQL (patch USE catalog.database)
TMP_SQL=$(mktemp)
sed "s/USE demo\.[^;]*;/USE demo.${NAMESPACE};/" "$SQL_HOST" > "$TMP_SQL"
SQL_CONTAINER="/tmp/$(basename "${SQL_CONTAINER}").run"
docker cp "$TMP_SQL" "${CONTAINER}:${SQL_CONTAINER}"
rm -f "$TMP_SQL"

SPARK_OPTS=(
  --master "local[*]"
  --conf "spark.driver.memory=${SPARK_DRIVER_MEMORY:-24g}"
  --conf "spark.executor.memory=${SPARK_EXECUTOR_MEMORY:-24g}"
  --conf "spark.sql.shuffle.partitions=${SPARK_SHUFFLE_PARTITIONS:-64}"
  --conf "spark.sql.adaptive.enabled=true"
  --conf "spark.sql.ansi.enabled=true"
)

echo "Running ${QUERY} on demo.${NAMESPACE} ..."
/usr/bin/time -f 'elapsed_sec=%e' -o "$TIME" \
  docker exec -i "$CONTAINER" \
    spark-sql "${SPARK_OPTS[@]}" -f "$SQL_CONTAINER" \
  > "$OUT"

echo "Wrote ${OUT} and ${TIME}"
