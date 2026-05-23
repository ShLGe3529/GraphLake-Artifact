#!/usr/bin/env bash
# exp2 — GraphLake vs PuppyGraph, full LDBC schema, BI-2/5/8/13/16 query latency.
set -ex

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULT_DIR="${REPO_ROOT}/experiments/results/exp2"
SUMMARY="${RESULT_DIR}/query_summary.csv"
GRAPHLAKE_CONTAINER="${GRAPHLAKE_CONTAINER:-graphlakeproto}"
GRAPHLAKE_IMAGE="${GRAPHLAKE_IMAGE:-graphlake-artifact:latest}"
GRAPHLAKE_IMAGE_TAR="${GRAPHLAKE_IMAGE_TAR:-/ssd_root/liu3529/graphlake-artifact.tar}"
TG_CMD=/home/tigergraph/tigergraph/app/cmd
GSTORE_CONFIG=/home/tigergraph/tigergraph/data/gstore/0/part/config.yaml
GRAPHLAKE_FILTERS_FILE=/tmp/graphlake_filters.properties
MC_CONTAINER="${MC_CONTAINER:-mc}"
MC_MYDB_PATH=minio/warehouse/graphcatalog/mydb
LOAD_TIMEOUT_SEC="${GRAPHLAKE_LOAD_TIMEOUT_SEC:-7200}"
POLL_SEC=5
PUPPYGRAPH_CONTAINER="${PUPPYGRAPH_CONTAINER:-puppygraph-baseline}"
PUPPYGRAPH_CPU_THRESHOLD="${PUPPYGRAPH_CPU_THRESHOLD:-600.0}"
PUPPYGRAPH_IDLE_SEC="${PUPPYGRAPH_IDLE_SEC:-3}"
DROP_CACHES="${REPO_ROOT}/experiments/utils/drop_caches.sh"
TS_NOW() { date -u +%Y-%m-%dT%H:%M:%SZ; }
drop_os_cache() {
  echo "Dropping OS page cache ..."
  "${DROP_CACHES}"
}

mkdir -p "${RESULT_DIR}"
echo "engine,query,database,startup_sec,query_sec,timestamp" >"${SUMMARY}"

echo "======== Step 0: Check storage ========"
docker ps --format '{{.Names}}' | grep -x minio
docker ps --format '{{.Names}}' | grep -x "${MC_CONTAINER}"
docker network inspect lakehouse-net >/dev/null

echo "======== Step 1: Standard Iceberg ingest ========"
cd "${REPO_ROOT}/dataset"
./generate_ldbc.sh sf30 
docker compose -f "${REPO_ROOT}/systems/spark/docker-compose.yml" up -d
sleep 10
./run_ingest.sh standard
cd "${REPO_ROOT}"

echo "======== Step 2: GraphLake — load schema, patch ActiveCol, install queries ========"
drop_os_cache
echo "Step 2a: Load image and start ${GRAPHLAKE_CONTAINER}"
docker image inspect "${GRAPHLAKE_IMAGE}" >/dev/null 2>&1 || docker load -i "${GRAPHLAKE_IMAGE_TAR}"
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

echo "Step 2b: Install full GSQL schema (no -g); startup = GPE Ready to build edge lists"
docker cp "${REPO_ROOT}/systems/graphlake/conf/schema_full.gsql" \
  "${GRAPHLAKE_CONTAINER}:/tmp/schema_full.gsql"
docker exec -u tigergraph "${GRAPHLAKE_CONTAINER}" \
  "${TG_CMD}/gsql" "/tmp/schema_full.gsql"

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

echo "Step 2d: Patch gstore ActiveCol (full BI-2..16) and restart TigerGraph"
docker cp "${REPO_ROOT}/systems/graphlake/patch_gstore_activecols.py" \
  "${GRAPHLAKE_CONTAINER}:/tmp/patch_gstore_activecols.py"
docker exec -u tigergraph "${GRAPHLAKE_CONTAINER}" \
  python3 /tmp/patch_gstore_activecols.py "${GSTORE_CONFIG}" full
sleep 10
kill -9 $(pgrep tg_dbs_gped) 2>/dev/null || true
kill -9 $(pgrep tg_dbs_gsed) 2>/dev/null || true
kill -9 $(pgrep tg_dbs_restd) 2>/dev/null || true
docker exec -u tigergraph "${GRAPHLAKE_CONTAINER}" "${TG_CMD}/gadmin" restart -y
sleep 30

echo "Step 2e: Install BI queries"
for QF in bi-2 bi-5 bi-8 bi-13 bi-16; do
  docker cp "${REPO_ROOT}/systems/graphlake/queries/${QF}.gsql" \
    "${GRAPHLAKE_CONTAINER}:/tmp/${QF}.gsql"
  docker exec -u tigergraph "${GRAPHLAKE_CONTAINER}" \
    "${TG_CMD}/gsql" -g ldbc_snb "/tmp/${QF}.gsql"
done

mkdir -p "${RESULT_DIR}/graphlake"
echo "startup_sec=${GRAPHLAKE_STARTUP_SEC}" >"${RESULT_DIR}/graphlake/startup_time.txt"

echo "======== Step 3: GraphLake / bi-2 ========"
/usr/bin/time -f 'elapsed_sec=%e' -o "${RESULT_DIR}/graphlake/bi-2_time.txt" \
  curl -sf -H "GSQL-TIMEOUT:3600000" \
  "http://127.0.0.1:14240/restpp/query/ldbc_snb/bi2?date=2010-12-25&tagClass=Person" \
  -o "${RESULT_DIR}/graphlake/bi-2_result.json"
echo "graphlake,bi-2,mydb,${GRAPHLAKE_STARTUP_SEC},$(grep '^elapsed_sec=' "${RESULT_DIR}/graphlake/bi-2_time.txt" | cut -d= -f2),$(TS_NOW)" >>"${SUMMARY}"

echo "======== Step 4: GraphLake / bi-5 ========"
/usr/bin/time -f 'elapsed_sec=%e' -o "${RESULT_DIR}/graphlake/bi-5_time.txt" \
  curl -sf -H "GSQL-TIMEOUT:3600000" \
  "http://127.0.0.1:14240/restpp/query/ldbc_snb/bi5?tag=Augustine_of_Hippo" \
  -o "${RESULT_DIR}/graphlake/bi-5_result.json"
echo "graphlake,bi-5,mydb,${GRAPHLAKE_STARTUP_SEC},$(grep '^elapsed_sec=' "${RESULT_DIR}/graphlake/bi-5_time.txt" | cut -d= -f2),$(TS_NOW)" >>"${SUMMARY}"

echo "======== Step 5: GraphLake / bi-8 ========"
/usr/bin/time -f 'elapsed_sec=%e' -o "${RESULT_DIR}/graphlake/bi-8_time.txt" \
  curl -sf -H "GSQL-TIMEOUT:3600000" \
  "http://127.0.0.1:14240/restpp/query/ldbc_snb/bi8?tag=Muammar_Gaddafi&startDate=2011-1-1&endDate=2012-12-25" \
  -o "${RESULT_DIR}/graphlake/bi-8_result.json"
echo "graphlake,bi-8,mydb,${GRAPHLAKE_STARTUP_SEC},$(grep '^elapsed_sec=' "${RESULT_DIR}/graphlake/bi-8_time.txt" | cut -d= -f2),$(TS_NOW)" >>"${SUMMARY}"

echo "======== Step 6: GraphLake / bi-13 ========"
/usr/bin/time -f 'elapsed_sec=%e' -o "${RESULT_DIR}/graphlake/bi-13_time.txt" \
  curl -sf -H "GSQL-TIMEOUT:3600000" \
  "http://127.0.0.1:14240/restpp/query/ldbc_snb/bi13?country=Brazil&endDate=2011-12-25" \
  -o "${RESULT_DIR}/graphlake/bi-13_result.json"
echo "graphlake,bi-13,mydb,${GRAPHLAKE_STARTUP_SEC},$(grep '^elapsed_sec=' "${RESULT_DIR}/graphlake/bi-13_time.txt" | cut -d= -f2),$(TS_NOW)" >>"${SUMMARY}"

echo "======== Step 7: GraphLake / bi-16 ========"
/usr/bin/time -f 'elapsed_sec=%e' -o "${RESULT_DIR}/graphlake/bi-16_time.txt" \
  curl -sf -H "GSQL-TIMEOUT:3600000" \
  "http://127.0.0.1:14240/restpp/query/ldbc_snb/bi16?tagA=Adolf_Hitler&dateA=2012-05-08&tagB=Hamid_Karzai&dateB=2012-05-12&maxKnowsLimit=4" \
  -o "${RESULT_DIR}/graphlake/bi-16_result.json"
echo "graphlake,bi-16,mydb,${GRAPHLAKE_STARTUP_SEC},$(grep '^elapsed_sec=' "${RESULT_DIR}/graphlake/bi-16_time.txt" | cut -d= -f2),$(TS_NOW)" >>"${SUMMARY}"

echo "Step 7b: clear lakehouse data and stop GraphLake"
docker exec "${MC_CONTAINER}" mc rm -r --force "${MC_MYDB_PATH}"
docker stop "${GRAPHLAKE_CONTAINER}"

echo "======== Step 8: Start PuppyGraph + full schema ========"
drop_os_cache
docker compose -f "${REPO_ROOT}/systems/puppygraph/docker-compose.yml" up -d
sleep 15

echo "Step 8b: Tune BE (datacache_mem_size=32G, mem_limit=65%) and restart BE"
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

echo "Step 8c: POST schema.json and measure startup (blackout / steady CPU)"
PUPPY_RESULT_DIR="${RESULT_DIR}/puppygraph"
mkdir -p "${PUPPY_RESULT_DIR}"
PUPPY_START=$(date +%s)
PUPPY_SCHEMA_RESP=$(
  curl -XPOST -H "content-type: application/json" \
    --data-binary @"${REPO_ROOT}/systems/puppygraph/schema.json" \
    --user puppygraph:puppygraph123 \
    http://localhost:8081/schema
)
echo "${PUPPY_SCHEMA_RESP}"
echo "${PUPPY_SCHEMA_RESP}" | grep -q '"Status":"OK"' || {
  echo "ERROR: PuppyGraph schema POST did not return Status OK" >&2
  exit 1
}
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
echo "startup_sec=${PUPPY_STARTUP_SEC}" >"${PUPPY_RESULT_DIR}/startup_time.txt"

for Q in bi-2 bi-5 bi-8 bi-13 bi-16; do
  echo "======== PuppyGraph / ${Q} ========"
  if RESULT_DIR="${PUPPY_RESULT_DIR}" /usr/bin/time -f 'elapsed_sec=%e' \
    -o "${PUPPY_RESULT_DIR}/${Q}_time.txt" \
    python3 "${REPO_ROOT}/systems/puppygraph/run_cypher.py" "${Q}"; then
    PUPPY_QUERY_SEC=$(grep '^elapsed_sec=' "${PUPPY_RESULT_DIR}/${Q}_time.txt" | cut -d= -f2)
  else
    echo "WARNING: PuppyGraph ${Q} failed; recording query_sec=fail" >&2
    PUPPY_QUERY_SEC=fail
  fi
  echo "puppygraph,${Q},mydb,${PUPPY_STARTUP_SEC},${PUPPY_QUERY_SEC},$(TS_NOW)" >>"${SUMMARY}"
done

echo "======== Step 14: Stop PuppyGraph ========"
docker compose -f "${REPO_ROOT}/systems/puppygraph/docker-compose.yml" down

echo "Clear lakehouse data (mc rm ${MC_MYDB_PATH})"
docker exec "${MC_CONTAINER}" mc rm -r --force "${MC_MYDB_PATH}" || true

echo "======== Step 15: Summary ========"
cat "${SUMMARY}"
echo "Wrote ${SUMMARY}"
echo "GraphLake startup: ${RESULT_DIR}/graphlake/startup_time.txt"
echo "PuppyGraph startup: ${PUPPY_RESULT_DIR}/startup_time.txt"
