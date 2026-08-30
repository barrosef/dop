# Plataforma DOP — features e user stories

> **Status:** Rascunho para revisão do Dev · **Data:** 2026-08-29
> **Base:** specs SP-0, ADRs 0001–0012, spec de navegação e cockpit (protótipo aprovado)
> **Fases:** conforme o faseamento do `ROADMAP.md` — **[F1]** constrói-se agora;
> **[F2]** modelado no schema desde já, construído na fase seguinte.

Formato: cada story em uma linha, com critérios de aceite enxutos. Detalhe fino de tela
pertence ao protótipo; detalhe de regra pertence às specs citadas.

---

## 1. Sign up PF **[F1]**

- **US-1.1** Como dev, quero me cadastrar com e-mail e senha para usar a plataforma sem
  depender de terceiros.
  - conta pessoal criada automaticamente no cadastro (handle derivado do e-mail; colisão sufixa)
  - aterrissa no Primeiro uso (3 passos)
- **US-1.2** Como dev, quero me cadastrar com Google, GitHub ou LinkedIn para entrar em
  um clique.
  - mesmos efeitos da US-1.1; provedor fica vinculado ao perfil
- **US-1.3** Como dev, quero que entrar depois por outro provedor com o mesmo e-mail
  caia na mesma conta, para nunca ter usuário duplicado.
  - account linking ativo desde o dia 1 (spec de identidade §1); vínculo visível no perfil

## 2. Sign in **[F1]**

- **US-2.1** Como dev, quero entrar por qualquer método vinculado e cair **no último
  cockpit em que estava**, com a demanda que estava selecionada.
  - zero telas intermediárias; primeiro login cai no Primeiro uso
- **US-2.2** Como dev, quero que minha conta ativa, projeto e card selecionado
  sobrevivam ao logout/login e sejam compartilháveis por URL.
  - URL profunda `/:conta/:workspace/:projeto?card=` restaura o estado exato

## 3. Contas organizacionais **[F2]**

- **US-3.1** Como dev, quero criar uma organização informando nome e CNPJ e começar a
  usá-la imediatamente.
  - autofill de razão social/endereço pelo CNPJ; criador vira `owner`; sem espera nem documento (ADR-0004)
- **US-3.2** Como owner, quero verificar o domínio da empresa por registro TXT para
  destravar entrada automática por e-mail do domínio, selo e disputa de handle.
- **US-3.3** Como dev, quero alternar entre minha conta pessoal e as organizações num
  seletor único, trocando toda a árvore com um clique.
  - integrações/workspaces/projetos exibidos são sempre os da conta ativa; requisição sem conta ativa é inválida

## 4. Convites e acessos **[F2]**

- **US-4.1** Como owner/admin, quero convidar um dev por e-mail **compondo no convite** o
  papel e as concessões de **recursos** (integrações, skills, workflows, fluxos git —
  ADR-0013), para que ele já entre com o acesso certo.
  - papéis pré-definidos: `owner`, `admin`, `developer`, `viewer`; concessões `use`/`manage` por recurso; sem defaults
  - convite expira em 14 dias; revogável enquanto pendente; reenvio invalida o anterior
- **US-4.2** Como convidado, quero aceitar pelo link — com cadastro no caminho se eu
  ainda não existir — e cair direto na conta da organização.
  - aceite exige sessão autenticada e mostra claramente em qual conta se está entrando (risco R-3 da spec)
- **US-4.3** Como owner/admin, quero editar papel e concessões de qualquer membro a
  qualquer tempo, e desvincular sem tocar no que é pessoal dele.
  - invariante: a conta nunca fica sem `owner` ativo — operação que violaria é recusada com mensagem
- **US-4.4** Como developer, quero ver apenas os recursos que me foram concedidos ao
  configurar projetos.
  - revogar `use` não derruba projetos já configurados (credencial é da conta)

## 5. Workspaces **[F1]**

- **US-5.1** Como dev, quero criar um workspace com nome, chave, descrição e tags — e
  nada mais — para agrupar projetos sem burocracia.
- **US-5.2** Como dev, quero ver workspaces e projetos numa árvore lateral com busca,
  e alcançar qualquer projeto em no máximo 2 cliques.
- **US-5.3** Como dev, quero editar o workspace num painel deslizante sem sair do
  cockpit onde estou.

## 6. Projetos **[F1]**

- **US-6.1** Como dev, quero criar um projeto escolhendo repositórios **das integrações
  da conta** — lista já autenticada, sem digitar credencial.
  - provider é do repositório: GitHub e GitLab podem conviver no mesmo projeto
  - repositórios de contas diferentes não se misturam (spec de identidade §7)
- **US-6.2** Como dev, quero vincular o espaço do task manager (Jira/ClickUp/…) e o
  projeto lá dentro, para os cards fluírem para o cockpit.
  - tipos de card vêm do provider, dinâmicos
- **US-6.3** Como dev, quero manter regras do projeto (convenções que os agentes
  obedecem) e ver o conhecimento acumulado (índice, memórias) na configuração.
  - camadas da ADR-0009; regras editáveis; memória consultável
- **US-6.4** Como dev, quero adicionar/remover repositórios depois, num painel
  deslizante, sem recriar o projeto.

## 7. Cockpit / IDE **[F1, seções marcadas]**

### Navegação do cockpit
- **US-7.0.1** Como dev, quero selecionar um card na faixa e ver todas as seções se
  restringirem àquela demanda; desselecionar volta ao agregado do projeto.
- **US-7.0.2** Como dev, quero a caixa de atenção global (🔔) me dizendo **onde sou
  necessário** entre todas as demandas da conta, com cada item me levando ao lugar da
  resolução.
  - tipos de item conforme spec de conversação §3; só entra o que exige decisão humana
- **US-7.0.3** Como dev, quero a paleta ⌘K para pular a qualquer projeto/demanda e
  disparar ações sem tocar o mouse.

### 7.1 Overview
- **US-7.1.1** Como dev, quero KPIs do escopo (cards, threads bloqueadas, fila de merge,
  custo) e a atividade recente dos agentes numa olhada.

### 7.2 Chat
- **US-7.2.1** Como dev, quero conversar com o agente principal da demanda numa thread
  própria, e ver as threads dos subagentes separadas, sem misturar timelines (ADR-0010).
- **US-7.2.2** Como dev, quero lançar um subagente com propósito e ferramentas (MCPs da
  workspace), e acompanhar a ficha dele na thread.
- **US-7.2.3** Como dev, quero que conclusões virem **achados** visíveis, reutilizados
  pelos agentes irmãos e gravados no dossiê.

### 7.3 QA
- **US-7.3.1** Como dev, quero resultados de AAA/e2e e dos critérios de aceitação por
  demanda e por repo, com o Allure embutido.

### 7.4 Código & entrega
- **US-7.4.1** Como dev, quero navegar repos → branches → PRs → diffs no escopo atual.
- **US-7.4.2** Como dev, quero ver a fila de merge por repositório — posição, estado,
  sobreposições detectadas — e decidir conflitos escalados (ADR-0008).

### 7.5 Runtime
- **US-7.5.1** Como dev, quero ver os serviços do sandbox da demanda, logs em streaming
  por serviço, e abrir um terminal no ambiente.

### 7.6 Spec & docs
- **US-7.6.1** Como dev, quero ler a spec da demanda com seus critérios e **aprovar ou
  pedir ajustes** dali mesmo (o pedido de ajuste abre o chat).
  - formato dos critérios: P-8 (SP-4 núcleo) — a story não depende da sintaxe final

### 7.7 Timeline
- **US-7.7.1** Como dev, quero a linha do tempo de eventos da demanda — quem fez o quê,
  com qual credencial — e o custo/cache dela (ADR-0006/0011).

### 7.8 Arquitetura
- **US-7.8.1** Como dev, quero o mapa do projeto (índice da base de conhecimento
  renderizado) e os achados arquiteturais acumulados.
- **US-7.8.2** Como dev, quero pedir uma análise arquitetural a um subagente a partir
  desta seção, com a thread aparecendo no Chat.

## 8. Recursos da conta

- **US-8.1 [F1]** Como dev, quero conectar um **provider de agente** (Claude, Codex,
  Google Code Assist) por OAuth da minha assinatura ou API key, para os agentes das
  minhas demandas rodarem com a minha credencial.
  - credencial via SecretStore; modelos aparecem como cardápio do router; medição de custo inalterada
- **US-8.2 [F1]** Como dev, quero anexar um **fluxo git** ao projeto — adotado do
  catálogo ou criado na conta — para a nomenclatura de branches, a promoção e a fila de
  merge obedecerem à governança declarada.
  - exemplo de referência: trunk + release com `epic/`/`feat/`/`bug/`/`hotfix` e tipo de card determinando prefixo e fluxo
- **US-8.3 [F2]** Como owner/admin de PJ, quero compartilhar skills, workflows e fluxos
  git com membros, pelas mesmas concessões das integrações.
- **US-8.4 [F2]** Como dev, quero adotar um recurso do catálogo da plataforma como cópia
  versionada da minha conta, e ver o diff quando o catálogo evoluir.

---

## Fora deste rascunho (registrado para não sumir)

- Integrações git/task manager da conta (conectar provider, credencial de organização)
  — pré-requisito das US-6.x; stories na spec de integrações, telas no Primeiro uso e
  no painel da conta.
- Editor/formato declarativo do fluxo git e do workflow — spec própria quando o SP-4
  núcleo fixar o ciclo da demanda.
- Ciclo de vida completo da demanda (criar/iniciar/portões) — depende do SP-4 núcleo.
- Notificações fora da plataforma (e-mail/push) — projeções futuras da caixa de atenção.
