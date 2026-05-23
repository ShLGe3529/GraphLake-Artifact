#!/usr/bin/env bash
# Install GSQL queries. Usage: ./install_queries.sh [all|bi-16|bi-2|...]
set -ex

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER="${GRAPHLAKE_CONTAINER:-graphlakeproto}"
GRAPH="${GRAPHLAKE_GRAPH:-ldbc_snb}"
SCOPE="${1:-all}"

docker ps --format '{{.Names}}' | grep -x "${CONTAINER}"

if [ "$SCOPE" = "all" ]; then
  for f in "${SCRIPT_DIR}"/queries/bi-*.gsql; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    echo "Installing ${base}"
    docker cp "$f" "${CONTAINER}:/tmp/${base}"
    docker exec -u tigergraph "${CONTAINER}" gsql -g "${GRAPH}" "/tmp/${base}"
  done
else
  q="$SCOPE"
  [ "$q" = "bi16" ] && q="bi-16"
  [ "${q#bi-}" = "$q" ] && q="bi-${q#bi-}"
  f="${SCRIPT_DIR}/queries/${q}.gsql"
  docker cp "$f" "${CONTAINER}:/tmp/$(basename "$f")"
  docker exec -u tigergraph "${CONTAINER}" gsql -g "${GRAPH}" "/tmp/$(basename "$f")"
fi
echo "Query install done: ${SCOPE}"
