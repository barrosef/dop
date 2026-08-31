# ADR-0017 — O `.proto` é a fonte da verdade do contrato

- **Status:** Aceita
- **Data:** 2026-08-30
- **Resolve:** F-12 (contrato triplicado)

## Contexto

O contrato já nascia triplicado: `types.ts` escrito à mão no frontend, um `openapi.yaml`
vazio com codegen rodando sobre o nada, e um futuro proto do núcleo. Três fontes, nenhuma
autoritativa — o *drift* começou antes de existir produto.

## Decisão

**Um `.proto` por domínio, versionado, é a única fonte.** Dele são gerados:

- servidor e tipos do **core** (Go);
- cliente do **BFF** (Python);
- cliente do **dop-cli**;
- tipos do **frontend** (TS) e, quando útil, o OpenAPI do BFF.

```
proto/dop/v1/  common · identity · resource · hierarchy · workflow
               demand · execution · delivery · knowledge · cost
```

Convenções obrigatórias:

1. **Streaming server-side** para tudo ao vivo (`WatchDemand`, `StreamLogs`,
   `WatchAttention`); o BFF converte em SSE para o browser.
2. **`Ref` em vez de id solto** (`AccountRef{id}`) — tenant nunca é string anônima.
3. **Toda RPC de escrita carrega `idempotency_key`** — com eventos e retries, isso é
   requisito, não luxo.
4. Compatibilidade validada no CI (`buf breaking`): campo não muda de número nem de tipo.
5. **Quem chama e em qual conta viaja na metadata**, não no corpo — `x-actor-id`,
   `x-account-id`, `x-request-id`, resolvidos por interceptor antes de qualquer
   caso de uso. Contexto é preocupação transversal: no corpo, cada RPC teria que
   lembrar de conferir, e a que esquecesse viraria buraco de isolamento.

   *Dívida registrada:* as mensagens de requisição ainda declaram um campo
   `CallContext ctx = 1` de uma tentativa anterior. O servidor **ignora** esse
   campo — autoriza só pela metadata. Um contrato que declara um campo que não
   tem efeito ensina o errado a quem lê e faz o cliente acreditar que está
   escopando a chamada quando não está. O campo sai dos protos (número 1
   reservado, para não quebrar compatibilidade) num passe dedicado.

## Alternativas consideradas

**OpenAPI como fonte, gRPC gerado dele.** Inverte a dependência: o contrato interno
(core) passaria a depender do formato da borda. Descartada.

**Contratos escritos à mão nas duas pontas.** É o estado atual, e é o problema.

## Consequências

- ➕ Uma verdade; o drift vira erro de build, não descoberta em produção.
- ➕ O frontend deixa de inventar semântica (F-15): `types.ts` vira artefato gerado.
- ➖ `buf` e codegen entram no CI desde o primeiro dia.
- ➖ Mudança de contrato exige disciplina de versionamento (aditivo por padrão).
