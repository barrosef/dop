# Verificação e entrega

> **Status:** Aprovada para revisão · **Data:** 2026-08-29 · **Projeto:** plataforma DOP
>
> **Responde:** o caminho do código do sandbox até a `main` — aceitação, crítico,
> evidência, PR e fila de merge.
>
> **Não responde:** o formato/sintaxe dos critérios na spec (núcleo do SP-4, pendente);
> revisão humana dentro do provedor (é o portão nativo do git, mantido).

Decisões de base: [ADR-0007](../../adr/0007-sem-verde-sem-pr.md),
[ADR-0008](../../adr/0008-merge-queue-por-repositorio.md),
[ADR-0003](../../adr/0003-credencial-de-organizacao-autoria-humana.md).

## 1. O caminho, de ponta a ponta

```
spec (critérios executáveis)
  → agente itera no sandbox até o verde        [falha persistente → caixa de atenção]
  → crítico revisa (instância limpa)           [reprova → volta ao agente, com parecer]
  → PR com pacote de evidência                 [credencial da conta; author = dev]
  → fila de merge do repositório               [rebase → re-verificação → merge serial]
  → main                                       [evento → índice atualiza, demanda avança]
```

## 2. Aceitação

Critérios da spec que uma máquina executa no sandbox: suítes de teste (unitário/AAA/
e2e sobre a pilha do compose interno) e checagens derivadas da spec. Resultado de cada
execução é evento (ADR-0006). Regra da ADR-0007: **nenhum PR abre com aceitação
falhando** — falha persistente vira bloqueio com pergunta, nunca PR quebrado.

## 3. O crítico

- Instância independente com contexto limpo (não herda a conversa de quem implementou);
  modelo **forte** — não se economiza no freio (ADR-0011).
- Recebe: diff completo, spec, resultados de aceitação, achados da demanda.
- Emite parecer estruturado: `aprova | aprova com ressalvas | reprova (motivos)`.
  Reprova volta ao agente com o parecer; aprova segue ao PR com o parecer anexado.

## 4. O PR e o pacote de evidência

Composição fixa: resumo da mudança e da demanda; **quem pediu** (corpo do PR) e
**quem conduziu** (`author` dos commits) — ADR-0003; resultados de aceitação e testes;
parecer do crítico; links para o trace da demanda. O revisor humano recebe leitura de
exceção, não arqueologia.

## 5. A fila de merge

Estados por repositório: `na fila → rebase → re-verificação → merge` — um por vez.

- **Rebase e resolução de conflito são tarefa do agente da demanda**; falha escala à
  caixa de atenção com o contexto do conflito.
- **Re-verificação roda a aceitação de novo** sobre o resultado do rebase — é o que
  pega a quebra semântica entre demandas paralelas.
- **Fila nativa do provedor** (GitHub merge queue, GitLab merge trains) é usada quando
  existir, via `GitProvider`; a fila do DOP orquestra por cima e cobre o resto.
- **Detecção de sobreposição:** o orquestrador compara os arquivos tocados pelas
  demandas ativas do mesmo repositório e sinaliza colisão provável **antes** do PR —
  no cockpit e, quando exigir decisão, na caixa de atenção.
- Posição na fila e previsão são visíveis no cockpit.

## 6. Riscos

| # | |
|---|---|
| R-1 | Fila longa em repositório quente serializa a entrega — a detecção de sobreposição e o agendamento por conta são as válvulas |
| R-2 | Crítico complacente devolve o problema ao humano — calibrar com as métricas de F-7 (PRs reprovados pós-crítico) |
| R-3 | Re-verificação repetida em fila é o maior consumidor de computação do fluxo — cache de build por conta é pré-requisito, não luxo |
