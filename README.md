# Mini Lakehouse: Trino + Iceberg (JDBC catalog) + MinIO + PostgreSQL

Минимальный, но полностью рабочий lakehouse-стек в Docker: SQL-движок Trino
поверх табличного формата Apache Iceberg, метаданные каталога — в PostgreSQL
(через JDBC-каталог Iceberg), сами данные — в S3-совместимом хранилище MinIO.

## Структура репозитория

```
.
├── docker-compose.yml       # описание всех сервисов
├── trino/
│   └── catalog/              # конфиги коннекторов Trino (.properties)
│       ├── iceberg.properties   # JDBC-каталог Iceberg + доступ к S3 (MinIO)
│       └── postgres.properties  # опционально: прямой доступ к Postgres
├── sql/                       # SQL-скрипты
│   ├── init_iceberg_catalog.sql  # ⚠️ обязателен, см. "Известная проблема"
│   ├── create_table.sql          # создание схемы/таблицы в Trino
│   ├── insert.sql                # тестовые данные
│   └── select.sql                # проверочные выборки + метатаблицы Iceberg
├── healthcheck/                # проверка живости сервисов
│   ├── check_stack.sh             # bash/curl-вариант
│   └── check_stack.py             # python-вариант (глубже проверяет)
└── README.md
```

## Архитектура

```
┌─────────────┐        SQL          ┌──────────────┐
│   клиент    │ ───────────────────▶│    Trino     │
│ (CLI/DBeaver│                      │ (SQL engine) │
│  /BI-тул)   │◀─────────────────── │              │
└─────────────┘       результат      └──────┬───────┘
                                             │
                       ┌─────────────────────┼─────────────────────┐
                       │                                           │
              метаданные (JDBC)                            данные (S3 API)
                       │                                           │
                       ▼                                           ▼
              ┌─────────────────┐                        ┌─────────────────┐
              │   PostgreSQL    │                        │      MinIO      │
              │ iceberg_catalog │                        │  bucket:        │
              │  - iceberg_tables       │                │  warehouse/     │
              │  - iceberg_namespace_   │                │   demo/orders/  │
              │    properties           │                │    data/*.parquet
              └─────────────────┘                        │    metadata/*.json,*.avro
                                                           └─────────────────┘
```

- **Trino** — исполняет SQL, планирует чтение/запись файлов.
- **Iceberg** (табличный формат) — версионирование, схема, партиционирование,
  снапшоты. Подключён к Trino через **JDBC-каталог**.
- **PostgreSQL** — хранит реестр таблиц Iceberg (какая таблица где лежит,
  какой metadata-файл актуален) — играет роль metastore + может использоваться
  как обычная сервисная БД.
- **MinIO** — S3-совместимое объектное хранилище для файлов данных (Parquet)
  и метаданных Iceberg (JSON/Avro).

## Быстрый старт

```bash
docker compose up -d
docker compose ps
```

Дождись, пока `postgres` и `minio` станут `healthy`, `trino` — `healthy` (может
занять 20-30 секунд на первом старте из-за загрузки JVM и всех коннекторов),
а `minio-init` завершится с `Exit 0`.

Проверить, что всё живо:

```bash
chmod +x healthcheck/check_stack.sh
./healthcheck/check_stack.sh

# или более подробно:
python3 healthcheck/check_stack.py
```

## ⚠️ Известная проблема: баг Trino с JDBC-каталогом Iceberg

Начиная с Trino 414 и вплоть до актуальных версий (включая используемую здесь)
в самом Trino есть баг: при инициализации JDBC-каталога Iceberg передаётся
`initializeCatalogTables=false`, из-за чего Trino **не создаёт** служебные
таблицы `iceberg_tables` и `iceberg_namespace_properties` в Postgres сам.
Без них любой запрос к каталогу `iceberg` падает с ошибкой:

```
Cannot check and eventually update SQL schema
Caused by: relation "iceberg_tables" does not exist
```

Подробности: [github.com/trinodb/trino/issues/20419](https://github.com/trinodb/trino/issues/20419)

**Решение уже встроено в этот репозиторий**: `docker-compose.yml` монтирует
`sql/init_iceberg_catalog.sql` в `/docker-entrypoint-initdb.d/` контейнера
Postgres — официальный образ `postgres` автоматически выполняет все скрипты
из этой папки при первой инициализации пустого volume. Поэтому при обычном
`docker compose up -d` с нуля всё работает сразу, без ручных действий.

Если ты когда-то пересоздашь volume Postgres командой `docker compose down -v`
и снова поднимешь стек — скрипт выполнится заново автоматически, никаких
дополнительных шагов не требуется.

Если по какой-то причине таблицы всё равно не создались (например, volume был
инициализирован ещё до появления этого скрипта в репозитории), примени его
вручную:

```bash
docker exec -i lakehouse-postgres psql -U iceberg -d iceberg_catalog < sql/init_iceberg_catalog.sql
```

## Работа с данными

Зайди в интерактивный Trino CLI:

```bash
docker exec -it lakehouse-trino trino
```

Выполняй команды из `sql/` **по одной** (не вставляй весь файл разом при первом
запуске — параллельные DDL-запросы к ещё не инициализированному каталогу могут
вызвать гонку):

```sql
-- из sql/create_table.sql
CREATE SCHEMA IF NOT EXISTS iceberg.demo WITH (location = 's3://warehouse/demo');
CREATE TABLE IF NOT EXISTS iceberg.demo.orders (...) WITH (format = 'PARQUET', partitioning = ARRAY['month(order_date)']);
```

Либо выполни файл целиком через `-f` (после того как каталог уже был
инициализирован хотя бы одним запросом):

```bash
docker exec -i lakehouse-trino trino -f - < sql/create_table.sql
docker exec -i lakehouse-trino trino -f - < sql/insert.sql
docker exec -i lakehouse-trino trino -f - < sql/select.sql
```

## Проверка на уровне хранилища

```bash
# метаданные каталога в Postgres
docker exec -it lakehouse-postgres psql -U iceberg -d iceberg_catalog -c "SELECT * FROM iceberg_tables;"

# файлы данных и метаданных в MinIO
docker exec -it lakehouse-minio mc ls -r local/warehouse

# MinIO веб-консоль
# http://localhost:9001  (minioadmin / minioadmin)
```

## Подключение внешних инструментов

- **JDBC**: `jdbc:trino://localhost:8080/iceberg/demo`
- **DBeaver / DataGrip**: драйвер Trino, host `localhost`, port `8080`, catalog `iceberg`
- **Spark / Flink**: можно подключить тот же JDBC-каталог (тот же Postgres) как
  общий metastore для нескольких движков одновременно — в этом и смысл
  lakehouse-архитектуры: данные и метаданные не привязаны к одному движку.

## Остановка / очистка

```bash
docker compose down          # остановить, данные сохранятся в volume
docker compose down -v       # остановить и удалить все данные (Postgres + MinIO)
```

## Возможные доработки

- Заменить Trino на **Doris/StarRocks** — архитектура интеграции с MinIO/Iceberg
  там отличается (не через JDBC-каталог напрямую).
- Добавить **Nessie** вместо JDBC-каталога для git-like версионирования каталога.
- Добавить **Superset** или **Metabase** для BI поверх Trino.
- Вынести пароли в `.env` файл вместо хардкода в `docker-compose.yml`.
