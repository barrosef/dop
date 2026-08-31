# ADR-0019 — Outbox transacional + NATS JetStream

- **Status:** Aceita
- **Data:** 2026-08-30
- **Realiza:** [ADR-0006](0006-demanda-como-log-de-eventos.md) (o log) e o requisito de processos desacoplados com transações atômicas

## Contexto

O produto pediu: processos desacoplados, resiliência forte e **transações atômicas
baseadas em eventos**, síncronas ou assíncronas. O modo ingênuo — gravar no banco e
depois publicar no broker — tem uma janela onde o processo morre entre as duas ações:
estado mudou, ninguém soube. Commit distribuído (2PC) resolve e cobra caro em
complexidade e disponibilidade.

## Decisão

**Transactional outbox.** Toda mudança de estado grava, **na mesma transação Postgres**,
o estado novo *e* o evento na tabela append-only. Commit ⇒ atômico por construção.
Um **relay** lê o outbox e publica no broker, marcando o publicado — entrega ao menos uma
vez, sem 2PC.

**Broker: NATS JetStream.** Leve (um container), roda idêntico em k3s e GKE, persistente,
com consumer groups, DLQ e replay.

**Consumidores idempotentes** constroem projeções (dossiê, timeline, caixa de atenção,
métricas, custo) e reagem (techlead desperta, launcher provisiona, índice regenera).
Retry com backoff; mensagem envenenada vai para DLQ.

**Processos longos são sagas** orquestradas pelo core — a finalização da demanda
(commits → PRs → fila de merge → conflitos → dossiê) é o caso canônico: cada passo emite
evento, falha compensa ou escala à caixa de atenção, e o estado da saga vive no Postgres.
O usuário percebe como síncrono porque o BFF empurra progresso por SSE; a execução é
assíncrona e sobrevive a reinícios.

## Alternativas consideradas

**Kafka.** Caminhão para a nossa carga; custo operacional e de memória desproporcional.
**Google Pub/Sub.** Managed e bom, mas amarra ao GCP — fica como **segundo adaptador** da
porta `EventBus`, para quem preferir gerenciado.
**Redis Streams.** Descartada: sem as garantias de JetStream, e traria um serviço que
ainda não precisamos (não há requisito de cache).
**Publicar direto do código, sem outbox.** É a janela de perda que esta ADR existe para
fechar.

## Consequências

- ➕ Atomicidade real sem 2PC; nunca "gravei mas não publiquei".
- ➕ Replay de graça: a verdade é o log, projeções são reconstruíveis.
- ➖ Latência do relay (poll) entre commit e publicação — aceitável; reduzível com
  `LISTEN/NOTIFY` se doer.
- ➖ Idempotência vira obrigação de todo consumidor, não recomendação.
- ➖ Mais uma peça a operar (NATS), mitigada por ser um container só.
