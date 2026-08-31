# ADR-0016 — Núcleo em Go, BFF em Python, e a fronteira entre eles

- **Status:** Aceita
- **Data:** 2026-08-30
- **Refina:** [ADR-0001](0001-infraestrutura-atras-de-portas.md) · **Resolve:** F-14 (motor de agente atrás de porta)

## Contexto

A plataforma tem duas naturezas de trabalho muito diferentes: **domínio, estado e
transações** (identidade, recursos, fluxos, demandas, entrega, custo) e **conversa com
modelos de IA** (sessões longas, streaming de tokens, ferramentas, embeddings). Forçar
as duas no mesmo idioma cobra em algum lugar: gRPC e concorrência em Python são
desconfortáveis; o ecossistema de agentes e embeddings em Go é raso.

## Decisão

**`dop-core` em Go. `dop-api` (BFF) em Python.**

| | dop-core (Go) | dop-api (Python) |
|---|---|---|
| Responsabilidade | domínio, estado, transações, eventos, orquestração | protocolo, sessão de agente, conversa com modelos |
| Fala | gRPC (servidor) · Postgres · NATS · API do k8s | REST+SSE (app) · gRPC (CLI, sandbox) · **cliente gRPC do core** |
| Modos | `serve` · `worker` · `sched` · `launcher` (um binário) | um processo ASGI |

**A fronteira, em uma regra: o BFF não tem banco.** Nenhuma conexão do Python ao
Postgres — nem "só para uma consulta rápida". Dois donos do schema é como a fronteira
morre. Quando o BFF precisa registrar algo, **chama o core**, que grava estado e evento
na mesma transação.

**~~O `AgentRuntime` vive no BFF~~ — SUBSTITUÍDA pela [ADR-0023](0023-runtime-de-agente-no-nucleo.md): o runtime passou para o núcleo, porque a credencial do provedor não pode chegar à camada exposta à internet.** ~~O `AgentRuntime` vive no BFF~~ (ADR-0015 §7 do substrato): o core decide *o quê*
(fluxo, ficha, orçamento, roteamento — ADR-0011); o BFF executa a conversa com o modelo
e devolve eventos ao core. O sandbox fala **apenas com o BFF**, o que mantém a
allowlist de egress mínima (F-10).

## Alternativas consideradas

**Tudo em Python.** Continuidade com o repertório existente e um só idioma. Descartada
para o núcleo: o core é servidor gRPC com consumidores de evento e um daemon de
Kubernetes — trabalho em que Go é materialmente melhor (binário único, startup
instantâneo no scale-to-zero, concorrência barata).

**Tudo em Go.** Coerente no backend, mas o BFF perderia o ecossistema de IA (SDK de
agente, embeddings, tokenização) — que é justamente o miolo do produto.

**TypeScript no backend inteiro** (um idioma com o frontend). Descartada pelo mesmo
motivo: as bibliotecas de agente e embedding mais completas são Python.

## Consequências

- ➕ Cada peça no idioma em que o trabalho dela é natural.
- ➕ A fronteira "core é dono do estado" força a arquitetura limpa por construção.
- ➕ O sandbox tem um só interlocutor (BFF) — superfície de segurança menor.
- ➖ Dois idiomas: dois toolchains, dois lint/test, dois pipelines de imagem.
- ➖ Toda chamada do BFF ao core é rede — exige deadline, retry e idempotência
  (o proto carrega `idempotency_key` em toda escrita).
- ➖ Tipos duplicados nas duas pontas, mitigado por gerar ambos do mesmo proto
  ([ADR-0017](0017-proto-como-fonte-da-verdade.md)).
