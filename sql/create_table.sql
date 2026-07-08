CREATE SCHEMA IF NOT EXISTS iceberg.demo
WITH (location = 's3://warehouse/demo');

CREATE TABLE IF NOT EXISTS iceberg.demo.orders (
    order_id   BIGINT,
    customer   VARCHAR,
    amount     DECIMAL(10,2),
    order_date DATE
)
WITH (
    format = 'PARQUET',
    partitioning = ARRAY['month(order_date)']
);
