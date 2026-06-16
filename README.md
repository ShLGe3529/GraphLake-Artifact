# GraphLake Artifact

Reproducibility package for **GraphLake** over Iceberg on MinIO. Single machine, Docker, **64 GB RAM** recommended.

**Design:** experiment scripts are **flat bash** with `set -ex` — every step is an explicit `echo` + `docker` / `docker compose` command you can copy to a terminal.

## Layout

| Path | Role |
|------|------|
| `docker-compose.yml` | MinIO + `lakehouse-net` |
| `dataset/` | LDBC download + Iceberg ingest |
| `systems/` | Engine compose files, SQL/Cypher/GSQL queries (optional helpers) |
| `experiments/` | **exp0–exp2** main scripts (run these) |

## Step 1 — Storage

```bash
cd /path/to/GraphLake-Artifact
docker compose up -d
```

MinIO: http://localhost:9001 (`admin` / `password`), S3 API http://localhost:19000

## Step 2 — LDBC download + Spark (once)

```bash
cd dataset
./generate_ldbc.sh
docker compose -f ../systems/spark/docker-compose.yml up -d
cd ..
```

Each experiment script runs its own **ingest** (`run_ingest.sh standard` or `partitioned`) when you execute it.

## Step 3 — Experiments

| Script | What it does |
|--------|----------------|
| `experiments/exp0_filter_pushdown_demo.sh` | GraphLake load only; 3 tables; **month** partition on `comment_hascreator_person` only |
| `experiments/exp1_end_to_end.sh` | BI-16 on GraphLake, PuppyGraph, Trino, Spark, Neo4j |
| `experiments/exp2_loading_query.sh` | BI-2/5/8/13/16 on GraphLake + PuppyGraph |
| `experiments/run_all.sh` | exp0 → exp1 → exp2 |

```bash
# Example (use sudo if needed)
sudo bash experiments/exp0_filter_pushdown_demo.sh
```

Results: `experiments/results/exp0|exp1|exp2/`

If there is a license issue for GraphLake execution, please run
`docker pull shlge3529/graphlake-artifact:latest` to manually refresh the docker image.

## Requirements

Linux, Docker Compose v2, `curl`, `zstd`, `tar`, Python 3 + `neo4j` pip package (PuppyGraph).

## Scope of Reproducibility

This artifact provides the source code and execution scripts to evaluate the core design of GraphLake: **Zero-ETL graph execution** and **partition-aware filter pushdown** for **ephemeral BI workloads**. 

The provided scripts run a complete validation loop consisting of three core experiments:
* **Exp0 (Filter Pushdown):** Evaluates the efficiency of leveraging Iceberg metadata for partition pruning during dynamic graph construction.
* **Exp1 (End-to-End Time):** Measures end-to-end latency on the dynamically constructed topologies using LDBC SNB BI-16.
* **Exp2 (Loading-Query Time):** Compares the startup and query time of GraphLake against baseline systems.

### Omitted Experiments
The global graph algorithms (Graph500 Scale 22) and multi-node scalability benchmarks evaluated in the paper are omitted from this single-node Docker artifact because Exp0 through Exp2 are sufficient to validate the core technical claims and the Zero-ETL architecture of GraphLake presented in the paper.