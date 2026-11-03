#!/bin/sh
# Local apenas: o desafio pede 2 instâncias PostgreSQL no Compose para 3 serviços.
# O postgres-flags hospeda flags_db (criado pelo POSTGRES_DB) e também targeting_db.
# Na AWS cada serviço tem o próprio RDS.
set -eu
# No entrypoint do Postgres, conecta pelo socket local com o usuário da imagem.
export PGUSER="${PGUSER:-${POSTGRES_USER:-postgres}}" PGDATABASE="${PGDATABASE:-${POSTGRES_DB:-postgres}}"
psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE targeting_db"
psql -v ON_ERROR_STOP=1 -d targeting_db -f /sql/targeting-init.sql
