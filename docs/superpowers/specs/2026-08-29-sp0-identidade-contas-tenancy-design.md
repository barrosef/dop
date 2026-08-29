# SP-0 — Identidade, contas e tenancy

> **Status:** Aprovado para revisão
> **Data:** 2026-08-29
> **Projeto:** plataforma DOP
> **Escopo:** quem é o usuário, o que é uma conta, como se possui e se isola, onde vivem as integrações, e a hierarquia conta → workspace → projeto
> **Não-escopo:** modelo de trabalho e etapas (SP-4), topologia de componentes (SP-1), modelo de domínio do card (SP-3), contrato e protocolos (SP-2), runtime e implantação (SP-5), integração com o Claude (SP-6)

## 0. Onde esta spec se encaixa

A reestruturação da plataforma DOP foi decomposta em sete subprojetos, porque decidir
detalhe de um antes de fixar a fronteira entre eles produz retrabalho:

| | Subprojeto | Decide |
|---|---|---|
| **SP-0** | **Identidade, contas e tenancy** | *esta spec* |
| SP-4 | Modelo de trabalho: specs e autonomia | O que a plataforma faz; onde o humano decide, aprova e dá contexto |
| SP-1 | Topologia de componentes e repositórios | Quais componentes existem e o papel de cada um |
| SP-3 | Modelo de domínio e persistência | Workspace, projeto, card, artefato, evento |
| SP-2 | Contrato e protocolos | Fonte da verdade do contrato; REST, gRPC e streaming |
| SP-5 | Runtime, ambiente e IDE | Terminal, execução paralela, implantação |
| SP-6 | Integração com o Claude | Agente, chat como canal de comando |

SP-0 é o mais a montante: todo o resto opera dentro de uma conta. O modelo de domínio
ganha tenant em toda entidade, a borda autentica toda chamada, e os segredos passam a
ser por conta.

## 1. Princípio transversal — infraestrutura atrás de portas

**Regra forte, válida para toda a plataforma e não apenas para esta spec.**

Toda infraestrutura é alcançada exclusivamente por uma **porta definida pelo domínio**,
com adaptadores específicos de fornecedor injetados num *composition root* e escolhidos
por configuração. O domínio não importa SDK de fornecedor. Arquitetura hexagonal, com o
D e o I do SOLID como critério de aceite: o domínio depende de abstrações, e as
abstrações são estreitas.

O alvo concreto: a plataforma roda em **GCP Cloud Run** e em **cluster k3s/Rancher ou
OKD** sem uma linha de mudança no domínio — só fiação diferente.

### 1.1 Duas famílias de portas

Elas se parecem e têm ciclos de vida opostos. Confundi-las é o erro típico deste desenho.

| | **Portas de infraestrutura** | **Portas de provedor de domínio** |
|---|---|---|
| Exemplos | `SecretStore`, `IdentityProvider`, `ObjectStore`, repositórios, `EventBus` | `GitProvider`, `TaskManagerProvider`, `RuntimeOrchestrator` |
| Quem escolhe | O ambiente de implantação | A configuração da conta |
| Quando | Uma vez, no boot | A cada requisição |
| Quantos ativos | Um | Vários simultâneos |

A segunda família precisa suportar coexistência: uma mesma workspace tem repositório no
GitHub e no GitLab ao mesmo tempo.

### 1.2 O que torna a regra real

Três disciplinas, sem as quais "hexagonal" vira nome de pasta:

1. **Dois adaptadores por porta desde o primeiro dia.** O adaptador local não é "para
   depois" — é a prova de que a porta está certa. Porta com um adaptador só é palpite, e
   sai no formato do fornecedor que a inspirou.
2. **Um conjunto de testes de contrato por porta**, que todo adaptador passa. É o que
   garante substituibilidade de fato.
3. **Porta estreita, em linguagem do domínio.** O domínio pede `SecretStore.get(ref)`,
   não `accessSecretVersion`.

### 1.3 Vazamentos conhecidos e como tratá-los

Decididos agora para não doerem depois:

- **Versionamento de segredo fica fora da porta.** O Secret Manager tem versões e IAM por
  segredo; o Secret do k8s é plano e sem histórico. Se um dia for necessário, entra como
  capacidade opcional que o domínio nunca assume.
- **Secret do k8s montado como volume é eventualmente consistente** — o kubelet sincroniza
  em torno de um minuto. Como a porta promete leitura-após-escrita, o adaptador k8s lê
  pela API, não pelo volume.
- **Claims de Firebase não cruzam a fronteira.** O `IdentityProvider` devolve um principal
  normalizado — `subject`, `email`, `emailVerified`, provedores vinculados. É o que
  permite trocar por Keycloak, Zitadel ou Ory sem tocar no domínio.

## 2. Identidade e posse

Três entidades, e só três.

**`User`** — a identidade da pessoa. Identificador do provedor de identidade, e-mail,
nome, avatar e provedores vinculados. A autenticação usa **Firebase Authentication** como
primeiro adaptador do `IdentityProvider`, com quatro métodos: e-mail e senha, Google,
GitHub e LinkedIn. **Account linking está habilitado**: o mesmo e-mail chegando por dois
provedores resolve para o mesmo `User`, evitando duplicatas.

**`Account`** — a unidade de posse e de isolamento. Campos: `kind: 'personal' |
'organization'`, um *handle* único, e nome de exibição. Contas de organização carregam
ainda CNPJ, razão social, endereço e o estado da verificação de domínio.

**`Membership`** — o vínculo `User × Account` com um papel. É onde mora todo o controle
de acesso.

No cadastro, a conta pessoal nasce junto com o usuário: `kind: 'personal'`, handle
derivado do e-mail, uma membership `owner`.

**Toda chamada à API carrega uma conta ativa**, determinada por um **seletor de conta**
na interface. É ela que decide onde uma integração criada vai parar e o que o usuário
enxerga. Requisição sem conta ativa é inválida.

### 2.1 A forma da posse

```
Plataforma
├── Conta PF 01  (kind=personal, raiz)  ─┐
├── Conta PF 02  (kind=personal, raiz)  ─┼─ existem por si só
└── Conta PJ     (kind=organization)     │
      ├── vínculo → PF 01   papel: owner │  o vínculo é uma linha,
      └── vínculo → PF 02   papel: developer ┘  não cópia nem aninhamento
```

O papel mora **na linha**, não na pessoa: a mesma PF é `owner` numa PJ e `developer` em
outra sem que nada mude nela.

**Duas consequências de "vínculo apenas":**

- Workspaces, projetos e integrações da PF **não passam a ser** da PJ, nem o contrário.
  Cada conta possui o seu; o vínculo dá acesso ao que é da PJ e nada mais.
- Desvincular uma PF da PJ tira o acesso ao que é da PJ e **não toca em nada** do que é
  dela.

O seletor lista a conta pessoal mais toda PJ em que o usuário tenha vínculo.

**PF e PJ dividem o mesmo espaço de nomes de handle.** Se alguém toma `acme` como conta
pessoal, a organização Acme não pode usá-lo. É o preço de ambas serem endereçáveis do
mesmo jeito, e é o comportamento do GitHub.

## 3. Hierarquia

```
Plataforma (nível 0)   catálogo de provedores, templates, skills — não pertence a ninguém
   ╎
  Conta (PF ou PJ)     transversal: possui e isola
   └── Workspace (1)   nome, chave, descrição, schema de tags
         └── Projeto (2)   repositórios + espaço do task manager,
                           consumidos das integrações da conta dona
```

Um projeto consome as integrações da **conta que possui o workspace onde ele está**.
Mover um workspace para outra conta troca, de uma vez, o conjunto de integrações
disponível a todos os seus projetos. Um projeto **não** compõe integrações de contas
diferentes — se compusesse, responder "com qual credencial isto foi feito?" deixaria de
ser trivial, e essa pergunta é a base do dossiê.

### 3.1 Renomeação

O que hoje se chama **workspace** passa a se chamar **projeto**, e o nome *workspace* é
reaproveitado para o agrupador acima dele. É o tipo de mudança que, feita pela metade,
deixa o time falando duas línguas por meses; a execução completa vira tarefa do plano.

### 3.2 Colisão terminológica com os task managers

Os task managers também têm "workspace" — o ClickUp chama assim o seu tenant. Com o DOP
passando a ter *workspace* como conceito próprio e diferente, a palavra nua fica ambígua
em toda conversa e em toda tela.

**Convenção:** o lado do provedor chama-se **espaço do provedor**, ou é sempre qualificado
(*workspace do ClickUp*). A palavra "workspace" sozinha refere-se apenas ao conceito do
DOP.

## 4. Integrações no nível da conta

Integrações deixam de ser configuradas dentro do que hoje é workspace e sobem para a
conta. O projeto passa a **consumir** o que já está integrado.

**A entidade `Integration`:**

| Campo | |
|---|---|
| `accountId` | a conta dona — é o que decide compartilhamento |
| `category` | `git` ou `task_manager` |
| `provider` | `github`, `gitlab`, `gitlab_self_hosted`, `azure_devops`, `bitbucket` / `jira`, `clickup`, `redmine` |
| `baseUrl` | para self-hosted |
| `authMethod` | `oauth_app`, `oauth_user`, `token`, `ssh_key` |
| `credentialRef` | **referência lógica opaca** ao segredo — nunca o segredo |
| `connectedByUserId` | quem estabeleceu |
| `status` | `active`, `expired`, `revoked`, `error` |

### 4.1 Onde a credencial vive

Atrás da porta `SecretStore`. O `credentialRef` é uma **referência lógica** que só o
adaptador resolve: em GCP vira caminho no Secret Manager; em k3s/OKD vira nome de Secret
no namespace da conta. O domínio de integrações nunca sabe qual. O banco guarda **apenas
a referência** — nenhum token, nenhuma chave privada, em nenhuma hipótese.

### 4.2 Compartilhamento

**Integração de conta PF nunca é usada numa PJ e nunca é vista por outros membros dela.
Somente integração de conta PJ é compartilhável.**

### 4.3 O titular da credencial

Um token OAuth de usuário pertence à *pessoa*. Quando ela sai da empresa, revoga o acesso
ou troca a senha, a integração morre — e leva junto todos os projetos da PJ que dependiam
dela.

**Numa conta PJ, usa-se credencial de organização:** GitHub App instalado na organização,
*group access token* no GitLab, service principal no Azure DevOps. Sobrevive a demissões.
Token pessoal é permitido como saída, mas a interface exibe de quem ele depende, para que
o risco seja visível em vez de descoberto no dia em que quebra.

Numa conta PF, qualquer método serve — a pessoa é a conta.

### 4.4 Autoria no repositório

Com credencial de organização, o DOP age como a instalação do App, e o histórico do
repositório deixaria de dizer quem pediu a mudança — perdendo justamente a
rastreabilidade que o dossiê promete.

**Decisão:** o push e a abertura do PR usam a credencial da organização; **cada commit
leva `author` com nome e e-mail do dev que conduziu o card**, e o corpo do PR identifica
quem pediu. Robustez da credencial de organização com rastreabilidade humana preservada.

### 4.5 Como o projeto consome

O projeto guarda **referências**, jamais credenciais: para cada repositório, a integração
de origem e o identificador do repositório nela; para o task manager, a integração, o
espaço do provedor e o projeto lá dentro. Configurar um projeto é escolher de uma lista já
autenticada.

## 5. Papéis e concessões

Dois eixos independentes.

**Papel** — o que a pessoa pode fazer *na conta*. Um por `Membership`.

| Papel | |
|---|---|
| `owner` | Controle total, incluindo faturamento, transferência de posse e exclusão da conta. Numa conta PF é o único vínculo existente |
| `admin` | Gere membros, integrações e workspaces. Tudo menos faturamento e exclusão |
| `developer` | Trabalha nos cards: executa, conversa com o Claude, abre PR. Não gere membros nem cria integrações |
| `viewer` | Só leitura — acompanhar cards, ver o dossiê. Serve para PO e gestor |

Ficaram deliberadamente de fora um `maintainer` intermediário e um papel separado de
faturamento. Papel é um campo na membership: acrescentar depois não exige migração.

**Concessão de integração** — por usuário, por integração, com nível **`use`** (pode
escolher aquela integração ao configurar projetos) ou **`manage`** (pode editar,
reconectar e revogar). Ortogonal ao papel.

`owner` e `admin` têm `manage` implícito em tudo — sem isso surge o cenário em que ninguém
consegue consertar uma integração quebrada.

**Não há default.** No momento do vínculo, quem convida compõe papel e concessões
livremente: tudo, nada ou uma seleção. Depois, adiciona, remove e altera a qualquer tempo.

**`use` controla configuração, não execução.** Revogar o `use` de alguém não derruba os
projetos já configurados — a credencial é da conta, não da pessoa. O que se perde é a
capacidade de escolher aquela integração ao montar projetos novos.

## 6. Ciclo de vida da organização

**Criação.** O usuário informa nome e CNPJ; o CNPJ preenche razão social e endereço
automaticamente e já confirma que a empresa existe e está ativa. A conta nasce na hora,
`kind: 'organization'`, e quem criou vira `owner`. Nenhuma espera, nenhum documento.

**Verificação de domínio.** Opcional, feita quando o usuário quiser: a plataforma gera um
valor, o usuário publica um registro TXT no DNS do domínio da empresa, a plataforma
confere. Prova controle organizacional sem papelada — é o que GitHub e GCP fazem.

**O que a verificação destrava:**

- **Entrada automática por domínio** — qualquer e-mail `@dominio` entra sem convite
  individual.
- **Selo de verificada**, com o domínio à vista.
- **Contestação de handle** — só organização verificada pode disputar um identificador
  tomado por terceiro.

Todo o resto funciona sem verificação: integrações, convites individuais, workspaces,
projetos, execução. Uma organização não verificada é plenamente utilizável; ela apenas não
pode fazer afirmações sobre si mesma que não provou.

> **Nota de proveniência.** O requisito original pedia validar CPF do titular ou
> procuração, citando GitHub e GCP como referência de fluidez. Verificado: **nenhum dos
> dois valida titularidade**. O GitHub cria organização instantaneamente sem verificação
> alguma; o GCP exige domínio verificado por DNS para criar o nó de organização. A
> verificação de domínio entrega a validação pretendida sem o atrito que o requisito
> pedia para evitar.

## 7. Fases

**Modelo completo desde o primeiro dia, construção parcial.**

**Nasce no schema agora, mesmo sem tela:** `Account` com `kind`, `Membership` com papel,
`Integration` com `accountId`, e a tabela de concessões. Toda entidade de domínio carrega
conta, workspace e projeto desde a primeira migração. A borda autentica toda chamada e
resolve conta ativa desde a primeira rota.

**Constrói-se agora:** autenticação pelos quatro métodos, conta pessoal automática no
cadastro, integrações pessoais com o `SecretStore` já atrás da porta e com os dois
adaptadores, e a hierarquia workspace → projeto.

**Fica para a fase seguinte:** criação de organização, autofill por CNPJ, convite e vínculo
de membros, edição de papéis e concessões, verificação de domínio, credencial de
organização.

A fase 2 entra **sem migração** — é o que justifica modelar tudo agora. E a fase 1 já
exercita o multi-tenant de verdade, porque toda consulta filtra por conta desde o início;
a conta simplesmente é sempre pessoal.

## 8. Consequências e riscos

| # | |
|---|---|
| R-1 | **Multi-tenant é mudança de classe de produto.** A documentação anterior fixava monousuário sem RBAC, e listava multiusuário como fora de escopo. Isto substitui aquela decisão |
| R-2 | **Cloud Run e sessão longa não se dão bem.** Cloud Run é escalonado por requisição, com escala a zero e sem afinidade de instância; sessão de terminal é estado longo preso a um processo. A leitura provável é separar **plano de controle** (auth, contas, integrações — roda nos dois) de **plano de execução** (terminal, runtime, streaming longo — quer cluster). Decisão pertence a SP-5, mas o risco nasce aqui |
| R-3 | **Custo da renomeação** *workspace → projeto* em código, rotas, internacionalização, mocks e documentação. Feita pela metade, custa mais do que feita de uma vez |
| R-4 | **Handle compartilhado entre PF e PJ** gera disputa de nome. Mitigado pela contestação por organização verificada |
| R-5 | **Credencial de organização é ponto único de falha.** Se o App é desinstalado ou o token revogado, todos os projetos daquela conta param. Exige monitoramento de `status` e alerta ao `owner` |
| R-6 | **Account linking mal configurado cria usuários duplicados**, e duplicata em sistema multi-tenant vira problema de acesso. Precisa estar habilitado desde o primeiro dia |

## 9. Dependências deixadas para outras specs

- **SP-5** — plano de controle × plano de execução; adaptadores de runtime; terminal.
- **SP-3** — como conta, workspace e projeto aparecem em cada agregado; persistência.
- **SP-2** — como a conta ativa trafega no contrato REST e gRPC.
- **SP-1** — em quais componentes o `IdentityProvider` e o `SecretStore` são fiados.
