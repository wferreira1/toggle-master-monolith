#!/usr/bin/env bash
# Remove TODOS os recursos da Fase 2 para parar a cobrança.
# Ordem: Load Balancer (via Ingress) -> dados -> cluster/VPC -> filas, tabela, ECR.
# Uso: ./infra/teardown-aws.sh   (pede confirmação)
set -euo pipefail
cd "$(dirname "$0")"
export AWS_REGION="${AWS_REGION:-us-east-1}" AWS_DEFAULT_OUTPUT=text AWS_PAGER=""
CLUSTER=togglemaster-fase2
log() { printf '\033[1;31m==> %s\033[0m\n' "$*"; }

read -r -p "Apagar o ambiente ToggleMaster Fase 2 na conta $(aws sts get-caller-identity --query Account)? Digite 'apagar': " ok
[[ "$ok" == "apagar" ]] || { echo "Cancelado."; exit 1; }

log "Kubernetes: apps e Nginx Ingress (remove o NLB antes de apagar a VPC)"
kubectl delete namespace togglemaster --ignore-not-found --wait=true || true
helm uninstall ingress-nginx -n ingress-nginx --wait 2>/dev/null || true
helm uninstall keda -n keda --wait 2>/dev/null || true

log "RDS (sem snapshot final)"
DBS=$(aws rds describe-db-instances --query 'DBInstances[?starts_with(DBInstanceIdentifier,`togglemaster-`)].DBInstanceIdentifier')
for db in $DBS; do
  aws rds delete-db-instance --db-instance-identifier "$db" --skip-final-snapshot --delete-automated-backups >/dev/null && echo "   $db"
done

log "ElastiCache"
aws elasticache delete-cache-cluster --cache-cluster-id togglemaster-redis >/dev/null 2>&1 && echo "   togglemaster-redis" || true

for db in $DBS; do aws rds wait db-instance-deleted --db-instance-identifier "$db"; done
aws elasticache wait cache-cluster-deleted --cache-cluster-id togglemaster-redis 2>/dev/null || true

log "Subnet groups e Security Group de dados"
aws rds delete-db-subnet-group --db-subnet-group-name togglemaster-data 2>/dev/null || true
aws elasticache delete-cache-subnet-group --cache-subnet-group-name togglemaster-data 2>/dev/null || true
SG=$(grep '^DATA_SG=' infra-ids.env 2>/dev/null | cut -d= -f2 || true)
[[ -n "$SG" ]] && aws ec2 delete-security-group --group-id "$SG" 2>/dev/null || true

log "EKS: cluster, node group, roles IRSA e VPC (10-15 min)"
eksctl delete cluster --name "$CLUSTER" --region "$AWS_REGION" --wait --disable-nodegroup-eviction || true

log "SQS, DynamoDB e ECR"
for q in togglemaster-events togglemaster-events-local; do
  url=$(aws sqs get-queue-url --queue-name "$q" --query QueueUrl 2>/dev/null) && aws sqs delete-queue --queue-url "$url" && echo "   $q"
done
aws dynamodb delete-table --table-name ToggleMasterAnalytics >/dev/null 2>&1 && echo "   ToggleMasterAnalytics" || true
for s in auth-service flag-service targeting-service evaluation-service analytics-service; do
  aws ecr delete-repository --repository-name "togglemaster-$s" --force >/dev/null 2>&1 && echo "   togglemaster-$s" || true
done

log "Verificação final (deve vir vazio)"
aws eks list-clusters --query clusters
aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier'
aws elasticache describe-cache-clusters --query 'CacheClusters[].CacheClusterId'
aws ec2 describe-nat-gateways --filter Name=state,Values=available --query 'NatGateways[].NatGatewayId'
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName'
echo "Pronto. Apague infra/infra-ids.env se não for recriar o ambiente."
