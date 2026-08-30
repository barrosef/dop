# Navegação e cockpit

> **Status:** Aprovada (protótipo validado pelo Dev em 2026-08-29) · **Projeto:** plataforma DOP
>
> **Responde:** o padrão de navegação da plataforma e a anatomia do cockpit.
>
> **Protótipo clicável:** https://claude.ai/code/artifact/184e2f56-7cf4-4c94-9e39-b49c993c73da
>
> **Não responde:** conteúdo detalhado de cada seção (evolui com SP-4 núcleo e com as
> user stories); protocolo (SP-2).

## 1. Princípio

**Zero telas até o trabalho.** Login cai no último cockpit aberto, com a demanda que
estava selecionada. Trocar de projeto: 1 clique. Trocar de demanda: 1 clique. Trocar de
workspace: 2. Configuração é desvio de 10 segundos (painel deslizante), nunca viagem.

## 2. Chrome global

- **Header fino:** logo, **seletor de conta ativa** (pessoal + PJs, estilo GitHub — SP-0),
  breadcrumb `conta / workspace / projeto [/ demanda]`, **caixa de atenção (🔔 com
  badge)** e paleta **⌘K**.
- **Caixa de atenção é global**, nunca seção de cockpit: cruza todas as demandas da
  conta ativa; cada item navega direto ao lugar da resolução (thread, spec, PR, conflito).
- **Barra lateral esquerda = a árvore**, e só ela: workspaces → projetos, com busca;
  colapsável a ícones; engrenagem por hover abre painel deslizante de configuração.
  Não existem "lista de workspaces" nem "dashboard geral": a árvore é a lista, o
  Overview do projeto é o dashboard.
- **⌘K:** pular para workspace/projeto/demanda, criar demanda, abrir configuração.

## 3. Cockpit — três colunas, dois escopos

```
[árvore] [seções] [conteúdo]     + faixa de demandas horizontal no topo do cockpit
```

- A **faixa de demandas** (cards do provider, duplo status, filtrável) atravessa o topo —
  a seleção de card é transversal às seções.
- **Escopo projeto** (nenhum card selecionado): tudo agregado.
- **Escopo demanda** (card selecionado, 1 clique): tudo restrito à demanda + o que só
  existe com uma (chat/threads, runtime do sandbox, spec). Clicar de novo desseleciona.
- Indicador de escopo fixo no rodapé da barra de seções.
- **URL profunda:** `/:conta/:workspace/:projeto?card=<id>` — todo estado navegável é
  linkável.

## 4. As seções (barra lateral vertical, ícones + rótulo)

| # | Seção | Conteúdo | Base |
|---|---|---|---|
| 7.1 | Overview | KPIs, cards com duplo status, atividade dos agentes, filas | |
| 7.2 | Chat | Threads multi-agente, fichas, achados, lançar subagente | ADR-0010 |
| 7.3 | QA | AAA/e2e, Allure, resultados de aceitação | ADR-0007 |
| 7.4 | Código & entrega | Repos → branches → PRs → diffs; fila de merge com posição e sobreposições | ADR-0008 |
| 7.5 | Runtime | Serviços do sandbox, logs em streaming, terminal | substrato |
| 7.6 | Spec & docs | Spec da demanda, critérios, portão de aprovação, artefatos MD | spec-driven |
| 7.7 | Timeline | Dossiê como linha do tempo de eventos; custo e cache da demanda | ADR-0006/0011 |
| 7.8 | Arquitetura | Índice da base de conhecimento renderizado, achados arquiteturais, análise sob demanda | ADR-0009 |

## 5. Inventário de telas fora do cockpit

1. **Auth** — sign in/up, 4 métodos.
2. **Primeiro uso** — conta → 1 integração → workspace + projeto; tudo revisitável.
3. **Painéis deslizantes** — conta (integrações, membros, perfis), workspace (tags),
   projeto (repos, task manager, regras, conhecimento).

Nada além disso.
