#!/usr/bin/env python3
"""Load LDBC SNB CSV into Iceberg demo.mydb.<table> (standard, non-partitioned).

Each table is dropped and recreated (overwrite). Re-run after changing LDBC_SCALE
because every scale factor uses the same database name mydb.
"""

import os

os.environ.setdefault("LDBC_SCALE", "sf1")
os.environ.setdefault("ICEBERG_CATALOG", "demo")
os.environ.setdefault("ICEBERG_NAMESPACE", "mydb")
os.environ["PARTITION_BY_CREATION_DATE"] = "false"

_LOADER = os.path.join(os.path.dirname(__file__), "ldbc_loader.py")
with open(_LOADER, encoding="utf-8") as f:
    exec(compile(f.read(), _LOADER, "exec"), {"__name__": "__main__"})
