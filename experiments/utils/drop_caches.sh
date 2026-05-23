#!/usr/bin/env bash
# Drop Linux page cache (requires write access to /proc/sys/vm/drop_caches).
set -ex

sync
echo 3 > /proc/sys/vm/drop_caches
echo "Page cache dropped."
