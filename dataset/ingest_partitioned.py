#!/usr/bin/env python3
"""Re-load into demo.mydb.<table> with comment partitioned by month(creation_date) (exp0).

Same overwrite policy as standard ingest (DROP + createOrReplace per table).
GraphLake filter env (Java String -> creation_date >= value):
  GRAPHLAKE_FILTER_COMMENT=2010-12-01T00:00:00
creation_date is Iceberg timestamp; use ISO-8601 date-time (or YYYY-MM-DD for midnight).
"""

import os

os.environ.setdefault("LDBC_SCALE", "sf1")
os.environ.setdefault("ICEBERG_CATALOG", "demo")
os.environ.setdefault("ICEBERG_NAMESPACE", "mydb")
os.environ["PARTITION_BY_CREATION_DATE"] = "true"
os.environ["PARTITION_TABLES"] = "comment"
os.environ["PARTITION_GRANULARITY"] = "month"

_LOADER = os.path.join(os.path.dirname(__file__), "ldbc_loader.py")
with open(_LOADER, encoding="utf-8") as f:
    exec(compile(f.read(), _LOADER, "exec"), {"__name__": "__main__"})
