# ADR-0008 — Merge queue por repositório; conflito é tarefa de agente

- **Status:** Aceita
- **Data:** 2026-08-29
- **Resolve:** F-4 — ver `docs/analysis/2026-08-29-revisao-critica-plataforma.md`

## Contexto

O paralelismo é requisito explícito: SUOPTS-1501/1502/1503 simultâneas, "independente de
repos coincidirem". Três PRs verdes — cada um testado contra a `main` de quando sua
branch nasceu. O primeiro merge invalida os outros dois: na melhor hipótese, conflito de
texto; na pior, **quebra semântica silenciosa** (um PR remove a checagem que o outro
assumia). CI de PR não vê; produção vê. Frotas de agente produzem PR numa taxa que
transforma esse acidente mensal em ocorrência diária.

## Decisão

1. **Fila de merge por repositório, como conceito do domínio.** PR verde entra na fila;
   a fila reaplica cada PR sobre a `main` atualizada, **re-executa a verificação**
   (ADR-0007) e mergeia um de cada vez. Só entra o que está verde contra o estado real.
2. **Conflito é tarefa de agente.** Rebase e resolução são tentados pelo agente da
   demanda; falha escala ao humano pela caixa de atenção, com o contexto do conflito.
   (Os fluxos do utilitário dop-cmd — integração, preparação e resolução de conflito —
   são conhecimento minerável aqui; conhecimento, não código.)
3. **Sobreposição é detectada cedo.** O orquestrador enxerga quais demandas ativas tocam
   os mesmos arquivos e sinaliza o risco **antes** do PR, não depois.
4. **Fila nativa do provedor quando existir** (merge queue do GitHub, merge trains do
   GitLab), consumida pela porta `GitProvider`; a fila do DOP orquestra por cima e cobre
   os provedores sem o recurso.

## Alternativas consideradas

**Merge otimista** (mergeia na ordem de chegada). Descartada: é exatamente o cenário da
quebra semântica.

**Um arquivo, um dono** (nenhum arquivo tocado por duas demandas). Descartada: mata o
paralelismo que é requisito — vira fila disfarçada.

**Só a fila do provedor.** Descartada como única via: nem todo provedor tem, e o DOP
precisa da visão entre demandas (item 3) que o provedor não tem.

## Consequências

- ➕ Quebra semântica entre demandas paralelas deixa de chegar à `main`.
- ➖ Merge serializado por repositório: latência de entrega cresce com a fila — visível
  no cockpit, com posição e previsão.
- ➖ Re-verificação a cada posição da fila custa computação; o cache por conta e a
  suspensão preemptiva são as válvulas.
