# Plataforma DOP — features e user stories

> **Status:** Rascunho para revisão do Dev · **Data:** 2026-08-30 (rev. 2 — recursos
> promovidos a feature de base, ADR-0013)
> **Base:** specs SP-0 (identidade, integrações, recursos), ADRs 0001–0013, spec de
> navegação e cockpit (protótipo aprovado)
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
- **US-3.6 [F2]** Como dev, quero manter **skills** e **workflows humano↔agente** como
  recursos versionados.
  - o formato do workflow depende do SP-4 núcleo (P-8/ciclo da demanda)
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

## 8. Cockpit / IDE **[F1]**

### Navegação
- **US-8.0.1** Como dev, quero selecionar um card na faixa e ver todas as seções se
  restringirem à demanda; desselecionar volta ao agregado do projeto.
- **US-8.0.2** Como dev, quero a caixa de atenção global (🔔) dizendo **onde sou
  necessário** entre todas as demandas da conta, cada item levando ao lugar da
  resolução.
  - só entra o que exige decisão humana (spec de conversação §3)
- **US-8.0.3** Como dev, quero a paleta ⌘K para pular a qualquer projeto/demanda e
  disparar ações sem mouse.

### 8.1 Overview
- **US-8.1.1** Como dev, quero KPIs do escopo (cards, threads bloqueadas, fila de
  merge, custo) e a atividade recente dos agentes numa olhada.

### 8.2 Chat
- **US-8.2.1** Como dev, quero conversar com o agente principal numa thread própria e
  ver as threads dos subagentes separadas, sem misturar timelines (ADR-0010).
- **US-8.2.2** Como dev, quero lançar um subagente com propósito e ferramentas (MCPs e
  skills concedidos), acompanhando a ficha dele — inclusive o modelo, vindo das
  integrações de agente da conta.
- **US-8.2.3** Como dev, quero que conclusões virem **achados** visíveis, reutilizados
  pelos irmãos e gravados no dossiê.

### 8.3 QA
- **US-8.3.1** Como dev, quero resultados de AAA/e2e e dos critérios de aceitação por
  demanda e por repo, com Allure embutido.

### 8.4 Código & entrega
- **US-8.4.1** Como dev, quero navegar repos → branches → PRs → diffs no escopo atual.
  - branches nomeadas conforme o fluxo git anexado ao projeto
- **US-8.4.2** Como dev, quero a fila de merge por repositório — posição, estado,
  sobreposições — e decidir conflitos escalados (ADR-0008).

### 8.5 Runtime
- **US-8.5.1** Como dev, quero os serviços do sandbox da demanda, logs em streaming por
  serviço, e um terminal no ambiente.

### 8.6 Spec & docs
- **US-8.6.1** Como dev, quero ler a spec da demanda com seus critérios e **aprovar ou
  pedir ajustes** dali (o pedido abre o chat).
  - independe da sintaxe final dos critérios (P-8)

### 8.7 Timeline
- **US-8.7.1** Como dev, quero a linha do tempo de eventos da demanda — quem fez o quê,
  com qual credencial — e custo/cache (ADR-0006/0011/0012).

### 8.8 Arquitetura
- **US-8.8.1** Como dev, quero o mapa do projeto (índice renderizado) e os achados
  arquiteturais acumulados.
- **US-8.8.2** Como dev, quero pedir análise arquitetural a um subagente daqui, com a
  thread aparecendo no Chat.

---

## Fora deste rascunho (registrado para não sumir)

- Ciclo de vida completo da demanda — criar/iniciar/portões — depende do SP-4 núcleo.
- Editor/formato declarativo de fluxo git e workflow — spec própria após o SP-4 núcleo.
- Credencial de organização (GitHub App etc.) — [F2], spec de integrações §4.
- Notificações fora da plataforma (e-mail/push) — projeções futuras da caixa de atenção.
