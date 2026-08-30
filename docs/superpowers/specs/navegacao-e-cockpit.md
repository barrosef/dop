# Navegação e cockpit

> **Status:** Aprovada (rev. 2 — painel-sobre-barra, 2026-08-30) · **Projeto:** plataforma DOP
>
> **Responde:** o padrão de navegação da plataforma e a anatomia do cockpit.
> **Base:** ADR-0014 (fluxo dinâmico), ADR-0010 (threads), ADR-0006 (eventos).
> O protótipo clicável de 2026-08-29 valida o chrome global e os escopos; a anatomia
> interna do cockpit desta revisão (painel-sobre-barra) o substitui e será prototipada
> na próxima iteração visual.

## 1. Princípios

- **Zero telas até o trabalho.** Login cai no último cockpit; projeto a 1 clique,
  demanda a 1 clique, workspace a 2. Configuração é painel deslizante, nunca página.
- **A lei do cockpit: painel é "o quê", centro é "o conteúdo".** Toda função — atual ou
  futura — é um par painel+centro no mesmo padrão (§3). Função nova não toca o chrome.

## 2. Chrome global

Header fino (logo, seletor de conta ativa, breadcrumb, caixa de atenção 🔔 global, ⌘K);
árvore lateral workspaces→projetos com busca; painéis deslizantes de configuração.
Inalterado desde a rev. 1. Fora do cockpit só existem Auth e Primeiro uso.

## 3. Anatomia do cockpit

```
┌───────────────────────────────────────────────────────────────┐
│  [Overview]                            ← acima do task header,│
│  task header: faixa de cards (filtra tudo abaixo)   fora dele │
├────┬─────────────────┬────────────────────────────────────────┤
│ 💬 │                 │                                        │
│ 📁 │  PAINEL         │   CENTRO                               │
│ 🖥 │  sobrepõe a     │   acionado pelas opções do painel      │
│ ✓  │  barra; barra   │   (no Chat: as etapas do fluxo)        │
│ 🏛 │  encolhe p/     │                                        │
│ ⏱ │  ícones         │                                        │
└────┴─────────────────┴────────────────────────────────────────┘
```

- **Padrão de navegação (o padrão VS Code):** clicar num botão da barra abre o
  **painel** sobrepondo a barra, que encolhe a ícones para trocar de função; o
  **centro** responde à seleção no painel. Painel colapsável; larguras persistidas por
  função.
- **Task header** (faixa de cards com duplo status, filtrável): a seleção define o
  escopo de barra, painel e centro. Clicar no chip do card abre o detalhe do card do
  provider (card original + artefatos).
- **Overview fica acima do task header, fora da barra** — ele não responde ao filtro de
  cards, e a posição diz isso. Na v1 é um botão que toma o centro; a forma final será
  explorada depois (P-10). Um item já definido do Overview: **Arquitetura do projeto** —
  análises gerais geradas por solicitação do dev a partir de código-fonte, documentos,
  repositórios e recursos de infraestrutura, para gerar conhecimento e identificar
  stacks, integrações e pontos fortes/fracos, **propondo melhorias** em diagramas e
  gráficos (ex.: "100 integrações, 90 sem resiliência" — diagrama do fluxo sem
  resiliência + gráfico do índice). Distingue-se da Arquitetura da barra: a da barra é
  por task; a do Overview é do projeto inteiro, imune ao filtro.
- **Escopos:** projeto (nenhum card) e demanda (card selecionado). URL profunda
  `/:conta/:workspace/:projeto?card=` preservada.

## 4. As funções da barra

| Função | Painel | Centro |
|---|---|---|
| **Chat** | Threads da demanda: `#principal` + subagentes, fichas, achados, lançar subagente (ADR-0010) | **Régua de etapas do fluxo efetivo** (ADR-0014), em abas — artefatos, portões e renderizador por tipo de etapa |
| **Repos** | Árvore git completa: repos → branches → PRs/MRs → arquivos (modificados, ignorados, gitStatus) → **fila de merge** (ADR-0008) | Diff, arquivo, detalhe do PR com pacote de evidência, estado da fila |
| **Infra** | Três grupos: **aplicações** (pods/containers da demanda), **bancos**, **serviços remotos** — com estado | Logs em streaming, terminal, detalhe do recurso. **Acessa o ambiente da aplicação, nunca a microVM do agente** |
| **QA** | Grupos de qualidade: Aceitação (critérios da spec) · Testes (aaa/e2e/integração) · Cobertura · Relatórios Allure · Histórico/flakiness · **Padrões & conformidade · Duplicação · Complexidade & dívida · Dependências & vulnerabilidades** (stack Sonar-like em container) | Painel do grupo selecionado |
| **Arquitetura** | **Artefatos arquiteturais das demandas**, agrupados por task e por tipo — diagramas (arquiteturais, de fluxo/operacionais), documentos técnicos, pareceres/relatórios executivos — mais o mapa do projeto (índice ADR-0009) no escopo de projeto | Canvas interativo para diagramas (ex.: Claude Design), viewer para documentos. **Ligada às tasks e filtrada pelo task header**: no escopo de demanda, só os artefatos daquela task |
| **Timeline** | Filtros/agrupamentos de evento: agentes, git, portões, custo | A linha do tempo (projeção do log — ADR-0006): quem fez o quê, com qual credencial; custo e cache (ADR-0011/0012). É onde auditoria e replay ficam visíveis |

**Divisão QA × Arquitetura: QA mede, Arquitetura explica.** Todo índice — de produto ou
de código — é QA; Arquitetura é **produto do trabalho**: seus artefatos nascem de
solicitações do dev nas demandas (pedir um diagrama de integração de uma feature, uma
análise forense de um hotfix que rende parecer com diagramas e documento técnico) —
subagentes com thread no Chat (ADR-0010), resultado gravado como artefato da demanda e
na memória do projeto (ADR-0009).

**Não são funções da barra** (decisão explícita): Spec/Docs (artefatos moram nas
etapas); Custo (grupo da Timeline; conta em configuração); Segurança (grupo de QA na
v1, promove-se se crescer); caixa de atenção (global, no header).

## 5. O centro do Chat — renderização do fluxo

O centro lê o **fluxo efetivo** da demanda (estrutura da ADR-0014) e desenha a régua de
etapas sem conhecer nenhuma composição: o **tipo** da etapa escolhe o renderizador —
documentos MD (contexto/spec/plano), progresso de execução (implementação), abas
aaa/e2e/integração (teste), **checklist de validação com planos e links marcáveis**
(validação_humana), **passos com estados e geração de PRs** (finalização). Os
renderizadores derivam dos componentes já definidos no dop-app (ValidationStageView,
FinalizationStageView, doc-viewer, test-stage-view) — repensados, não descartados.
