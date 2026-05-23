#!/usr/bin/env bash
# Download and extract LDBC SNB BI (composite-projected-fk).
# Default scale: sf1. Other scales: sf3, sf10, sf30, sf100, ...
# Data: https://github.com/ldbc/ldbc_snb_bi/blob/main/snb-bi-pre-generated-data-sets.md
#
# Usage:
#   ./generate_ldbc.sh              # sf1 (default)
#   ./generate_ldbc.sh sf30         # scale factor 30
#   ./generate_ldbc.sh sf30 <url>   # custom download URL

set -ex

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/raw/ldbc-snb"
SCALE_FILE="${SCRIPT_DIR}/.ldbc_scale"

usage() {
  cat <<'EOF'
Usage: ./generate_ldbc.sh [scale_factor] [download_url]

  scale_factor   LDBC BI scale (default: sf1). Examples: sf1, sf3, sf10, sf30, sf100
  download_url   Optional override; default:
                 https://datasets.ldbcouncil.org/bi-pre-audit/bi-<scale>-composite-projected-fk.tar.zst

Examples:
  ./generate_ldbc.sh
  ./generate_ldbc.sh sf30

[NOTICE] SF1000+ may be split into multiple .tar.zst.NNN files; pass the first part URL
         or download manually, then extract with:
         cat bi-sf1000-composite-projected-fk.tar.zst* | tar -xv --use-compress-program=unzstd
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# Parse scale vs URL
if [[ "${1:-}" =~ ^https?:// ]]; then
  SF="sf1"
  URL="$1"
elif [[ -z "${1:-}" ]]; then
  SF="sf1"
  URL=""
elif [[ "${1:-}" =~ ^[sS][fF][0-9]+$ ]]; then
  SF="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
  URL="${2:-}"
else
  echo "Error: invalid scale '${1}'. Expected sf1, sf30, ..." >&2
  usage >&2
  exit 1
fi

DATASET_DIR="bi-${SF}-composite-projected-fk"
if [[ -z "$URL" ]]; then
  URL="https://datasets.ldbcouncil.org/bi-pre-audit/${DATASET_DIR}.tar.zst"
fi
FILENAME="$(basename "$URL")"

mkdir -p "$DATA_DIR"
cd "$DATA_DIR"

if [[ -d "$DATASET_DIR" ]]; then
  echo "Dataset already present: ${DATA_DIR}/${DATASET_DIR}"
  echo "$SF" >"$SCALE_FILE"
  echo "Recorded scale in ${SCALE_FILE} (used by run_ingest.sh)"
  exit 0
fi

echo "Scale factor: ${SF}"
echo "Downloading ${URL} ..."
if command -v curl >/dev/null 2>&1; then
  curl --silent --fail -L "$URL" -o "$FILENAME"
elif command -v wget >/dev/null 2>&1; then
  wget "$URL" -O "$FILENAME" --no-check-certificate
else
  echo "Error: install curl or wget." >&2
  exit 1
fi

echo "Decompressing ${FILENAME} ..."
if [[ "$FILENAME" == *.tar.zst ]]; then
  if command -v zstd >/dev/null 2>&1; then
    zstd -d "$FILENAME"
    tar -xf "${FILENAME%.zst}"
    rm -f "$FILENAME" "${FILENAME%.zst}"
  else
    tar -xv --use-compress-program=unzstd -f "$FILENAME"
    rm -f "$FILENAME"
  fi
else
  echo "[NOTICE] Unknown archive extension; trying tar with zstd ..." >&2
  tar -xv --use-compress-program=unzstd -f "$FILENAME" || tar -xf "$FILENAME"
fi

echo "Decompressing nested .gz under ${DATASET_DIR} (gunzip removes .gz; scoped to this scale only) ..."
GZ_COUNT=$(find "$DATASET_DIR" -name '*.gz' 2>/dev/null | wc -l)
if [ "${GZ_COUNT}" -eq 0 ]; then
  echo "No .gz files under ${DATASET_DIR}; skip."
else
  echo "Found ${GZ_COUNT} .gz files; decompressing with $(nproc) workers ..."
  # Drop .gz when matching .csv already exists (e.g. prior gunzip -k run).
  find "$DATASET_DIR" -name '*.csv.gz' 2>/dev/null | while read -r gz; do
    csv="${gz%.gz}"
    if [ -f "${csv}" ]; then
      rm -f "${gz}"
    fi
  done
  GZ_LEFT=$(find "$DATASET_DIR" -name '*.gz' 2>/dev/null | wc -l)
  if [ "${GZ_LEFT}" -gt 0 ]; then
    find "$DATASET_DIR" -name '*.gz' -print0 | xargs -0 -r -n 16 -P "$(nproc)" gunzip
  fi
fi

echo "$SF" >"$SCALE_FILE"

echo "Done."
echo "  Scale file: ${SCALE_FILE}"
echo "  CSV root:   ${DATA_DIR}/${DATASET_DIR}/graphs/csv/bi/composite-projected-fk/"
echo ""
echo "Next: export LDBC_SCALE=${SF} ./run_ingest.sh standard   # -> demo.mydb.<table>"
