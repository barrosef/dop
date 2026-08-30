# ADR-0013 — Recurso como unidade de posse e compartilhamento da conta

- **Status:** Aceita
- **Data:** 2026-08-30

## Contexto

O modelo de compartilhamento existia para uma coisa só: integrações, com concessões
`use`/`manage` compostas no convite. Surgiram outras coisas que uma conta possui e quer
compartilhar sob autorização:

- **Skills** — capacidades reutilizáveis dos agentes;
- **Fluxos de trabalho humano↔agente** — como dev e agentes colaboram numa demanda;
- **Fluxos git** — governança de branches como artefato: taxonomia por tipo de card,
  base e direção (forward/reverso), composição de release, back-merge de hotfix,
  políticas. Exemplo real: a spec de governança do ecossistema Optum
  (trunk + release, `epic/`→`feat/`, tipo de card determinando prefixo e fluxo);
- E as próprias integrações ganharam uma terceira categoria: **providers de agente**
  (Claude, Codex, Google Code Assist…).

Criar um mecanismo de compartilhamento por tipo repetiria o erro que a ADR-0002 evitou
nas contas: N implementações da mesma política, divergindo.

## Decisão

1. **`Resource` é a unidade de posse e compartilhamento**: `{id, accountId, kind, name,
   config, credentialRef?}`. Tipos iniciais:

   | `kind` | Conteúdo | Credencial |
   |---|---|---|
   | `integration` | categorias `git`, `task_manager`, **`agent`** | sim |
   | `skill` | capacidade reutilizável de agente | não |
   | `workflow` | fluxo de trabalho humano↔agente | não |
   | `git_flow` | governança git declarativa (taxonomia, promoção, políticas) | não |

2. **A concessão passa a ser por recurso** — `use`/`manage`, por usuário, composta no
   convite e editável a qualquer tempo. As regras existentes não mudam, generalizam:
   recurso de conta PF é privado; só recurso de conta PJ é compartilhável; `owner`/`admin`
   têm `manage` implícito; revogar `use` não derruba o que já está configurado.
3. **A plataforma (nível 0) oferece recursos globais** — catálogo de providers, skills e
   fluxos padrão — que uma conta **adota** (cópia ou referência versionada) e então
   governa como seus.
4. **Projeto consome recursos da conta dona do workspace** — a regra das integrações,
   inalterada, agora vale para tudo: o fluxo git anexado ao projeto parametriza a fila
   de merge (ADR-0008) e a verificação; as skills e o workflow anexados parametrizam os
   agentes (fichas, ADR-0010).

## Alternativas consideradas

**Um mecanismo de compartilhamento por tipo.** Descartada: é a mesma política escrita
quatro vezes, com quatro telas e quatro bugs.

**Tudo como "integração".** Descartada: skill e fluxo não têm credencial, têm versão e
têm conteúdo — forçá-los na entidade errada cobraria em toda evolução.

## Consequências

- ➕ Tipo novo de recurso não toca no mecanismo de compartilhamento nem no convite.
- ➕ O fluxo git vira artefato governado e versionado — auditável, compartilhável entre
  projetos e contas, e legível pelos agentes como regra.
- ➖ A tabela de concessões do SP-0 generaliza (`resource_grants`); o schema nasce assim.
- ➖ Adoção de recurso global exige decisão de versionamento (cópia × referência) por
  tipo — registrada na spec de recursos.
