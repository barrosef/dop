# ADR-0015 — Orquestrador de projeto: o agente techlead

- **Status:** Aceita
- **Data:** 2026-08-30
- **Complementa:** [ADR-0008](0008-merge-queue-por-repositorio.md) (dá dono à detecção
  de sobreposição), [ADR-0010](0010-multi-agente-por-demanda.md) (agentes por demanda),
  [ADR-0006](0006-demanda-como-log-de-eventos.md) (a matéria-prima da observação)

## Contexto

Com demandas paralelas no mesmo projeto, surgem situações **transversais** que nenhum
agente de demanda enxerga sozinho: duas demandas mexendo nos mesmos arquivos, uma
demanda que depende do resultado da outra, mudanças de comportamento em que uma
interfere na outra. A ADR-0008 previu "o orquestrador enxerga sobreposição" sem dizer
quem ele é. Agora tem nome e natureza: **um agente**, não um cron de regras.

## Decisão

1. **Todo projeto tem um agente orquestrador — o techlead dos agentes de demanda.**
   Acionado **dinamicamente**: desperta quando o projeto tem 2+ demandas ativas;
   dorme fora disso. Vive na plataforma, não num sandbox de demanda; observa via log
   de eventos, estado das branches e fluxos das demandas.
2. **Observa o transversal:** sobreposição de arquivos entre branches ativas,
   dependência entre demandas, interferência de comportamento (uma mudança que quebra
   a premissa da outra).
3. **Autonomia primeiro:** ao identificar uma transversal, o techlead **planeja
   soluções** e aciona a **caixa de atenção** com uma provocação de decisão — opções
   prontas, com recomendação — nunca um alarme cru.
4. **Decisão vira diretriz de coordenação.** A escolha do dev reflete nas demandas
   como instrução aos agentes envolvidos. Exemplo canônico: "demanda 1 depende da 0"
   → decisão: quando a 0 commitar o que a 1 precisa, a 1 faz **cherry-pick** da branch
   da 0 e segue. A diretriz é evento (ADR-0006) e aparece nas threads das demandas.
5. **Regra de ouro: transversal identificada NUNCA pausa demanda.** A demanda 1 segue
   até onde dá; quando a condição da diretriz se cumprir (a 0 commitou), aplica a
   coordenação (cherry-pick feito) e continua. Bloqueio só existe se a própria demanda
   esgotar o que dá para fazer sem a condição — e aí é bloqueio dela, visível na caixa.
6. **Vocabulário inicial de diretrizes:** sequenciamento com cherry-pick/rebase entre
   branches; ordem preferencial na fila de merge; partição de arquivos ("a 2 não toca
   o módulo X até a 1 mergear"); verificação cruzada (rodar a aceitação da 1 sobre o
   resultado da 0). Extensível — é o techlead que propõe, o vocabulário só nomeia.

## Alternativas consideradas

**Regras estáticas de detecção (diff de paths + grafo de dependência declarado).**
Ficam como sensores do techlead, mas insuficientes sozinhas: interferência de
comportamento não aparece em path — precisa de leitura semântica das specs e diffs.

**Pausar demandas em risco até decisão.** Descartada com ênfase: mata o paralelismo
que é requisito e transforma detecção (barata) em bloqueio (caro). O custo de seguir e
coordenar depois é menor que o custo de parar.

**Techlead humano.** É o modo de todo mundo hoje — e é exatamente a atenção escassa
que a plataforma existe para poupar. O humano decide; o techlead detecta, planeja e
executa a coordenação.

## Consequências

- ➕ O paralelismo do requisito ("SUOPTS-1501/02/03 simultâneas, mesmo repo") ganha o
  supervisor que faltava; F-4 fecha por inteiro (fila de merge + coordenação a montante).
- ➕ A caixa de atenção recebe itens de decisão prontos, não sintomas.
- ➖ Custo de modelo do techlead: observação é barata (eventos/diffs), planejamento é
  caro — roteado como investigação (ADR-0011); desperta por evento, não por polling.
- ➖ Diretriz de coordenação é estado novo entre demandas — precisa aparecer na
  Timeline e nas threads das duas pontas, ou vira mágica invisível.
