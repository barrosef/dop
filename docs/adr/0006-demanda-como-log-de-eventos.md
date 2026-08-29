# ADR-0006 — A demanda é um log de eventos; tudo o mais é projeção

- **Status:** Aceita
- **Data:** 2026-08-29
- **Resolve:** F-8 (trace/replay), F-7 (telemetria), P-1 (auditoria) — ver `docs/analysis/2026-08-29-revisao-critica-plataforma.md`

## Contexto

Cinco necessidades distintas pedem, cada uma, um registro do que aconteceu numa demanda:

1. **Depuração** — reproduzir passo a passo uma demanda que deu errado.
2. **Auditoria** — numa organização, responder "quem autorizou este push, com qual
   credencial?" (encadeia com a ADR-0003).
3. **O dossiê** — os requisitos já pedem que ele seja "gerado em runtime, etapa por
   etapa", não montado no fim.
4. **Segurança** — perícia e detecção quando um conteúdo malicioso tenta desviar o
   agente.
5. **Métricas** — intervenções humanas, retrabalho, tempo-até-verde.

Construir cinco mecanismos é escrever o mesmo dado cinco vezes e vê-los divergir.

## Decisão

**Toda ação sobre uma demanda emite um evento imutável**, num log append-only por
demanda: `{quando, ator (humano | agente | subagente), ação, credencial usada (ref),
entrada resumida, resultado}`. O log é a espinha da demanda; **dossiê, linha do tempo,
auditoria, replay e métricas são projeções** dele — leituras, nunca escritas próprias.

Consequência para o SP-3: o log de eventos é cidadão de primeira classe da persistência;
o banco de documentos serve projeções, não o substitui (fecha F-16).

## Alternativas consideradas

**Um armazenamento por consumidor** (tabela de dossiê + trilha de auditoria + pipeline de
métricas). Descartada: escrita tripla, divergência garantida, e o replay nunca chega.

**Log textual não estruturado.** Descartada: não é consultável nem projetável; auditoria
em multi-tenant precisa de campos, não de grep.

## Consequências

- ➕ Um investimento, cinco retornos; P-1 sai da lista de pendências.
- ➕ Os "achados" dos subagentes (ADR-0010) e o metering (ADR-0011) são só mais dois
  tipos de evento — nada de mecanismo novo.
- ➖ Disciplina de emissão em todo lugar: ação sem evento é bug, não detalhe.
- ➖ Volume: o log cresce com a frota; retenção e compactação são decisão do SP-3.
