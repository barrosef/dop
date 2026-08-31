# Plataforma DOP — decomposição e estado

Índice do projeto. Toda spec aponta para cá em vez de repetir o recorte.

## Subprojetos

| | Subprojeto | Decide | Estado |
|---|---|---|---|
| **SP-0** | Identidade, contas e tenancy | Quem é o usuário, o que é uma conta, como se possui e se isola, onde vivem as integrações, hierarquia conta → workspace → projeto | ✅ desenhado |
| **SP-4** | Modelo de trabalho: specs e autonomia | O que a plataforma faz; o que substitui as etapas; onde o humano decide, aprova e dá contexto | ✅ desenhado — subsistemas (ADRs 0006–0012) + **núcleo fechado pela ADR-0014** (fluxo dinâmico tipado e herdável); resta P-8 (sintaxe dos critérios) |
| **SP-1** | Topologia de componentes e repositórios | Quais componentes existem e o papel de cada um | ✅ desenhado — ADRs 0016–0020 + spec de arquitetura de backend |
| **SP-3** | Modelo de domínio e persistência | Workspace, projeto, card, artefato, evento; banco | ✅ decidido — ADR-0018/0019 + schema na spec de backend |
| **SP-2** | Contrato e protocolos | Fonte da verdade do contrato; REST, gRPC e streaming | ✅ decidido — ADR-0017 (proto); resta escrever os `.proto` |
| **SP-5** | Runtime, ambiente e IDE | Terminal, execução paralela, implantação | ⬜ |
| **SP-6** | Integração com o Claude | Agente, chat como canal de comando | ⬜ |

**Ordem:** SP-0 → SP-4 → SP-1 → SP-3 → SP-2 → SP-5 → SP-6.

SP-0 é o mais a montante: todo o resto opera dentro de uma conta. SP-4 vem logo depois
porque define *o que a plataforma faz* — SP-3 e SP-2 existem para servir isso, e decidir
schema ou contrato antes seria decidir no escuro.

## Documentos

| Documento | Responde |
|---|---|
| [`GLOSSARIO.md`](GLOSSARIO.md) | O que cada palavra significa |
| [`adr/`](adr/) | Por que cada decisão estruturante foi tomada |
| [`superpowers/specs/`](superpowers/specs/) | Como cada subsistema é |
| [`superpowers/plans/`](superpowers/plans/) | Em que ordem se constrói |

## Faseamento do SP-0

**Modelo completo desde o primeiro dia, construção parcial.**

**Nasce no schema agora, mesmo sem tela:** `Account` com `kind`, `Membership` com papel,
`Integration` com `accountId`, tabela de concessões e `Invite`. Toda entidade de domínio
carrega conta, workspace e projeto desde a primeira migração. A borda autentica toda
chamada e resolve conta ativa desde a primeira rota.

**Constrói-se agora:** autenticação pelos quatro métodos, conta pessoal automática no
cadastro, integrações pessoais com o `SecretStore` atrás da porta e os dois adaptadores,
e a hierarquia workspace → projeto.

**Fica para a fase seguinte:** criação de organização, autofill por CNPJ, convite e
vínculo de membros, edição de papéis e concessões, verificação de domínio, credencial de
organização.

A fase 2 entra **sem migração** — é o que justifica modelar tudo agora. A fase 1 já
exercita o multi-tenant de verdade, porque toda consulta filtra por conta desde o início;
a conta simplesmente é sempre pessoal.

## Ordem combinada

1. Terminar estrutura/arquitetura — **ferramentas do agente** (a peça que falta
   para a plataforma executar em vez de só modelar) e **cockpit**.
2. **Discussão** antes das user stories: comunicação (P-11), provisionamento de
   sandbox (P-24) e o modelo de conta/cobrança do agente (P-23).
3. User stories.

## Pendências transversais

Levantadas na revisão do SP-0, cada uma exigindo decisão própria e provável ADR:

| # | Pendência | Onde dói |
|---|---|---|
| ~~P-1~~ | **Resolvida pela ADR-0006** — auditoria é projeção do log de eventos da demanda | — |
| P-2 | **Transições de `status` da integração** — quem detecta `expired`, com que frequência, o que acontece com trabalho em andamento | SP-0 integrações + SP-5 execução |
| P-3 | **LGPD** — retenção, exclusão e residência, com CPF e CNPJ no escopo | Transversal; afeta exclusão de conta |
| ~~P-4~~ | **Resolvida** — plano de controle no Cloud Run; plano de execução em cluster (GKE/k3s). Spec de arquitetura de backend §1 | — |
| P-5 | **Custo da renomeação** *workspace → projeto* em código, rotas, i18n, mocks e documentação | Execução; vira tarefa de plano |
| P-6 | **Recuperação de organização órfã não verificada** — sem domínio provado, não há evidência disponível para reivindicar posse | SP-0 identidade |
| P-7 | **Calibrar o ModelRouter** — a tabela tarefa→(modelo, effort) da ADR-0011 nasce como palpite informado; calibra com telemetria real (F-7) e com os campos de cache dos eventos de custo | ADR-0011/0012 |
| P-8 | **Sintaxe dos critérios executáveis** dentro do artefato `spec` — a ADR-0007 fixa a exigência e a ADR-0014 fixa onde vivem | spec de fluxo |
| P-9 | **⭐ Compartilhamento externo de fluxos** (entre contas / catálogo comunitário) — **estratégica**: aguarda, não dorme; candidata a motor de popularização da plataforma. Revisitar a cada ciclo de planejamento | ADR-0014 §7 |
| P-11 | **⭐ Serviço de comunicação** — e-mail, SMS e push reagindo a eventos: validação de conta, recuperação de senha, convites, avisos de integração quebrada e de orçamento estourado. Templates com identidade visual. É consumidor da espinha de eventos (ADR-0019), não um sistema à parte | pendente de desenho |
| P-12 | **Campo `ctx` sem efeito nos protos** — toda requisição declara `CallContext ctx = 1`, e o servidor ignora: autoriza só pela metadata (ADR-0017, conv. 5). Contrato que declara campo sem efeito ensina o errado a quem lê. Remover em passe dedicado, reservando o número 1 | ADR-0017; toca os 10 protos |
| P-13 | **Emulador de Storage pendura com `application/json`** e cai sob ~16 operações simultâneas — guardar JSON no object store trava o ambiente local. Achado pela suíte de contrato do ObjectStore; não é defeito do adaptador (o de arquivos passa nos 13 subtestes). Decidir entre esperar correção do emulador, gravar JSON com outro Content-Type, ou usar `uploadType=multipart` | dop-infra/docs/ambiente-local.md |
| ~~P-14~~ | **Resolvida** — Dois adaptadores (GitHub e GitLab) com suíte de contrato, e o provedor resolvido POR REPOSITÓRIO (ADR-0013), não no boot | — |
| ~~P-15~~ | **Resolvida** — Launcher confere os isolamentos no boot e recusa subir sem saber; varredura de ociosos ligada ao scheduler | — |
| P-16 | **Artefato por etapa** — sem armazenamento de artefato, a spec fica fora do pacote de contexto (o pacote perde a spec, não fica incorreto) e o `ValidateFlow` não consegue exigir artefato de verdade | ADR-0014; domínios workflow/demand/knowledge |
| P-17 | **Emulador PRÓPRIO do Secret Manager** — hoje usamos um da comunidade (13 estrelas, mantenedor único), fixado por digest e isolado por NetworkPolicy. Decisão do dono: destravar agora, trocar pelo nosso depois. Escrito dos protos oficiais do googleapis, ~200 linhas, como já fazemos com a imagem do emulador do Firebase | dop-infra |
| P-18 | **Autenticar o chamador entre BFF e núcleo** — o núcleo confia em `x-actor-id`/`x-account-id` da metadata (ADR-0016). A NetworkPolicy faz a suposição valer, mas não é o mesmo que autenticar. Sandboxes rodam código de agente no mesmo cluster | dop-core + dop-infra; ADR-0016 |
| ~~P-19~~ | **Parcialmente resolvida** — `ListFindings`, `Contributors`/`Origins`, `dropped` e `currency` entraram no contrato. Resta a **consulta de evidência de verde**: `Evidence.Missing()` existe no domínio, mas `DeliveryService` não expõe, então a tela do PR não mostra o pacote que a ADR-0007 §4 exige | dop-core |
| ~~P-20~~ | **Resolvida** — Os quatro contornos saíram; o do `dropped` estava QUEBRADO, não funcionando | — |
| ~~P-21~~ | **Resolvida** — Caixa na borda, reusando o SSE existente; `AttentionUpdate` ganhou `event_id` para a retomada | — |
| ~~P-22~~ | **Resolvida** — Virou TESTE: varre `app/` atrás de cofre, chave de provedor e SDK de modelo | — |
| P-23 | **⭐ De quem é a conta do agente — e quem paga o quê.** **Termos da Anthropic VERIFICADOS em 2026-08-31** (`code.claude.com/docs/en/legal-and-compliance`), e eles fecham metade das opções: (a) **OAuth na conta do usuário — PROIBIDO.** *"Anthropic does not permit third-party developers to offer Claude.ai login into their own applications, or to route requests through Free, Pro, or Max plan credentials on behalf of their users"*, e *"developers may not collect, store, or intermediate Claude.ai credentials or session tokens"*. (b) **Revenda por conta enterprise do DOP — PROIBIDO.** *"Customers may not pay for, resell, or intermediate Claude usage on their end users' behalf. Each end user must authenticate with their own Anthropic API key, Claude subscription plan credentials, or 3P inference provider credential"*. (c) **BYOK — PERMITIDO, e descrito quase literalmente como o que já construímos**: *"configuring an API key in a development environment, secrets manager, or machine image for use by the customer's own authorized users — provided the resulting usage is billed to the key owner"*. (d) **Hospedar o Claude Code no sandbox e o usuário assinar com a própria assinatura — PERMITIDO com condições**: binário NÃO modificado, nenhum método de autenticação removido, sem pagar/revender/intermediar, e restrição de marca (não usar o nome nas nossas telas). **Falta verificar os termos dos OUTROS fornecedores** antes de generalizar | **discussão**, antes das user stories |
| P-24 | **⭐ Explorar o provisionamento de sandbox** — sob demanda (hoje), automático ao iniciar demanda, ou preguiçoso no primeiro turno que precisa agir. Custa CPU, memória e disco por demanda; a suspensão automática ameniza mas não elimina. Só faz sentido decidir depois que o agente souber usar ferramentas — antes disso nenhum sandbox precisa subir | **discussão**, junto de P-11 |
| P-10 | **Explorar o Overview** — forma final do nível acima do task header; já definido: item Arquitetura do projeto (análises gerais sob demanda: stacks, integrações, forças/fraquezas, propostas de melhoria em diagramas e gráficos) | spec de navegação §3 |
