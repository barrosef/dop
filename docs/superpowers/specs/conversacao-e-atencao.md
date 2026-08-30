# Conversação multi-agente e caixa de atenção

> **Status:** Aprovada para revisão · **Data:** 2026-08-29 · **Projeto:** plataforma DOP
>
> **Responde:** como o dev conversa com os agentes de uma demanda (threads) e como a
> plataforma dirige a atenção dele entre todas as demandas (caixa de atenção).
>
> **Não responde:** protocolo de transporte do chat (SP-2); telas finais (design do
> cockpit evolui sobre o dop-app existente).

Decisões de base: [ADR-0010](../../adr/0010-multi-agente-por-demanda.md),
[ADR-0006](../../adr/0006-demanda-como-log-de-eventos.md),
[ADR-0011](../../adr/0011-governanca-de-custo-llm.md).

## 1. Threads por demanda

```
SUOPT-1315
├── #principal     agente principal ←→ dev
├── #forense-db    subagente (MCP MySQL) ←→ dev
└── #logs          subagente ←→ dev
```

- Cada thread tem timeline própria; toda mensagem é evento (ADR-0006).
- **Ciclo da thread:** `aberta → ativa → bloqueada (pergunta pendente) → concluída`.
  Concluir exige publicar o **achado** — a thread não morre em silêncio.
- **Ficha do subagente** (visível na thread): propósito, ferramentas concedidas (MCPs
  da workspace — R1.14), modelo, fatia de orçamento.
- Quem lança: humano pelo chat, e o principal por iniciativa própria — a thread aparece
  de imediato (suposição registrada na ADR-0010, sujeita a veto).

## 2. Conhecimento cruzado

- **Consulta entre threads:** `ler_thread(id)`, `perguntar(id, questão)` — ferramentas
  dos agentes, com resposta síncrona ou via achado.
- **Quadro de achados da demanda:** resultado estruturado publicado ao concluir uma
  investigação; entra automaticamente no contexto dos irmãos, no dossiê e na memória do
  projeto (ADR-0009).
- Timelines brutas **não** são injetadas em contexto alheio — não escala e amplia
  injeção.
- **Intervenção do operador** numa thread (instrução vinda da caixa de atenção) entra
  como mensagem `system` no meio da conversa — preserva o prefixo cacheado (ADR-0012).
- **Higiene de thread de investigação:** publicado o achado, os resultados brutos de
  ferramenta (dumps, logs) são limpos do transcript por context editing; o achado é o
  registro durável.

## 3. Caixa de atenção

A fila única, entre **todas** as demandas da conta ativa, respondendo "onde eu sou
necessário, e em que ordem". Não é o chat: é o que leva ao chat certo.

| Tipo de item | Origem | Destino do clique |
|---|---|---|
| Pergunta de agente / thread bloqueada | ADR-0010 | a thread |
| Spec aguardando aprovação | ciclo da spec (SP-4 núcleo) | a spec |
| PR aguardando revisão | ADR-0007 | o PR com evidência |
| Conflito escalado da fila de merge | ADR-0008 | o contexto do conflito |
| **Transversal detectada pelo techlead** — dependência, sobreposição, interferência — com opções de diretriz prontas e recomendação | ADR-0015 | a decisão de coordenação |
| Demanda pausada por orçamento | ADR-0011 | decisão de gasto |
| Integração da conta quebrada | spec de integrações, R-1 | a integração |

- **Prioridade** por impacto (produção da fila de merge > pergunta exploratória) e
  idade; itens agrupáveis por demanda.
- Escopo: a **conta ativa** (SP-0); a visão cruza workspaces e projetos dela — é o
  R2.9 do PRD promovido de "proposto" a primitivo central.
- Todo item nasce de evento (ADR-0006) — a caixa é uma projeção, não um sistema.

## 4. Riscos

| # | |
|---|---|
| R-1 | Caixa barulhenta vira ruído e é ignorada — só entra o que exige decisão humana; status e progresso ficam no cockpit |
| R-2 | 5 demandas × 3 threads = 15 conversas: sem a caixa, o modelo multi-agente afoga o dev — os dois sobem juntos ou nenhum |
| R-3 | Notificação fora da plataforma (e-mail, push) fica para depois; a caixa é a fonte, canais são projeções futuras |
