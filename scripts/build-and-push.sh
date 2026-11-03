#!/usr/bin/env bash
# Builda as 5 imagens para linux/amd64 (nós t3 do EKS) e publica no ECR.
# Uso: ./scripts/build-and-push.sh [tag]   (tag padrão: v1)
set -euo pipefail
TAG="${1:-v1}"
REGION="${AWS_REGION:-us-east-1}"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

for s in auth-service flag-service targeting-service evaluation-service analytics-service; do
  img="$REGISTRY/togglemaster-$s:$TAG"
  echo "==> $img"
  docker buildx build --platform linux/amd64 -t "$img" --push "services/$s"
done
echo "Imagens publicadas em $REGISTRY com a tag $TAG"
