# ADR-0018 — PostgreSQL como banco único, com pgvector

- **Status:** Aceita
- **Data:** 2026-08-30
- **Resolve:** F-16 (sinais contraditórios de persistência) · **Refina:** [ADR-0006](0006-demanda-como-log-de-eventos.md)

## Contexto

O produto sinalizou "banco adequado, como Mongo por exemplo" numa conversa inicial. Ao
desenhar o backend, as cargas ficaram claras e são de três naturezas: relacional
(contas × vínculos × concessões × projetos), documental (fluxos, fichas, payloads de
evento) e semântica (memórias do conhecimento).

## Decisão

**PostgreSQL para tudo**, com JSONB e pgvector cobrindo as outras duas naturezas.

- **Relacional na medula:** integridade multi-tenant é FK e constraint, não convenção de
  aplicação. Toda tabela de domínio carrega `account_id`.
- **JSONB** para fluxos (ADR-0014), fichas de agente e payloads de evento — schema-livre
  onde interessa, com índice.
- **Log de eventos** em tabela append-only particionada por mês, com **outbox**
  ([ADR-0019](0019-outbox-e-nats.md)).
- **pgvector** para busca semântica das memórias (ADR-0009) — **sem vector-store extra**.
- **Projeções** (dossiê, timeline, caixa de atenção) começam como *views materializadas*;
  viram tabelas alimentadas pelo worker apenas se o custo mandar.
- Portabilidade: Cloud SQL no GCP, CloudNativePG no k3s — mesma engine.

## Alternativas consideradas

**MongoDB.** Bom para o documental, ruim para o relacional que domina o domínio;
integridade multi-tenant viraria responsabilidade da aplicação — o lugar errado.

**Postgres + vector-store dedicado** (Qdrant, pgvector externo). Descartada por YAGNI:
mais um serviço para operar antes de existir volume que justifique.

**Postgres + Kafka como log.** Descartada: o log vive no banco (outbox); o broker
transporta, não guarda a verdade.

## Consequências

- ➕ Um banco: uma operação, um backup, uma expertise — e economia real.
- ➕ Transação local resolve atomicidade sem 2PC.
- ➖ Carga de eventos concentrada no mesmo banco: exige partição, retenção e vigilância.
- ➖ Busca vetorial no Postgres tem teto; quando chegar, extrai-se atrás da mesma porta.
