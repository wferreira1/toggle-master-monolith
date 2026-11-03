#!/usr/bin/env bash
# Fluxo ponta a ponta dos 5 microsserviços.
# Uso: ./scripts/demo-local.sh                       (Docker Compose, portas 8001-8005)
#      BASE_URL=http://<load-balancer> ./scripts/demo-local.sh   (via Ingress)
set -euo pipefail

MASTER_KEY="${MASTER_KEY:-admin-secreto-123}"
FLAG="${FLAG:-enable-new-dashboard}"

if [[ -n "${BASE_URL:-}" ]]; then
  AUTH="$BASE_URL/auth"; FLAGS="$BASE_URL"; TARGETING="$BASE_URL"; EVAL="$BASE_URL"
else
  AUTH=http://localhost:8001; FLAGS=http://localhost:8002
  TARGETING=http://localhost:8003; EVAL=http://localhost:8004
fi

c() { curl -sS -m 10 "$@"; echo; }
step() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }

if [[ -z "${BASE_URL:-}" ]]; then
  step "Health checks"
  for p in 8001 8002 8003 8004 8005; do printf '%s ' "$p"; c "http://localhost:$p/health"; done
fi

step "Criar chave de API no auth-service (MASTER_KEY)"
RESP=$(curl -sS -m 10 -X POST "$AUTH/admin/keys" \
  -H "Authorization: Bearer $MASTER_KEY" -H 'Content-Type: application/json' \
  -d '{"name":"demo-video"}')
echo "$RESP"
KEY=$(echo "$RESP" | python3 -c 'import sys,json; print(json.load(sys.stdin)["key"])')

step "Validar a chave"
c "$AUTH/validate" -H "Authorization: Bearer $KEY"

step "Acessar flag-service sem chave (deve dar 401)"
c "$FLAGS/flags"

step "Criar a flag '$FLAG' (ignora 409 se já existir)"
c -X POST "$FLAGS/flags" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d "{\"name\":\"$FLAG\",\"description\":\"Novo dashboard\",\"is_enabled\":true}"

step "Criar regra de segmentação: 50% dos usuários"
c -X POST "$TARGETING/rules" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d "{\"flag_name\":\"$FLAG\",\"is_enabled\":true,\"rules\":{\"type\":\"PERCENTAGE\",\"value\":50}}"

step "Avaliar a flag para vários usuários (hot path com cache Redis)"
for u in user-1 user-2 user-3 user-4 user-5 user-1; do
  c "$EVAL/evaluate?user_id=$u&flag_name=$FLAG"
done

echo
echo "Chave criada (use nas próximas chamadas): $KEY"
