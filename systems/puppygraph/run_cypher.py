#!/usr/bin/env python3
"""Execute one PuppyGraph Cypher query via Bolt (adapted from puppygraph/scripts/run_single_query.py)."""

import json
import os
import sys
import time
from pathlib import Path

from neo4j import GraphDatabase

DEFAULT_PARAMS = {
    "bi-2": {"date": "2010-12-25", "tagClass": "Person"},
    "bi-5": {"tag": "Augustine_of_Hippo"},
    "bi-8": {
        "tag": "Muammar_Gaddafi",
        "startDate": "2011-1-1",
        "endDate": "2012-12-25",
    },
    "bi-13": {"country": "Brazil", "endDate": "2011-12-25"},
    "bi-16": {
        "tagA": "Adolf_Hitler",
        "dateA": "2012-05-08",
        "tagB": "Hamid_Karzai",
        "dateB": "2012-05-12",
        "maxKnowsLimit": 4,
    },
}


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <bi-2|bi-5|...>", file=sys.stderr)
        return 1

    query_name = sys.argv[1]
    script_dir = Path(__file__).resolve().parent
    query_file = script_dir / "queries" / f"{query_name}.cypher"
    if not query_file.is_file():
        print(f"Query file not found: {query_file}", file=sys.stderr)
        return 1

    uri = os.environ.get("PUPPYGRAPH_BOLT_URI", "bolt://localhost:7687")
    user = os.environ.get("PUPPYGRAPH_USER", "puppygraph")
    password = os.environ.get("PUPPYGRAPH_PASSWORD", "puppygraph123")
    params = DEFAULT_PARAMS.get(query_name, {})

    with open(query_file, encoding="utf-8") as f:
        cypher = f.read()

    driver = GraphDatabase.driver(uri, auth=(user, password))
    start = time.time()
    with driver.session() as session:
        result = session.run(cypher, params)
        rows = [record.data() for record in result]
    elapsed = time.time() - start
    driver.close()

    out_dir = Path(os.environ.get("RESULT_DIR", script_dir / "results"))
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / f"{query_name}_output.json").write_text(
        json.dumps(rows, indent=2, default=str), encoding="utf-8"
    )
    (out_dir / f"{query_name}_time.txt").write_text(
        f"elapsed_sec={elapsed:.3f}\n", encoding="utf-8"
    )
    print(f"OK {query_name} elapsed_sec={elapsed:.3f} rows={len(rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
