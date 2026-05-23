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
  --nodes=Forum="$CSV_BASE/header_nodes_Forum.csv,$CSV_BASE/nodes_Forum/.*\.csv" \
  --nodes=Person="$CSV_BASE/header_nodes_Person.csv,$CSV_BASE/nodes_Person/.*\.csv" \
  --nodes=Post="$CSV_BASE/header_nodes_Post.csv,$CSV_BASE/nodes_Post/.*\.csv" \
  --nodes=Organisation="$CSV_BASE/header_nodes_Organisation.csv,$CSV_BASE/nodes_Organisation/.*\.csv" \
  --nodes=Place="$CSV_BASE/header_nodes_Place.csv,$CSV_BASE/nodes_Place/.*\.csv" \
  --nodes=Tag="$CSV_BASE/header_nodes_Tag.csv,$CSV_BASE/nodes_Tag/.*\.csv" \
  --nodes=TagClass="$CSV_BASE/header_nodes_TagClass.csv,$CSV_BASE/nodes_TagClass/.*\.csv" \
  --relationships=HAS_CREATOR="$CSV_BASE/header_edges_comment_hascreator_person.csv,$CSV_BASE/edges_comment_hascreator_person/.*\.csv" \
  --relationships=HAS_TAG="$CSV_BASE/header_edges_comment_hastag_tag.csv,$CSV_BASE/edges_comment_hastag_tag/.*\.csv" \
  --relationships=IS_LOCATED_IN="$CSV_BASE/header_edges_comment_islocatedin_country.csv,$CSV_BASE/edges_comment_islocatedin_country/.*\.csv" \
  --relationships=REPLY_OF="$CSV_BASE/header_edges_comment_replyof_comment.csv,$CSV_BASE/edges_comment_replyof_comment/.*\.csv" \
  --relationships=REPLY_OF="$CSV_BASE/header_edges_comment_replyof_post.csv,$CSV_BASE/edges_comment_replyof_post/.*\.csv" \
  --relationships=CONTAINER_OF="$CSV_BASE/header_edges_forum_containerof_post.csv,$CSV_BASE/edges_forum_containerof_post/.*\.csv" \
  --relationships=HAS_MEMBER="$CSV_BASE/header_edges_forum_hasmember_person.csv,$CSV_BASE/edges_forum_hasmember_person/.*\.csv" \
  --relationships=HAS_MODERATOR="$CSV_BASE/header_edges_forum_hasmoderator_person.csv,$CSV_BASE/edges_forum_hasmoderator_person/.*\.csv" \
  --relationships=HAS_TAG="$CSV_BASE/header_edges_forum_hastag_tag.csv,$CSV_BASE/edges_forum_hastag_tag/.*\.csv" \
  --relationships=HAS_INTEREST="$CSV_BASE/header_edges_person_hasinterest_tag.csv,$CSV_BASE/edges_person_hasinterest_tag/.*\.csv" \
  --relationships=IS_LOCATED_IN="$CSV_BASE/header_edges_person_islocatedin_city.csv,$CSV_BASE/edges_person_islocatedin_city/.*\.csv" \
  --relationships=KNOWS="$CSV_BASE/header_edges_person_knows_person.csv,$CSV_BASE/edges_person_knows_person/.*\.csv" \
  --relationships=LIKES="$CSV_BASE/header_edges_person_likes_comment.csv,$CSV_BASE/edges_person_likes_comment/.*\.csv" \
  --relationships=LIKES="$CSV_BASE/header_edges_person_likes_post.csv,$CSV_BASE/edges_person_likes_post/.*\.csv" \
  --relationships=STUDY_AT="$CSV_BASE/header_edges_person_studyat_university.csv,$CSV_BASE/edges_person_studyat_university/.*\.csv" \
  --relationships=WORK_AT="$CSV_BASE/header_edges_person_workat_company.csv,$CSV_BASE/edges_person_workat_company/.*\.csv" \
  --relationships=HAS_CREATOR="$CSV_BASE/header_edges_post_hascreator_person.csv,$CSV_BASE/edges_post_hascreator_person/.*\.csv" \
  --relationships=HAS_TAG="$CSV_BASE/header_edges_post_hastag_tag.csv,$CSV_BASE/edges_post_hastag_tag/.*\.csv" \
  --relationships=IS_LOCATED_IN="$CSV_BASE/header_edges_post_islocatedin_country.csv,$CSV_BASE/edges_post_islocatedin_country/.*\.csv" \
  --relationships=IS_LOCATED_IN="$CSV_BASE/header_edges_organisation_islocatedin_place.csv,$CSV_BASE/edges_organisation_islocatedin_place/.*\.csv" \
  --relationships=IS_PART_OF="$CSV_BASE/header_edges_place_ispartof_place.csv,$CSV_BASE/edges_place_ispartof_place/.*\.csv" \
  --relationships=HAS_TYPE="$CSV_BASE/header_edges_tag_hastype_tagclass.csv,$CSV_BASE/edges_tag_hastype_tagclass/.*\.csv" \
  --relationships=IS_SUBCLASS_OF="$CSV_BASE/header_edges_tagclass_issubclassof_tagclass.csv,$CSV_BASE/edges_tagclass_issubclassof_tagclass/.*\.csv"

echo "✅ Import finished！"