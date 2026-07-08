-- =============================================================================
-- create_table.sql
--
-- Выполняется В TRINO (не в psql!), например:
--   docker exec -it lakehouse-trino trino -f /path/to/create_table.sql
-- или интерактивно через:
--   docker exec -it lakehouse-trino trino
--
-- Выполняй команды по одной — параллельная отправка нескольких DDL
-- в один и тот же новый каталог может вызвать гонку при первой
-- инициализации JDBC-каталога.
-- =============================================================================

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
