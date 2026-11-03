#!/usr/bin/env bash
# Provisiona os recursos AWS da Fase 2 (fora o cluster, que vem do eksctl).
# Idempotente: pode ser executado de novo; recursos existentes são reaproveitados.
#
# Uso:
#   ./infra/provision-aws.sh base   # ECR, SQS e DynamoDB (não dependem da VPC)
#   ./infra/provision-aws.sh data   # 3 RDS + ElastiCache (precisa do cluster/VPC)
#   ./infra/provision-aws.sh all
#
# RDS_DBS define quais RDS criar (padrão: os 3 do desafio). Contas no Free plan
# da AWS aceitam só 2 instâncias RDS; nesse caso use RDS_DBS="auth flags" e o
# targeting_db é criado como segundo database dentro do RDS do flags.
#
# Endpoints e senhas vão para infra/infra-ids.env (chmod 600, fora do Git).
set -euo pipefail
cd "$(dirname "$0")"

export AWS_REGION="${AWS_REGION:-us-east-1}" AWS_DEFAULT_OUTPUT=text AWS_PAGER=""
CLUSTER="togglemaster-fase2"
IDS="infra-ids.env"
TAGS="Key=project,Value=togglemaster Key=phase,Value=2"
RDS_DBS="${RDS_DBS:-auth flags targeting}"
SERVICES=(auth-service flag-service targeting-service evaluation-service analytics-service)

touch "$IDS"; chmod 600 "$IDS"
save() { grep -v "^$1=" "$IDS" > "$IDS.tmp" || true; echo "$1=$2" >> "$IDS.tmp"; mv "$IDS.tmp" "$IDS"; chmod 600 "$IDS"; }
get()  { grep "^$1=" "$IDS" 2>/dev/null | cut -d= -f2- || true; }
log()  { printf '\033[1;32m==> %s\033[0m\n' "$*"; }

provision_base() {
  log "ECR: 5 repositórios"
  for s in "${SERVICES[@]}"; do
    aws ecr describe-repositories --repository-names "togglemaster-$s" >/dev/null 2>&1 ||
      aws ecr create-repository --repository-name "togglemaster-$s" \
        --image-scanning-configuration scanOnPush=true --tags $TAGS >/dev/null
    echo "   togglemaster-$s"
  done

  log "SQS: filas Standard"
  for q in togglemaster-events togglemaster-events-local; do
    url=$(aws sqs create-queue --queue-name "$q" --tags project=togglemaster --query QueueUrl)
    echo "   $url"
  done
  save AWS_SQS_URL "$(aws sqs get-queue-url --queue-name togglemaster-events --query QueueUrl)"
  save LOCAL_SQS_URL "$(aws sqs get-queue-url --queue-name togglemaster-events-local --query QueueUrl)"

  log "DynamoDB: ToggleMasterAnalytics (PK event_id)"
  aws dynamodb describe-table --table-name ToggleMasterAnalytics >/dev/null 2>&1 ||
    aws dynamodb create-table --table-name ToggleMasterAnalytics \
      --attribute-definitions AttributeName=event_id,AttributeType=S \
      --key-schema AttributeName=event_id,KeyType=HASH \
      --billing-mode PAY_PER_REQUEST --tags $TAGS >/dev/null
  aws dynamodb wait table-exists --table-name ToggleMasterAnalytics
  echo "   ok"
}

provision_data() {
  log "Rede: lendo VPC, subnets privadas e Security Group do cluster"
  VPC=$(aws eks describe-cluster --name "$CLUSTER" --query cluster.resourcesVpcConfig.vpcId)
  CLUSTER_SG=$(aws eks describe-cluster --name "$CLUSTER" --query cluster.resourcesVpcConfig.clusterSecurityGroupId)
  PRIVATE_SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC" "Name=tag:kubernetes.io/role/internal-elb,Values=1" \
    --query 'Subnets[].SubnetId')
  echo "   VPC=$VPC  ClusterSG=$CLUSTER_SG  Subnets=$PRIVATE_SUBNETS"

  log "Security Group de dados: 5432/6379 só a partir do SG do cluster"
  DATA_SG=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC" "Name=group-name,Values=togglemaster-data" \
    --query 'SecurityGroups[0].GroupId')
  if [[ "$DATA_SG" == "None" || -z "$DATA_SG" ]]; then
    DATA_SG=$(aws ec2 create-security-group --group-name togglemaster-data \
      --description "RDS e ElastiCache - acesso apenas do EKS" --vpc-id "$VPC" \
      --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=sg-togglemaster-data},{Key=project,Value=togglemaster}]" \
      --query GroupId)
    for port in 5432 6379; do
      aws ec2 authorize-security-group-ingress --group-id "$DATA_SG" \
        --protocol tcp --port "$port" --source-group "$CLUSTER_SG" >/dev/null
    done
  fi
  save DATA_SG "$DATA_SG"; echo "   $DATA_SG"

  log "Subnet groups (RDS e ElastiCache) nas subnets privadas"
  aws rds describe-db-subnet-groups --db-subnet-group-name togglemaster-data >/dev/null 2>&1 ||
    aws rds create-db-subnet-group --db-subnet-group-name togglemaster-data \
      --db-subnet-group-description "Subnets privadas do ToggleMaster" \
      --subnet-ids $PRIVATE_SUBNETS --tags $TAGS >/dev/null
  aws elasticache describe-cache-subnet-groups --cache-subnet-group-name togglemaster-data >/dev/null 2>&1 ||
    aws elasticache create-cache-subnet-group --cache-subnet-group-name togglemaster-data \
      --cache-subnet-group-description "Subnets privadas do ToggleMaster" \
      --subnet-ids $PRIVATE_SUBNETS >/dev/null

  log "RDS: instâncias PostgreSQL ($RDS_DBS)"
  for db in $RDS_DBS; do
    id="togglemaster-$db"
    if ! aws rds describe-db-instances --db-instance-identifier "$id" >/dev/null 2>&1; then
      pass=$(openssl rand -hex 16)
      save "RDS_$(echo "$db" | tr a-z A-Z)_PASSWORD" "$pass"
      aws rds create-db-instance --db-instance-identifier "$id" \
        --engine postgres --engine-version 16 --db-instance-class db.t4g.micro \
        --allocated-storage 20 --storage-type gp3 \
        --master-username togglemaster --master-user-password "$pass" \
        --db-name "${db}_db" --db-subnet-group-name togglemaster-data \
        --vpc-security-group-ids "$DATA_SG" --no-publicly-accessible --no-multi-az \
        --backup-retention-period 0 --tags $TAGS >/dev/null
      echo "   $id criado"
    else
      echo "   $id já existe"
    fi
  done

  log "ElastiCache: Redis (1 nó)"
  aws elasticache describe-cache-clusters --cache-cluster-id togglemaster-redis >/dev/null 2>&1 ||
    aws elasticache create-cache-cluster --cache-cluster-id togglemaster-redis \
      --engine redis --cache-node-type cache.t4g.micro --num-cache-nodes 1 \
      --cache-subnet-group-name togglemaster-data --security-group-ids "$DATA_SG" \
      --tags $TAGS >/dev/null

  log "Aguardando RDS e ElastiCache ficarem disponíveis (5-10 min)"
  for db in $RDS_DBS; do
    aws rds wait db-instance-available --db-instance-identifier "togglemaster-$db"
    ep=$(aws rds describe-db-instances --db-instance-identifier "togglemaster-$db" \
      --query 'DBInstances[0].Endpoint.Address')
    save "RDS_$(echo "$db" | tr a-z A-Z)_ENDPOINT" "$ep"; echo "   togglemaster-$db: $ep"
  done
  aws elasticache wait cache-cluster-available --cache-cluster-id togglemaster-redis
  ep=$(aws elasticache describe-cache-clusters --cache-cluster-id togglemaster-redis \
    --show-cache-node-info --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address')
  save REDIS_ENDPOINT "$ep"; echo "   togglemaster-redis: $ep"
}

case "${1:-all}" in
  base) provision_base ;;
  data) provision_data ;;
  all)  provision_base; provision_data ;;
  *) echo "uso: $0 [base|data|all]"; exit 1 ;;
esac
log "Concluído. Valores em infra/$IDS"
