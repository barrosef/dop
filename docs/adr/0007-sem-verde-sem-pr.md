# ADR-0007 — Sem verde, sem PR: verificação nativa antes do humano

- **Status:** Aceita
- **Data:** 2026-08-29
- **Resolve:** F-3 — ver `docs/analysis/2026-08-29-revisao-critica-plataforma.md`

## Contexto

A pesquisa de 2026 é conclusiva: agentes já fecham o loop até o PR, e **o gargalo do
fluxo passou a ser a capacidade humana de revisar**. Sem verificação nativa, o
paralelismo do substrato só muda o lugar da fila — do desenvolvimento para a mesa do
revisor. O PRD já fixa que merge é decisão humana; esta ADR decide o que acontece
**antes** de o humano ser chamado.

## Decisão

Quatro regras, nesta ordem:

1. **A aceitação nasce na spec, executável.** Cada demanda carrega critérios que uma
   máquina verifica no sandbox: suítes de teste (unitário/AAA/e2e) e checagens derivadas
   da spec. Critério que não se executa não é critério — é desejo.
2. **O agente itera até o verde.** Nenhum PR é aberto com aceitação falhando. Falha
   persistente vira bloqueio com pergunta ao humano (caixa de atenção), nunca PR
   quebrado.
3. **Um crítico revisa antes do humano.** Instância independente, contexto limpo, sem o
   histórico de quem implementou: recebe diff + spec + evidência e emite veredito. É a
   primeira linha de defesa contra o carimbo (F-5).
4. **O PR carrega o pacote de evidência**: resultados da aceitação, execuções de teste,
   veredito do crítico e links para o trace (ADR-0006). O humano revisa exceção, não
   regra.

## Alternativas consideradas

**Revisão só humana.** É o default do mercado — e é onde a frota afoga o revisor.

**Auto-merge com verde.** Descartada: o portão humano do PR é não-objetivo fixado do
produto, e o crítico não substitui responsabilidade.

## Consequências

- ➕ O ganho de paralelismo chega inteiro ao merge, em vez de morrer na revisão.
- ➕ "Interrupções do agente" viram métrica de qualidade da spec (fecha F-7 em parte).
- ➖ O formato exato dos critérios executáveis pertence ao núcleo do SP-4 (ciclo da
  spec); esta ADR fixa a exigência, não a sintaxe.
- ➖ O crítico custa tokens — modelo forte, sem economia aqui (ADR-0011).
