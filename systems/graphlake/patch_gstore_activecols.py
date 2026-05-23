#!/usr/bin/env python3
"""Patch ActiveCols in gstore config.yaml (data-lake column indices per type)."""
import re
import sys

CONFIG_PATH = sys.argv[1] if len(sys.argv) > 1 else "/home/tigergraph/tigergraph/data/gstore/0/part/config.yaml"
PROFILE = sys.argv[2] if len(sys.argv) > 2 else "full"

# BI-2..BI-16 column indices (Iceberg / parquet attribute order in full LDBC schema).
ACTIVE_COLS_FULL = {
    "Comment": [1, 5],
    "Post": [1, 7],
    "Tag": [1],
    "TagClass": [1],
    "Person": [0, 1],
    "Place": [1],
    "PERSON_KNOWS_PERSON": [2],
}

# BI-16 subgraph (schema_bi16.gsql).
ACTIVE_COLS_BI16 = {
    "Comment": [1],
    "Tag": [1],
    "Person": [0],
    "COMMENT_HASTAG_TAG": [],
    "COMMENT_HASCREATOR_PERSON": [],
    "PERSON_KNOWS_PERSON": [],
}

PROFILE_MAP = {
    "full": ACTIVE_COLS_FULL,
    "bi16": ACTIVE_COLS_BI16,
}


def _fmt(cols):
    return "[" + ", ".join(str(c) for c in cols) + "]"


def _patch_activecols(text, field, name, cols):
    """Match gstore config blocks: VertexName/EdgeName then ActiveCols: [...]."""
    pattern = (
        rf"({field}:\s*{re.escape(name)}\s*\n"
        rf"(?:[ \t]+[^\n]+\n)*?"
        rf"[ \t]+ActiveCols:\s*)\[[^\]]*\]"
    )
    return re.subn(pattern, rf"\g<1>{_fmt(cols)}", text, count=1)


def patch_config(text, mapping):
    for name, cols in mapping.items():
        for field in ("VertexName", "EdgeName"):
            text, n = _patch_activecols(text, field, name, cols)
            if n:
                print(f"[INFO] {field}: {name} ActiveCols -> {_fmt(cols)}")
                break
        else:
            print(
                f"[WARN] {name!r} not found (no VertexName/EdgeName with ActiveCols)",
                file=sys.stderr,
            )
    return text


def main():
    mapping = PROFILE_MAP.get(PROFILE)
    if mapping is None:
        print(f"Unknown profile {PROFILE!r}; use: full | bi16", file=sys.stderr)
        sys.exit(1)
    with open(CONFIG_PATH, encoding="utf-8") as f:
        text = f.read()
    text = patch_config(text, mapping)
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        f.write(text)


if __name__ == "__main__":
    main()
