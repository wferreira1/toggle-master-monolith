#!/bin/sh
# Cadastra no auth-service a chave de serviço usada pelo evaluation-service
# (SERVICE_API_KEY) para chamar flag-service e targeting-service.
# O auth-service guarda só o SHA-256 da chave, então gravamos o hash.
# Idempotente: pode rodar várias vezes.
#
# Uso: DATABASE_URL=... SERVICE_API_KEY=... seed-service-key.sh
#  ou, no entrypoint do Postgres, sem DATABASE_URL (usa o socket local).
set -eu
# No entrypoint do Postgres, conecta pelo socket local com o usuário da imagem.
export PGUSER="${PGUSER:-${POSTGRES_USER:-postgres}}" PGDATABASE="${PGDATABASE:-${POSTGRES_DB:-postgres}}"
: "${SERVICE_API_KEY:?SERVICE_API_KEY deve ser definida}"

psql ${DATABASE_URL:+"$DATABASE_URL"} -v ON_ERROR_STOP=1 -v key="$SERVICE_API_KEY" <<'SQL'
INSERT INTO api_keys (name, key_hash)
VALUES ('evaluation-service', encode(sha256(convert_to(:'key', 'UTF8')), 'hex'))
ON CONFLICT (key_hash) DO NOTHING;
SQL
echo "Chave de serviço do evaluation-service cadastrada."
