#!/usr/bin/env bash
# Manual BI query via REST. Usage: ./run_query.sh <mydb> <bi-2|bi-5|bi-8|bi-13|bi-16>
# Experiment scripts use curl directly; this is an optional helper.
set -ex

CONTAINER="${GRAPHLAKE_CONTAINER:-graphlakeproto}"
HOST="${GRAPHLAKE_REST_HOST:-http://127.0.0.1:14240}"
GRAPH="${GRAPHLAKE_GRAPH:-ldbc_snb}"
RESULT_DIR="${RESULT_DIR:-$(cd "$(dirname "$0")" && pwd)/results/mydb}"
QUERY="${2:?}"
mkdir -p "${RESULT_DIR}"

case "$QUERY" in
  bi-2)  URL="${HOST}/restpp/query/${GRAPH}/bi2?date=2010-12-25&tagClass=Person" ;;
  bi-5)  URL="${HOST}/restpp/query/${GRAPH}/bi5?tag=Augustine_of_Hippo" ;;
  bi-8)  URL="${HOST}/restpp/query/${GRAPH}/bi8?tag=Muammar_Gaddafi&startDate=2011-1-1&endDate=2012-12-25" ;;
  bi-13) URL="${HOST}/restpp/query/${GRAPH}/bi13?country=Brazil&endDate=2011-12-25" ;;
  bi-16) URL="${HOST}/restpp/query/${GRAPH}/bi16?tagA=Adolf_Hitler&dateA=2012-05-08&tagB=Hamid_Karzai&dateB=2012-05-12&maxKnowsLimit=4" ;;
  *) echo "Unknown query: $QUERY" >&2; exit 1 ;;
esac

/usr/bin/time -f 'elapsed_sec=%e' -o "${RESULT_DIR}/${QUERY}_time.txt" \
  curl -sf -H "GSQL-TIMEOUT:3600000" "${URL}" -o "${RESULT_DIR}/${QUERY}_result.json"
echo "Wrote ${RESULT_DIR}/${QUERY}_time.txt"
