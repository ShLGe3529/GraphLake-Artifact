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
  --nodes=Person="$CSV_BASE/header_nodes_Person.csv,$CSV_BASE/nodes_Person/.*\.csv" \
  --relationships=HAS_CREATOR="$CSV_BASE/header_edges_comment_hascreator_person.csv,$CSV_BASE/edges_comment_hascreator_person/.*\.csv" \
  --relationships=HAS_TAG="$CSV_BASE/header_edges_comment_hastag_tag.csv,$CSV_BASE/edges_comment_hastag_tag/.*\.csv" \
  --relationships=REPLY_OF="$CSV_BASE/header_edges_comment_replyof_comment.csv,$CSV_BASE/edges_comment_replyof_comment/.*\.csv" \
  --relationships=LIKES="$CSV_BASE/header_edges_person_likes_comment.csv,$CSV_BASE/edges_person_likes_comment/.*\.csv" 

echo "✅ Import finished！"