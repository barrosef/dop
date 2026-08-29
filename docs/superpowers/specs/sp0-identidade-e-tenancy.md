# SP-0 — Identidade e tenancy

> **Status:** Aprovada para revisão · **Data:** 2026-08-29 · **Projeto:** plataforma DOP
>
> **Responde:** quem é o usuário, o que é uma conta, como se possui e se isola, e como se
> entra e se sai de uma conta.
>
> **Não responde:** integrações e credenciais → [`sp0-integracoes-e-credenciais.md`](sp0-integracoes-e-credenciais.md).
> Decomposição e faseamento → [`ROADMAP.md`](../../ROADMAP.md). Vocabulário →
> [`GLOSSARIO.md`](../../GLOSSARIO.md). Justificativas → [`adr/`](../../adr/).

Decisões de base: [ADR-0002](../../adr/0002-conta-como-unidade-de-posse.md) (conta como
unidade de posse), [ADR-0005](../../adr/0005-plataforma-multi-tenant.md) (multi-tenant),
[ADR-0004](../../adr/0004-verificacao-de-organizacao-por-dominio.md) (verificação por
domínio), [ADR-0001](../../adr/0001-infraestrutura-atras-de-portas.md) (portas).

## 1. Identidade

**`User`** — a identidade da pessoa. Identificador do provedor, e-mail, nome, avatar e
provedores vinculados. Existe uma vez na plataforma, independentemente de quantas contas
acesse.

A autenticação usa **Firebase Authentication** como primeiro adaptador da porta
`IdentityProvider`, com quatro métodos: e-mail e senha, Google, GitHub e LinkedIn.

Conforme a ADR-0001, o adaptador devolve um **principal normalizado** — `subject`,
`email`, `emailVerified`, provedores vinculados. Claim de Firebase não cruza a fronteira
do domínio.

**Account linking habilitado desde o primeiro dia.** O mesmo e-mail chegando por dois
provedores resolve para o mesmo `User`. Sem isso, a pessoa que entrou por Google e depois
por GitHub vira dois usuários — e duplicata em sistema multi-tenant não é incômodo
cosmético, é confusão de acesso.

## 2. Conta e posse

**`Account`** — a unidade de posse e de isolamento:

| Campo | |
|---|---|
| `kind` | `personal` ou `organization` |
| `handle` | identificador único na plataforma; PF e PJ dividem o mesmo espaço de nomes |
| `displayName` | nome de exibição |
| *(organização)* | CNPJ, razão social, endereço, estado da verificação de domínio |

**`Membership`** — o vínculo `User × Account`, portando um papel. É onde mora todo o
controle de acesso.

No cadastro, a conta pessoal nasce junto com o usuário: `kind: 'personal'`, handle
derivado do e-mail, uma membership `owner`. Havendo colisão de handle, sufixa-se até
resolver; o usuário pode trocar depois.

### 2.1 A forma da posse

```
Plataforma
├── Conta PF 01  (kind=personal, raiz)  ─┐
├── Conta PF 02  (kind=personal, raiz)  ─┼─ existem por si só
└── Conta PJ     (kind=organization)     │
      ├── vínculo → PF 01   papel: owner       │  o vínculo é uma linha,
      └── vínculo → PF 02   papel: developer  ─┘  não cópia nem aninhamento
```

O papel mora **na linha**, não na pessoa: a mesma PF é `owner` numa organização e
`developer` em outra sem que nada mude nela.

**Duas consequências de "vínculo apenas":**

- Workspaces, projetos e integrações da conta pessoal **não passam a ser** da organização,
  nem o contrário. Cada conta possui o seu; o vínculo dá acesso ao que é da organização e
  nada mais.
- Desvincular tira o acesso ao que é da organização e **não toca em nada** do que é da
  pessoa.

### 2.2 Conta ativa

**Toda chamada à API carrega uma conta ativa**, determinada por um **seletor** na
interface. É ela que decide o que o usuário enxerga e onde o que ele criar vai parar.
Requisição sem conta ativa é inválida.

O seletor lista a conta pessoal mais toda organização em que o usuário tenha vínculo.

## 3. Ciclo do vínculo

Um vínculo nasce de um **convite**. Não há outra porta de entrada, exceto a entrada
automática por domínio de organização verificada (§6).

**`Invite`**: `accountId`, `email`, `role`, concessões, `invitedByUserId`, `status`,
`expiresAt`.

```
pending ──aceite──▶ accepted
   │
   ├──14 dias──▶ expired
   └──revogação──▶ revoked
```

Regras:

- **Papel e concessões são compostos no convite**, não depois. Quem convida escolhe
  livremente: tudo, nada ou uma seleção. Depois do aceite, tudo é editável a qualquer
  tempo.
- O convite é endereçado a um **e-mail**. Se já existe `User` com aquele e-mail, o aceite
  cria a `Membership` direto; se não, o aceite passa pelo cadastro e o vínculo se conclui
  ao final dele.
- **Expira em 14 dias.** Reenviar gera novo convite e invalida o anterior.
- **Revogável enquanto `pending`.**
- Convite para e-mail que já é membro daquela conta é recusado.

## 4. Papéis e concessões

Dois eixos independentes.

**Papel** — o que a pessoa pode fazer *na conta*. Um por `Membership`.

| Papel | |
|---|---|
| `owner` | Controle total, incluindo faturamento, transferência de posse e exclusão da conta |
| `admin` | Gere membros, integrações e workspaces. Tudo menos faturamento e exclusão |
| `developer` | Trabalha nos cards: executa, conversa com o Claude, abre PR. Não gere membros nem cria integrações |
| `viewer` | Só leitura — acompanhar cards, ver o dossiê. Serve para PO e gestor |

Ficaram deliberadamente de fora um `maintainer` intermediário e um papel separado de
faturamento. Papel é um campo na membership: acrescentar depois não exige migração, e
inventar hierarquia que ninguém pediu é complexidade que se paga sem receber.

**Concessão de integração** — por usuário, por integração, com nível `use` ou `manage`.
Ortogonal ao papel; definida em
[`sp0-integracoes-e-credenciais.md`](sp0-integracoes-e-credenciais.md).

`owner` e `admin` têm `manage` implícito em toda integração — sem isso surge o cenário em
que ninguém consegue consertar uma integração quebrada.

**Não há default.** O acesso é o que foi composto no convite e o que se editou depois.

## 5. Sucessão e conta órfã

**Invariante: toda conta tem ao menos um `owner` ativo.** O sistema recusa qualquer
operação que o viole, com mensagem explícita.

- Um `owner` **não pode** rebaixar-se nem sair enquanto for o último. Precisa promover
  outro antes.
- Conta pessoal tem exatamente um vínculo, `owner`, não removível. Excluí-la é excluir o
  usuário — ver P-3 no `ROADMAP.md`.

**Recuperação de organização órfã** — o único `owner` ficou inacessível (saiu da empresa,
perdeu o acesso, faleceu):

- Se a organização é **verificada por domínio**, um `admin` reivindica a posse
  **reprovando o controle do domínio** — o mesmo mecanismo da ADR-0004. Resolvido pelo
  próprio cliente, sem intervenção.
- Se **não é verificada**, não há prova disponível. Fica pendente (P-6).

Esse reaproveitamento é um argumento a mais para a verificação de domínio: ela paga duas
vezes.

## 6. Organizações

**Criação.** Nome e CNPJ; o CNPJ preenche razão social e endereço automaticamente e já
confirma que a empresa existe e está ativa. A conta nasce na hora, `kind: 'organization'`,
e quem criou vira `owner`. Nenhuma espera, nenhum documento.

**Verificação de domínio.** Opcional, feita quando o usuário quiser: a plataforma gera um
valor, o usuário publica um registro TXT no DNS do domínio da empresa, a plataforma
confere.

**A verificação destrava três capacidades:**

- **entrada automática por domínio** — qualquer e-mail `@dominio` entra sem convite;
- **selo de verificada**, com o domínio à vista;
- **contestação de handle** tomado por terceiro.

E serve de prova na recuperação de conta órfã (§5).

Todo o resto funciona sem verificação. Organização não verificada é plenamente utilizável
— apenas não pode fazer afirmações sobre si mesma que não provou.

## 7. Hierarquia

```
Plataforma (nível 0)   catálogo de provedores, templates, skills — não pertence a ninguém
   ╎
  Conta (PF ou PJ)     transversal: possui e isola
   └── Workspace (1)   nome, chave, descrição, schema de tags
         └── Projeto (2)   repositórios + espaço do task manager
```

Um projeto consome as integrações da **conta que possui o workspace onde ele está**. Mover
um workspace para outra conta troca, de uma vez, o conjunto de integrações disponível a
todos os seus projetos.

**Um projeto não compõe integrações de contas diferentes.** Se compusesse, responder "com
qual credencial isto foi feito?" deixaria de ser trivial — e essa pergunta é a base do
dossiê.

## 8. Riscos

| # | |
|---|---|
| R-1 | **Handle compartilhado entre PF e PJ** gera disputa de nome. Mitigado pela contestação por organização verificada (§6) |
| R-2 | **Account linking mal configurado cria usuários duplicados**, e duplicata em multi-tenant vira problema de acesso. Precisa estar ativo desde o primeiro dia (§1) |
| R-3 | **Convite por e-mail é vetor de phishing interno.** O aceite precisa exigir sessão autenticada e exibir claramente em qual conta se está entrando |
| R-4 | **Renomeação `workspace → projeto`** atravessa código, rotas, i18n, mocks e documentação. Feita pela metade, custa mais que feita de uma vez (P-5) |

## 9. Pendências

Registradas no [`ROADMAP.md`](../../ROADMAP.md), decisão própria cada uma:

- **P-1** — trilha de auditoria de concessões e vínculos.
- **P-3** — LGPD: retenção, exclusão e residência, com CPF e CNPJ no escopo.
- **P-6** — recuperação de organização órfã **não verificada**.
