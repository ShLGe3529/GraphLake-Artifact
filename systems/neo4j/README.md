# Neo4j Baseline

Uses **projection-optimized CSV** from `dataset/export_neo4j_csv.py` (column pruning for fair comparison).

## Workflow

```bash
# 1. Export CSV (Spark ingest stack)
cd dataset && ./run_ingest.sh neo4j

# 2. Offline import (BI-16 subgraph by default)
cd ../systems/neo4j
./run_import.sh bi16

# 3. Run server
docker compose up -d

# 4. Query
./run_query.sh bi-16
```

Import profiles: `bi2`, `bi5`, `bi8`, `bi13`, `bi16`, `full` — see `import/import_ldbc-*.sh`.

Expected CSV layout under `dataset/exports/neo4j/mydb_bi16/`:

- `header_nodes_*.csv`, `nodes_*/*.csv`
- `header_edges_*.csv`, `edges_*/*.csv`
