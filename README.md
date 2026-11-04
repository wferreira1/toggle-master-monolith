# ToggleMaster — Tech Challenge Fase 2

O projeto evolui o MVP monolítico da Fase 1 para um ecossistema de cinco microsserviços (código oficial do desafio) containerizados e implantados no Kubernetes/EKS.

## Estrutura

```text
services/                Código oficial dos 5 microsserviços (github.com/FIAP-TCs) + Dockerfiles
  auth-service/          Go     · PostgreSQL  · :8001  /validate, /admin/keys
  flag-service/          Python · PostgreSQL  · :8002  /flags
  targeting-service/     Python · PostgreSQL  · :8003  /rules
  evaluation-service/    Go     · Redis + SQS · :8004  /evaluate
  analytics-service/     Python · SQS -> DynamoDB · :8005  (worker, só /health)
db/                      Scripts de init dos bancos locais e cadastro da chave de serviço
k8s/                     Namespace, Deployments, Services, ConfigMap, Secret, Ingress, HPA, KEDA
infra/                   EKS (eksctl), IAM e roteiro de provisionamento AWS
scripts/                 demo-local.sh e build-and-push.sh
```

### Ajustes feitos no código oficial

O código dos professores foi usado como veio. Mudamos só o necessário para ele compilar e rodar:

| Serviço | Problema | Correção |
|---|---|---|
| auth-service | `go.mod` declara `pgx/v4/stdlib` como módulo (inválido) e há imports sem uso; o driver `pgx` era importado sem `_` e não se registrava | linha removida do `go.mod`, imports limpos, `_ "github.com/jackc/pgx/v4/stdlib"`, `go.sum` gerado |
| evaluation-service | `context` importado sem uso, `os` usado sem import, `go.sum` era cópia do `go.mod` | imports corrigidos, `go.sum` regenerado |
| flag / targeting | `psycopg2-binary==2.9.5` traz libpq sem suporte a SCRAM (padrão do Postgres 14+/RDS) | `psycopg2-binary==2.9.10` |
| flag / targeting / analytics | `Flask==2.2.2` puxa Werkzeug 3, incompatível | `Werkzeug==2.2.2` fixado |
| analytics-service | `boto3==1.26.50` não aceita endpoint por variável de ambiente (DynamoDB Local) | `boto3==1.35.99` |

Os serviços não criam as próprias tabelas. Os `db/init.sql` oficiais rodam no init do Postgres local e, no Kubernetes, num initContainer.
O evaluation-service precisa de uma chave de API (`SERVICE_API_KEY`) cadastrada no auth-service. Ela é semeada (só o hash SHA-256) por `db/seed-service-key.sh`.

## Execução local

Pré-requisitos: Docker Desktop (Compose v2).

```bash
docker compose up --build -d
docker compose ps          # 9 contêineres: 5 apps + 2 PostgreSQL + Redis + DynamoDB Local
./scripts/demo-local.sh    # chave -> flag -> regra 50% -> avaliações
```

O desafio pede 2 PostgreSQL localmente para 3 serviços. Por isso o `postgres-flags` hospeda `flags_db` e `targeting_db`. Na AWS são 3 RDS independentes.

Como não há emulador de SQS entre os 9 contêineres, o fluxo evaluation → SQS → analytics → DynamoDB Local usa uma fila SQS real. Coloque `LOCAL_SQS_URL=https://sqs.us-east-1.amazonaws.com/<conta>/togglemaster-events-local` num arquivo `.env` (não versionado). As credenciais vêm de `~/.aws`. Sem essa variável, o evaluation só registra os eventos no log.

## AWS/EKS

Leia [`infra/PROVISIONAMENTO-AWS.md`](infra/PROVISIONAMENTO-AWS.md) antes de criar recursos. O roteiro cobre:

- EKS com nós gerenciados e Auto Scaling 1/2/4;
- cinco repositórios ECR e publicação das imagens;
- três RDS PostgreSQL independentes, ElastiCache Redis, DynamoDB e SQS;
- Metrics Server, Nginx Ingress, Secrets Manager/External Secrets e IRSA;
- fallback AWS Academy com `LabRole`, HPA por CPU e Secret local base64 não versionado.

Depois de publicar as imagens:

```bash
kubectl apply -k k8s/overlays/aws
kubectl -n togglemaster get pods,svc,ingress,hpa
```

Substitua o account ID e a tag no overlay `k8s/overlays/aws/kustomization.yaml`, ou use `scripts/build-and-push.ps1` e ajuste o overlay antes do `kubectl apply`.

## Documentação da entrega

- [Vídeo da Fase 2](https://youtu.be/L5yOFp3EYJU)
- [Relatório da Fase 2](entregaveis/fase-2/fase-2.md)
- [Arquitetura da Fase 2](docs/ARQUITETURA-FASE-2.md)
- [Diagrama Mermaid](docs/arquitetura-fase-2.mmd)
- [Análise da Fase 1](docs/ANALISE-ARQUITETURA.md)
- [Relatório da Fase 1](entregaveis/fase-1/fase-1.md)

## Encerramento

Depois da avaliação, remova o cluster, RDS, ElastiCache, fila, tabela e repositórios ECR para evitar custos contínuos. Não versione credenciais, URLs reais de banco ou chaves AWS.
