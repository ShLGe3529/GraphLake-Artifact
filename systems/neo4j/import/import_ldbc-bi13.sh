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
  --nodes=Place="$CSV_BASE/header_nodes_Place.csv,$CSV_BASE/nodes_Place/.*\.csv" \
  --nodes=Person="$CSV_BASE/header_nodes_Person.csv,$CSV_BASE/nodes_Person/.*\.csv" \
  --relationships=IS_PART_OF="$CSV_BASE/header_edges_place_ispartof_place.csv,$CSV_BASE/edges_place_ispartof_place/.*\.csv" \
  --relationships=IS_LOCATED_IN="$CSV_BASE/header_edges_person_islocatedin_city.csv,$CSV_BASE/edges_person_islocatedin_city/.*\.csv" \
  --relationships=HAS_CREATOR="$CSV_BASE/header_edges_comment_hascreator_person.csv,$CSV_BASE/edges_comment_hascreator_person/.*\.csv" \
  --relationships=LIKES="$CSV_BASE/header_edges_person_likes_comment.csv,$CSV_BASE/edges_person_likes_comment/.*\.csv" 

echo "✅ Import finished！"