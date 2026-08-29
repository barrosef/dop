# ADR-0003 — Credencial de organização para agir, autoria humana no commit

- **Status:** Aceita
- **Data:** 2026-08-29

## Contexto

Um token OAuth de usuário pertence à *pessoa*. Quando ela sai da empresa, revoga o acesso
ou troca a senha, a integração morre — e leva junto todos os projetos da organização que
dependiam dela. Numa conta pessoal isso é aceitável, porque a pessoa é a conta. Numa
organização é uma bomba-relógio.

Mas a alternativa óbvia cria outro problema: se a plataforma age com credencial de
organização, ela aparece no repositório como a instalação do App, e o histórico deixa de
dizer quem pediu a mudança. Rastreabilidade é justamente o que o dossiê do card promete.

## Decisão

**Duas escolhas independentes, uma para cada problema.**

**Para agir:** conta de organização usa **credencial de organização** — GitHub App
instalado na organização, *group access token* no GitLab, service principal no Azure
DevOps. Sobrevive a demissões. Token pessoal é permitido como saída, mas a interface
exibe de quem ele depende, para que o risco fique visível em vez de ser descoberto no dia
em que quebra. Conta pessoal usa qualquer método.

**Para atribuir:** o push e a abertura do PR usam a credencial da organização, mas **cada
commit leva `author` com nome e e-mail do dev que conduziu o card**, e o corpo do PR
identifica quem pediu.

## Alternativas consideradas

**Tudo em nome da organização.** Mais simples e uniforme. Descartada: o repositório deixa
de guardar quem conduziu, e a rastreabilidade fica presa dentro da plataforma — inútil
para quem lê o histórico do repositório meses depois.

**Credencial da pessoa quando ela tiver uma**, caindo para a da organização como reserva.
Atribuição perfeita. Descartada porque contradiz a regra de que integração de conta
pessoal não é usada em organização, e reintroduz exatamente a fragilidade que esta ADR
existe para eliminar.

## Consequências

- ➕ A integração sobrevive à saída de qualquer pessoa.
- ➕ O histórico do repositório mantém rastreabilidade humana sem depender do token de
  ninguém. É como bots de CI sérios operam.
- ➖ **Ponto único de falha:** se o App é desinstalado ou o token revogado, todos os
  projetos daquela conta param. Exige monitoramento do `status` da integração e alerta ao
  `owner`.
- ➖ O ator do push e o autor do commit são entidades diferentes, o que pode confundir
  quem lê a interface do provedor sem contexto.
