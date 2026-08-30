# Fluxo de trabalho dinâmico

> **Status:** Aprovada para revisão · **Data:** 2026-08-30 · **Projeto:** plataforma DOP
>
> **Responde:** o formato do recurso `workflow`, a cadeia de herança, o ciclo na demanda
> e como agente e tela o consomem. É o núcleo do SP-4.
> **Não responde:** sintaxe dos critérios executáveis dentro do artefato `spec` (P-8);
> compartilhamento externo (P-9).

Decisões de base: [ADR-0014](../../adr/0014-fluxo-de-trabalho-dinamico.md),
[ADR-0013](../../adr/0013-recurso-como-unidade-de-compartilhamento.md),
[ADR-0006](../../adr/0006-demanda-como-log-de-eventos.md),
[ADR-0007](../../adr/0007-sem-verde-sem-pr.md).

## 1. A estrutura

```
Fluxo {
  nome, descrição, versão,
  etapas: [ {
    chave,               // única no fluxo
    nome,                // livre, do autor
    tipo,                // vocabulário da plataforma — decide renderizador e comportamento
    artefatos: [...],    // o que a etapa produz: documento | spec | plano | plano_testes | diagrama | relatório
    portão: humano | nenhum,
    subetapas?: [...]    // ex.: teste → [aaa, e2e, integração]
  } ]
}
```

**Tipos v1:** `contexto`, `spec`, `plano`, `implementação`, `teste` (subtipos `aaa`,
`e2e`, `integração`), `validação_humana`, `finalização`, `genérico`. Tipo novo é
evolução da plataforma (exige decisão); composição nova é liberdade do usuário.

**Sem na v1, de propósito:** condicionais, paralelismo de etapas, DSL de regras.
Evoluem sobre a mesma estrutura.

## 2. Contratos por tipo

O tipo é um contrato de três pontas — **tela** (renderizador), **agente** (o que
produzir e onde parar) e **plataforma** (que eventos emitir):

| Tipo | Agente produz | Tela renderiza | Nota |
|---|---|---|---|
| `contexto` | levantamento do terreno (repos, pontos de impacto) | documento MD | absorve o "init" antigo: lê o card do provider |
| `spec` | a spec com critérios executáveis | documento + portão de aprovação | ADR-0007; sintaxe dos critérios = P-8 |
| `plano` | plano de implementação e de testes | documento + abas | |
| `implementação` | código nas branches do fluxo git anexado | progresso por repo/tarefa | |
| `teste` | execução das suítes por subtipo | abas aaa/e2e/integração, resultados | verde exigido antes do PR (ADR-0007) |
| `validação_humana` | plano de validação com links | **checklist marcável item a item**, expansível | o dev valida fora e marca; pode falar com o agente no meio |
| `finalização` | PRs, entrada na fila de merge, encerramento | passos com estados idle/running/done/warn/error | ADR-0008; dossiê consolidado |
| `genérico` | o que a descrição da etapa pedir | documento | válvula de escape |

## 3. Cadeia de resolução

`plataforma ◁ conta ◁ workspace ◁ projeto ◁ demanda` — o mais próximo vence; herda-se
por omissão, sobrepõe-se por declaração. A interface sempre exibe a origem do fluxo
efetivo ("herdado do projeto ◂ workspace ◂ conta"). O dev pode escolher um fluxo só
para uma demanda; **promoção** leva um fluxo a níveis acima (quem tem `manage`).

**Acesso (ADR-0014 §6):** numa PJ, fluxos são abertos dentro da conta por default,
restringíveis por concessão. Escopos v1: privado → conta. Externo = P-9.

## 4. Ciclo na demanda

1. Demanda inicia → resolve o fluxo efetivo → **congela a versão**.
2. Cada transição de etapa, artefato produzido e portão decidido é **evento**
   (ADR-0006); a régua do centro do Chat é projeção.
3. Portão `humano` pendente vira item da **caixa de atenção**.
4. Etapas geram os artefatos no storage de conhecimento (ADR-0009); achados de
   subagentes anexam-se à etapa corrente.

## 5. O default da plataforma

Recurso global do catálogo (adotável por cópia versionada — ADR-0013 §3):

```
contexto → spec (portão humano) → plano → implementação
        → teste [aaa, e2e, integração] → validação_humana (portão humano) → finalização
```

## 6. Riscos

| # | |
|---|---|
| R-1 | Fluxo sem etapa `spec` quebra o método spec-driven — a validação estrutural avisa (não bloqueia: contas mandam no seu processo, a plataforma explicita o custo) |
| R-2 | Demanda longa com fluxo congelado divergindo do fluxo novo da conta — a origem visível e o congelamento explícito são a resposta; migração de demanda em voo fica fora da v1 |
| R-3 | Vocabulário de tipos crescer sem controle — tipo novo exige decisão da plataforma (ADR-0014 §1) |
