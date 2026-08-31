# `dop-infra` — infraestrutura da plataforma DOP

> **Status:** Aprovada para revisão · **Data:** 2026-08-29 · **Projeto:** plataforma DOP
>
> **Responde:** onde vive a infraestrutura, como QA/stage/prod nascem sem duplicar
> declaração, e como um desenvolvedor sobe as dependências localmente.
>
> **Não responde:** qual é o alvo de computação (P-4), qual é o banco (SP-3), qual é a
> topologia de componentes (SP-1). Ver [`ROADMAP.md`](../../ROADMAP.md).

Decisão de base: [ADR-0001](../../adr/0001-infraestrutura-atras-de-portas.md) — é ela que
define o que precisa de emulador e o que não precisa.

## 1. Estado desta entrega

O `dop-infra` nasce com **duas velocidades deliberadamente diferentes**:

| Parte | Estado nesta entrega |
|---|---|
| **Terraform** | **Estrutura, sem resources.** Ainda não há projeto encorpado para publicar versão; provisionar agora seria construir para jogar fora |
| **Ambiente local (k3s)** | **Funcional.** Os emuladores sobem, e um desenvolvedor consegue trabalhar contra eles |

A assimetria é intencional: a estrutura do Terraform é problema conhecido e vale fixar
cedo, mas seu conteúdo depende de decisões que ainda não foram tomadas. O ambiente local
não depende de nenhuma delas — as dependências de infraestrutura já são conhecidas.

## 2. Estrutura do repositório

```
dop-infra/
├── README.md
├── Makefile                    mínimo: guarda de contexto + atalhos; ENV obrigatório no Terraform
├── terraform/
│   ├── bootstrap/              projetos, bucket de estado, SAs do CI — aplicado uma vez
│   ├── modules/                blocos reutilizáveis; nenhum valor de ambiente dentro
│   │   ├── project-baseline/   APIs, IAM base, logging, orçamento
│   │   ├── identity/           Firebase Auth + provedores OAuth
│   │   ├── secrets/            Secret Manager + Workload Identity
│   │   ├── network/
│   │   ├── runtime-service/    aguarda SP-5 / P-4
│   │   └── data/               aguarda SP-3
│   └── stacks/
│       └── platform/           ÚNICO root module
│           ├── main.tf  variables.tf  outputs.tf  versions.tf  backend.tf
│           └── envs/
│               ├── qa.tfvars      qa.backend.hcl
│               ├── stage.tfvars   stage.backend.hcl
│               └── prod.tfvars    prod.backend.hcl
├── k3s/
│   ├── emulators/              SÓ o que não tem adaptador nativo
│   │   └── firebase-auth/
│   ├── services/               serviços reais de apoio ao desenvolvimento
│   │   ├── minio/
│   │   └── mongodb/
│   └── overlays/local/         composição do ambiente local
└── docs/
```

## 3. Terraform — organização

**Um projeto GCP por ambiente:** `dop-qa`, `dop-stage`, `dop-prod`. IAM, cotas,
faturamento e limites de API isolados de verdade; erro em QA não alcança produção por
acidente.

**Um único root module.** Os arquivos `qa.tfvars`, `stage.tfvars` e `prod.tfvars` mudam
**valores**, nunca declarações. Um resource novo aparece uma vez, dentro de um módulo, e
os três ambientes o ganham juntos. É o requisito de "não duplicidade de resources".

**Estado por ambiente via `-backend-config`**, num arquivo `.backend.hcl` por ambiente.
Não se usa `terraform workspace`: workspaces compartilham configuração de backend e
credenciais, e "esqueci de trocar de workspace" é um modo de falha que aplica QA em
produção. Com projeto por ambiente, o alvo tem que estar **explícito no comando**.

**Proteções desde já**, mesmo sem resources: `prevent_destroy` previsto nos módulos de
dado, `deletion_protection` ligado em `prod.tfvars`, service account de CI por ambiente
com permissão apenas no projeto dela, e um `Makefile` que recusa executar sem `ENV`.

**O que "vazio" significa exatamente:** os diretórios, `versions.tf`, `backend.tf` e as
declarações de variável existem; **não há bloco `resource`**. O esqueleto precisa passar
em `terraform fmt -check` e `terraform validate` — estrutura válida que não provisiona
nada. `bootstrap/` fica documentado e **não aplicado**.

**Dois módulos nascem só com interface.** `runtime-service/` e `data/` recebem variáveis e
outputs, sem implementação, até que SP-5 decida onde a execução roda e SP-3 decida o
banco. Módulo com fronteira definida e miolo pendente é honesto; módulo chutado é dívida.

## 4. Ambiente local — o que sobe

### 4.1 O cluster

**Não existe cluster local na máquina hoje** — nem k3s, k3d, kind ou minikube. Há
`kubectl` (com Kustomize embutido, dispensando o binário avulso) e `docker`.

O cluster é provisionado com **k3d**: é o próprio k3s empacotado para rodar em Docker.
Instala-se com um binário, cria e destrói em segundos, e mantém a fidelidade ao k3s que
a portabilidade da ADR-0001 pressupõe. Instalar k3s nativo exigiria systemd e privilégio
de root, tomando a rede do host — custo desproporcional para um ambiente de
desenvolvimento descartável.

Cluster `dop-local`, que produz o contexto `k3d-dop-local`.

### 4.2 Guarda de contexto — requisito rígido

O `kubectl` desta máquina aponta hoje para **`sar-sicar-prod`, namespace de produção de
um projeto de cliente sem relação com o DOP**, num cluster OKD remoto. Um `apply`
descuidado implantaria os emuladores em produção alheia.

**A única automação que existe é a guarda de contexto**, num `Makefile` mínimo: cada
alvo que fala com cluster verifica antes que `kubectl config current-context` seja
exatamente `k3d-dop-local` e **recusa executar** caso não seja — antes do comando, nunca
como aviso. Não é conveniência: é a diferença entre um ambiente de desenvolvimento e um
incidente. Fora essa guarda, nada de script; comando composto só nasce quando a repetição
doer de verdade.

### 4.3 Os componentes

Namespace `dop-local`, composto por Kustomize. **Construído e testado em 2026-08-31.**

| Componente | Papel | Porta |
|---|---|---|
| **PostgreSQL 17 + pgvector** | Estado, log de eventos e busca semântica (ADR-0018) | 5432 |
| **NATS JetStream** | Broker de eventos (ADR-0019) | 4222 · monitor 8222 |
| **Emuladores Firebase** | Auth e Storage — mesmo SDK da produção (ADR-0020) | 9099 · 9199 · hub 4400 |

**Kustomize, não Helm** — conjunto pequeno e interno; sem linguagem de template a
aprender, e o overlay `local` expressa literalmente "a base mais os emuladores".

**Tudo é declarativo — não há script de orquestração.** O que num ambiente de
`docker compose` exigiria um `dev.sh` (criar diretório de dados, importar condicional,
esperar ficar pronto, dar tempo ao encerramento, resetar volume root-owned) o Kubernetes
resolve em manifesto:

| Necessidade | Recurso |
|---|---|
| persistência entre reinícios | PVC |
| `--import` condicional | `if` no `command` do container — a lógica vive no pod |
| tempo para o `--export-on-exit` concluir | `terminationGracePeriodSeconds: 30` |
| configuração compartilhada com o deploy | ConfigMap a partir dos arquivos versionados |
| reset dos dados | `kubectl delete pvc` — sem malabarismo de permissão |
| esperar ficar pronto | `readinessProbe` |

Operação do dia a dia: `kubectl apply -k`, `k3d cluster start/stop` e **k9s** para logs,
exec e inspeção.

**A imagem do emulador é construída aqui, não puxada da comunidade.** O Firebase não
publica container oficial só do emulador de Auth; a alternativa seria confiar numa imagem
de terceiro. Constrói-se uma imagem fina sobre Node com `firebase-tools` **em versão
fixada** — coerente com a postura de cadeia de suprimentos que o `dop-app` já adota, onde
o `pnpm-workspace.yaml` impõe idade mínima de release contra ataque de supply chain.

**Consumo medido:** ~958 MB no total (cluster 935 + LB 10 + registry 13). O emulador é o
mais pesado por ser Java; `k3d cluster stop` devolve tudo preservando os dados.

## 5. Emulador não é adaptador

A distinção que governa o que entra em `k3s/emulators/`, e que é fácil de errar:

| Serviço | Nuvem | Local | Por quê |
|---|---|---|---|
| Identidade | Firebase Auth | **Emulador** | Emissão e verificação de token não se reimplementa |
| Segredos | Secret Manager | **Secret do k8s** | Já é adaptador da ADR-0001. Emular seria duplicar trabalho |
| Objetos | GCS / Firebase Storage | **Emulador Firebase Storage** | Mesmo SDK e semântica da produção; MinIO só se surgir cliente sem GCP |
| Banco | Cloud SQL Postgres | container real | Banco roda igual local; não é emulação |
| Serviços | a decidir | container no k3s | Cloud Run não tem emulador; container é o denominador comum |

**Regra: só entra em `emulators/` o que não tem adaptador nativo.** Hoje a lista tem
**um item** — o Emulator Suite do Firebase, que cobre Auth e Storage no mesmo processo.

**Armadilhas resolvidas na construção** (detalhadas em `dop-infra/docs/ambiente-local.md`):
`HOME` gravável para usuário arbitrário; JARs baixados na build; JDK 21; a probe checa o
**hub (4400)**, não a UI (que só sobe se algum emulador tiver UI); e tag de imagem
versionada, porque reconstruir com a mesma tag não garante que o pod puxe a nova camada.

## 6. Absorção do `infra/` da raiz

O meta-repositório tem `infra/` com um `docker-compose.yml` esqueleto e dois Dockerfiles,
criados no bootstrap do projeto e nunca preenchidos.

**O `dop-infra` assume o ambiente local e o `infra/` da raiz é removido.** Manter os dois
garante que um desatualiza em silêncio, e não há investimento a preservar. O k3s local
também é mais próximo do alvo de produção do que o compose, encurtando a distância entre
"funciona na minha máquina" e "funciona no cluster".

## 7. Repositório

`Digital-Business-One/dop-infra`, privado, **submodule** em `repos/dop-infra` — consistente
com `dop-api`, `dop-app` e `dop-cli`, todos componentes da plataforma.

## 8. Verificação

O critério é assimétrico, como a entrega:

**Terraform** — `terraform fmt -check` e `terraform init -backend=false && terraform
validate` passam no stack `platform`. Nada é aplicado.

**Local** — o overlay sobe num k3s real e os três componentes respondem:

0. A guarda de contexto **recusa** executar quando o contexto ativo não é
   `k3d-dop-local` — testado deliberadamente antes de qualquer outra coisa.
1. `make up` (guarda de contexto + `kubectl apply -k`) deixa os pods `Running`.
2. O emulador Firebase Auth responde na 9099.
3. O MinIO aceita criação de bucket.
4. O MongoDB aceita conexão e um `ping`.
5. `make down` remove o namespace sem deixar resíduo; `make reset` apaga os PVCs.

## 9. Riscos e pendências

| # | |
|---|---|
| R-1 | **Emulador de Auth não é Firebase.** Diferenças de comportamento aparecem sob autenticação federada e account linking — exatamente o que a spec de identidade exige desde o dia um. O emulador valida fluxo, não equivalência |
| R-2 | **Imagem própria do emulador exige manutenção** — `firebase-tools` fixado envelhece e precisa de atualização deliberada |
| R-3 | **Contexto de `kubectl` apontando para produção alheia.** O estado atual da máquina é exatamente esse. Mitigado pela guarda de §4.2, que é obrigatória em todo alvo |
| R-4 | **k3d não é idêntico a um k3s nativo** em rede e armazenamento. Suficiente para as dependências desta spec; deixa de ser quando o plano de execução (P-4) entrar |
| R-5 | **Terraform vazio por muito tempo apodrece.** Estrutura sem uso não é exercitada; quando os resources chegarem, a organização pode não servir. Mitigação: `validate` no CI desde já |
| P-4 | Alvo de computação — Cloud Run × cluster. Bloqueia `modules/runtime-service/` |
| SP-3 | Escolha do banco. Bloqueia `modules/data/` e confirma ou troca o MongoDB local |
