# ADR-0009 — Contexto é subsistema: base de conhecimento e pacote por demanda

- **Status:** Aceita
- **Data:** 2026-08-29
- **Resolve:** F-2 — ver `docs/analysis/2026-08-29-revisao-critica-plataforma.md`

## Contexto

O que separa um agente útil de um inútil em 2026 é contexto: regras do projeto, mapa do
código, memória do que já foi tentado. Nos requisitos isso aparecia como "contexto criado
pelo Claude" e "regras da workspace" — sem entidade, sem porta, sem mecanismo. A
diretriz do produto é explícita: documentação em storage seguro, disponível e
permissionado, acessível às microVMs, "para que os agentes trabalhem de modo inteligente
de verdade".

O storage é a metade fácil. A metade que gera inteligência é **o que** está lá e **como**
é montado por demanda.

## Decisão

1. **Base de conhecimento por projeto**, versionada, com três camadas:
   - **Regras** — convenções que o agente obedece ("nunca mergear `desenv` na feature");
   - **Índice** — mapa do código: o que vive onde, como buildar, como testar. Sem ele,
     cada demanda gasta seus primeiros 30 minutos redescobrindo o repositório;
   - **Memória** — achados e lições de demandas passadas, ADRs, análises forenses (os
     artefatos que o dossiê já prometia).
2. **Acesso por porta** (`KnowledgeStore`, sobre `ObjectStore` — ADR-0001), em storage
   permissionado por conta/projeto, exposto ao sandbox **somente leitura** durante a
   execução.
3. **Pacote de contexto por demanda**, montado no provisionamento do sandbox: spec da
   demanda + regras + índice dos repositórios envolvidos + memórias relevantes. É a
   bagagem de bordo do agente — curada, não despejada.
4. **Escrita de volta no encerramento**: achados (ADR-0010) e lições da demanda entram
   na camada de memória. Contexto é um ciclo, não um arquivo.
5. **O índice se atualiza por evento de merge** (ADR-0006/0008), não por cron: o mapa
   acompanha a `main` real.

## Alternativas consideradas

**Pasta de documentos crua no sandbox.** Descartada: sem curadoria nem montagem, o
agente escava — e escavar é o que o pacote existe para eliminar.

**Tudo embutido no prompt.** Descartada: estoura a janela de contexto e cresce com o
projeto, não com a demanda.

**Serviço de RAG externo por cliente.** Adiada: a porta permite plugar depois; começar
por aí é comprar infraestrutura antes de ter conteúdo.

## Consequências

- ➕ O agente nasce sabendo o que esta sessão de trabalho sabe — regras, mapa, memória.
- ➕ A análise forense de hoje é o contexto da demanda de amanhã.
- ➖ Curadoria tem custo: montagem do pacote e relevância da memória são trabalho real
  do orquestrador.
- ➖ Storage por conta com permissão fina — mais uma superfície para os testes de
  contrato do `SecretStore`/`ObjectStore` cobrirem.
