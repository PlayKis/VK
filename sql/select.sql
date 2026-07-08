
SELECT * FROM iceberg.demo.orders ORDER BY order_id;

SELECT * FROM iceberg.demo."orders$history";

SELECT * FROM iceberg.demo."orders$snapshots";

SELECT file_path, record_count, file_size_in_bytes
FROM iceberg.demo."orders$files";

SELECT * FROM iceberg.demo."orders$partitions";
