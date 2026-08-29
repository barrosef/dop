# ADR-0005 — Plataforma multi-tenant com organizações

- **Status:** Aceita
- **Data:** 2026-08-29

## Contexto

A documentação anterior do produto fixava o modelo de uso como **monousuário,
multi-projeto em paralelo**, sem multiusuário nem RBAC, e listava "multiusuário com RBAC
avançado" explicitamente fora de escopo. O produto era entendido como ferramenta local de
um desenvolvedor.

O direcionamento mudou: a plataforma passa a ter usuários com autenticação própria,
organizações com membros, papéis e controle de acesso por integração — rodando em cluster
ou em nuvem, não na máquina de alguém.

## Decisão

**Substituir a decisão anterior.** A plataforma é multi-tenant desde o modelo de dados:

- Existe `User`, com autenticação por e-mail e senha, Google, GitHub e LinkedIn.
- Existe `Account`, pessoal ou organização ([ADR-0002](0002-conta-como-unidade-de-posse.md)).
- **Toda entidade de domínio carrega conta, workspace e projeto desde a primeira
  migração**, e toda chamada na borda é autenticada e resolve conta ativa.

O modelo nasce completo mesmo onde a funcionalidade ainda não existe — organizações,
membros e papéis entram numa fase seguinte **sem migração**, porque o schema já os previa.

## Alternativas consideradas

**Manter monousuário e acrescentar tenancy depois.** Mais rápido para chegar ao produto.
Descartada: retrofitar isolamento multi-tenant é das migrações mais caras e arriscadas que
existem — cada consulta escrita sem filtro de conta vira um vazamento em potencial, e o
custo cresce com a base de código.

**Construir tudo antes de voltar ao núcleo do produto.** Descartada por adiar
demais o produto que justifica a plataforma. O meio-termo adotado — modelar tudo,
construir autenticação e conta pessoal — já exercita o multi-tenant de verdade, porque
toda consulta filtra por conta desde o início; a conta simplesmente é sempre pessoal.

## Consequências

- ➕ Isolamento correto desde a primeira linha, sem a migração mais cara do catálogo.
- ➕ Organizações entram sem tocar no schema.
- ➖ Escopo maior: autenticação, contas, papéis e concessões antes de qualquer valor de
  produto entregue.
- ➖ Segredos passam a ser por conta, e não mais globais do processo.
- ➖ Traz CPF e CNPJ para dentro do sistema, com as obrigações de proteção de dados que
  isso implica (P-3 no `ROADMAP.md`).
