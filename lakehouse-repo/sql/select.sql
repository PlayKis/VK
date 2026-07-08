-- =============================================================================
-- select.sql
--
-- Выполняется В TRINO. Проверочные запросы: сами данные и
-- служебные метатаблицы Iceberg (снапшоты, история, файлы).
-- =============================================================================

-- Основные данные
SELECT * FROM iceberg.demo.orders ORDER BY order_id;

-- История снапшотов таблицы (каждый INSERT/UPDATE создаёт новый снапшот)
SELECT * FROM iceberg.demo."orders$history";

-- Список всех снапшотов с их summary
SELECT * FROM iceberg.demo."orders$snapshots";

-- Файлы данных, из которых физически состоит таблица
SELECT file_path, record_count, file_size_in_bytes
FROM iceberg.demo."orders$files";

-- Партиции таблицы
SELECT * FROM iceberg.demo."orders$partitions";
