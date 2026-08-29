# ADR-0012 — Economia de tokens como disciplina de engenharia

- **Status:** Aceita
- **Data:** 2026-08-29
- **Complementa:** [ADR-0011](0011-governanca-de-custo-llm.md) (que mede e orça; esta decide **como gastar menos sem perder eficácia**)

## Contexto

Num loop de agente, a conversa inteira é reenviada a cada turno: um agente de 40 turnos
paga o transcript 40 vezes. A API oferece mecanismos com desconto de até 90% (cache) e
50% (batch) — mas todos exigem disciplina de engenharia para funcionar; nenhum é flag.
E metade da economia não vem da API: vem de decisões de arquitetura que o DOP já tomou
por outros motivos (quarentena por subagente, achados, projeções por código).

## Decisão

### 1. Cache-first: o prompt do agente é desenhado para o prefixo estável

- Layout fixo: `[sistema → ferramentas determinísticas → pacote de contexto] →
  breakpoint → conversa`. Leitura de cache custa ~0,1× do input; escrita 1,25×
  (TTL 5 min) — o estável sai a ~10% do preço.
- **O pacote de contexto é serializado deterministicamente**: ordem estável, sem
  timestamps, sem IDs voláteis. Byte mudado no prefixo invalida tudo dali em diante.
- Intervenção do operador entra como **mensagem `system` no meio da conversa**
  (mecanismo nativo, preserva o prefixo) — nunca editando o topo do prompt.
- Telemetria: `cache_read_input_tokens` zerado em turnos repetidos = invalidador
  silencioso = **alerta**, via evento de custo (ADR-0006/0011).

### 2. Contexto sujo não entra no principal

- Quarentena por subagente (ADR-0010): logs, dumps e leituras volumosas vivem na
  thread do especialista; o principal recebe o **achado**. Onde couber,
  **programmatic tool calling**: o filtro roda em código no sandbox e só o resultado
  final passa pelo modelo.
- **Context editing** nas threads de investigação: publicado o achado, os resultados
  brutos de ferramenta saem do transcript.
- Achados e pareceres usam **structured outputs**: tersos, validados, sem re-parse.

### 3. Retomada por reconstrução, não por replay

Demanda suspensa que retoma dias depois **não** reenvia o transcript (caro, e o cache
já expirou): o contexto é reconstruído do zero — pacote + achados + resumo do trace.
Eventos e achados são o material de reconstrução; compaction é rede de segurança
dentro de uma sessão contínua, não mecanismo de retomada.

### 4. Não usar LLM onde código resolve

Dossiê, métricas, auditoria e caixa de atenção são projeções do log de eventos
(ADR-0006), computadas em código. Custo de token: zero.

### 5. Assíncrono vai para o Batch (50% de desconto)

Regeneração de índice pós-merge, poda de memória, resumos de dossiê, métricas
noturnas — nada disso é interativo; tudo roda em batch.

### 6. Ferramentas sob demanda

Workspaces com muitos MCPs usam **tool search com carregamento adiado**: o agente não
carrega o catálogo de schemas — busca e carrega o que a tarefa pede, preservando o
cache (schemas são anexados, não trocados).

### Regra que limita todas as outras

**Não se economiza no crítico** (ADR-0007/0011): modelo forte, effort máximo.
Economizar no freio devolve o custo em PR reprovado — o retrabalho mais caro do fluxo.

## Alternativas consideradas

**Tratar custo só com router de modelo.** Insuficiente: o maior desperdício de um loop
de agente é o reenvio do transcript, e o router não toca nele.

**Compaction como mecanismo de retomada.** Descartada: reconstrução por eventos é mais
barata, mais limpa e já temos o material (ADR-0006/0009/0010).

## Consequências

- ➕ A economia vem majoritariamente de decisões já tomadas — esta ADR as torna regra.
- ➕ Desperdício vira visível: cache miss é alerta, não mistério.
- ➖ Serialização determinística do pacote é restrição permanente sobre a ADR-0009.
- ➖ Reconstrução de retomada precisa ser comprovadamente suficiente — se o agente
  "esquecer" o que importava, o resumo do trace é que está fraco; calibrar com F-7.
