#!/usr/bin/env bash
# Seed the Avalon database end to end: app schema + warehouse.
# Prereq: the stack is up (docker compose -f docker/docker-compose.yml up -d)
set -euo pipefail

cd "$(dirname "$0")"

DSN="${AVALON_DSN:-postgresql://avalon:avalon_dev_password@localhost:5432/avalon}"

echo "==> Waiting for Postgres..."
until docker exec avalon-postgres pg_isready -U avalon -d avalon >/dev/null 2>&1; do sleep 1; done

echo "==> Generating synthetic data (app schema)..."
python3 generate_data.py --dsn "$DSN" --truncate "$@"

echo "==> Loading the warehouse star schema..."
docker exec -i avalon-postgres psql -U avalon -d avalon -v ON_ERROR_STOP=1 < load_warehouse.sql

echo "==> Done."
