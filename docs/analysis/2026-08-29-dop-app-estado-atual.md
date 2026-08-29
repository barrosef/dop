# `dop-app` — estado atual (análise)

> **Data:** 2026-08-29
> **Base analisada:** branch `dev`, commit `ef9a3de` ("Validate multi-repository commit attribution")
> **Método:** leitura do código, do histórico, do grafo de imports e das capturas de tela versionadas
> **Propósito:** insumo para a rodada de reestruturação

## Sumário

O `dop-app` **deixou de ser um frontend**. Hoje é um **monorepo pnpm** com frontend,
servidor HTTP, servidor de terminal PTY, banco, contrato OpenAPI e pipeline de codegen.
O produto foi rebatizado na interface para **"DOP IDE"** e reorganizado em torno de um
**cockpit único por workspace**, no lugar da navegação por telas do PRD.

Três achados exigem decisão antes de qualquer coisa:

1. **O meta-repositório aponta para o lugar errado.** O submodule está fixado em
   `ad15b82` da `main` — um scaffold de 1 commit. Todo o trabalho real está na `dev`, que
   **não tem ancestral comum com a `main`**. As duas histórias são independentes.
2. **3.523 linhas estão órfãs.** A tela de execução em 7 etapas, construída ao longo dos
   prompts de ajuste 05–17, **não é mais alcançável pela aplicação**. A reestruturação
   para cockpit trocou o roteamento e não reancorou a tela.
3. **O `dop-app` cresceu um backend por dentro.** Existe um servidor Express com terminal
   PTY rodando lá. Isso colide de frente com a arquitetura `dop-core` (núcleo gRPC) +
   `dop-api` (BFF) decidida na conversa anterior.

## 1. Números

| | |
|---|---|
| Commits na `dev` | 42, de 2026-05-28 a 2026-08-27 |
| Volume | 128 arquivos, 16.797 linhas inseridas |
| Arquivos versionados | 233 (133 `.tsx`, 39 `.ts`) |
| Código próprio (sem `ui/` do shadcn) | ~9.600 linhas |
| Código órfão | 3.523 linhas (37% do código próprio) |
| Idiomas | `pt-BR` e `en`, ~430 chaves |
| Capturas de tela versionadas | 13 |

## 2. O que o repositório é hoje

Monorepo pnpm (Node 24, TypeScript 5.9), organizado em `artifacts/` (aplicações) e
`lib/` (pacotes compartilhados):

```
artifacts/
├── dop/               frontend React 19 + Vite 7 + Tailwind 4 + shadcn   (97 arquivos)
├── api-server/        Express 5 + pino + WebSocket + node-pty            (13 arquivos)
└── mockup-sandbox/    sandbox de preview de mockups                      (69 arquivos)
lib/
├── api-spec/          OpenAPI 3.1 + Orval (codegen)
├── api-zod/           schemas Zod gerados + regra de atribuição de commits
├── api-client-react/  cliente react-query gerado
└── db/                Drizzle + PostgreSQL
scripts/               utilitários do workspace
```

### 2.1 O que é substância e o que é andaime

Distinção importante, porque o volume engana:

**Andaime do template Replit, sem conteúdo de produto:**
- `lib/api-spec/openapi.yaml` — declara **um único endpoint**, `GET /healthz`.
- `lib/db/src/schema/index.ts` — **nenhuma tabela**; só o comentário de exemplo e `export {}`.
- `lib/api-zod` e `lib/api-client-react` — gerados a partir do OpenAPI acima, portanto
  contêm apenas `HealthStatus`.
- `replit.md` — template não preenchido, ainda com `# [Project name]` e seções
  "_Populate as you build_".

**Código próprio real no backend — apenas dois arquivos:**
- `artifacts/api-server/src/lib/terminal-server.ts` (270 linhas) — servidor de terminal
  sobre WebSocket + `node-pty`, com limite de 4 sessões, timeout de ociosidade de 20 min,
  teto de 16 KB por entrada, validação de identificadores e confinamento do PTY a uma raiz
  (`DOP_TERMINAL_ROOT`).
- `lib/api-zod/src/repository-commit-attribution.ts` (58 linhas) — regra de domínio, ver §4.

Ou seja: **o backend do `dop-app` não implementa nada do DOP**. Toda a lógica de produto
vive no frontend, alimentada por `mockClient.ts`.

### 2.2 Consequência: o pipeline de codegen está desconectado

O contrato real do produto está em `artifacts/dop/src/lib/api/types.ts` (TypeScript escrito
à mão). O `openapi.yaml` não o descreve. Logo, o cliente gerado por Orval **não é usado**
para dados do DOP — o frontend consome `mockClient` diretamente. A infraestrutura de
codegen existe e está vazia.

## 3. A reestruturação para IDE

O documento `attached_assets/Pasted-Chat-vamos-reestruturar-...txt` registra a instrução
que originou a virada. Seis pontos, e o terceiro é a tese:

> "Vamos pensar mais como IDE, a plataforma é um ambiente de desenvolvimento, não é um
> sistema. Então o foco sempre tem que estar no desenvolvimento e nas atividades
> relacionadas ao dev e ao que um desenvolvedor precisa saber."

O que foi efetivamente implementado dessa instrução:

| Instrução | Estado |
|---|---|
| "demandas" → **cards**, com tipos dinâmicos vindos do provider | ✅ `Card`, `cardTypes: string[]` por workspace; `Demand` mantido como alias |
| Visão detalhada **começa na workspace**, card vira filtro | ✅ Rota única `/workspaces/:id`; card selecionado vira `?card=`; rotas antigas redirecionam |
| Centralizar branches e PRs **dentro de repositórios** | ✅ Árvore `repo → overview / branches / PRs`, com `NodeKind` e navegação nível a nível |
| Sumir com o painel separado de branches/PRs | ✅ Seções do cockpit: `overview`, `chat`, `repos`, `infra` |
| i18n `en` + `pt-BR` | ✅ `i18n.ts`, ~430 chaves nos dois idiomas |
| "Dossiê" → expressão técnica correta | ✅ `DemandDossier` → **`RepositoryOverview`** |

Além do pedido, apareceram duas capacidades de IDE que não estavam em nenhum documento
anterior:

- **Terminal interativo real** — `infra-terminal.tsx` no frontend contra o PTY do
  `api-server`. Não é log simulado: é shell.
- **Runtime com escopo por card** — `RuntimeApp.taskId` e `RuntimeService.taskIds`
  permitem que a mesma aplicação rode em portas diferentes para cards diferentes
  (nos mocks: `portal-backend` nas portas 8080, 8083 e 8084 para os cards d-1, d-3 e d-4).
  Isso é comportamento de ambiente de desenvolvimento paralelo, não de dashboard.

## 4. O contrato evoluiu bem além do PRD

`types.ts` e `client.ts` divergiram substancialmente do `DopApi` preliminar do prompt do
Replit. As mudanças confirmam, no código, várias das tensões levantadas na análise dos 20
prompts de ajuste.

### 4.1 Provider git por repositório — confirmado

```ts
type GitProvider = 'azure_devops' | 'github' | 'gitlab' | 'gitlab_self_hosted' | 'bitbucket';
interface RepoConfig { provider?: GitProvider; ... }   // por REPO
interface Workspace  { gitProvider?: GitProvider; ... } // agora opcional
```

O `gitProvider` da workspace virou opcional e o provider passou para o repositório — e os
mocks já exercitam isso: a workspace "API de Pagamentos" tem repositórios em Azure DevOps
**e** GitLab simultaneamente. **Bitbucket** apareceu, sem constar de nenhum documento.

### 4.2 Task manager plural — antes do previsto

```ts
interface TaskManagerConfig { provider: 'jira' | 'clickup' | 'redmine' | 'custom'; ... }
```

O PRD colocava ClickUp e outros explicitamente **fora de escopo do 1.0**. A interface já
os assume, e os mocks já usam ClickUp.

### 4.3 Tipos novos que não existiam

| Tipo | Origem | O que carrega |
|---|---|---|
| `ExecTask` | prompt 06 | `parallelGroup: number` — paralelismo entre repositórios como dado de primeira classe |
| `ExecFile` | prompt 06.3 | `diff` unificado, `linesAdded`/`linesRemoved`, `error` |
| `TestPlan` | prompt 11 | plano de testes `unit` e `e2e` em Markdown |
| `Reviewer` | prompt 13.5 | `status: 'approved' \| 'rejected' \| 'pending'` por revisor |
| `RuntimeService` | prompt 03.2 | infra com escopo por card |
| `RepositoryOverview` | chat de reestruturação | substitui `DemandDossier` |

E os existentes ganharam corpo: `Stage` agora tem `document`, `execData` e `testPlan`;
`FileTouched` ganhou `gitStatus`, `repo`, `branch`, `diff` e contagem de linhas;
`PullRequest` ganhou `reviewers[]`.

### 4.4 Uma regra de domínio genuína, descoberta pela UI

`repository-commit-attribution.ts` é o achado mais interessante do repositório. É a única
lógica de negócio real escrita, e nasceu de um problema que só aparece quando se tenta
exibir o dado:

> Um card que toca **vários repositórios** não pode reaproveitar um total de commits
> agregado como se fosse de um repositório. Ou há contagem para **todos** os repositórios,
> ou a atribuição é declarada **indisponível**. E, havendo atribuição, o agregado precisa
> bater com a soma.

O schema Zod recusa a carga que violar isso, e o frontend valida **toda** carga de card na
fronteira (`validateCard`). É uma regra que a plataforma precisa honrar do lado do
servidor — e é exatamente o tipo de coisa que aparece ao construir a tela antes da API.

### 4.5 O que a interface ganhou

```ts
listAllCards(): Promise<Card[]>                        // consulta cross-workspace
streamLogs(cardId, source, filter?: { testType, testRepo })   // logs seletivos
```

`listAllCards` é o embrião do requisito R2.9 ("onde sou necessário", visão entre
projetos). O filtro em `streamLogs` atende os prompts 07.1 e 12.

### 4.6 O que os 20 prompts pediram e a interface ainda não tem

- Criar e listar repositórios remotos no provider (prompts 14, 18, 20).
- CRUD e versionamento dos artefatos Markdown — hoje `Stage.document` é uma string de
  leitura, sem caminho de escrita (prompts 05, 11).
- Checklist de validação humana (prompts 12, 16).
- Processo de finalização observável (prompt 17).
- Configuração custom por card e composição de repositórios por card (primeira linha do
  arquivo de prompts + prompt 14).

## 5. Código órfão

Verificado pelo grafo de imports. Nada abaixo é alcançável a partir de `App.tsx`:

| Arquivo | Linhas | Conteúdo |
|---|---|---|
| `pages/card-execution.tsx` | 2.231 | A tela de execução inteira: 7 etapas, chat, dossiê, diffs, PRs |
| `components/test-stage-view.tsx` | 444 | Etapa 5 — testes, barras hierárquicas, badges |
| `components/exec-stage-view.tsx` | 312 | Etapa 4 — execução, progresso por repo e arquivo |
| `components/plan-stage-view.tsx` | 268 | Etapa 3 — plano + abas de plano de testes |
| `pages/cards-list.tsx` | 137 | Listagem de cards anterior ao cockpit |
| `components/doc-viewer.tsx` | 131 | Visualizador Markdown com fonte/preview |
| **Total** | **3.523** | |

Isso é o resultado acumulado dos prompts de ajuste 05 a 17 — planejamento, execução,
testes, validação humana e finalização. A reestruturação para cockpit substituiu o
roteamento (`/workspaces/:id/cards/:cardId` agora redireciona para `/workspaces/:id`) sem
reancorar a tela em lugar nenhum.

**Não é lixo.** É a única implementação existente do modelo de etapas, e o cockpit atual
não tem substituto para ela: o `contextual-overview.tsx` (340 linhas, vivo) cobre KPIs,
QA, infraestrutura e Allure, mas não cobre execução por etapas.

A decisão sobre esse código — reancorar, reescrever ou descartar — é uma das questões da
reestruturação.

## 6. Riscos e pendências

| # | Item | Detalhe |
|---|---|---|
| A-1 | **Ponteiro do submodule inválido** | O meta-repo fixa `ad15b82` (`main`, scaffold). Um `git submodule update` descarta o checkout da `dev`. Nada do trabalho de três meses está referenciado pelo meta-repositório |
| A-2 | **Históricos sem ancestral comum** | `dev` e `main` não podem ser reconciliadas por merge normal. Exige decisão explícita: promover a `dev`, ou adotá-la como branch padrão |
| A-3 | **Terminal PTY sem autenticação** | Quando `DOP_TERMINAL_ROOT` não está definido, o PTY cai no diretório de trabalho do servidor, com aviso em log. A própria memória do agente registra que "um terminal compartilhado ou publicado precisa de autorização autenticada explícita e raízes de execução isoladas" — isso ainda não existe |
| A-4 | **Colisão arquitetural** | Há um servidor Express dentro do `dop-app`. A arquitetura decidida prevê `dop-core` (núcleo gRPC) e `dop-api` (BFF REST + gRPC). Três backends onde o desenho prevê dois, e o de dentro do frontend não é nenhum dos dois |
| A-5 | **Contrato duplicado** | O contrato vive em `types.ts` (à mão) e o `openapi.yaml` está vazio. O codegen roda sobre o vazio. Ou o OpenAPI passa a ser a fonte, ou o pipeline sai |
| A-6 | **`replit.md` não preenchido** | Continua com `[Project name]` e as seções de arquitetura e produto por preencher |
| A-7 | **KPIs zerados na captura** | A tela padrão mostra "2 repositórios" e zero em branches, PRs, arquivos e testes, com "Carregando tasks..." fixo no topo. Pode ser estado de filtro ou defeito de agregação — não verificado em execução |

Não executei `pnpm install` nem `typecheck`: a análise foi estática. O estado de build não
está verificado.

## 7. O que isso significa para a plataforma

Três leituras que valem para a reestruturação:

**A UI descobriu requisitos que os documentos não tinham.** A regra de atribuição de
commits, o runtime com escopo por card, o paralelismo como dado (`parallelGroup`), o
provider por repositório — nada disso estava no PRD, e tudo apareceu ao construir a tela.
O `types.ts` de hoje é uma fonte de requisitos mais atual que o PRD 1.0.

**A tese de IDE bate com a arquitetura decidida, e a reforça.** Terminal interativo,
runtime paralelo por card, navegação por árvore de repositório — são capacidades de
ambiente de desenvolvimento, e todas dependem de streaming bidirecional e de estado
compartilhado. Justificam o núcleo gRPC e o BFF com streaming melhor do que o PRD original
justificava.

**O modelo de etapas ficou órfão bem na hora em que a autonomia entra em pauta.** As 3.523
linhas paradas implementam um fluxo de 7 etapas com forte dependência de intervenção
humana — justamente o que a nova direção quer revisar em favor de autonomia. O código
ficou inacessível antes de a decisão ser tomada. Reancorar sem repensar seria restaurar o
modelo antigo por inércia.
