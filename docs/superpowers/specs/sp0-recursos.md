# SP-0 — Recursos da conta

> **Status:** Aprovada para revisão · **Data:** 2026-08-30 · **Projeto:** plataforma DOP
>
> **Responde:** o que é um recurso, quais tipos existem, como se compartilha e como um
> projeto consome.
>
> **Não responde:** credenciais → [`sp0-integracoes-e-credenciais.md`](sp0-integracoes-e-credenciais.md);
> contas e vínculos → [`sp0-identidade-e-tenancy.md`](sp0-identidade-e-tenancy.md).

Decisão de base: [ADR-0013](../../adr/0013-recurso-como-unidade-de-compartilhamento.md).

## 1. A entidade

`Resource`: `{id, accountId, kind, name, version, config, credentialRef?}`.

| `kind` | O que descreve | Exemplo |
|---|---|---|
| `integration` | Conexão com provedor externo (`git`, `task_manager`, `agent`) | GitHub da org; Claude por API key |
| `skill` | Capacidade reutilizável concedida a agentes | "análise forense de banco" |
| `workflow` | Fluxo de trabalho humano↔agente: portões, quem aprova o quê | "spec aprovada pelo dev antes de implementar" |
| `git_flow` | Governança git declarativa: taxonomia de branch por tipo de card, bases, direção (forward/reverso), composição de release, políticas | trunk + release do ecossistema Optum |

Recursos sem credencial são **versionados** — mudar um fluxo git em uso gera versão
nova; projetos migram explicitamente.

## 2. Compartilhamento

O mecanismo é o das integrações, generalizado (ADR-0013): recurso de PF é privado;
recurso de PJ é compartilhável por **concessão `use`/`manage` por usuário**, composta no
convite e editável sempre; `owner`/`admin` têm `manage` implícito; revogar `use` não
derruba o que já está configurado.

## 3. Recursos globais da plataforma

O nível 0 mantém o catálogo: providers suportados, skills padrão, fluxos git de
referência. Uma conta **adota** um recurso global:

- `git_flow`, `workflow`, `skill`: **cópia versionada** — a conta passa a governar a sua;
  atualização do catálogo é oferta, nunca imposição.
- `integration`: nunca é global — credencial é sempre da conta.

## 4. Consumo pelo projeto

O projeto anexa recursos da conta dona do workspace — regra única, a mesma das
integrações:

| Recurso anexado | Quem o lê |
|---|---|
| `git_flow` | fila de merge (ADR-0008), verificação e entrega, nomenclatura de branch por tipo de card |
| `workflow` | portões e papéis do ciclo da demanda (SP-4 núcleo) |
| `skill` | fichas dos agentes (ADR-0010) |
| `integration` | repositórios, task manager, modelos dos agentes |

## 5. Riscos

| # | |
|---|---|
| R-1 | Fluxo git mal escrito quebra a entrega de todos os projetos que o usam — validação estrutural na criação e simulação a seco antes de ativar versão nova |
| R-2 | Proliferação de tipos de recurso — tipo novo exige ADR, não é extensão livre |
| R-3 | Adoção por cópia diverge do catálogo — a origem fica registrada e o diff é visível |
