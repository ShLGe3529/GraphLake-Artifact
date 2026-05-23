import os
import time
from pyspark.sql import SparkSession

print("Starting BI-16 projection export (column pruning) to Neo4j CSV ...")
start_time = time.time()

ICEBERG_CATALOG = os.environ.get("ICEBERG_CATALOG", "demo")
ICEBERG_NAMESPACE = os.environ.get("ICEBERG_NAMESPACE", "mydb")
QUERY_SUITE = os.environ.get("NEO4J_QUERY_SUITE", "bi16")

db_prefix = f"{ICEBERG_CATALOG}.{ICEBERG_NAMESPACE}"
output_base_dir = os.environ.get(
    "NEO4J_EXPORT_DIR",
    f"/data/dataset/exports/neo4j/{ICEBERG_NAMESPACE}_{QUERY_SUITE}",
)

local_base_dir = output_base_dir
if not os.path.exists(local_base_dir):
    os.makedirs(local_base_dir)

spark = SparkSession.builder.appName("Lakehouse_to_Neo4j_Optimized_CSV").getOrCreate()

# Spark type -> Neo4j header suffix
def get_neo4j_type_suffix(spark_type):
    """Map Spark column type to Neo4j CSV header suffix."""
    spark_type = spark_type.lower()
    if spark_type == 'bigint' or spark_type == 'long':
        return ":long"
    elif spark_type == 'int' or spark_type == 'integer':
        return ":int"
    elif spark_type == 'timestamp':
        return ":datetime"
    elif spark_type == 'date':
        return ":date"
    elif spark_type == 'double':
        return ":double"
    elif spark_type == 'float':
        return ":float"
    elif spark_type == 'boolean':
        return ":boolean"
    else:
        return ""

def export_vertex(table_suffix, label, columns_to_keep=None):
    out_path = f"{output_base_dir}/nodes_{label}"
    print(f"Exporting vertex {label} from {table_suffix} -> {out_path} ...")

    df = spark.table(f"{db_prefix}.{table_suffix}")

    if columns_to_keep:
        df = df.select(*columns_to_keep)

    for col_name, spark_type in df.dtypes:
        if col_name == "id":
            df = df.withColumnRenamed(col_name, f"id:ID({label})")
        else:
            neo4j_suffix = get_neo4j_type_suffix(spark_type)
            if neo4j_suffix:
                df = df.withColumnRenamed(col_name, f"{col_name}{neo4j_suffix}")

    header_file = os.path.join(local_base_dir, f"header_nodes_{label}.csv")
    with open(header_file, "w", encoding="utf-8") as f:
        f.write(",".join(df.columns) + "\n")

    df.write.mode("overwrite") \
        .option("header", "false") \
        .option("quote", '"') \
        .option("escape", '"') \
        .option("timestampFormat", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'") \
        .csv(out_path)

def export_edge(table_suffix, rel_type, src_label, src_col, tgt_label, tgt_col, columns_to_keep=None):
    out_path = f"{output_base_dir}/edges_{table_suffix}"
    print(f"Exporting edge {rel_type} from {table_suffix} -> {out_path} ...")

    df = spark.table(f"{db_prefix}.{table_suffix}")

    if columns_to_keep:
        df = df.select(*columns_to_keep)

    for col_name, spark_type in df.dtypes:
        if col_name == src_col:
            df = df.withColumnRenamed(col_name, f":START_ID({src_label})")
        elif col_name == tgt_col:
            df = df.withColumnRenamed(col_name, f":END_ID({tgt_label})")
        else:
            neo4j_suffix = get_neo4j_type_suffix(spark_type)
            if neo4j_suffix:
                df = df.withColumnRenamed(col_name, f"{col_name}{neo4j_suffix}")

    header_file = os.path.join(local_base_dir, f"header_edges_{table_suffix}.csv")
    with open(header_file, "w", encoding="utf-8") as f:
        f.write(",".join(df.columns) + "\n")

    df.write.mode("overwrite") \
        .option("header", "false") \
        .option("quote", '"') \
        .option("escape", '"') \
        .option("timestampFormat", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'") \
        .csv(out_path)


# Vertices (BI-16 projection)
vertex_configs = [
    ("tag", "Tag", ["id", "name"]),
    ("person", "Person", ["id"]),
    ("comment", "Comment", ["id", "creation_date"]),
]

for config in vertex_configs:
    export_vertex(*config)

# Edges (BI-16 projection)
edge_configs = [
    ("comment_hastag_tag", "HAS_TAG", "Comment", "comment_id", "Tag", "tag_id", ["comment_id", "tag_id"]),
    ("comment_hascreator_person", "HAS_CREATOR", "Comment", "comment_id", "Person", "person_id", ["comment_id", "person_id"]),
    ("person_knows_person", "KNOWS", "Person", "person1_id", "Person", "person2_id", ["person1_id", "person2_id"]),
]

for config in edge_configs:
    export_edge(*config)
end_time = time.time()
print(f"BI-16 projection export done in {(end_time - start_time) / 60:.2f} minutes")
