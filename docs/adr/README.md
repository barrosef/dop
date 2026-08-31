# Decisões de arquitetura — plataforma DOP

Registro das decisões estruturantes, no formato MADR: contexto, decisão, alternativas
consideradas e consequências. ADR **não muda** depois de aceita — é substituída.

Uma decisão vira ADR quando é citada por mais de uma spec, quando teve alternativa real
descartada, ou quando alguém daqui a seis meses vai perguntar "por que assim?".

| # | Título | Status |
|---|---|---|
| [0001](0001-infraestrutura-atras-de-portas.md) | Infraestrutura atrás de portas com adaptadores plugáveis | Aceita |
| [0002](0002-conta-como-unidade-de-posse.md) | Conta como unidade única de posse e isolamento | Aceita |
| [0003](0003-credencial-de-organizacao-autoria-humana.md) | Credencial de organização para agir, autoria humana no commit | Aceita |
| [0004](0004-verificacao-de-organizacao-por-dominio.md) | Verificação de organização por domínio, não por titularidade | Aceita |
| [0005](0005-plataforma-multi-tenant.md) | Plataforma multi-tenant com organizações | Aceita |
| [0006](0006-demanda-como-log-de-eventos.md) | A demanda é um log de eventos; tudo o mais é projeção | Aceita |
| [0007](0007-sem-verde-sem-pr.md) | Sem verde, sem PR: verificação nativa antes do humano | Aceita |
| [0008](0008-merge-queue-por-repositorio.md) | Merge queue por repositório; conflito é tarefa de agente | Aceita |
| [0009](0009-contexto-como-subsistema.md) | Contexto é subsistema: base de conhecimento e pacote por demanda | Aceita |
| [0010](0010-multi-agente-por-demanda.md) | Multi-agente por demanda: threads endereçáveis e achados publicados | Aceita |
| [0011](0011-governanca-de-custo-llm.md) | Governança de custo de LLM: medição firme, roteamento em rascunho | **Rascunho** |
| [0012](0012-economia-de-tokens.md) | Economia de tokens como disciplina de engenharia | Aceita |
| [0013](0013-recurso-como-unidade-de-compartilhamento.md) | Recurso como unidade de posse e compartilhamento da conta | Aceita |
| [0014](0014-fluxo-de-trabalho-dinamico.md) | Fluxo de trabalho dinâmico, tipado e herdável | Aceita |
| [0015](0015-orquestrador-de-projeto.md) | Orquestrador de projeto: o agente techlead | Aceita |
| [0016](0016-stack-go-core-python-bff.md) | Núcleo em Go, BFF em Python, e a fronteira entre eles | Aceita |
| [0017](0017-proto-como-fonte-da-verdade.md) | O `.proto` é a fonte da verdade do contrato | Aceita |
| [0018](0018-persistencia-postgres.md) | PostgreSQL como banco único, com pgvector | Aceita |
| [0019](0019-outbox-e-nats.md) | Outbox transacional + NATS JetStream | Aceita |
| [0020](0020-emuladores-firebase-e-dono-unico.md) | Emuladores Firebase no local; Terraform como dono único | Aceita |
