#!/usr/bin/env bash
# Run a LDBC BI Cypher query inside neo4j-baseline.
# Usage: ./run_query.sh [_namespace] <query_name>
#   query_name: bi-2 | bi-5 | bi-8 | bi-13 | bi-16  (namespace ignored after import)
set -ex

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER="${NEO4J_CONTAINER:-neo4j-baseline}"
RESULT_DIR="${RESULT_DIR:-${SCRIPT_DIR}/results}"
mkdir -p "$RESULT_DIR"

if [[ $# -eq 2 ]]; then
  QUERY="$2"
elif [[ $# -eq 1 ]]; then
  QUERY="$1"
else
  echo "Usage: $0 [_namespace] <bi-2|bi-5|bi-8|bi-13|bi-16>" >&2
  exit 1
fi

CYPHER_FILE="/query/${QUERY}.cypher"
OUT="${RESULT_DIR}/${QUERY}_output.csv"
TIME="${RESULT_DIR}/${QUERY}_time.txt"

declare -a PARAMS=()
case "$QUERY" in
  bi-2)
    PARAMS=(--param "date => datetime('2010-12-25')" --param "tagClass => 'Person'") ;;
  bi-5)
    PARAMS=(--param "tag => 'Augustine_of_Hippo'") ;;
  bi-8)
    PARAMS=(--param "tag => 'Muammar_Gaddafi'"
            --param "startDate => datetime('2011-1-1')"
            --param "endDate => datetime('2012-12-25')") ;;
  bi-13)
    PARAMS=(--param "country => 'Brazil'"
            --param "endDate => datetime('2011-12-25')") ;;
  bi-16)
    PARAMS=(--param "tagA => 'Adolf_Hitler'"
            --param "dateA => datetime('2012-05-08')"
            --param "tagB => 'Hamid_Karzai'"
            --param "dateB => datetime('2012-05-12')"
            --param "maxKnowsLimit => 4") ;;
  *)
    echo "Unknown query: ${QUERY}" >&2
    exit 1
    ;;
esac

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "Container ${CONTAINER} not running." >&2
  exit 1
fi

echo "Running ${QUERY} ..."
/usr/bin/time -f 'elapsed_sec=%e' -o "$TIME" \
  docker exec -i "$CONTAINER" \
    cypher-shell -u neo4j -p password \
      -f "$CYPHER_FILE" \
      "${PARAMS[@]}" \
      --format plain \
  > "$OUT"

echo "Wrote ${OUT} and ${TIME}"
