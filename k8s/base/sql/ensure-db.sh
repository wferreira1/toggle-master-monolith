#!/bin/sh
# initContainer: garante que o database de DATABASE_URL existe e aplica o schema.
# Uso: ensure-db.sh <arquivo.sql>
# O CREATE DATABASE só é necessário quando dois serviços dividem um RDS
# (ex.: targeting_db dentro do RDS do flags, no Free plan da AWS).
set -eu
DB=$(echo "$DATABASE_URL" | sed -E 's#^[^/]*//[^/]*/([^?]*).*#\1#')
ADMIN_URL=$(echo "$DATABASE_URL" | sed -E "s#/$DB([?]|\$)#/postgres\\1#")

until pg_isready -d "$ADMIN_URL" -q; do echo "aguardando o banco..."; sleep 3; done
if [ "$(psql "$ADMIN_URL" -tAc "SELECT 1 FROM pg_database WHERE datname = '$DB'")" != "1" ]; then
  psql "$ADMIN_URL" -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"$DB\""
fi
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$1"
echo "Schema $1 aplicado em $DB"
