# Contexto e conhecimento

> **Status:** Aprovada para revisão · **Data:** 2026-08-29 · **Projeto:** plataforma DOP
>
> **Responde:** o que o agente sabe antes de começar, onde esse saber vive, como é
> montado por demanda e como cresce.
>
> **Não responde:** formato da spec da demanda (núcleo do SP-4, pendente); persistência
> física (SP-3).

Decisão de base: [ADR-0009](../../adr/0009-contexto-como-subsistema.md); apoia-se em
[ADR-0006](../../adr/0006-demanda-como-log-de-eventos.md) e
[ADR-0010](../../adr/0010-multi-agente-por-demanda.md).

## 1. A base de conhecimento do projeto

Entidade versionada, por projeto, em três camadas:

| Camada | Conteúdo | Quem escreve |
|---|---|---|
| **Regras** | Convenções que o agente obedece: fluxo de branches, proibições, padrões de nome, política de teste | Humano (e agente, com aprovação) |
| **Índice** | Mapa dos repositórios: módulos, responsabilidades, como buildar, como testar, portas e serviços | Gerado pelo agente; atualizado por evento de merge |
| **Memória** | Achados de demandas passadas, lições, ADRs do cliente, análises forenses | Escrita de volta no fim de cada demanda |

## 2. Onde vive

Atrás da porta `KnowledgeStore` (sobre `ObjectStore`, ADR-0001), em storage
permissionado por conta e projeto. O sandbox recebe o recorte do seu projeto em
**somente leitura** durante a execução; a escrita de volta passa pela plataforma, que a
registra como evento (ADR-0006).

## 3. O pacote de contexto

Montado pelo orquestrador no `provision()` do sandbox:

```
pacote = spec da demanda
       + regras do projeto
       + índice DOS REPOSITÓRIOS DA DEMANDA (não do projeto inteiro)
       + memórias relevantes (seleção por relação com a demanda)
       + achados já publicados na demanda (em retomada)
```

Disciplina de tamanho: o pacote cresce com a **demanda**, não com o projeto. O que não
coube entra por consulta — o agente pode pedir mais (`buscar_memoria`,
`ler_indice(repo)`) durante a execução.

## 4. O ciclo

```
provisiona → agente trabalha (lê pacote, consulta mais)
          → subagentes publicam achados (ADR-0010)
          → demanda encerra → achados e lições → camada de memória
          → merge na main → evento → índice re-gera o trecho afetado
```

A análise forense de hoje é o contexto da demanda de amanhã. Contexto é ciclo, não
arquivo.

## 5. Riscos

| # | |
|---|---|
| R-1 | Memória cresce sem curadoria e vira ruído — relevância na montagem do pacote é trabalho do orquestrador, com poda periódica |
| R-2 | Índice desatualizado é pior que índice ausente (mente com confiança) — por isso a atualização é por evento de merge, nunca por cron |
| R-3 | Conteúdo da memória inclui texto de terceiros (cards, logs) — entra no pacote como não confiável, pela regra de segurança do substrato |
