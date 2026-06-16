#!/usr/bin/env bash
# exp1 — End-to-end BI-16 (per-engine timing definitions):
#   Neo4j:    etl_sec = Iceberg->CSV export + neo4j-admin import; query_sec only (no startup)
#   Trino/Spark: query_sec only
#   GraphLake: startup_sec = first gsql schema load, GPE "Build EdgeRefBlocks takes Xms" (config restart excluded)
#   PuppyGraph: startup_sec = blackout after schema POST (steady CPU); tune be.conf first
set -ex

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULT_DIR="${REPO_ROOT}/experiments/results/exp1"
SUMMARY="${RESULT_DIR}/e2e_bi16_summary.csv"
GRAPHLAKE_CONTAINER="${GRAPHLAKE_CONTAINER:-graphlakeproto}"
PUPPYGRAPH_CONTAINER="${PUPPYGRAPH_CONTAINER:-puppygraph-baseline}"
GRAPHLAKE_IMAGE="${GRAPHLAKE_IMAGE:-shlge3529/graphlake-artifact:latest}"
TG_CMD=/home/tigergraph/tigergraph/app/cmd
GSTORE_CONFIG=/home/tigergraph/tigergraph/data/gstore/0/part/config.yaml
GRAPHLAKE_FILTERS_FILE=/tmp/graphlake_filters.properties
MC_CONTAINER="${MC_CONTAINER:-mc}"
MC_MYDB_PATH=minio/warehouse/graphcatalog/mydb
LOAD_TIMEOUT_SEC="${GRAPHLAKE_LOAD_TIMEOUT_SEC:-7200}"
POLL_SEC=5
PUPPYGRAPH_CPU_THRESHOLD="${PUPPYGRAPH_CPU_THRESHOLD:-600.0}"
PUPPYGRAPH_IDLE_SEC="${PUPPYGRAPH_IDLE_SEC:-3}"
QUERY=bi-16
TS_NOW() { date -u +%Y-%m-%dT%H:%M:%SZ; }
DROP_CACHES="${REPO_ROOT}/experiments/utils/drop_caches.sh"
drop_os_cache() {
  echo "Dropping OS page cache ..."
  "${DROP_CACHES}"
}

mkdir -p "${RESULT_DIR}"
echo "engine,query,database,etl_sec,startup_sec,query_sec,timestamp" >"${SUMMARY}"

echo "======== Step 0: Check storage ========"
docker ps --format '{{.Names}}' | grep -x minio
docker ps --format '{{.Names}}' | grep -x "${MC_CONTAINER}"
docker network inspect lakehouse-net >/dev/null

echo "======== Step 1: Standard Iceberg ingest (demo.mydb) ========"
cd "${REPO_ROOT}/dataset"
./generate_ldbc.sh sf30 
docker compose -f "${REPO_ROOT}/systems/spark/docker-compose.yml" up -d
sleep 10
./run_ingest.sh standard
cd "${REPO_ROOT}"

# =============================================================================
echo "======== Step 2: GraphLake / BI-16 ========"
drop_os_cache
echo "Step 2a: Load image and start ${GRAPHLAKE_CONTAINER}"
docker rm -f "${GRAPHLAKE_CONTAINER}" 2>/dev/null || true
docker run -d --name "${GRAPHLAKE_CONTAINER}" \
  --network lakehouse-net \
  -p 14240:14240 \
  -p 9000:9000 \
  --ulimit nofile=1000000:1000000 \
  -e GRAPHLAKE_ICEBERG_NAMESPACE=mydb \
  -e AWS_ACCESS_KEY_ID=admin \
  -e AWS_SECRET_ACCESS_KEY=password \
  -e AWS_REGION=us-east-2 \
  "${GRAPHLAKE_IMAGE}"
docker exec "${GRAPHLAKE_CONTAINER}" bash -c ": > ${GRAPHLAKE_FILTERS_FILE}"
docker exec -u tigergraph "${GRAPHLAKE_CONTAINER}" "${TG_CMD}/gadmin" start all
sleep 30

echo "Step 2b: Install BI-16 GSQL schema (no -g); startup = Build EdgeRefBlocks from GPE log"
docker cp "${REPO_ROOT}/systems/graphlake/conf/schema_bi16.gsql" \
  "${GRAPHLAKE_CONTAINER}:/tmp/schema_bi16.gsql"
docker exec -u tigergraph "${GRAPHLAKE_CONTAINER}" \
  "${TG_CMD}/gsql" "/tmp/schema_bi16.gsql"

GRAPHLAKE_STARTUP_MS=NA
ELAPSED_GL=0
while [ "${ELAPSED_GL}" -lt "${LOAD_TIMEOUT_SEC}" ]; do
  LOG_LINE=$(docker exec "${GRAPHLAKE_CONTAINER}" bash -c \
    'grep "Build EdgeRefBlocks takes" /home/tigergraph/tigergraph/log/gpe/log.INFO 2>/dev/null | tail -1' || true)
  if [ -n "${LOG_LINE}" ]; then
    echo "${LOG_LINE}"
    GRAPHLAKE_STARTUP_MS=$(echo "${LOG_LINE}" | sed -n 's/.*Build EdgeRefBlocks takes \([0-9]*\)ms.*/\1/p')
    break
  fi
  sleep "${POLL_SEC}"
  ELAPSED_GL=$((ELAPSED_GL + POLL_SEC))
done
GRAPHLAKE_STARTUP_SEC=NA
if [ -n "${GRAPHLAKE_STARTUP_MS}" ] && [ "${GRAPHLAKE_STARTUP_MS}" != NA ]; then
  GRAPHLAKE_STARTUP_SEC=$(awk -v ms="${GRAPHLAKE_STARTUP_MS}" 'BEGIN { printf "%.3f", ms/1000 }')
fi
echo "GraphLake startup_sec=${GRAPHLAKE_STARTUP_SEC} (from Build EdgeRefBlocks; config restart below is NOT startup)"

echo "Step 2c: Patch ActiveCol (bi16) and restart TigerGraph (not counted as startup)"
docker cp "${REPO_ROOT}/systems/graphlake/patch_gstore_activecols.py" \
  "${GRAPHLAKE_CONTAINER}:/tmp/patch_gstore_activecols.py"
docker exec -u tigergraph "${GRAPHLAKE_CONTAINER}" \
  python3 /tmp/patch_gstore_activecols.py "${GSTORE_CONFIG}" bi16
sleep 10
kill -9 $(pgrep tg_dbs_gped)
kill -9 $(pgrep tg_dbs_gsed)
kill -9 $(pgrep tg_dbs_restd)
docker exec -u tigergraph "${GRAPHLAKE_CONTAINER}" "${TG_CMD}/gadmin" restart -y
sleep 30

echo "Step 2d: Install BI-16 query and run REST (query time only)"
docker cp "${REPO_ROOT}/systems/graphlake/queries/bi-16.gsql" \
  "${GRAPHLAKE_CONTAINER}:/tmp/bi-16.gsql"
docker exec -u tigergraph "${GRAPHLAKE_CONTAINER}" \
  "${TG_CMD}/gsql" -g ldbc_snb "/tmp/bi-16.gsql"
mkdir -p "${RESULT_DIR}/graphlake"
/usr/bin/time -f 'elapsed_sec=%e' -o "${RESULT_DIR}/graphlake/${QUERY}_time.txt" \
  curl -sf -H "GSQL-TIMEOUT:3600000" \
  "http://127.0.0.1:14240/restpp/query/ldbc_snb/bi16?tagA=Adolf_Hitler&dateA=2012-05-08&tagB=Hamid_Karzai&dateB=2012-05-12&maxKnowsLimit=4" \
  -o "${RESULT_DIR}/graphlake/${QUERY}_result.json"
GRAPHLAKE_QUERY_SEC=$(grep '^elapsed_sec=' "${RESULT_DIR}/graphlake/${QUERY}_time.txt" | cut -d= -f2)
echo "graphlake,${QUERY},mydb,,${GRAPHLAKE_STARTUP_SEC},${GRAPHLAKE_QUERY_SEC},$(TS_NOW)" >>"${SUMMARY}"

echo "Step 2e: clear lakehouse data and stop GraphLake"
docker exec "${MC_CONTAINER}" mc rm -r --force "${MC_MYDB_PATH}"
docker stop "${GRAPHLAKE_CONTAINER}"

# =============================================================================
echo "======== Step 3: PuppyGraph / BI-16 ========"
drop_os_cache
echo "Step 3a: Start ${PUPPYGRAPH_CONTAINER}"
docker compose -f "${REPO_ROOT}/systems/puppygraph/docker-compose.yml" up -d
sleep 15

echo "Step 3b: Tune BE (datacache_mem_size=32G, mem_limit=65%) and restart BE"
docker exec --user root "${PUPPYGRAPH_CONTAINER}" sed -i \
  's/^datacache_mem_size = .*/datacache_mem_size = 32G/' \
  /opt/lib/dataaccess/be/conf/be.conf
docker exec --user root "${PUPPYGRAPH_CONTAINER}" sed -i \
  's/^mem_limit = .*/mem_limit = 65%/' \
  /opt/lib/dataaccess/be/conf/be.conf
docker exec --user root "${PUPPYGRAPH_CONTAINER}" \
  /opt/lib/dataaccess/be/bin/stop_be.sh
docker exec --user root "${PUPPYGRAPH_CONTAINER}" bash -c \
  '/opt/lib/dataaccess/be/bin/start_be.sh &'
sleep 30

echo "Step 3c: POST schema_bi16.json and measure startup (blackout / steady CPU)"
mkdir -p "${RESULT_DIR}/puppygraph"
PUPPY_START=$(date +%s)
echo "Sending schema mapping request to PuppyGraph..."
PUPPY_SCHEMA_RESP=$(
  curl -XPOST -H "content-type: application/json" \
    --data-binary @"${REPO_ROOT}/systems/puppygraph/schema_bi16.json" \
    --user puppygraph:puppygraph123 \
    http://localhost:8081/schema
)
echo "${PUPPY_SCHEMA_RESP}"
echo "${PUPPY_SCHEMA_RESP}" | grep -q '"Status":"OK"' || {
  echo "ERROR: PuppyGraph schema POST did not return Status OK" >&2
  exit 1
}
echo "Waiting for PuppyGraph server restart after schema POST..."
sleep 10
PUPPYGRAPH_PID=$(pgrep -f 'dataaccess_be' | head -1)
echo "PuppyGraph dataaccess_be PID on host: ${PUPPYGRAPH_PID}"
if [ -z "${PUPPYGRAPH_PID}" ]; then
  echo "ERROR: dataaccess_be PID not found on host" >&2
  exit 1
fi
echo "Waiting for PuppyGraph materialization (CPU < ${PUPPYGRAPH_CPU_THRESHOLD}% for ${PUPPYGRAPH_IDLE_SEC}s) ..."
PUPPY_IDLE_COUNT=0
while true; do
  CPU_USAGE=$(top -b -n 2 -d 1 -p "${PUPPYGRAPH_PID}" | awk -v pid="${PUPPYGRAPH_PID}" \
    '$1 == pid {cpu=$9} END {print cpu}')
  if [ -z "${CPU_USAGE}" ]; then
    PUPPYGRAPH_PID=$(pgrep -f 'dataaccess_be' | head -1)
    CPU_USAGE=$(top -b -n 2 -d 1 -p "${PUPPYGRAPH_PID}" | awk -v pid="${PUPPYGRAPH_PID}" \
      '$1 == pid {cpu=$9} END {print cpu}')
  fi
  if [ -z "${CPU_USAGE}" ]; then
    echo "ERROR: lost dataaccess_be PID ${PUPPYGRAPH_PID}" >&2
    exit 1
  fi
  echo "PuppyGraph CPU: ${CPU_USAGE}%"
  IS_IDLE=$(awk -v cpu="${CPU_USAGE}" -v t="${PUPPYGRAPH_CPU_THRESHOLD}" \
    'BEGIN {if (cpu+0 < t+0) print 1; else print 0}')
  if [ "${IS_IDLE}" -eq 1 ]; then
    PUPPY_IDLE_COUNT=$((PUPPY_IDLE_COUNT + 1))
    if [ "${PUPPY_IDLE_COUNT}" -ge "${PUPPYGRAPH_IDLE_SEC}" ]; then
      PUPPY_END=$(date +%s)
      PUPPY_STARTUP_SEC=$((PUPPY_END - PUPPY_START - PUPPYGRAPH_IDLE_SEC + 1))
      echo "PuppyGraph startup_sec=${PUPPY_STARTUP_SEC} (steady blackout)"
      break
    fi
  else
    PUPPY_IDLE_COUNT=0
  fi
done

sleep 300

echo "Step 3d: Run BI-16 Cypher (query time)"
pip3 install neo4j
PUPPY_RESULT_DIR="${RESULT_DIR}/puppygraph"
if RESULT_DIR="${PUPPY_RESULT_DIR}" /usr/bin/time -f 'elapsed_sec=%e' \
  -o "${PUPPY_RESULT_DIR}/${QUERY}_time.txt" \
  python3 "${REPO_ROOT}/systems/puppygraph/run_cypher.py" "${QUERY}"; then
  PUPPY_QUERY_SEC=$(grep '^elapsed_sec=' "${PUPPY_RESULT_DIR}/${QUERY}_time.txt" | cut -d= -f2)
else
  echo "WARNING: PuppyGraph BI-16 query failed; recording query_sec=fail" >&2
  PUPPY_QUERY_SEC=fail
fi
echo "puppygraph,${QUERY},mydb,,${PUPPY_STARTUP_SEC},${PUPPY_QUERY_SEC},$(TS_NOW)" >>"${SUMMARY}"

echo "Step 3e: Stop PuppyGraph"
docker compose -f "${REPO_ROOT}/systems/puppygraph/docker-compose.yml" down

# =============================================================================
echo "======== Step 4: Trino / BI-16 (query time only) ========"
drop_os_cache
echo "Step 4a: Start Trino"
docker compose -f "${REPO_ROOT}/systems/trino/docker-compose.yml" up -d
sleep 20

echo "Step 4b: Run BI-16 SQL"
mkdir -p "${RESULT_DIR}/trino"
/usr/bin/time -f 'elapsed_sec=%e' -o "${RESULT_DIR}/trino/mydb_${QUERY}_time.txt" \
  docker exec -i trino-baseline trino \
    --catalog iceberg --schema mydb \
    --output-format CSV_HEADER \
    -f /query/BI-16.sql \
  > "${RESULT_DIR}/trino/mydb_${QUERY}_result.csv"
TRINO_QUERY_SEC=$(grep '^elapsed_sec=' "${RESULT_DIR}/trino/mydb_${QUERY}_time.txt" | cut -d= -f2)
echo "trino,${QUERY},mydb,,,${TRINO_QUERY_SEC},$(TS_NOW)" >>"${SUMMARY}"

echo "Step 4c: Stop Trino"
docker compose -f "${REPO_ROOT}/systems/trino/docker-compose.yml" down

# =============================================================================
echo "======== Step 5: Spark / BI-16 (query time only) ========"
drop_os_cache
echo "Step 5a: Start Spark + Iceberg REST"
docker compose -f "${REPO_ROOT}/systems/spark/docker-compose.yml" up -d
sleep 10

echo "Step 5b: Copy patched SQL into spark-iceberg (/tmp; /data/queries is ro)"
SPARK_SQL_RUN=/tmp/bi-16.spark.sql.run
sed "s/USE demo\.[^;]*;/USE demo.mydb;/" \
  "${REPO_ROOT}/systems/spark/queries/BI-16.sql" > /tmp/bi-16.spark.sql
docker cp /tmp/bi-16.spark.sql "spark-iceberg:${SPARK_SQL_RUN}"

echo "Step 5c: spark-sql -f BI-16"
mkdir -p "${RESULT_DIR}/spark"
/usr/bin/time -f 'elapsed_sec=%e' -o "${RESULT_DIR}/spark/mydb_${QUERY}_time.txt" \
  docker exec -i spark-iceberg spark-sql \
    --master 'local[*]' \
    --conf spark.driver.memory=24g \
    --conf spark.executor.memory=24g \
    -f "${SPARK_SQL_RUN}" \
  > "${RESULT_DIR}/spark/mydb_${QUERY}_result.tsv"
SPARK_QUERY_SEC=$(grep '^elapsed_sec=' "${RESULT_DIR}/spark/mydb_${QUERY}_time.txt" | cut -d= -f2)
echo "spark,${QUERY},mydb,,,${SPARK_QUERY_SEC},$(TS_NOW)" >>"${SUMMARY}"

# =============================================================================
echo "======== Step 6: Neo4j / BI-16 (etl = export + import; query only) ========"
drop_os_cache
echo "Step 6a: Export BI-16 projection CSV from Iceberg (ETL part 1)"
mkdir -p "${RESULT_DIR}/neo4j"
cd "${REPO_ROOT}/dataset"
export NEO4J_EXPORT_DIR="${REPO_ROOT}/dataset/exports/neo4j/mydb_bi16"
/usr/bin/time -f 'elapsed_sec=%e' -o "${RESULT_DIR}/neo4j/export_time.txt" \
  ./run_ingest.sh neo4j
NEO4J_EXPORT_SEC=$(grep '^elapsed_sec=' "${RESULT_DIR}/neo4j/export_time.txt" | cut -d= -f2)
cd "${REPO_ROOT}"

echo "Step 6b: neo4j-admin import (ETL part 2)"
# CSV at /import/csv (ro); --entrypoint bash skips image chown on /var/lib/neo4j/import
/usr/bin/time -f 'elapsed_sec=%e' -o "${RESULT_DIR}/neo4j/import_time.txt" \
  docker run --rm \
    --network lakehouse-net \
    --entrypoint bash \
    -v "${REPO_ROOT}/systems/neo4j/data:/data" \
    -v "${NEO4J_EXPORT_DIR}:/import/csv:ro" \
    -v "${REPO_ROOT}/systems/neo4j/import/import_ldbc-bi16.sh:/import_ldbc.sh:ro" \
    neo4j:latest \
    /import_ldbc.sh
NEO4J_IMPORT_SEC=$(grep '^elapsed_sec=' "${RESULT_DIR}/neo4j/import_time.txt" | cut -d= -f2)
NEO4J_ETL_SEC=$(awk -v a="${NEO4J_EXPORT_SEC}" -v b="${NEO4J_IMPORT_SEC}" 'BEGIN { printf "%.3f", a+b }')
echo "Neo4j etl_sec=${NEO4J_ETL_SEC} (export=${NEO4J_EXPORT_SEC} + import=${NEO4J_IMPORT_SEC})"

echo "Step 6c: Start Neo4j"
docker compose -f "${REPO_ROOT}/systems/neo4j/docker-compose.yml" up -d
sleep 20

echo "Step 6d: cypher-shell BI-16 (query time)"
/usr/bin/time -f 'elapsed_sec=%e' -o "${RESULT_DIR}/neo4j/${QUERY}_time.txt" \
  docker exec -i neo4j-baseline cypher-shell -u neo4j -p password \
    -f /query/bi-16.cypher \
    --param "tagA => 'Adolf_Hitler'" \
    --param "dateA => datetime('2012-05-08')" \
    --param "tagB => 'Hamid_Karzai'" \
    --param "dateB => datetime('2012-05-12')" \
    --param "maxKnowsLimit => 4" \
    --format plain \
  > "${RESULT_DIR}/neo4j/${QUERY}_output.csv"
NEO4J_QUERY_SEC=$(grep '^elapsed_sec=' "${RESULT_DIR}/neo4j/${QUERY}_time.txt" | cut -d= -f2)
echo "neo4j,${QUERY},mydb,${NEO4J_ETL_SEC},,${NEO4J_QUERY_SEC},$(TS_NOW)" >>"${SUMMARY}"

echo "Step 6e: Stop Neo4j"
docker compose -f "${REPO_ROOT}/systems/neo4j/docker-compose.yml" down

echo "Clear lakehouse data (mc rm ${MC_MYDB_PATH})"
docker exec "${MC_CONTAINER}" mc rm -r --force "${MC_MYDB_PATH}" || true

# -----------------------------------------------------------------------------
echo "======== Step 7: Summary ========"
cat "${SUMMARY}"
echo "Wrote ${SUMMARY}"
