#!/bin/bash

# CSV path inside importer container
CSV_BASE="${NEO4J_CSV_BASE:-/import/csv}"

echo "🚀 Starting offline LDBC import into Neo4j database (neo4j)..."

# # Full import
# --overwrite-destination=true: overwrite if partial import left data
# --skip-bad-relationships=true & --skip-duplicate-nodes=true: skip bad rows for robustness

neo4j-admin database import full neo4j \
  --overwrite-destination=true \
  --skip-bad-relationships=true \
  --skip-duplicate-nodes=true \
  --nodes=Comment="$CSV_BASE/header_nodes_Comment.csv,$CSV_BASE/nodes_Comment/.*\.csv" \
  --nodes=Tag="$CSV_BASE/header_nodes_Tag.csv,$CSV_BASE/nodes_Tag/.*\.csv" \
  --nodes=TagClass="$CSV_BASE/header_nodes_TagClass.csv,$CSV_BASE/nodes_TagClass/.*\.csv" \
  --relationships=HAS_TAG="$CSV_BASE/header_edges_comment_hastag_tag.csv,$CSV_BASE/edges_comment_hastag_tag/.*\.csv" \
  --relationships=HAS_TYPE="$CSV_BASE/header_edges_tag_hastype_tagclass.csv,$CSV_BASE/edges_tag_hastype_tagclass/.*\.csv" 

echo "✅ Import finished！"