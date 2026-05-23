#!/usr/bin/env bash
# Run PuppyGraph Cypher query (Bolt).
# Usage: ./run_query.sh <namespace> <query_name>
# [NOTICE] pip install -r requirements.txt; schema is POSTed on each run (see load_schema.sh).
set -ex

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -eq 1 ]]; then
  NAMESPACE="mydb"
  QUERY="$1"
elif [[ $# -eq 2 ]]; then
  NAMESPACE="$1"
  QUERY="$2"
else
  echo "Usage: $0 [mydb] <bi-2|bi-5|bi-8|bi-13|bi-16>" >&2
  exit 1
fi

export RESULT_DIR="${RESULT_DIR:-${SCRIPT_DIR}/results/${NAMESPACE}}"

"${SCRIPT_DIR}/load_schema.sh"

if ! python3 -c "import neo4j" 2>/dev/null; then
  echo "Install neo4j driver: pip install neo4j" >&2
  exit 1
fi

python3 "${SCRIPT_DIR}/run_cypher.py" "$QUERY"
