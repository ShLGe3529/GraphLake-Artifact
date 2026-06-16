# GraphLake

Zero-ETL queries over Iceberg on MinIO. Lake queries live under `queries/`; schemas under `conf/`.

## Image

The image tag is shlge3529/graphlake-artifact/latest

## Start (artifact image / exp1–exp2)

The image is automatically downloaded in `docker run`

After lakehouse load, set `ActiveCol` in `~/tigergraph/data/gstore/0/part/config.yaml`:

```bash
python3 systems/graphlake/patch_gstore_activecols.py <config.yaml> bi16   # exp1
python3 systems/graphlake/patch_gstore_activecols.py <config.yaml> full  # exp2
```

Profiles: **bi16** = Comment[1], Tag[1], Person[0], …; **full** = Comment[1,5], Post[1,7], Tag[1], TagClass[1], Person[0,1], Place[1], PERSON_KNOWS_PERSON[2].

## Start (compose baseline)

```bash
docker compose -f systems/graphlake/docker-compose.yml up -d
systems/graphlake/install_schema.sh full    # or bi16
systems/graphlake/install_queries.sh all  # or bi-16
```

## Iceberg database

GraphLake hardcodes Iceberg database **`mydb`** → tables `demo.mydb.<name>`.

## Manifest filter pushdown (Java)

Per-table environment variables on the **GraphLake container**:

```bash
export GRAPHLAKE_FILTER_COMMENT=2010-12-01T00:00:00
# creation_date is Iceberg timestamp; Java: greaterThanOrEqual("creation_date", <String>)
# ISO-8601: YYYY-MM-DDTHH:MM:SS or YYYY-MM-DD (midnight). Month partitions: use YYYY-MM-01T00:00:00
# unset or empty -> read all data files
```

Pattern: `GRAPHLAKE_FILTER_<UPPERCASE_TABLE>` where `<UPPERCASE_TABLE>` is the simple table name (`COMMENT` for `demo.mydb.comment`).

## Run a query (manual)

See `experiments/exp1_end_to_end.sh` for inline `curl` examples, or:

```bash
GRAPHLAKE_CONTAINER=graphlakeproto systems/graphlake/run_query.sh mydb bi-2
```

REST: `http://localhost:14240/restpp/query/ldbc_snb/bi2?...`

## Files loaded (from log)

```bash
docker exec graphlake-baseline \
  grep "DataLakeTest: Ready to build edge lists for" \
  /home/tigergraph/tigergraph/log/gpe/log.INFO | tail -1
```

The number after `for` is the count of files loaded (used in exp0).
