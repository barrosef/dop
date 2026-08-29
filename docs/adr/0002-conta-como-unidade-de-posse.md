# ADR-0002 — Conta como unidade única de posse e isolamento

- **Status:** Aceita
- **Data:** 2026-08-29

## Contexto

Tanto uma pessoa física quanto uma organização possuem integrações, workspaces e
projetos. Os requisitos traziam uma tensão aparente: integrações "podem ser vistas e
manipuladas somente por esse usuário", mas um membro vinculado a uma organização "tem
acesso controlado a todas as integrações" dela.

Era preciso um modelo em que as duas afirmações fossem verdadeiras ao mesmo tempo, sem
regra especial para cada caso.

## Decisão

Uma entidade **`Account`** com `kind: 'personal' | 'organization'`. Tudo o que se possui
— integração, workspace, projeto — carrega um `accountId`, e apenas isso. O vínculo
usuário↔conta é uma **`Membership`** portando um papel. No cadastro, a conta pessoal
nasce junto com o usuário.

A tensão dos requisitos **dissolve-se por construção**: integração de conta pessoal é
privada porque a conta tem um membro só; integração de organização é compartilhada porque
a conta tem vários, sob papéis e concessões. Nenhum código precisa saber a diferença.

Contas pessoais e organizações são ambas raízes da plataforma e **dividem o mesmo espaço
de nomes de handle**.

## Alternativas consideradas

**Dono polimórfico** — cada recurso guardando `ownerType: 'user' | 'org'` mais `ownerId`.
Modela literalmente o texto dos requisitos. Descartada: toda consulta passa a precisar de
dois campos e de um desvio; regras de acesso ficam escritas duas vezes; e transferir
recurso entre pessoa e organização vira migração em vez de atualização. É o modelo que o
GitLab tinha e do qual migrou para *namespaces* por esses motivos.

**Namespaces aninháveis** — árvore genérica com herança de permissão em qualquer
profundidade, ao estilo dos *groups* do GitLab. Descartada por YAGNI: a hierarquia pedida
é fixa e de três níveis (conta → workspace → projeto). Construir árvore genérica para
representar estrutura fixa é pagar complexidade de herança, ciclos e resolução de
permissão sem ter o requisito.

## Consequências

- ➕ **Uma só fronteira de isolamento**: toda consulta filtra por um campo.
- ➕ Papéis funcionam igual em PF e PJ — a conta pessoal tem um vínculo, `owner`.
- ➕ Transferir workspace entre contas é trocar um valor.
- ➕ O seletor de conta lista pessoal e organizações no mesmo lugar porque são a mesma coisa.
- ➖ Cria-se uma conta pessoal implícita que o usuário nunca pediu e talvez não perceba.
- ➖ Handle compartilhado gera disputa de nome: se alguém toma `acme` como conta pessoal, a
  organização Acme não pode usá-lo. Mitigado por [ADR-0004](0004-verificacao-de-organizacao-por-dominio.md).
