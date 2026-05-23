#!/usr/bin/env bash
# Run exp0, exp1, exp2 in order.
set -ex

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "======== Run exp0_filter_pushdown_demo.sh ========"
bash "${REPO_ROOT}/experiments/exp0_filter_pushdown_demo.sh"

echo "======== Run exp1_end_to_end.sh ========"
bash "${REPO_ROOT}/experiments/exp1_end_to_end.sh"

echo "======== Run exp2_loading_query.sh ========"
bash "${REPO_ROOT}/experiments/exp2_loading_query.sh"

echo "======== All done. Results under ${REPO_ROOT}/experiments/results/ ========"
