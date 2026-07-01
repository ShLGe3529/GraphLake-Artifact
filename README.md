# GraphLake Artifact

Reproducibility artifact for **GraphLake** over Iceberg on MinIO. It is recommended to run on a single machine with larger than **64 GB RAM**.

Due to proprietary licensing, the GraphLake runtime is provided as a Docker image shlge3529/graphlake-artifact:latest, and TigerGraph runtime is not included in this artifact.


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

## Step 2 — LDBC download + Spark (once)

```bash
cd dataset
./generate_ldbc.sh
docker compose -f ../systems/spark/docker-compose.yml up -d
cd ..
```

## Step 3 — Experiments

| Script | What it does |
|--------|----------------|
| `experiments/exp0_filter_pushdown_demo.sh` | Demonstrate that GraphLake maps a graph on a constrained partition using **month** filter on `comment_hascreator_person`. The result is verified because GraphLake loads less files compared to an null filter case.|
| `experiments/exp1_end_to_end.sh` | Demonstrate that GraphLake has less end-to-end execution time (cold run) compared with other systems. The results are verified by calculating end-to-end execution time of 5 systems (GraphLake, PuppyGraph, Trino, Spark, Neo4j) on BI-16. TigerGraph is omitted here due to proprietary licensing. |
| `experiments/exp2_loading_query.sh` | Demonstrate that GraphLake has both lower startup time and query time compared to PuppyGraph. The results are verified by comparing startup time and query time on BI-2/5/8/13/16.|
| `experiments/run_all.sh` | exp0 → exp1 → exp2. |

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

This artifact provides the execution scripts to evaluate the core design of GraphLake.

The provided scripts run a complete validation loop consisting of three core experiments:
* **Exp0 (Filter Pushdown):** Validate the feasibility of leveraging Iceberg metadata for partition pruning during dynamic graph construction.
* **Exp1 (End-to-End Time):** Measures end-to-end latency using LDBC SNB BI-16 against other systems.
* **Exp2 (Loading-Query Time):** Compares the startup and query time of GraphLake against PuppyGraph.

### Omitted Experiments
The graph algorithm (Graph500 Scale 22) and multi-node scalability benchmarks evaluated in the paper are omitted from this single-node Docker artifact because Exp0 through Exp2 are sufficient to validate the core technical claims and architecture of GraphLake presented in the paper.