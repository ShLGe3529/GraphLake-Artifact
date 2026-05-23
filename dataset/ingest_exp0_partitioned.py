#!/usr/bin/env python3
"""exp0 ingest: comment, person, comment_hascreator_person only.

Month partitions on comment_hascreator_person only (creation_date).
GraphLake filter env: GRAPHLAKE_FILTER_COMMENT_HASCREATOR_PERSON=<ISO timestamp> (partitioned edge table).
"""

import os

os.environ.setdefault("LDBC_SCALE", "sf1")
os.environ.setdefault("ICEBERG_CATALOG", "demo")
os.environ.setdefault("ICEBERG_NAMESPACE", "mydb")
os.environ["INGEST_ONLY_TYPES"] = "comment,person,comment_hascreator_person"
os.environ["PARTITION_BY_CREATION_DATE"] = "true"
os.environ["PARTITION_TABLES"] = "comment_hascreator_person"
os.environ["PARTITION_GRANULARITY"] = "month"

_LOADER = os.path.join(os.path.dirname(__file__), "ldbc_loader.py")
with open(_LOADER, encoding="utf-8") as f:
    exec(compile(f.read(), _LOADER, "exec"), {"__name__": "__main__"})
