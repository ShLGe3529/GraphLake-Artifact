from pyspark.sql import SparkSession
from pyspark.sql.types import StructType, StructField, StringType, IntegerType, TimestampType, LongType
from pyspark.sql.functions import days, months
import os

# Artifact configuration (override via environment variables)
LDBC_SCALE = os.environ.get("LDBC_SCALE", "sf1")
ICEBERG_CATALOG = os.environ.get("ICEBERG_CATALOG", "demo")
ICEBERG_NAMESPACE = os.environ.get("ICEBERG_NAMESPACE", "mydb")
LDBC_DATA_ROOT = os.environ.get("LDBC_DATA_ROOT", "/data/dataset/raw/ldbc-snb")
INGEST_LOG = os.environ.get("INGEST_LOG", f"/data/dataset/logs/{ICEBERG_NAMESPACE}_ingest.log")
PARTITION_BY_CREATION_DATE = os.environ.get("PARTITION_BY_CREATION_DATE", "false").lower() in (
    "1", "true", "yes"
)
# Iceberg table names are lowercase; loader loop keys use LDBC camelCase (e.g. comment_hasCreator_person).
_ICEBERG_TO_TYPE = {
    "comment_hascreator_person": "comment_hasCreator_person",
}


def _resolve_type_key(name: str) -> str:
    key = name.strip()
    return _ICEBERG_TO_TYPE.get(key.lower(), key)


PARTITION_TABLES = {
    _resolve_type_key(t)
    for t in os.environ.get("PARTITION_TABLES", "comment").split(",")
    if t.strip()
}
# day | month — partitioned ingest (exp0) uses month(creation_date) by default.
PARTITION_GRANULARITY = os.environ.get("PARTITION_GRANULARITY", "day").lower()
REPARTITION_COUNT = int(os.environ.get("REPARTITION_COUNT", "32"))
# Always drop existing tables before write: all SF share demo.mydb (standard + partitioned ingest).
DROP_BEFORE_WRITE = os.environ.get("ICEBERG_DROP_BEFORE_WRITE", "true").lower() in (
    "1", "true", "yes"
)
PURGE_ON_DROP = os.environ.get("ICEBERG_PURGE_ON_DROP", "true").lower() in (
    "1", "true", "yes"
)

sf_scale = LDBC_SCALE
csv_dataset_root = (
    f"{LDBC_DATA_ROOT}/bi-{sf_scale}-composite-projected-fk/graphs/csv/bi/composite-projected-fk"
)
os.makedirs(os.path.dirname(INGEST_LOG), exist_ok=True)

_ingest_only_raw = os.environ.get("INGEST_ONLY_TYPES", "").strip()
INGEST_ONLY_TYPES = (
    {_resolve_type_key(t) for t in _ingest_only_raw.split(",") if t.strip()}
    if _ingest_only_raw
    else None
)

print(
    f"[INFO] Ingest LDBC_SCALE={sf_scale} -> {ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.* "
    f"(partitioned={PARTITION_BY_CREATION_DATE}, granularity={PARTITION_GRANULARITY})"
)
if INGEST_ONLY_TYPES:
    print(f"[INFO] INGEST_ONLY_TYPES={sorted(INGEST_ONLY_TYPES)}")
if PARTITION_BY_CREATION_DATE:
    print(f"[INFO] PARTITION_TABLES={sorted(PARTITION_TABLES)}")
print(
    f"[INFO] ICEBERG_DROP_BEFORE_WRITE={DROP_BEFORE_WRITE} "
    f"(each table is DROP + createOrReplace; same mydb for every SF)"
)
if PURGE_ON_DROP:
    print("[INFO] ICEBERG_PURGE_ON_DROP=true — old data files removed from object storage")

# spark-submit does not inject a global `spark` (unlike pyspark shell).
spark = SparkSession.builder.appName(
    f"LDBC_Ingest_{ICEBERG_NAMESPACE}_{sf_scale}"
).getOrCreate()

with open(INGEST_LOG, "w", encoding="utf-8") as _log:
    _log.write(
        f"Ingest started: scale={sf_scale} namespace={ICEBERG_NAMESPACE} "
        f"partitioned={PARTITION_BY_CREATION_DATE} drop_before_write={DROP_BEFORE_WRITE}\n"
    )

#================================Comment Node & Edges=======================
# schema for comment
comment_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),
  StructField("id", LongType(), True),
  StructField("location_ip", StringType(), True),
  StructField("browser_used", StringType(), True),
  StructField("content", StringType(), True),
  StructField("length", LongType(), True)
])

comment_schema = StructType([
  StructField("id", LongType(), True),
  StructField("creation_date", TimestampType(), True),
  StructField("location_ip", StringType(), True),
  StructField("browser_used", StringType(), True),
  StructField("content", StringType(), True),
  StructField("length", LongType(), True)
])
comment_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Comment/"

# schema for comment has creator
comment_hasCreator_person_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),   # TIMESTAMP
  StructField("comment_id", LongType(), True),        # LONG
  StructField("person_id", LongType(), True)          # LONG
])

comment_hasCreator_person_schema = StructType([
  StructField("comment_id", LongType(), True),        # LONG
  StructField("person_id", LongType(), True),          # LONG
  StructField("creation_date", TimestampType(), True)   # TIMESTAMP
])
comment_hasCreator_person_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Comment_hasCreator_Person/"

# schema for comment has tag creationDate|CommentId|TagId
comment_hasTag_tag_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),   # TIMESTAMP
  StructField("comment_id", LongType(), True),        # LONG
  StructField("tag_id", LongType(), True)             # LONG
])

comment_hasTag_tag_schema = StructType([
  StructField("comment_id", LongType(), True),        # LONG
  StructField("tag_id", LongType(), True),          # LONG
  StructField("creation_date", TimestampType(), True)   # TIMESTAMP
])
comment_hasTag_tag_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Comment_hasTag_Tag/"

# schema for comment isLocatedIn Country creationDate|CommentId|CountryId
comment_isLocatedIn_country_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),   # TIMESTAMP
  StructField("comment_id", LongType(), True),        # LONG
  StructField("country_id", LongType(), True)             # LONG
])

comment_isLocatedIn_country_schema = StructType([
  StructField("comment_id", LongType(), True),        # LONG
  StructField("country_id", LongType(), True),          # LONG
  StructField("creation_date", TimestampType(), True)   # TIMESTAMP
])
comment_isLocatedIn_country_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Comment_isLocatedIn_Country/"

# schema for comment replyOf comment creationDate|Comment1Id|Comment2Id
comment_replyOf_comment_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),   # TIMESTAMP
  StructField("comment1_id", LongType(), True),        # LONG
  StructField("comment2_id", LongType(), True)             # LONG
])

comment_replyOf_comment_schema = StructType([
  StructField("comment1_id", LongType(), True),        # LONG
  StructField("comment2_id", LongType(), True),          # LONG
  StructField("creation_date", TimestampType(), True)   # TIMESTAMP
])
comment_replyOf_comment_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Comment_replyOf_Comment/"

# schema for comment replyOf post creationDate|CommentId|PostId
comment_replyOf_post_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),   # TIMESTAMP
  StructField("comment_id", LongType(), True),        # LONG
  StructField("post_id", LongType(), True)             # LONG
])

comment_replyOf_post_schema = StructType([
  StructField("comment_id", LongType(), True),        # LONG
  StructField("post_id", LongType(), True),          # LONG
  StructField("creation_date", TimestampType(), True)   # TIMESTAMP
])
comment_replyOf_post_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Comment_replyOf_Post/"

#================================Forum Node & Edges=======================
# schema for forum creationDate|id|title
forum_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),
  StructField("id", LongType(), True),
  StructField("title", StringType(), True)
])

forum_schema = StructType([
  StructField("id", LongType(), True),
  StructField("creation_date", TimestampType(), True),
  StructField("title", StringType(), True)
])
forum_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Forum/"

# schema for forum containerOf post creationDate|ForumId|PostId
forum_containerOf_post_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),   # TIMESTAMP
  StructField("forum_id", LongType(), True),        # LONG
  StructField("post_id", LongType(), True)             # LONG
])

forum_containerOf_post_schema = StructType([
  StructField("forum_id", LongType(), True),        # LONG
  StructField("post_id", LongType(), True),          # LONG
  StructField("creation_date", TimestampType(), True)   # TIMESTAMP
])
forum_containerOf_post_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Forum_containerOf_Post/"

# schema for forum hasMember person creationDate|ForumId|PersonId
forum_hasMember_person_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),   # TIMESTAMP
  StructField("forum_id", LongType(), True),        # LONG
  StructField("person_id", LongType(), True)             # LONG
])

forum_hasMember_person_schema = StructType([
  StructField("forum_id", LongType(), True),        # LONG
  StructField("person_id", LongType(), True),          # LONG
  StructField("creation_date", TimestampType(), True)   # TIMESTAMP
])
forum_hasMember_person_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Forum_hasMember_Person/"

# schema for forum hasModerator person creationDate|ForumId|PersonId
forum_hasModerator_person_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),   # TIMESTAMP
  StructField("forum_id", LongType(), True),        # LONG
  StructField("person_id", LongType(), True)             # LONG
])

forum_hasModerator_person_schema = StructType([
  StructField("forum_id", LongType(), True),        # LONG
  StructField("person_id", LongType(), True),          # LONG
  StructField("creation_date", TimestampType(), True)   # TIMESTAMP
])
forum_hasModerator_person_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Forum_hasModerator_Person/"

# schema for forum has tag creationDate|ForumId|TagId
forum_hasTag_tag_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),   # TIMESTAMP
  StructField("forum_id", LongType(), True),        # LONG
  StructField("tag_id", LongType(), True)             # LONG
])

forum_hasTag_tag_schema = StructType([
  StructField("forum_id", LongType(), True),        # LONG
  StructField("tag_id", LongType(), True),          # LONG
  StructField("creation_date", TimestampType(), True)   # TIMESTAMP
])
forum_hasTag_tag_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Forum_hasTag_Tag/"

#================================Person Node & Edges=======================
# schema for person
person_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),  # TIMESTAMP
  StructField("id", LongType(), True),               # LONG
  StructField("first_name", StringType(), True),       # STRING
  StructField("last_name", StringType(), True),        # STRING
  StructField("gender", StringType(), True),           # STRING
  StructField("birthday", TimestampType(), True),           # DATE
  StructField("location_ip", StringType(), True),      # STRING
  StructField("browser_used", StringType(), True),     # STRING
  StructField("language", StringType(), True),  # ARRAY<STRING>
  StructField("email", StringType(), True)      # ARRAY<STRING>
])

person_schema = StructType([
  StructField("id", LongType(), True),               # LONG
  StructField("creation_date", TimestampType(), True),  # TIMESTAMP
  StructField("first_name", StringType(), True),       # STRING
  StructField("last_name", StringType(), True),        # STRING
  StructField("gender", StringType(), True),           # STRING
  StructField("birthday", TimestampType(), True),           # DATE
  StructField("location_ip", StringType(), True),      # STRING
  StructField("browser_used", StringType(), True),     # STRING
  StructField("language", StringType(), True),  # ARRAY<STRING>
  StructField("email", StringType(), True)      # ARRAY<STRING>
])
person_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Person/"

# schema for person hasInterest tag creationDate|personId|interestId
person_hasInterest_tag_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),   # TIMESTAMP
  StructField("person_id", LongType(), True),        # LONG
  StructField("interest_id", LongType(), True)             # LONG
])

person_hasInterest_tag_schema = StructType([
  StructField("person_id", LongType(), True),        # LONG
  StructField("interest_id", LongType(), True),          # LONG
  StructField("creation_date", TimestampType(), True)   # TIMESTAMP
])
person_hasInterest_tag_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Person_hasInterest_Tag/"

# schema for person isLocatedIn City creationDate|PersonId|CityId
person_isLocatedIn_city_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),   # TIMESTAMP
  StructField("person_id", LongType(), True),        # LONG
  StructField("city_id", LongType(), True)             # LONG
])

person_isLocatedIn_city_schema = StructType([
  StructField("person_id", LongType(), True),        # LONG
  StructField("city_id", LongType(), True),          # LONG
  StructField("creation_date", TimestampType(), True)   # TIMESTAMP
])
person_isLocatedIn_city_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Person_isLocatedIn_City/"

# schema for person knows person
person_knows_person_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),   # TIMESTAMP
  StructField("person1_id", LongType(), True),        # LONG
  StructField("person2_id", LongType(), True)        # LONG
])

person_knows_person_schema = StructType([
  StructField("person1_id", LongType(), True),        # LONG
  StructField("person2_id", LongType(), True),        # LONG
  StructField("creation_date", TimestampType(), True)   # TIMESTAMP
])
person_knows_person_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Person_knows_Person/"

# schema for person likes comment
person_likes_comment_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),   # TIMESTAMP
  StructField("person_id", LongType(), True),        # LONG
  StructField("comment_id", LongType(), True)        # LONG
])

person_likes_comment_schema = StructType([
  StructField("person_id", LongType(), True),        # LONG
  StructField("comment_id", LongType(), True),        # LONG
  StructField("creation_date", TimestampType(), True)   # TIMESTAMP
])
person_likes_comment_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Person_likes_Comment/"

# schema for person likes post
person_likes_post_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),   # TIMESTAMP
  StructField("person_id", LongType(), True),        # LONG
  StructField("post_id", LongType(), True)        # LONG
])

person_likes_post_schema = StructType([
  StructField("person_id", LongType(), True),        # LONG
  StructField("post_id", LongType(), True),        # LONG
  StructField("creation_date", TimestampType(), True)   # TIMESTAMP
])
person_likes_post_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Person_likes_Post/"

# schema for person studyAt university creationDate|PersonId|UniversityId|classYear
person_studyAt_university_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),   # TIMESTAMP
  StructField("person_id", LongType(), True),        # LONG
  StructField("university_id", LongType(), True),        # LONG
  StructField("class_year", LongType(), True)        # LONG
])

person_studyAt_university_schema = StructType([
  StructField("person_id", LongType(), True),        # LONG
  StructField("university_id", LongType(), True),        # LONG
  StructField("creation_date", TimestampType(), True),   # TIMESTAMP
  StructField("class_year", LongType(), True)        # LONG
])
person_studyAt_university_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Person_studyAt_University/"

# schema for person workAt Company creationDate|PersonId|CompanyId|workFrom
person_workAt_company_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),   # TIMESTAMP
  StructField("person_id", LongType(), True),        # LONG
  StructField("company_id", LongType(), True),        # LONG
  StructField("work_from", LongType(), True)        # LONG
])

person_workAt_company_schema = StructType([
  StructField("person_id", LongType(), True),        # LONG
  StructField("company_id", LongType(), True),        # LONG
  StructField("creation_date", TimestampType(), True),   # TIMESTAMP
  StructField("work_from", LongType(), True)        # LONG
])
person_workAt_company_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Person_workAt_Company/"

#================================Post Node & Edges=======================
# schema for post creationDate|id|imageFile|locationIP|browserUsed|language|content|length
post_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),
  StructField("id", LongType(), True),
  StructField("image_file", StringType(), True),
  StructField("location_ip", StringType(), True),
  StructField("browser_used", StringType(), True),
  StructField("language", StringType(), True),
  StructField("content", StringType(), True),
  StructField("length", LongType(), True)
])

post_schema = StructType([
  StructField("id", LongType(), True),
  StructField("creation_date", TimestampType(), True),
  StructField("image_file", StringType(), True),
  StructField("location_ip", StringType(), True),
  StructField("browser_used", StringType(), True),
  StructField("language", StringType(), True),
  StructField("content", StringType(), True),
  StructField("length", LongType(), True)
])
post_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Post/"

# schema for post has creator
post_hasCreator_person_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),   # TIMESTAMP
  StructField("post_id", LongType(), True),        # LONG
  StructField("person_id", LongType(), True)          # LONG
])

post_hasCreator_person_schema = StructType([
  StructField("post_id", LongType(), True),        # LONG
  StructField("person_id", LongType(), True),          # LONG
  StructField("creation_date", TimestampType(), True)   # TIMESTAMP
])
post_hasCreator_person_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Post_hasCreator_Person/"

# schema for post has tag creationDate|PostId|TagId
post_hasTag_tag_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),   # TIMESTAMP
  StructField("post_id", LongType(), True),        # LONG
  StructField("tag_id", LongType(), True)             # LONG
])

post_hasTag_tag_schema = StructType([
  StructField("post_id", LongType(), True),        # LONG
  StructField("tag_id", LongType(), True),          # LONG
  StructField("creation_date", TimestampType(), True)   # TIMESTAMP
])
post_hasTag_tag_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Post_hasTag_Tag/"

# schema for post isLocatedIn Country creationDate|PostId|CountryId
post_isLocatedIn_country_csv_schema = StructType([
  StructField("creation_date", TimestampType(), True),   # TIMESTAMP
  StructField("post_id", LongType(), True),        # LONG
  StructField("country_id", LongType(), True)             # LONG
])

post_isLocatedIn_country_schema = StructType([
  StructField("post_id", LongType(), True),        # LONG
  StructField("country_id", LongType(), True),          # LONG
  StructField("creation_date", TimestampType(), True)   # TIMESTAMP
])
post_isLocatedIn_country_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/dynamic/Post_isLocatedIn_Country/"

#================================Organisation Node & Edges=======================
# schema for organisation id|type|name|url
organisation_csv_schema = StructType([
  StructField("id", LongType(), True),
  StructField("type", StringType(), True),
  StructField("name", StringType(), True),
  StructField("url", StringType(), True)
])

organisation_schema = StructType([
  StructField("id", LongType(), True),
  StructField("type", StringType(), True),
  StructField("name", StringType(), True),
  StructField("url", StringType(), True)
])
organisation_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/static/Organisation/"

# schema for organisation isLocatedIn place OrganisationId|PlaceId
organisation_isLocatedIn_place_csv_schema = StructType([
  StructField("organisation_id", LongType(), True),        # LONG
  StructField("place_id", LongType(), True)             # LONG
])

organisation_isLocatedIn_place_schema = StructType([
  StructField("organisation_id", LongType(), True),        # LONG
  StructField("place_id", LongType(), True)             # LONG
])
organisation_isLocatedIn_place_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/static/Organisation_isLocatedIn_Place/"


#================================Place Node & Edges=======================
# schema for place id|name|url|type
place_csv_schema = StructType([
  StructField("id", LongType(), True),
  StructField("name", StringType(), True),
  StructField("url", StringType(), True),
  StructField("type", StringType(), True)
])

place_schema = StructType([
  StructField("id", LongType(), True),
  StructField("name", StringType(), True),
  StructField("url", StringType(), True),
  StructField("type", StringType(), True)
])
place_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/static/Place/"

# schema for place isPartOf place Place1Id|Place2Id
place_isPartOf_place_csv_schema = StructType([
  StructField("place1_id", LongType(), True),        # LONG
  StructField("place2_id", LongType(), True)             # LONG
])

place_isPartOf_place_schema = StructType([
  StructField("place1_id", LongType(), True),        # LONG
  StructField("place2_id", LongType(), True)             # LONG
])
place_isPartOf_place_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/static/Place_isPartOf_Place/"

#================================Tag Node & Edges=======================
# schema for tag id|name|url
tag_csv_schema = StructType([
  StructField("id", LongType(), True),
  StructField("name", StringType(), True),
  StructField("url", StringType(), True)
])

tag_schema = StructType([
  StructField("id", LongType(), True),
  StructField("name", StringType(), True),
  StructField("url", StringType(), True)
])
tag_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/static/Tag/"

# schema for tag hasType tagclass TagId|TagClassId
tag_hasType_tagclass_csv_schema = StructType([
  StructField("tag_id", LongType(), True),        # LONG
  StructField("tagclass_id", LongType(), True)             # LONG
])

tag_hasType_tagclass_schema = StructType([
  StructField("tag_id", LongType(), True),        # LONG
  StructField("tagclass_id", LongType(), True)             # LONG
])
tag_hasType_tagclass_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/static/Tag_hasType_TagClass/"

#================================TagClass Node & Edges=======================
# schema for tagclass id|name|url
tagclass_csv_schema = StructType([
  StructField("id", LongType(), True),
  StructField("name", StringType(), True),
  StructField("url", StringType(), True)
])

tagclass_schema = StructType([
  StructField("id", LongType(), True),
  StructField("name", StringType(), True),
  StructField("url", StringType(), True)
])
tagclass_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/static/TagClass/"

# schema for tagclass isSubclassOf tagclass TagClass1Id|TagClass2Id
tagclass_isSubclassOf_tagclass_csv_schema = StructType([
  StructField("tagclass1_id", LongType(), True),        # LONG
  StructField("tagclass2_id", LongType(), True)             # LONG
])

tagclass_isSubclassOf_tagclass_schema = StructType([
  StructField("tagclass1_id", LongType(), True),        # LONG
  StructField("tagclass2_id", LongType(), True)             # LONG
])
tagclass_isSubclassOf_tagclass_csv_folder_path = f"{csv_dataset_root}/initial_snapshot/static/TagClass_isSubclassOf_TagClass/"

types = ["comment", "comment_hasCreator_person", "comment_hasTag_tag", "comment_isLocatedIn_country",
 "comment_replyOf_comment", "comment_replyOf_post", "forum", "forum_containerOf_post", "forum_hasMember_person",
 "forum_hasModerator_person", "forum_hasTag_tag", "person", "person_hasInterest_tag", "person_isLocatedIn_city",
 "person_knows_person", "person_likes_comment", "person_likes_post", "person_studyAt_university",
 "person_workAt_company", "post", "post_hasCreator_person", "post_hasTag_tag", "post_isLocatedIn_country",
 "organisation", "organisation_isLocatedIn_place", "place", "place_isPartOf_place", "tag", "tag_hasType_tagclass",
 "tagclass", "tagclass_isSubclassOf_tagclass"]

if INGEST_ONLY_TYPES:
    types = [t for t in types if t in INGEST_ONLY_TYPES]
    print(f"[INFO] Ingesting {len(types)} table(s): {types}")

static_types = ["organisation", "organisation_isLocatedIn_place", "place", "place_isPartOf_place",
 "tag", "tag_hasType_tagclass", "tagclass", "tagclass_isSubclassOf_tagclass"]

vertex_types = ["comment", "forum", "person", "post", "organisation", "place", "tag", "tagclass"]

#case sf300
sf300_64_partitions = ["comment", "forum_hasMember_person"]

#sf1000_64_partitions = ["comment_replyOf_comment", "comment_replyOf_post", "person_likes_post", "post_hasTag_tag"]
#sf1000_128_partitions = ["comment_hasCreator_person", "comment_hasTag_tag", "comment_isLocatedIn_country", "person_likes_comment",
#"post"]
#sf1000_256_partitions = ["comment", "forum_hasMember_person"]

vertex_row_count = 0
edge_row_count = 0

for target_type in types:
  if target_type == "comment":
    csv_folder_path = comment_csv_folder_path
    schema = comment_schema
    csv_schema = comment_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.comment"
  elif target_type == "comment_hasCreator_person":
    csv_folder_path = comment_hasCreator_person_csv_folder_path
    schema = comment_hasCreator_person_schema
    csv_schema = comment_hasCreator_person_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.comment_hascreator_person"
  elif target_type == "comment_hasTag_tag":
    csv_folder_path = comment_hasTag_tag_csv_folder_path
    schema = comment_hasTag_tag_schema
    csv_schema = comment_hasTag_tag_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.comment_hastag_tag"
  elif target_type == "comment_isLocatedIn_country":
    csv_folder_path = comment_isLocatedIn_country_csv_folder_path
    schema = comment_isLocatedIn_country_schema
    csv_schema = comment_isLocatedIn_country_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.comment_islocatedin_country"
  elif target_type == "comment_replyOf_comment":
    csv_folder_path = comment_replyOf_comment_csv_folder_path
    schema = comment_replyOf_comment_schema
    csv_schema = comment_replyOf_comment_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.comment_replyof_comment"
  elif target_type == "comment_replyOf_post":
    csv_folder_path = comment_replyOf_post_csv_folder_path
    schema = comment_replyOf_post_schema
    csv_schema = comment_replyOf_post_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.comment_replyof_post"
  elif target_type == "forum":
    csv_folder_path = forum_csv_folder_path
    schema = forum_schema
    csv_schema = forum_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.forum"
  elif target_type == "forum_containerOf_post":
    csv_folder_path = forum_containerOf_post_csv_folder_path
    schema = forum_containerOf_post_schema
    csv_schema = forum_containerOf_post_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.forum_containerof_post"
  elif target_type == "forum_hasMember_person":
    csv_folder_path = forum_hasMember_person_csv_folder_path
    schema = forum_hasMember_person_schema
    csv_schema = forum_hasMember_person_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.forum_hasmember_person"
  elif target_type == "forum_hasModerator_person":
    csv_folder_path = forum_hasModerator_person_csv_folder_path
    schema = forum_hasModerator_person_schema
    csv_schema = forum_hasModerator_person_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.forum_hasmoderator_person"
  elif target_type == "forum_hasTag_tag":
    csv_folder_path = forum_hasTag_tag_csv_folder_path
    schema = forum_hasTag_tag_schema
    csv_schema = forum_hasTag_tag_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.forum_hastag_tag"
  elif target_type == "person":
    csv_folder_path = person_csv_folder_path
    schema = person_schema
    csv_schema = person_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.person"
  elif target_type == "person_hasInterest_tag":
    csv_folder_path = person_hasInterest_tag_csv_folder_path
    schema = person_hasInterest_tag_schema
    csv_schema = person_hasInterest_tag_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.person_hasinterest_tag"
  elif target_type == "person_isLocatedIn_city":
    csv_folder_path = person_isLocatedIn_city_csv_folder_path
    schema = person_isLocatedIn_city_schema
    csv_schema = person_isLocatedIn_city_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.person_islocatedin_city"
  elif target_type == "person_knows_person":
    csv_folder_path = person_knows_person_csv_folder_path
    schema = person_knows_person_schema
    csv_schema = person_knows_person_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.person_knows_person"
  elif target_type == "person_likes_comment":
    csv_folder_path = person_likes_comment_csv_folder_path
    schema = person_likes_comment_schema
    csv_schema = person_likes_comment_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.person_likes_comment"
  elif target_type == "person_likes_post":
    csv_folder_path = person_likes_post_csv_folder_path
    schema = person_likes_post_schema
    csv_schema = person_likes_post_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.person_likes_post"
  elif target_type == "person_studyAt_university":
    csv_folder_path = person_studyAt_university_csv_folder_path
    schema = person_studyAt_university_schema
    csv_schema = person_studyAt_university_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.person_studyat_university"
  elif target_type == "person_workAt_company":
    csv_folder_path = person_workAt_company_csv_folder_path
    schema = person_workAt_company_schema
    csv_schema = person_workAt_company_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.person_workat_company"
  elif target_type == "post":
    csv_folder_path = post_csv_folder_path
    schema = post_schema
    csv_schema = post_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.post"
  elif target_type == "post_hasCreator_person":
    csv_folder_path = post_hasCreator_person_csv_folder_path
    schema = post_hasCreator_person_schema
    csv_schema = post_hasCreator_person_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.post_hascreator_person"
  elif target_type == "post_hasTag_tag":
    csv_folder_path = post_hasTag_tag_csv_folder_path
    schema = post_hasTag_tag_schema
    csv_schema = post_hasTag_tag_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.post_hastag_tag"
  elif target_type == "post_isLocatedIn_country":
    csv_folder_path = post_isLocatedIn_country_csv_folder_path
    schema = post_isLocatedIn_country_schema
    csv_schema = post_isLocatedIn_country_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.post_islocatedin_country"
  elif target_type == "organisation":
    csv_folder_path = organisation_csv_folder_path
    schema = organisation_schema
    csv_schema = organisation_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.organisation"
  elif target_type == "organisation_isLocatedIn_place":
    csv_folder_path = organisation_isLocatedIn_place_csv_folder_path
    schema = organisation_isLocatedIn_place_schema
    csv_schema = organisation_isLocatedIn_place_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.organisation_islocatedin_place"
  elif target_type == "place":
    csv_folder_path = place_csv_folder_path
    schema = place_schema
    csv_schema = place_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.place"
  elif target_type == "place_isPartOf_place":
    csv_folder_path = place_isPartOf_place_csv_folder_path
    schema = place_isPartOf_place_schema
    csv_schema = place_isPartOf_place_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.place_ispartof_place"
  elif target_type == "tag":
    csv_folder_path = tag_csv_folder_path
    schema = tag_schema
    csv_schema = tag_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.tag"
  elif target_type == "tag_hasType_tagclass":
    csv_folder_path = tag_hasType_tagclass_csv_folder_path
    schema = tag_hasType_tagclass_schema
    csv_schema = tag_hasType_tagclass_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.tag_hastype_tagclass"
  elif target_type == "tagclass":
    csv_folder_path = tagclass_csv_folder_path
    schema = tagclass_schema
    csv_schema = tagclass_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.tagclass"
  elif target_type == "tagclass_isSubclassOf_tagclass":
    csv_folder_path = tagclass_isSubclassOf_tagclass_csv_folder_path
    schema = tagclass_isSubclassOf_tagclass_schema
    csv_schema = tagclass_isSubclassOf_tagclass_csv_schema
    table_name = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}.tagclass_issubclassof_tagclass"
  else:
    # Unknown type — skip
    print(f"Unknown type {target_type}, skipping.")
    continue

  print(f"Preparing load csv files of type {target_type}")

  if not os.path.isdir(csv_folder_path):
    print(f"CSV folder does not exist: {csv_folder_path}. Skipping {target_type}.")
    continue

  # List all CSV files in the directory
  csv_files = [os.path.join(csv_folder_path, file) for file in os.listdir(csv_folder_path) if file.endswith(".csv")]

  # Check if there are any files in the directory
  if not csv_files:
    print("No CSV files found in the folder.")
    continue
  else:
    print(f"Found {len(csv_files)} CSV files to process.")

  dfs = []

  for i, file_path in enumerate(csv_files):
    print(f"Processing file {i + 1}/{len(csv_files)}: {file_path}")
    df = (spark.read.option("delimiter", "|")
            .option("header", "true")
            .schema(csv_schema)
            .csv(file_path))
    df = df.select([f.name for f in schema.fields])
    row_count = df.count()
    print(f"Number of rows in {file_path}: {row_count}")
    dfs.append(df)

  # Union all DataFrames
  combined_df = dfs[0]
  for df in dfs[1:]:
    combined_df = combined_df.union(df)
  # Repartition to control output parallelism56)
  if target_type in static_types:
    pass
  else:
    combined_df = combined_df.repartition(REPARTITION_COUNT)

  # Show preview
  combined_df.show(5)
  print("Total row count:", combined_df.count())

  with open(INGEST_LOG, "a") as f:
    f.write(f"Table {table_name} has total row count: {combined_df.count()}\n")

  if target_type in vertex_types:
    vertex_row_count += combined_df.count()
  else:
    edge_row_count += combined_df.count()

  print(f"Writing to Iceberg table: {table_name}")
  if DROP_BEFORE_WRITE:
    purge_sql = " PURGE" if PURGE_ON_DROP else ""
    print(f"  DROP TABLE IF EXISTS {table_name}{purge_sql} ...")
    spark.sql(f"DROP TABLE IF EXISTS {table_name}{purge_sql}")

  writer = combined_df.writeTo(table_name)
  if (
    PARTITION_BY_CREATION_DATE
    and target_type in PARTITION_TABLES
    and "creation_date" in combined_df.columns
  ):
    if PARTITION_GRANULARITY in ("month", "months"):
      writer = writer.partitionedBy(months("creation_date"))
      print(f"  Iceberg partition: months(creation_date) on {table_name}")
    else:
      writer = writer.partitionedBy(days("creation_date"))
      print(f"  Iceberg partition: days(creation_date) on {table_name}")
  writer.createOrReplace()

print("Processing complete. All files have been written to the Iceberg table.")

with open(INGEST_LOG, "a") as f:
  f.write(f"Vertex has total row count: {vertex_row_count}\n")
  f.write(f"Edge has total row count: {edge_row_count}\n")