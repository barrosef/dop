# Plataforma DOP — features e user stories

> **Status:** Rascunho para revisão do Dev · **Data:** 2026-08-30 (rev. 3 — fluxo
> dinâmico e cockpit painel-sobre-barra)
> **Base:** specs SP-0 (identidade, integrações, recursos), fluxo de trabalho,
> navegação rev. 2; ADRs 0001–0014
> **Fases:** conforme `ROADMAP.md` — **[F1]** constrói-se agora; **[F2]** modelado no
> schema desde já, construído na fase seguinte.

A ordem das features segue a dependência real: identidade → **recursos** (os projetos
consomem recursos; sem eles não há projeto) → hierarquia → cockpit. Organizações e
convites são [F2] e vêm depois na numeração, ainda que no schema existam desde o dia 1.

---

## 1. Sign up PF **[F1]**

- **US-1.1** Como dev, quero me cadastrar com e-mail e senha.
  - conta pessoal criada automaticamente (handle derivado do e-mail; colisão sufixa)
  - aterrissa no Primeiro uso (3 passos)
- **US-1.2** Como dev, quero me cadastrar com Google, GitHub ou LinkedIn em um clique.
  - mesmos efeitos da US-1.1; provedor vinculado ao perfil
- **US-1.3** Como dev, quero que entrar depois por outro provedor com o mesmo e-mail
  caia na mesma conta.
  - account linking ativo desde o dia 1; vínculos visíveis no perfil

## 2. Sign in **[F1]**

- **US-2.1** Como dev, quero entrar por qualquer método vinculado e cair **no último
  cockpit em que estava**, com a demanda que estava selecionada.
  - zero telas intermediárias; primeiro login cai no Primeiro uso
- **US-2.2** Como dev, quero que conta ativa, projeto e card selecionado sobrevivam ao
  logout/login e sejam compartilháveis por URL.
  - `/:conta/:workspace/:projeto?card=` restaura o estado exato

## 3. Recursos da conta **[F1 no núcleo]**

> Recurso = unidade de posse e compartilhamento (ADR-0013): integrações (git, task
> manager, **agente**), skills, workflows humano↔agente e fluxos git. Projetos só
> consomem — nada de credencial digitada em projeto.

- **US-3.1 [F1]** Como dev, quero conectar um provider **git** (GitHub, GitLab, GitLab
  self-hosted, Azure DevOps, Bitbucket) por OAuth, token ou chave SSH.
  - credencial só no SecretStore; repositórios ficam disponíveis para os projetos da conta
- **US-3.2 [F1]** Como dev, quero conectar um **task manager** (Jira, ClickUp, Redmine)
  para meus cards fluírem para os cockpits.
- **US-3.3 [F1]** Como dev, quero conectar um provider de **agente** (Claude, Codex,
  Google Code Assist) por OAuth da minha assinatura ou API key.
  - os modelos viram o cardápio do router; custo BYO medido igual (ADR-0011)
- **US-3.4 [F1]** Como dev, quero ver o estado das minhas integrações (`active`,
  `expired`, `error`) e ser avisado na caixa de atenção quando uma quebrar.
- **US-3.5 [F1]** Como dev, quero manter **fluxos git** na conta — criados por mim ou
  adotados do catálogo — versionados, com validação estrutural e simulação a seco.
  - declaram: taxonomia de branch por tipo de card, bases, direção, composição de release, políticas
- **US-3.6 [F1]** Como dev, quero manter **fluxos de trabalho** versionados — compostos
  de etapas tipadas (ADR-0014) — criando os meus ou adotando o default da plataforma.
  - validação estrutural na criação; aviso quando faltar etapa `spec`
- **US-3.6b [F1]** Como dev, quero que workspace, projeto e demanda **herdem** o fluxo do
  nível acima e possam sobrepor com um próprio — vendo sempre a origem do fluxo efetivo.
  - cadeia plataforma ◁ conta ◁ workspace ◁ projeto ◁ demanda; demanda congela a versão ao iniciar
- **US-3.6c [F2]** Como dev, quero **promover** um fluxo que criei numa demanda para o
  projeto, a workspace ou a conta.
- **US-3.6d [F2]** Como dev, quero manter **skills** como recursos versionados.
- **US-3.7 [F2]** Como dev, quero adotar um recurso do catálogo da plataforma como
  cópia versionada, vendo o diff quando o catálogo evoluir.

## 4. Contas organizacionais **[F2]**

- **US-4.1** Como dev, quero criar uma organização com nome e CNPJ e usá-la
  imediatamente.
  - autofill de razão social/endereço; criador vira `owner`; sem espera (ADR-0004)
- **US-4.2** Como owner, quero verificar o domínio por registro TXT para destravar
  entrada automática por e-mail do domínio, selo e disputa de handle.
- **US-4.3** Como dev, quero alternar entre conta pessoal e organizações num seletor
  único, trocando toda a árvore com um clique.
  - tudo o que se vê é da conta ativa; requisição sem conta ativa é inválida

## 5. Convites e acessos **[F2]**

- **US-5.1** Como owner/admin, quero convidar um dev por e-mail **compondo no convite**
  o papel e as concessões de **recursos**, para ele entrar com o acesso certo.
  - papéis: `owner`, `admin`, `developer`, `viewer`; concessão `use`/`manage` por recurso; sem defaults
  - expira em 14 dias; revogável pendente; reenvio invalida o anterior
- **US-5.2** Como convidado, quero aceitar pelo link — com cadastro no caminho se eu não
  existir — e cair na conta da organização.
  - aceite exige sessão autenticada e mostra claramente qual conta se está entrando
- **US-5.3** Como owner/admin, quero editar papel e concessões a qualquer tempo, e
  desvincular sem tocar no que é pessoal do membro.
  - invariante: a conta nunca fica sem `owner` ativo
- **US-5.4** Como developer, quero ver apenas os recursos que me foram concedidos ao
  configurar projetos.
  - revogar `use` não derruba projetos já configurados

## 6. Workspaces **[F1]**

- **US-6.1** Como dev, quero criar um workspace com nome, chave, descrição e tags — e
  nada mais.
- **US-6.2** Como dev, quero a árvore lateral com busca alcançando qualquer projeto em
  até 2 cliques.
- **US-6.3** Como dev, quero editar o workspace num painel deslizante, sem sair de onde
  estou.

## 7. Projetos **[F1]**

- **US-7.1** Como dev, quero criar um projeto escolhendo repositórios **das integrações
  da conta** — lista já autenticada, sem digitar credencial.
  - provider é do repositório: GitHub e GitLab convivem no mesmo projeto
  - recursos de contas diferentes não se misturam
- **US-7.2** Como dev, quero vincular o espaço do task manager e o projeto lá dentro.
  - tipos de card vêm do provider, dinâmicos
- **US-7.3** Como dev, quero **anexar recursos ao projeto**: um fluxo git [F1] — que a
  fila de merge, a verificação e a nomenclatura de branches passam a obedecer — e
  workflow/skills [F2] — que parametrizam os agentes.
- **US-7.4** Como dev, quero manter regras do projeto e consultar o conhecimento
  acumulado (índice, memórias) na configuração (ADR-0009).
- **US-7.5** Como dev, quero adicionar/remover repositórios e recursos depois, em
  painel deslizante, sem recriar o projeto.
- **US-7.6** Como dev, quero que o projeto tenha um **agente techlead** (ADR-0015),
  acionado quando houver demandas paralelas, que detecte transversais — dependências,
  sobreposição de arquivos, interferência de comportamento — planeje soluções e me
  **provoque decisões na caixa de atenção** com opções prontas.
  - decisão vira diretriz de coordenação (ex.: "demanda 1 cherry-pick da branch da 0 quando ela commitar")
  - **nenhuma demanda pausa por transversal detectada** — segue até onde dá e aplica a diretriz quando a condição se cumprir
  - diretrizes visíveis na Timeline e nas threads das demandas envolvidas

## 8. Cockpit / IDE **[F1]**

> Lei do cockpit (spec de navegação rev. 2): botão da barra abre **painel** sobrepondo a
> barra (que encolhe a ícones); o **centro** responde ao painel. Task header filtra tudo;
> Overview fica acima dele, fora da barra.

### Navegação
- **US-8.0.1** Como dev, quero selecionar um card na faixa e ver barra, painel e centro
  se restringirem à demanda; desselecionar volta ao agregado do projeto.
- **US-8.0.2** Como dev, quero a caixa de atenção global (🔔) dizendo onde sou
  necessário, cada item levando ao lugar da resolução — incluindo portões de fluxo
  pendentes.
- **US-8.0.3** Como dev, quero a paleta ⌘K para pular a qualquer projeto/demanda sem
  mouse.
- **US-8.0.4** Como dev, quero o **Overview** num botão acima do task header — visão do
  projeto inteiro, imune ao filtro de cards.
- **US-8.0.5** Como dev, quero clicar no chip do card e ver o card original do provider
  com seus artefatos.

### 8.1 Chat (painel: threads · centro: etapas do fluxo)
- **US-8.1.1** Como dev, quero conversar com o principal e com cada subagente em threads
  separadas, com fichas e achados (ADR-0010).
- **US-8.1.2** Como dev, quero o centro exibindo a **régua de etapas do fluxo efetivo**
  da demanda — qualquer fluxo, renderizado pelo tipo de cada etapa (ADR-0014).
  - documentos MD com viewer/fonte e edição; portões de aprovação visíveis
- **US-8.1.3** Como dev, quero a etapa de **validação humana** como checklist marcável
  item a item, gerada do plano de validação, com links — podendo reprovar um item e
  tratar com o agente no chat.
- **US-8.1.4** Como dev, quero a etapa de **finalização** com passos visíveis
  (commits/pushes → PRs → fila de merge → conflitos → dossiê) e estados por passo.

### 8.2 Repos (painel: árvore git · centro: conteúdo)
- **US-8.2.1** Como dev, quero a visão git completa: repos → branches → PRs/MRs →
  arquivos com status git, diffs arquivo a arquivo.
  - branches nomeadas conforme o fluxo git anexado
- **US-8.2.2** Como dev, quero a **fila de merge** por repositório — posição,
  re-verificação, sobreposições — e decidir conflitos escalados (ADR-0008).

### 8.3 Infra (painel: aplicações · bancos · serviços remotos)
- **US-8.3.1** Como dev, quero ver as aplicações da demanda com estado, logs em
  streaming e terminal — **no ambiente da aplicação, nunca na microVM do agente**.
- **US-8.3.2** Como dev, quero listar bancos e serviços remotos que o sistema usa, com
  estado e logs quando disponíveis.

### 8.4 QA (painel: grupos de qualidade · centro: painel do grupo)
- **US-8.4.1** Como dev, quero os grupos de qualidade do produto: aceitação, testes
  (aaa/e2e/integração), cobertura, relatórios Allure, histórico/flakiness.
- **US-8.4.2** Como dev, quero os grupos de qualidade de código: padrões & conformidade,
  duplicação, complexidade & dívida, dependências & vulnerabilidades.
  - alimentados por stack Sonar-like em container + achados de agentes

### 8.5 Arquitetura (painel: artefatos por task e tipo · centro: canvas/viewer)
- **US-8.5.1** Como dev, quero pedir análises e **diagramas arquiteturais e de fluxo**
  de uma feature ligada à task — "o fluxo do pagamento que envia e-mail, baixa estoque
  e passa pela fila" — produzidos por subagente (thread no Chat), renderizados em canvas
  interativo e guardados como artefatos da demanda.
- **US-8.5.2** Como dev, quero que uma **análise forense** (ex.: de um hotfix
  importante) renda um **parecer**: diagramas + documento técnico/executivo, agrupados
  na Arquitetura sob aquela task.
- **US-8.5.3** Como dev, quero navegar os artefatos arquiteturais **filtrados pelo task
  header** — a demanda selecionada mostra só os dela; sem seleção, todos do projeto,
  mais o mapa (índice ADR-0009).

### 8.6 Timeline (painel: filtros de evento · centro: linha do tempo)
- **US-8.6.1** Como dev, quero a linha do tempo da demanda — quem fez o quê, com qual
  credencial — filtrável por agentes, git, portões e custo (ADR-0006/0011/0012).

---

## Fora deste rascunho (registrado para não sumir)

- Sintaxe dos critérios executáveis dentro do artefato `spec` — P-8.
- Formato declarativo do **fluxo git** (o do fluxo de trabalho já está na spec) e os
  editores visuais de ambos.
- Credencial de organização (GitHub App etc.) — [F2], spec de integrações §4.
- Notificações fora da plataforma (e-mail/push) — projeções futuras da caixa de atenção.
