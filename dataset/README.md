# Dataset Preparation

Download LDBC SNB BI CSVs, load into Iceberg on MinIO, and export Neo4j projection CSVs.

## Iceberg naming

All tables use **`demo.mydb.<lowercase_table>`** (e.g. `demo.mydb.comment`, `demo.mydb.person_knows_person`).

| Ingest | Effect |
|--------|--------|
| `run_ingest.sh standard` | `demo.mydb.*` non-partitioned tables; **DROP + overwrite** each table |
| `run_ingest.sh partitioned` | Same `mydb`; **DROP + overwrite**; `comment` uses `months(creation_date)` partitions |
| `run_ingest.sh partitioned-exp0` | **exp0 only**: `comment`, `person`, `comment_hascreator_person`; month partition on **edge** `comment_hascreator_person` only |

**All scale factors (sf1, sf30, …) share `demo.mydb`.** After `./generate_ldbc.sh sf30`, you must re-run ingest so old SF data is replaced (default `ICEBERG_DROP_BEFORE_WRITE=true`, `ICEBERG_PURGE_ON_DROP=true`).

## Prerequisites

- Docker Compose v2
- Disk: ~30 GB (SF1), much more for SF30+
- `curl` or `wget`, `zstd`, `tar`

## Step 1 — Download LDBC SNB

[Pre-generated data sets](https://github.com/ldbc/ldbc_snb_bi/blob/main/snb-bi-pre-generated-data-sets.md)

```bash
./generate_ldbc.sh           # default sf1
./generate_ldbc.sh sf30
```

Scale is stored in `.ldbc_scale` and used by `run_ingest.sh`.

## Step 2 — Start storage and Spark

```bash
docker compose up -d
docker compose -f systems/spark/docker-compose.yml up -d
```

## Step 3 — Ingest

```bash
cd dataset
./run_ingest.sh standard
# ./run_ingest.sh partitioned-exp0   # exp0 (3 tables, edge partition)
# ./run_ingest.sh partitioned        # full mydb with comment partitions
```

## Step 4 — Neo4j export (optional)

```bash
./run_ingest.sh neo4j
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LDBC_SCALE` | `sf1` / `.ldbc_scale` | `bi-<scale>-composite-projected-fk` folder |
| `ICEBERG_CATALOG` | `demo` | Catalog name |
| `ICEBERG_NAMESPACE` | `mydb` | Database (always `mydb` for partitioned ingest too) |
| `PARTITION_GRANULARITY` | `month` | `month` or `day` for `creation_date` transforms |
| `PARTITION_TABLES` | `comment` / `comment_hascreator_person` | Iceberg table names to partition (`partitioned` vs `partitioned-exp0`) |
| `INGEST_ONLY_TYPES` | (unset) | Comma list of tables to ingest; exp0 sets `comment,person,comment_hascreator_person` |
| `GRAPHLAKE_FILTER_COMMENT` | `2010-12-01T00:00:00` | ISO timestamp for exp0 (Iceberg `timestamp` column) |
| `ICEBERG_DROP_BEFORE_WRITE` | `true` | `DROP TABLE IF EXISTS` before each table write |
| `ICEBERG_PURGE_ON_DROP` | `true` | Remove orphaned files from MinIO on DROP (set `false` if unsupported) |
