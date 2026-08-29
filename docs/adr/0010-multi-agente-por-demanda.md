# ADR-0010 — Multi-agente por demanda: threads endereçáveis e achados publicados

- **Status:** Aceita (definitiva, por decisão do produto)
- **Data:** 2026-08-29

## Contexto

Uma demanda real pode exigir especialistas simultâneos. Caso concreto do produto:
SUOPT-1315 — o principal implementa; um subagente faz análise forense do banco via MCP
MySQL; outro vasculha os logs do servidor. O dev precisa conversar com os três **sem
misturar as timelines**, e os três precisam usar as conversas uns dos outros como
conhecimento.

Dois eixos que não se confundem: **entre demandas** (1 demanda = 1 microVM, fronteira
dura) e **dentro da demanda** (N agentes no mesmo sandbox, colaborando). Esta ADR trata
do segundo. No mercado, subagente é caixa-preta: despacha-se e espera-se. Subagente
endereçável, com thread própria e interrogável em voo, não existe nas ferramentas atuais.

## Decisão

1. **A conversa da demanda é um conjunto de threads**, não uma timeline: `#principal`
   mais uma thread por subagente. Cada uma com histórico próprio; o dev entra e conversa
   com aquele agente, isoladamente.
2. **Todo subagente nasce com ficha**: propósito, ferramentas concedidas (ex.: o MCP
   MySQL da workspace — R1.14 ganha seu uso real), modelo (decisão do router, ADR-0011)
   e fatia do orçamento da demanda.
3. **Conhecimento cruzado por consulta, não por despejo.** Threads são legíveis pelos
   irmãos como ferramenta (`ler_thread`, `perguntar`); despejar timelines inteiras no
   contexto de cada agente não escala e amplia a superfície de injeção.
4. **Conclusão vira achado publicado**: resultado estruturado no quadro comum da demanda
   ("deadlock na tabela X, 14:02–14:07, causado pela migration Y"). Achados entram
   automaticamente no contexto dos irmãos, são eventos (ADR-0006) e alimentam a memória
   do projeto (ADR-0009).
5. **Quem lança subagentes: o humano e o agente principal.** O humano, pelo chat; o
   principal, por iniciativa própria quando julgar necessário — a thread aparece de
   imediato para o dev acompanhar ou intervir.
   > **Suposição registrada:** a iniciativa própria do principal foi adotada por
   > coerência com a filosofia de autonomia; o produto pode restringi-la na revisão.
6. **A fronteira de segurança continua sendo a demanda.** Subagentes compartilham
   microVM, workspace, credencial e quota — são colaboradores, não estranhos.

## Alternativas consideradas

**Agente único sequencial.** Descartada: perde especialização e paraleliza nada.

**Um sandbox por subagente.** Descartada: quebra o workspace compartilhado (o forense
precisa do mesmo banco que o principal sobe), multiplica custo e não compra isolamento
que importe — os agentes cooperam.

**Timeline única compartilhada.** Descartada: é o problema que o requisito veio resolver.

## Consequências

- ➕ UX genuinamente nova no mercado — o dev-gestor conversa com cada membro do time.
- ➕ Threads, achados e fichas são eventos e entidades que o dossiê e a memória já
  esperavam.
- ➖ A porta `AgentRuntime` precisa suportar N sessões por sandbox.
- ➖ Mais threads = mais pontos de atenção; a caixa de atenção deixa de ser opcional
  (F-5) e vira pré-requisito de escala.
