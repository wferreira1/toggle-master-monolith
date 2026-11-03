#!/usr/bin/env bash
# Cria/atualiza o Secret togglemaster-runtime a partir de infra/infra-ids.env
# (gerado por infra/provision-aws.sh). Nada é gravado no Git: o kubectl
# codifica os valores em base64 e envia direto para o cluster.
# MASTER_KEY e SERVICE_API_KEY são geradas uma vez e guardadas no mesmo arquivo.
set -euo pipefail
cd "$(dirname "$0")/.."
IDS=infra/infra-ids.env
get() { grep "^$1=" "$IDS" | cut -d= -f2-; }
gen() { if ! grep -q "^$1=" "$IDS"; then echo "$1=$2" >> "$IDS"; fi; get "$1"; }

MASTER_KEY=$(gen MASTER_KEY "$(openssl rand -hex 16)")
SERVICE_API_KEY=$(gen SERVICE_API_KEY "tm_key_$(openssl rand -hex 32)")
url() { echo "postgres://togglemaster:$(get "RDS_$1_PASSWORD")@$(get "RDS_$1_ENDPOINT"):5432/$2?sslmode=require"; }
# Free plan: sem RDS próprio para o targeting, o targeting_db fica no RDS do flags.
TARGETING_RDS=TARGETING; grep -q '^RDS_TARGETING_ENDPOINT=' "$IDS" || TARGETING_RDS=FLAGS

kubectl create namespace togglemaster --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n togglemaster create secret generic togglemaster-runtime \
  --from-literal=AUTH_DATABASE_URL="$(url AUTH auth_db)" \
  --from-literal=FLAGS_DATABASE_URL="$(url FLAGS flags_db)" \
  --from-literal=TARGETING_DATABASE_URL="$(url $TARGETING_RDS targeting_db)" \
  --from-literal=REDIS_URL="redis://$(get REDIS_ENDPOINT):6379" \
  --from-literal=AWS_SQS_URL="$(get AWS_SQS_URL)" \
  --from-literal=MASTER_KEY="$MASTER_KEY" \
  --from-literal=SERVICE_API_KEY="$SERVICE_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "Secret togglemaster-runtime aplicado (chaves: $(kubectl -n togglemaster get secret togglemaster-runtime -o jsonpath='{.data}' | python3 -c 'import sys,json;print(", ".join(json.load(sys.stdin)))'))"
