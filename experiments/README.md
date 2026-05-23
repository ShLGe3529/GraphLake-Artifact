# Experiments

All scripts use **`set -ex`**: fail fast, print every command.

| Script | Ingest inside script | Output |
|--------|----------------------|--------|
| `exp0_filter_pushdown_demo.sh` | `run_ingest.sh partitioned-exp0` | `results/exp0/summary.csv` |
| `exp1_end_to_end.sh` | `run_ingest.sh standard` (+ neo4j export) | `results/exp1/e2e_bi16_summary.csv` (`etl_sec,startup_sec,query_sec`) |
| `exp2_loading_query.sh` | `run_ingest.sh standard` | `results/exp2/query_summary.csv` (`startup_sec`, `query_sec`) + `graphlake/puppygraph/startup_time.txt` |

No `source` of shared experiment libraries — open any script and follow top-to-bottom.

图算法实验（graph500-22）已移至 `tmp/exp3-archive/`（见根目录 README **Omitted Experiments**）。

`exp1_end_to_end.sh` calls `experiments/utils/drop_caches.sh` before each engine (needs write access to `/proc/sys/vm/drop_caches`).

## exp1 timing (`e2e_bi16_summary.csv`)

| Engine | `etl_sec` | `startup_sec` | `query_sec` |
|--------|-----------|---------------|-------------|
| **Neo4j** | Iceberg → CSV export + `neo4j-admin` import | — | `cypher-shell` BI-16 |
| **GraphLake** | — | First `gsql` schema load: GPE `Build EdgeRefBlocks takes Xms` → seconds (ActiveCol restart **not** included) | REST BI-16 |
| **PuppyGraph** | — | Blackout after `POST /schema`: CPU &lt; 600% for 3s (`dataaccess_be` PID on host); after `be.conf` 32G / 65% + BE restart | Bolt BI-16 |
| **Trino / Spark** | — | — | SQL only |

## exp2 timing (`query_summary.csv`)

| Engine | `startup_sec` | `query_sec` |
|--------|---------------|-------------|
| **GraphLake** | GPE log `Ready to build edge lists for N edge files` (poll seconds; ActiveCol restart **not** included) | REST per BI query |
| **PuppyGraph** | Blackout after `POST /schema` (same as exp1) | Bolt per BI query |

Also written: `results/exp2/graphlake/startup_time.txt`, `results/exp2/puppygraph/startup_time.txt`.

## Environment

| Variable | Default | Used by |
|----------|---------|---------|
| `GRAPHLAKE_CONTAINER` | `graphlakeproto` | exp0–exp2 GraphLake steps |
| `GRAPHLAKE_IMAGE` | `graphlake-artifact:latest` | exp1/exp2: `docker load` + `docker run` |
| `GRAPHLAKE_IMAGE_TAR` | `/ssd_root/liu3529/graphlake-artifact.tar` | exp1/exp2 image tar |
| `GRAPHLAKE_FILTER_COMMENT_HASCREATOR_PERSON` | `2010-12-01T00:00:00Z` | exp0 Scenario B: `/tmp/graphlake_filters.properties` (must include `Z` or `+00:00`) |
| `GRAPHLAKE_LOAD_TIMEOUT_SEC` | `7200` | exp0/exp1 GraphLake GPE wait |
| `PUPPYGRAPH_CONTAINER` | `puppygraph-baseline` | exp1 PuppyGraph |
| `PUPPYGRAPH_CPU_THRESHOLD` | `600.0` | exp1 PuppyGraph startup (blackout) |
| `PUPPYGRAPH_IDLE_SEC` | `3` | exp1 PuppyGraph steady-state seconds |
