# Compute Engines (`systems/`)

Each engine is isolated: own `docker-compose.yml`, joins **`lakehouse-net`**, and exposes **`run_query.sh <namespace> <query_name>`** (Neo4j: `run_query.sh <query_name>` after import).

Shared BI query set: **bi-2, bi-5, bi-8, bi-13, bi-16**.

| Engine | Directory | Container | Start |
|--------|-----------|-----------|-------|
| Spark SQL | `spark/` | `spark-iceberg` | `docker compose up -d` (+ root MinIO) |
| Trino | `trino/` | `trino-baseline` | `docker compose up -d` |
| PuppyGraph | `puppygraph/` | `puppygraph-baseline` | `docker compose up -d` then `load_schema.sh` |
| Neo4j | `neo4j/` | `neo4j-baseline` | `run_import.sh bi16` then `docker compose up -d` |
| GraphLake | `graphlake/` | `graphlake-baseline` | See `graphlake/README.md` |

## Namespace convention

| Database | Use |
|----------|-----|
| `mydb` | All Iceberg tables (`demo.mydb.*`). GraphLake hardcodes this name. |

| Profile | PuppyGraph | GraphLake |
|---------|------------|-----------|
| `bi16` | `schema_bi16.json` | `conf/schema_bi16.gsql` |
| `full` | `schema.json` | `conf/schema_full.gsql` |

Filter pushdown (**exp0**): partitioned ingest + `GRAPHLAKE_FILTER` on `demo.mydb`.

## Example

```bash
# From repo root — storage must be up
docker compose up -d

# Trino
docker compose -f systems/trino/docker-compose.yml up -d
systems/trino/run_query.sh mydb bi-16

# Tear down when done (ephemeral)
docker compose -f systems/trino/docker-compose.yml down
```

## Cold cache

Before timed runs:

```bash
sudo experiments/utils/drop_caches.sh
```

Stop other engines first so page cache reflects a single system.
