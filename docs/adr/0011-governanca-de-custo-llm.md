# ADR-0011 — Governança de custo de LLM: medição firme, roteamento em rascunho

- **Status:** **Rascunho** (medição e orçamento: firmes; roteamento: evoluir)
- **Data:** 2026-08-29
- **Resolve:** F-6 — ver `docs/analysis/2026-08-29-revisao-critica-plataforma.md`

## Contexto

N agentes autônomos × sessões longas × multi-tenant = a maior linha de custo variável do
produto — e nenhum documento tinha uma linha sobre isso. Sem medição por conta não há
modelo de negócio; sem orçamento por demanda, uma demanda patológica queima dinheiro em
loop; sem roteamento, tudo roda no modelo mais caro.

## Decisão

Duas partes firmes e uma em rascunho:

1. **Medição desde o primeiro dia (firme).** Todo uso de modelo emite evento de custo
   (tokens, modelo, demanda, thread, conta) no log da demanda (ADR-0006). Medição é
   projeção — nenhum sistema paralelo.
2. **Orçamento por demanda com corte suave (firme).** Estourou: a demanda **pausa e
   pergunta** (caixa de atenção), nunca morre no meio nem segue queimando.
3. **`ModelRouter` (rascunho — evoluir).** Porta que escolhe modelo/agente por tipo de
   trabalho: mecânico (mensagem de commit, resumo de log, atualização de dossiê, chave
   de i18n) → barato; planejamento, implementação e **o crítico** (ADR-0007) → forte.
   Regra que já nasce fixa: **não se economiza no crítico** — é o freio.

## Alternativas consideradas

**Modelo único forte para tudo.** Simples e caro; vira teto de margem.

**Roteamento por heurística de tamanho de prompt.** Descartada: o que importa é a
natureza da tarefa, não o comprimento.

## Consequências

- ➕ Custo visível por demanda/conta antes de existir cobrança.
- ➕ A porta segue a ADR-0001: provedores de modelo trocam de líder por semestre.
- ➖ Política de roteamento exige calibração com dados reais — por isso rascunho: a
  tabela tarefa→modelo será revista com a telemetria de F-7.
