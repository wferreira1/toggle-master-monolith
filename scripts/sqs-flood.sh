#!/usr/bin/env bash
# Envia N mensagens para a fila SQS (formato do EvaluationEvent do evaluation-service)
# para demonstrar o KEDA escalando o analytics-service pela profundidade da fila.
# Uso: ./scripts/sqs-flood.sh [quantidade]   (padrão: 2000, em lotes de 10)
set -euo pipefail
cd "$(dirname "$0")/.."
TOTAL="${1:-2000}"
export AWS_REGION="${AWS_REGION:-us-east-1}" AWS_PAGER=""
QUEUE_URL="${AWS_SQS_URL:-$(grep '^AWS_SQS_URL=' infra/infra-ids.env | cut -d= -f2-)}"

batch() { # $1 = número do lote
  local entries="" ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  for i in 0 1 2 3 4 5 6 7 8 9; do
    local n=$(( $1 * 10 + i )) result=true
    (( n % 2 )) && result=false
    entries+="{\"Id\":\"m$i\",\"MessageBody\":\"{\\\"user_id\\\":\\\"flood-user-$n\\\",\\\"flag_name\\\":\\\"enable-new-dashboard\\\",\\\"result\\\":$result,\\\"timestamp\\\":\\\"$ts\\\"}\"},"
  done
  aws sqs send-message-batch --queue-url "$QUEUE_URL" --entries "[${entries%,}]" --query 'length(Successful)' --output text >/dev/null
}
export -f batch; export QUEUE_URL

echo "Enviando $TOTAL mensagens para $QUEUE_URL ..."
seq 0 $(( TOTAL / 10 - 1 )) | xargs -P 16 -I{} bash -c 'batch {}'
aws sqs get-queue-attributes --queue-url "$QUEUE_URL" \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
  --query 'Attributes' --output table
