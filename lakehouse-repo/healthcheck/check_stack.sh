#!/usr/bin/env bash
# =============================================================================
# check_stack.sh
#
# Быстрая проверка здоровья mini lakehouse через curl.
# Запускать с хоста (там, где поднят docker compose), не изнутри контейнера.
#
# Использование:
#   chmod +x healthcheck/check_stack.sh
#   ./healthcheck/check_stack.sh
# =============================================================================

set -uo pipefail

TRINO_URL="http://localhost:8080/v1/info"
MINIO_URL="http://localhost:9000/minio/health/live"
POSTGRES_HOST="localhost"
POSTGRES_PORT="5432"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

status=0

check_http() {
    local name="$1"
    local url="$2"
    if curl -sf -o /dev/null --max-time 5 "$url"; then
        echo -e "${GREEN}[OK]${NC}   $name ($url)"
    else
        echo -e "${RED}[FAIL]${NC} $name ($url)"
        status=1
    fi
}

check_tcp() {
    local name="$1"
    local host="$2"
    local port="$3"
    if (exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null; then
        exec 3>&- 3<&-
        echo -e "${GREEN}[OK]${NC}   $name (${host}:${port})"
    else
        echo -e "${RED}[FAIL]${NC} $name (${host}:${port})"
        status=1
    fi
}

echo "== Проверка mini lakehouse =="
echo

check_http "Trino"    "$TRINO_URL"
check_http "MinIO"    "$MINIO_URL"
check_tcp  "Postgres" "$POSTGRES_HOST" "$POSTGRES_PORT"

echo
if [ "$status" -eq 0 ]; then
    echo -e "${GREEN}Все сервисы отвечают.${NC}"
else
    echo -e "${RED}Есть проблемы — см. вывод выше.${NC}"
fi

exit $status
