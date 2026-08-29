# Revisão crítica — plataforma DOP × estado da arte (agosto 2026)

> **Data:** 2026-08-29
> **Método:** releitura de todos os requisitos e decisões (ADRs 0001–0005, specs SP-0,
> spec dop-infra, desenho do substrato de execução, PRD 1.0, 20 prompts de ajuste,
> análise do dop-app), comparados com o estado da arte de desenvolvimento autônomo com
> agentes. O `dop-cmd` foi usado **apenas como fonte de conhecimento** — é utilitário à
> parte e não integra a plataforma.
> **Propósito:** encontrar o máximo de pontos fracos e indicar soluções, antes do SP-4.

## 1. A intenção do projeto, como a entendo

Uma plataforma digital multi-tenant onde **o dev é gestor de agentes, não executor**:
demandas chegam do task manager, agentes as desenvolvem de ponta a ponta em sandboxes
isolados (microVM com Docker interno), com ambiente de teste full-stack por demanda,
specs como artefato durável, PR como entrega, e o humano decidindo, aprovando e dando
contexto. Núcleo gRPC + BFF multiprotocolo, infra hexagonal portável GCP ↔ k3s/OKD,
frontend com alma de IDE.

**O diferencial real, confirmado por pesquisa:** nenhum agente de mercado (Codex, Jules,
Devin, Copilot agent) sobe a *pilha da aplicação* da demanda — todos entregam sandbox de
código. O ambiente full-stack por demanda + a camada de gestão multi-conta é o que o DOP
tem que os outros não têm.

## 2. Pontos fracos e soluções

Ordenados por severidade. ⬛ crítico · 🟧 alto · 🟨 médio.

### A. Núcleo do produto

**⬛ F-1. O substrato avança na frente do modelo de trabalho.**
SP-4 — o que a plataforma *faz* — segue indefinido, enquanto sandbox, infra e identidade
já têm desenho. É inversão de dependência de produto: o substrato pode nascer com a forma
errada (ex.: ciclo suspend/resume dimensionado para portões que talvez nem existam).
*Solução:* travar SP-4 como próximo passo obrigatório antes de qualquer plano do
substrato; validar o substrato contra o ciclo de vida real da demanda.

**⬛ F-2. Não existe gestão de contexto/conhecimento do projeto.**
O que separa agente bom de agente inútil em 2026 é contexto: índice do código, convenções,
ADRs do cliente, memória de demandas anteriores, regras da workspace. Nos requisitos isso
aparece como "contexto criado pelo Claude" (etapa 2) e "regras da workspace" — mas não há
entidade, não há porta, não há design de recuperação.
*Solução:* elevar a **base de conhecimento por projeto** a subsistema de primeira classe
no SP-4: entidade versionada (regras, convenções, mapa do repo, memórias de demanda),
porta `KnowledgeStore`, e um "pacote de contexto" montado por demanda antes do agente
começar.

**⬛ F-3. O loop de verificação não está desenhado — e sem ele autonomia vira fila de revisão.**
A pesquisa de 2026 é explícita: agentes já fecham o loop até o PR; o gargalo passou a ser
a capacidade humana de revisar. Se o DOP não der ao agente critérios de aceitação
verificáveis por máquina (derivados da spec) + iteração até verde + crítico automático
pré-revisão, todo ganho de paralelismo morre na mesa do revisor.
*Solução:* no SP-4, aceitação nasce **na spec** em forma executável; o agente itera contra
ela no sandbox; um agente crítico revisa antes do humano; a evidência (testes, diffs,
execução) chega anexada ao PR. O humano revisa exceção, não regra.

**⬛ F-4. Paralelismo no mesmo repo sem orquestração de merge.**
O requisito diz: SUOPTS-1501/1502/1503 simultâneas "independente de repos coincidirem".
Três agentes, três PRs, arquivos sobrepostos — a ordem de merge decide o que sobrevive, e
CI não pega regressão comportamental entre PRs paralelos. A prática consolidada é **merge
queue serializado com verificação entre merges**. Nada disso está desenhado. (O `dop-cmd`
tem conhecimento minerável aqui: `integrate-desenv`, `prepare/finish-merge-conflicts`,
`solve-conflict` — fluxos reais de conflito testados em produção.)
*Solução:* merge queue por repositório como conceito do domínio; rebase automático da fila;
resolução de conflito como *tarefa de agente* com escalação a humano; o orquestrador
enxerga sobreposição de arquivos entre demandas ativas e sinaliza risco antes do PR.

**🟧 F-5. A atenção humana é o gargalo dimensionante — e está como "proposto".**
Com 6–8 demandas paralelas, o recurso escasso é a atenção do dev (o próprio PRD já dizia).
A visão cross-workspace "onde sou necessário" (R2.9) segue marcada como *proposta*. Pior:
o mesmo humano aprova a spec e revisa o PR — risco de carimbo.
*Solução:* **caixa de atenção** como primitivo central da UX (não tela opcional): fila
única priorizada de "decisões que só o humano pode tomar", com lote e contexto. Portões
com nível de risco: mudança de baixo risco com crítico verde pode ter revisão reduzida.

### B. Economia e operação

**⬛ F-6. Custo de LLM sem medição, orçamento ou roteamento.**
N agentes autônomos × sessões longas × multi-tenant = a maior linha de custo variável do
produto, e não há uma linha sobre isso em nenhum documento. Sem metering por conta, o
modelo de negócio é indefinível; sem budget por demanda, uma demanda patológica queima
dinheiro em loop.
*Solução:* medição de tokens/custo por demanda e por conta desde o primeiro dia (evento no
dossiê); orçamento com corte suave (pausa e pergunta) por demanda; porta `ModelRouter`
para rotear etapas mecânicas a modelos baratos.

**🟧 F-7. Nenhuma telemetria de qualidade do agente.**
Não há métrica planejada de: intervenções humanas por demanda, retrabalho, PRs recusados,
tempo até verde. Sem isso não há como saber se a autonomia melhora ou piora — e a
conversa já produziu a semente certa ("cada interrupção é sinal de spec incompleta").
*Solução:* métricas de demanda como parte do dossiê; painel de qualidade por projeto;
usar interrupções como métrica de qualidade de spec, fechando o ciclo spec-driven.

**🟧 F-8. Auditoria tratada como pendência (P-1) quando aqui ela é produto.**
Plataforma que executa agentes autônomos com credenciais de cliente precisa de trace
completo e reproduzível de cada ação — para confiança, depuração e conformidade. SOTA já
entrega replay de sessão.
*Solução:* linha do tempo da demanda como **log de eventos append-only** (alinha com o
dossiê incremental já pedido nos prompts 17); toda ação de agente vira evento com ator,
credencial usada e resultado. Isso também resolve P-1 de graça.

**🟨 F-9. Agendamento de demandas indefinido.**
O substrato é limitado por CPU (medido no doc de referência); o orquestrador "decide", mas
não existe. Quem enfileira, quem prioriza, o que acontece quando a 9ª demanda chega?
*Solução:* fila de admissão por conta/projeto com limites; prioridade explícita; suspensão
preemptiva de demandas ociosas (já desenhada) como válvula.

### C. Segurança

**⬛ F-10. Prompt injection não é tratado — e o DOP tem a tríade letal completa.**
O agente lê conteúdo não confiável (card do Jira, README do repo, código de terceiros),
tem credenciais (token de instalação) e tem saída para fora (git push, PR). Pesquisa de
2026 (OWASP, Microsoft) mostra injection como causa nº 1 de falha de segurança agêntica em
produção; um card malicioso pode instruir o agente a exfiltrar código.
*Solução em camadas:* (1) **egress allowlist por sandbox** — só git do provedor, BFF e
endpoints de modelo; (2) conteúdo de card/repo marcado como não confiável no contexto do
agente; (3) credencial mínima já existente (token 1h por instalação — manter); (4) redação
de segredos em toda saída (conhecimento do `dop-cmd`, ADR-0006 dele, minerar e reimplementar);
(5) detecção em runtime de comandos anômalos + trilha do F-8.

**🟧 F-11. Isolamento degradável precisa ser política de conta, não fallback silencioso.**
O `isolationTier` declarado já foi desenhado — falta o outro lado: a conta exigir tier
mínimo ("nunca rode minha demanda abaixo de kernel-emulated") e a plataforma recusar em
vez de degradar.
*Solução:* `minIsolationTier` como política da conta; violação = recusa com mensagem, não
downgrade.

### D. Consistência técnica

**🟧 F-12. O contrato já está triplicado antes de existir.**
`types.ts` à mão no frontend (rico, evoluído), `openapi.yaml` vazio com codegen rodando
sobre o nada, e um futuro `.proto` do core. Três fontes, nenhuma autoritativa — o drift já
começou no branch `dev`.
*Solução:* SP-2 decide **uma** fonte (provável: proto do core como verdade; OpenAPI do BFF
e types do front gerados). Até lá, congelar invenção de contrato novo no frontend.

**🟧 F-13. Governança dos repositórios está quebrada no dop-app.**
Submodule aponta para scaffold; todo o trabalho vive num branch `dev` sem ancestral comum
com `main`; 3.523 linhas órfãs aguardando decisão.
*Solução:* promover `dev` (ou reancorar main), fixar ponteiro, e decidir o destino do
código órfão **no SP-4** — nem restaurar por inércia, nem apagar antes da decisão do
modelo de etapas.

**🟧 F-14. O motor de agente não está atrás de porta.**
A ADR-0001 foi aplicada à infra, mas o agente em si (Claude Agent SDK) está sendo assumido
diretamente. É exatamente o tipo de dependência que a regra manda isolar — modelos e SDKs
estão trocando de líder a cada semestre.
*Solução:* porta `AgentRuntime` (iniciar sessão, continuar, cancelar, stream de eventos,
custo); Claude Agent SDK como primeiro adaptador.

**🟨 F-15. O frontend mock-first codificou semântica que o domínio nunca ratificou.**
`Stage.execData`, `parallelGroup`, formas de progresso — inventadas para a tela, podem não
casar com o SP-4. A exceção é a regra de atribuição de commits, que é domínio genuíno.
*Solução:* tratar `types.ts` como *inventário de requisitos* para o SP-4/SP-3, não como
contrato; ratificar explicitamente o que fica.

**🟨 F-16. Persistência com sinais contraditórios.**
"Mongo, por exemplo" convive com um dossiê incremental orientado a eventos (F-8) e specs
versionadas — cargas com naturezas diferentes (documento, log append-only, blob).
*Solução:* SP-3 decide com o log de eventos como cidadão de primeira classe; o banco de
documentos serve projeções, não substitui o log.

## 3. O que está forte (para não mexer)

- Ambiente full-stack por demanda — diferencial real, manter no centro.
- ADR-0001 (portas) com duas famílias e disciplina de dois adaptadores — acima do padrão
  de mercado; falta só aplicá-la ao agente (F-14).
- Conta como unidade de posse (ADR-0002) — modelo GitHub/GCP, dissolve os conflitos de
  requisito por construção.
- Credencial de organização + autoria humana (ADR-0003) — exatamente a prática de bots
  sérios de CI.
- Verificação por domínio (ADR-0004) — validada contra o que GitHub/GCP realmente fazem.
- Spec-driven como método — alinhado com a direção do mercado (Kiro, Spec Kit), e o DOP
  já convergia para isso antes de nomear.
- Regra de atribuição de commits (dop-app) — domínio genuíno descoberto pela UI.

## 4. Ordem recomendada de ataque

1. **SP-4** resolve F-1, F-3, F-15 e decide o destino do órfão (F-13) — é o desbloqueador.
2. **Segurança do sandbox** (F-10, F-11) entra na spec do substrato antes do plano.
3. **Merge queue e conflitos** (F-4) — desenho junto do SP-4, minerando o dop-cmd.
4. **Custo e telemetria** (F-6, F-7, F-8) — entram no SP-3 como eventos do dossiê.
5. **Contrato** (F-12) — SP-2 logo após SP-4; congelar invenção no front até lá.
6. **Portas faltantes** (F-14) — AgentRuntime na spec do substrato.
