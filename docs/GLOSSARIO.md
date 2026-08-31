# Glossário — plataforma DOP

Vocabulário do projeto. Quando um termo aqui colide com o de um provedor externo, a
convenção de desambiguação está registrada.

| Termo | Significado |
|---|---|
| **Plataforma** | O nível 0. Detém recursos globais que não pertencem a ninguém: catálogo de provedores, templates, skills |
| **Conta** | A unidade de posse e de isolamento. Tem `kind`: `personal` (PF) ou `organization` (PJ). Possui integrações, workspaces e projetos |
| **Conta ativa** | A conta sob a qual o usuário está operando no momento, escolhida no seletor. Toda chamada à API carrega uma |
| **Usuário** | A identidade da pessoa. Existe uma vez na plataforma, independentemente de quantas contas acesse |
| **Vínculo** (*membership*) | A ligação entre um usuário e uma conta, portando um papel. O papel mora no vínculo, não na pessoa |
| **Concessão** | Autorização de um usuário sobre uma integração específica, com nível `use` ou `manage`. Ortogonal ao papel |
| **Workspace** | Nível 1. Agrupa projetos. Tem nome, chave, descrição e schema de tags |
| **Projeto** | Nível 2. Onde vivem repositórios e o espaço do task manager, consumidos das integrações da conta dona |
| **Recurso** | Unidade de posse e compartilhamento da conta: integração, skill, workflow humano↔agente ou fluxo git. Concessão `use`/`manage` por usuário |
| **Integração** | Recurso com credencial: vínculo da conta com provedor externo — git, task manager ou **agente** (Claude, Codex, …) |
| **Fluxo git** | Recurso que declara a governança git: taxonomia de branch por tipo de card, bases, promoção, políticas |
| **Fluxo de trabalho** | Recurso que compõe o ciclo da demanda em etapas tipadas, com artefatos e portões (ADR-0014). Herdável na cadeia plataforma ◁ conta ◁ workspace ◁ projeto ◁ demanda |
| **Etapa tipada** | Elemento do fluxo cujo tipo (contexto, spec, plano, implementação, teste, validação_humana, finalização, genérico) decide o renderizador da tela e o comportamento do agente |
| **Portão** | Ponto do fluxo onde a demanda para e espera decisão humana; vira item da caixa de atenção |
| **Fluxo efetivo** | O fluxo que vale para uma demanda após resolver a cadeia de herança; a versão congela quando a demanda inicia |
| **Techlead (orquestrador de projeto)** | Agente do projeto, acionado com demandas paralelas: detecta transversais, planeja e provoca decisões na caixa de atenção; nunca pausa demandas (ADR-0015) |
| **Diretriz de coordenação** | Decisão do dev sobre uma transversal, aplicada pelos agentes das demandas (ex.: cherry-pick condicionado, ordem na fila, partição de arquivos) |
| **dop-core** | Núcleo em Go: domínio, estado, transações e eventos. Um binário, quatro modos (`serve`, `worker`, `sched`, `launcher`) |
| **dop-api (BFF)** | Borda em Python: REST+SSE para o app, gRPC para CLI e sandbox, e o `AgentRuntime`. Não tem banco |
| **Outbox** | Tabela onde o evento é gravado na mesma transação do estado; um relay publica no broker — atomicidade sem 2PC |
| **Projeção** | Leitura derivada do log de eventos (dossiê, timeline, caixa de atenção, métricas). Nunca escreve a verdade |
| **Card** | Item de trabalho vindo do task manager. Tem tipo dinâmico, definido pelo provedor |
| **Demanda** | Um card em execução na plataforma: sandbox, threads, spec, eventos. Card é a origem; demanda é o trabalho |
| **Sandbox** | O ambiente isolado de uma demanda: microVM com agente(s), workspace e Docker interno. Fronteira de segurança |
| **Subagente** | Agente especialista lançado dentro da demanda, no mesmo sandbox, com ficha própria (propósito, ferramentas, modelo, orçamento) |
| **Thread** | Timeline de conversa com um agente da demanda. Uma por agente; consultável pelos irmãos |
| **Achado** | Resultado estruturado publicado por um agente ao concluir uma investigação. Vira evento, dossiê e memória |
| **Pacote de contexto** | A bagagem montada por demanda: spec + regras + índice dos repos envolvidos + memórias relevantes |
| **Crítico** | Instância independente que revisa diff × spec antes do humano. Modelo forte, contexto limpo |
| **Pacote de evidência** | O que acompanha o PR: aceitação, testes, parecer do crítico, links do trace |
| **Fila de merge** | Fila por repositório que reaplica cada PR sobre a main atual e re-verifica antes de mergear, um por vez |
| **Caixa de atenção** | Fila única, entre todas as demandas da conta ativa, dos itens que exigem decisão humana. Não é o chat: leva ao chat certo |

## Desambiguações obrigatórias

**"Workspace" é o conceito do DOP e só ele.** Os task managers também usam a palavra — o
ClickUp chama assim o seu tenant. O lado de lá chama-se **espaço do provedor**, ou é
sempre qualificado: *workspace do ClickUp*. A palavra nua nunca se refere ao provedor.

**"Projeto" no DOP é o nível 2.** Quando se falar de projeto no Jira, no Azure DevOps ou
no GCP, qualifique sempre: *projeto do Jira*, *projeto do GCP*.

## Renomeação em curso

O que a documentação e o código anteriores chamavam de **workspace** passou a chamar-se
**projeto**, e o nome *workspace* foi reaproveitado para o agrupador acima dele. Material
antigo pode usar o sentido antigo — ver P-5 no [`ROADMAP.md`](ROADMAP.md).
