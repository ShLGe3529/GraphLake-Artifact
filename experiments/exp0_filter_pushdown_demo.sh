#!/usr/bin/env bash
# exp0 — GraphLake filter pushdown (3 Iceberg tables, month partition on comment_hascreator_person).
# Scenario A: empty /tmp/graphlake_filters.properties. Scenario B: filter in that file.
set -ex

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULT_DIR="${REPO_ROOT}/experiments/results/exp0"
SUMMARY="${RESULT_DIR}/summary.csv"
GRAPHLAKE_CONTAINER="${GRAPHLAKE_CONTAINER:-graphlakeproto}"
GRAPHLAKE_IMAGE="${GRAPHLAKE_IMAGE:-shlge3529/graphlake-artifact:latest}"
# Iceberg timestamptz literal needs zone offset (e.g. Z or +00:00), not bare ISO local time.
FILTER_DATE="${GRAPHLAKE_FILTER_COMMENT_HASCREATOR_PERSON:-2010-12-01T00:00:00Z}"
LOAD_TIMEOUT_SEC="${GRAPHLAKE_LOAD_TIMEOUT_SEC:-7200}"
POLL_SEC=5
SCHEMA_GSQL="${REPO_ROOT}/systems/graphlake/conf/schema_exp0.gsql"
TG_CMD=/home/tigergraph/tigergraph/app/cmd
GRAPHLAKE_FILTERS_FILE=/tmp/graphlake_filters.properties
MC_CONTAINER="${MC_CONTAINER:-mc}"
MC_MYDB_PATH=minio/warehouse/graphcatalog/mydb

mkdir -p "${RESULT_DIR}"
echo "scenario,database,filter_env,loading_time_sec,files_loaded,timestamp" >"${SUMMARY}"

# -----------------------------------------------------------------------------
echo "======== Step 0: Check MinIO and lakehouse-net ========"
docker ps --format '{{.Names}}' | grep -x minio
docker ps --format '{{.Names}}' | grep -x "${MC_CONTAINER}"
docker network inspect lakehouse-net >/dev/null

# -----------------------------------------------------------------------------
echo "======== Step 1: exp0 Iceberg ingest (comment, person, comment_hascreator_person) ========"
echo "         Month partition on comment_hascreator_person only."
cd "${REPO_ROOT}/dataset"
./generate_ldbc.sh
docker compose -f "${REPO_ROOT}/systems/spark/docker-compose.yml" up -d
sleep 10
./run_ingest.sh partitioned-exp0
cd "${REPO_ROOT}"

# -----------------------------------------------------------------------------
echo "======== Step 2: Scenario A — no manifest filter ========"
echo "Step 2a: docker run ${GRAPHLAKE_CONTAINER} (no filter)"
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
echo "Step 2a2: clear ${GRAPHLAKE_FILTERS_FILE} (no filter)"
docker exec "${GRAPHLAKE_CONTAINER}" bash -c ": > ${GRAPHLAKE_FILTERS_FILE}"
echo "gadmin start all, then wait 30s for TigerGraph"
docker exec -u tigergraph "${GRAPHLAKE_CONTAINER}" "${TG_CMD}/gadmin" start all
sleep 30

echo "Step 2b: Install exp0 schema (Comment, Person, COMMENT_HASCREATOR_PERSON)"
START_A=$(date +%s)
docker cp "${SCHEMA_GSQL}" "${GRAPHLAKE_CONTAINER}:/tmp/schema_exp0.gsql"
docker exec -u tigergraph "${GRAPHLAKE_CONTAINER}" \
  "${TG_CMD}/gsql" "/tmp/schema_exp0.gsql"

echo "Step 2c: Wait for GPE log 'Ready to build edge lists for <N> edge files'"
ELAPSED_A=0
FILES_A=NA
while [ "${ELAPSED_A}" -lt "${LOAD_TIMEOUT_SEC}" ]; do
  LOG_LINE=$(docker exec "${GRAPHLAKE_CONTAINER}" bash -c \
    'grep "Ready to build edge lists for" /home/tigergraph/tigergraph/log/gpe/log.INFO 2>/dev/null | grep "edge files" | tail -1' || true)
  if [ -n "${LOG_LINE}" ]; then
    FILES_A=$(echo "${LOG_LINE}" | sed -n 's/.*for \([0-9]*\) edge files.*/\1/p')
    break
  fi
  sleep "${POLL_SEC}"
  ELAPSED_A=$((ELAPSED_A + POLL_SEC))
done
END_A=$(date +%s)
LOAD_SEC_A=$((END_A - START_A))
echo "Scenario A: loading_time_sec=${LOAD_SEC_A} files_loaded=${FILES_A}"
echo "A,mydb,none,${LOAD_SEC_A},${FILES_A},$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"${SUMMARY}"
echo "Step 3d: clear lakehouse data (mc rm ${MC_MYDB_PATH})"
docker exec "${MC_CONTAINER}" mc rm -r --force "${MC_MYDB_PATH}"
docker stop "${GRAPHLAKE_CONTAINER}"

# -----------------------------------------------------------------------------
echo "======== Step 3: Scenario B — GRAPHLAKE_FILTER_COMMENT_HASCREATOR_PERSON=${FILTER_DATE} ========"
echo "Step 3a: docker run ${GRAPHLAKE_CONTAINER}"
docker rm -f "${GRAPHLAKE_CONTAINER}"
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
echo "Step 3a2: write ${GRAPHLAKE_FILTERS_FILE}"
docker exec "${GRAPHLAKE_CONTAINER}" bash -c \
  "echo 'GRAPHLAKE_FILTER_COMMENT_HASCREATOR_PERSON=${FILTER_DATE}' > ${GRAPHLAKE_FILTERS_FILE}"
echo "gadmin start all, then wait 30s for TigerGraph"
docker exec -u tigergraph "${GRAPHLAKE_CONTAINER}" "${TG_CMD}/gadmin" start all
sleep 30

echo "Step 3b: Install exp0 schema again"
START_B=$(date +%s)
docker cp "${SCHEMA_GSQL}" "${GRAPHLAKE_CONTAINER}:/tmp/schema_exp0.gsql"
docker exec -u tigergraph "${GRAPHLAKE_CONTAINER}" \
  "${TG_CMD}/gsql" "/tmp/schema_exp0.gsql"

echo "Step 3c: Wait for GPE log 'Ready to build edge lists for <N> edge files'"
ELAPSED_B=0
FILES_B=NA
while [ "${ELAPSED_B}" -lt "${LOAD_TIMEOUT_SEC}" ]; do
  LOG_LINE=$(docker exec "${GRAPHLAKE_CONTAINER}" bash -c \
    'grep "Ready to build edge lists for" /home/tigergraph/tigergraph/log/gpe/log.INFO 2>/dev/null | grep "edge files" | tail -1' || true)
  if [ -n "${LOG_LINE}" ]; then
    FILES_B=$(echo "${LOG_LINE}" | sed -n 's/.*for \([0-9]*\) edge files.*/\1/p')
    break
  fi
  sleep "${POLL_SEC}"
  ELAPSED_B=$((ELAPSED_B + POLL_SEC))
done
END_B=$(date +%s)
LOAD_SEC_B=$((END_B - START_B))
echo "Scenario B: loading_time_sec=${LOAD_SEC_B} files_loaded=${FILES_B}"
echo "B,mydb,GRAPHLAKE_FILTER_COMMENT_HASCREATOR_PERSON=${FILTER_DATE},${LOAD_SEC_B},${FILES_B},$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"${SUMMARY}"
echo "Step 4d: clear lakehouse data (mc rm ${MC_MYDB_PATH})"
docker exec "${MC_CONTAINER}" mc rm -r --force "${MC_MYDB_PATH}"
echo "Step 4e: stop ${GRAPHLAKE_CONTAINER}"
docker stop "${GRAPHLAKE_CONTAINER}"

echo "Clear lakehouse data (mc rm ${MC_MYDB_PATH})"
docker exec "${MC_CONTAINER}" mc rm -r --force "${MC_MYDB_PATH}" || true

# -----------------------------------------------------------------------------
echo "======== Step 4: Results ========"
cat "${SUMMARY}"
echo "Wrote ${SUMMARY}"
