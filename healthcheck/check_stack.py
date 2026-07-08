

import socket
import sys
import urllib.request
import urllib.error

TRINO_URL = "http://localhost:8080/v1/info"
MINIO_HEALTH_URL = "http://localhost:9000/minio/health/live"
POSTGRES_HOST = "localhost"
POSTGRES_PORT = 5432

GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
RESET = "\033[0m"

ok = True


def report(name: str, success: bool, detail: str = "") -> None:
    global ok
    tag = f"{GREEN}[OK]{RESET}" if success else f"{RED}[FAIL]{RESET}"
    suffix = f" — {detail}" if detail else ""
    print(f"{tag}   {name}{suffix}")
    if not success:
        ok = False


def check_http(name: str, url: str, timeout: float = 5.0) -> None:
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            report(name, response.status == 200, f"HTTP {response.status}")
    except urllib.error.URLError as exc:
        report(name, False, str(exc))
    except Exception as exc:  # noqa: BLE001
        report(name, False, str(exc))


def check_tcp(name: str, host: str, port: int, timeout: float = 5.0) -> None:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            report(name, True)
    except OSError as exc:
        report(name, False, str(exc))


def check_postgres_catalog_tables() -> None:
    try:
        import psycopg2  # type: ignore
    except ImportError:
        print(f"{YELLOW}[SKIP]{RESET} Postgres: iceberg_tables (psycopg2 не установлен)")
        return

    try:
        conn = psycopg2.connect(
            host=POSTGRES_HOST,
            port=POSTGRES_PORT,
            dbname="iceberg_catalog",
            user="iceberg",
            password="iceberg",
            connect_timeout=5,
        )
        with conn, conn.cursor() as cur:
            cur.execute(
                "SELECT table_name FROM information_schema.tables "
                "WHERE table_name IN ('iceberg_tables', 'iceberg_namespace_properties')"
            )
            found = {row[0] for row in cur.fetchall()}
        conn.close()

        expected = {"iceberg_tables", "iceberg_namespace_properties"}
        missing = expected - found
        if missing:
            report(
                "Postgres: служебные таблицы каталога",
                False,
                f"отсутствуют: {', '.join(sorted(missing))} — см. sql/init_iceberg_catalog.sql",
            )
        else:
            report("Postgres: служебные таблицы каталога", True, "iceberg_tables + iceberg_namespace_properties найдены")
    except Exception as exc:  # noqa: BLE001
        report("Postgres: служебные таблицы каталога", False, str(exc))


def check_minio_bucket() -> None:
    try:
        import boto3  # type: ignore
        from botocore.client import Config  # type: ignore
    except ImportError:
        print(f"{YELLOW}[SKIP]{RESET} MinIO: бакет warehouse (boto3 не установлен)")
        return

    try:
        s3 = boto3.client(
            "s3",
            endpoint_url="http://localhost:9000",
            aws_access_key_id="minioadmin",
            aws_secret_access_key="minioadmin",
            config=Config(signature_version="s3v4"),
            region_name="us-east-1",
        )
        buckets = {b["Name"] for b in s3.list_buckets().get("Buckets", [])}
        report("MinIO: бакет warehouse", "warehouse" in buckets, f"бакеты: {', '.join(sorted(buckets)) or '(нет)'}")
    except Exception as exc:  # noqa: BLE001
        report("MinIO: бакет warehouse", False, str(exc))


def main() -> int:
    print("== Проверка mini lakehouse ==\n")

    check_http("Trino (/v1/info)", TRINO_URL)
    check_http("MinIO (/minio/health/live)", MINIO_HEALTH_URL)
    check_tcp("Postgres (TCP)", POSTGRES_HOST, POSTGRES_PORT)
    check_postgres_catalog_tables()
    check_minio_bucket()

    print()
    if ok:
        print(f"{GREEN}Все обязательные проверки пройдены.{RESET}")
    else:
        print(f"{RED}Есть проблемы — см. вывод выше.{RESET}")

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
