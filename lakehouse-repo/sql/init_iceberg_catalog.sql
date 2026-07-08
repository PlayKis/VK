-- =============================================================================
-- init_iceberg_catalog.sql
--
-- ВАЖНО: этот скрипт выполняется в PostgreSQL (не в Trino!) через
-- /docker-entrypoint-initdb.d при первом старте контейнера postgres
-- на пустом volume. Он создаёт служебные таблицы реестра Iceberg
-- JDBC-каталога — те же самые, которые Trino/Iceberg должен был бы
-- создать сам при первом обращении.
--
-- Зачем это нужно:
-- Начиная с Trino 414 и вплоть до актуальных версий (включая 482,
-- используемую в этом compose) в Trino есть баг: JDBC-каталог Iceberg
-- инициализируется с флагом initializeCatalogTables=false, из-за чего
-- Trino НЕ создаёт таблицы iceberg_tables / iceberg_namespace_properties
-- автоматически и падает с ошибкой:
--   "Cannot check and eventually update SQL schema"
--   Caused by: relation "iceberg_tables" does not exist
--
-- См. https://github.com/trinodb/trino/issues/20419
--
-- DDL ниже — точная копия схемы, которую использует сам Apache Iceberg
-- (org.apache.iceberg.jdbc.JdbcUtil), поэтому Trino прекрасно работает
-- с этими таблицами дальше как ни в чём не бывало.
-- =============================================================================

CREATE TABLE IF NOT EXISTS iceberg_tables (
    catalog_name                VARCHAR(255) NOT NULL,
    table_namespace              VARCHAR(255) NOT NULL,
    table_name                   VARCHAR(255) NOT NULL,
    metadata_location             VARCHAR(1000),
    previous_metadata_location    VARCHAR(1000),
    iceberg_type                 VARCHAR(5),
    PRIMARY KEY (catalog_name, table_namespace, table_name)
);

CREATE TABLE IF NOT EXISTS iceberg_namespace_properties (
    catalog_name    VARCHAR(255) NOT NULL,
    namespace       VARCHAR(255) NOT NULL,
    property_key    VARCHAR(255) NOT NULL,
    property_value  VARCHAR(1000),
    PRIMARY KEY (catalog_name, namespace, property_key)
);
