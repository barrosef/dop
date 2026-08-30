# Plataforma DOP — decomposição e estado

Índice do projeto. Toda spec aponta para cá em vez de repetir o recorte.

## Subprojetos

| | Subprojeto | Decide | Estado |
|---|---|---|---|
| **SP-0** | Identidade, contas e tenancy | Quem é o usuário, o que é uma conta, como se possui e se isola, onde vivem as integrações, hierarquia conta → workspace → projeto | ✅ desenhado |
| **SP-4** | Modelo de trabalho: specs e autonomia | O que a plataforma faz; o que substitui as etapas; onde o humano decide, aprova e dá contexto | ✅ desenhado — subsistemas (ADRs 0006–0012) + **núcleo fechado pela ADR-0014** (fluxo dinâmico tipado e herdável); resta P-8 (sintaxe dos critérios) |
| **SP-1** | Topologia de componentes e repositórios | Quais componentes existem e o papel de cada um | ⬜ |
| **SP-3** | Modelo de domínio e persistência | Workspace, projeto, card, artefato, evento; banco | ⬜ |
| **SP-2** | Contrato e protocolos | Fonte da verdade do contrato; REST, gRPC e streaming | ⬜ |
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

## Pendências transversais

Levantadas na revisão do SP-0, cada uma exigindo decisão própria e provável ADR:

| # | Pendência | Onde dói |
|---|---|---|
| ~~P-1~~ | **Resolvida pela ADR-0006** — auditoria é projeção do log de eventos da demanda | — |
| P-2 | **Transições de `status` da integração** — quem detecta `expired`, com que frequência, o que acontece com trabalho em andamento | SP-0 integrações + SP-5 execução |
| P-3 | **LGPD** — retenção, exclusão e residência, com CPF e CNPJ no escopo | Transversal; afeta exclusão de conta |
| P-4 | **Plano de controle × plano de execução** — Cloud Run não sustenta sessão longa de terminal | SP-5 |
| P-5 | **Custo da renomeação** *workspace → projeto* em código, rotas, i18n, mocks e documentação | Execução; vira tarefa de plano |
| P-6 | **Recuperação de organização órfã não verificada** — sem domínio provado, não há evidência disponível para reivindicar posse | SP-0 identidade |
| P-7 | **Calibrar o ModelRouter** — a tabela tarefa→(modelo, effort) da ADR-0011 nasce como palpite informado; calibra com telemetria real (F-7) e com os campos de cache dos eventos de custo | ADR-0011/0012 |
| P-8 | **Sintaxe dos critérios executáveis** dentro do artefato `spec` — a ADR-0007 fixa a exigência e a ADR-0014 fixa onde vivem | spec de fluxo |
| P-9 | **⭐ Compartilhamento externo de fluxos** (entre contas / catálogo comunitário) — **estratégica**: aguarda, não dorme; candidata a motor de popularização da plataforma. Revisitar a cada ciclo de planejamento | ADR-0014 §7 |
| P-10 | **Explorar o Overview** — forma final do nível acima do task header; já definido: item Arquitetura do projeto (análises gerais sob demanda: stacks, integrações, forças/fraquezas, propostas de melhoria em diagramas e gráficos) | spec de navegação §3 |
