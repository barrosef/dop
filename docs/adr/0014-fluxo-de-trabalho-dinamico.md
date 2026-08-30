# ADR-0014 — Fluxo de trabalho dinâmico, tipado e herdável

- **Status:** Aceita
- **Data:** 2026-08-30
- **Refina:** [ADR-0013](0013-recurso-como-unidade-de-compartilhamento.md) (dá formato ao
  recurso `workflow` e ajusta o default de acesso por tipo de recurso)

## Contexto

O ciclo da demanda estava indefinido (núcleo do SP-4). O produto decidiu: **o fluxo de
desenvolvimento humano↔agente é dinâmico** — a plataforma tem um default, mas cada
conta, workspace, projeto e até uma demanda específica pode trabalhar do seu jeito. A
tela do chat e o agente precisam entender qualquer fluxo sem conhecer nenhum: o fluxo é
**dado**, não código.

Referências de mercado ocupam extremos: Jira customiza só status (sem artefatos nem
agente); GitHub Actions é fluxo-como-código para máquina, não para acompanhamento
humano; BPMN modela tudo e custa um analista. O meio-termo — etapas tipadas + composição
livre — está vago.

## Decisão

1. **Etapas têm tipo semântico; fluxos são composições.** O vocabulário de tipos é da
   plataforma: `contexto`, `spec`, `plano`, `implementação`, `teste` (subtipos `aaa`,
   `e2e`, `integração`), `validação_humana`, `finalização`, `genérico`. O tipo determina
   o **renderizador** na tela e o **comportamento** do agente (que artefato produzir,
   onde parar). Tipo novo exige evolução da plataforma; composição nova, não.
2. **Estrutura v1, deliberadamente simples:**
   ```
   Fluxo { nome, versão, etapas: [
     { chave, nome, tipo, artefatos: [documento|spec|plano|plano_testes|…],
       portão: humano | nenhum, subetapas? } ] }
   ```
   Sem condicionais, sem paralelismo de etapas, sem DSL de regras — evoluem sobre a
   mesma estrutura.
3. **Cadeia de resolução com herança:** `plataforma ◁ conta ◁ workspace ◁ projeto ◁
   demanda` — o nível mais próximo vence; herda-se por omissão, sobrepõe-se por
   declaração. A interface sempre mostra **de onde veio** o fluxo efetivo.
4. **A demanda congela a versão do fluxo ao iniciar.** Progresso de etapa é evento
   (ADR-0006); a régua da tela é projeção.
5. **Promoção:** um fluxo criado num nível pode ser promovido a um nível acima (demanda
   → projeto → workspace → conta) por quem tiver `manage`.
6. **Default de acesso por tipo de recurso** (refinamento da ADR-0013): recurso **com
   credencial** (`integration`) permanece fechado — concessão composta no convite;
   recurso **de conteúdo** (`workflow`, `skill`, `git_flow`) numa conta PJ é **aberto
   dentro da conta por default**, restringível por concessão. Credencial é risco; fluxo
   é conhecimento — defaults opostos são a política certa.
7. **Escopos de compartilhamento v1:** privado → conta. Compartilhamento **externo**
   (entre contas / catálogo comunitário) fica fora da v1 — decisão estratégica
   registrada como P-9: aguarda, não dorme.
8. **O fluxo default da plataforma** (catálogo, nível 0): contexto → spec → plano →
   implementação → teste (aaa/e2e/integração) → validação humana → finalização.

## Alternativas consideradas

**Etapas fixas da plataforma.** Era o desenho anterior (e o do PRD antigo). Descartada:
contas trabalham diferente, e o custo do dinamismo caiu a quase zero com etapas tipadas
— o estático vira o caso particular de um fluxo só.

**Motor de workflow completo (BPMN/Temporal).** Descartada na v1: compra condicionais e
paralelismo que ninguém pediu ao preço de complexidade que todos pagariam.

**Fluxo como código (YAML por repo).** Descartada como interface primária: o público é
o dev-gestor na tela, não um pipeline; nada impede exportação futura.

## Consequências

- ➕ Fecha o núcleo do SP-4: o ciclo da demanda é o fluxo efetivo resolvido pela cadeia.
- ➕ Os renderizadores são os componentes órfãos do dop-app promovidos por tipo
  (validação com checklist, finalização com passos, documentos MD, abas de teste).
- ➕ "Processo dinâmico", adiado pelo PRD antigo para pós-MVP, vira o modelo — sem custo
  extra de tela, porque a tela nunca conheceu etapas fixas.
- ➖ Cadeia de herança exige rastro visível ("herdado de…") — sem isso vira suporte.
- ➖ P-8 continua aberta: a sintaxe dos critérios executáveis dentro do artefato `spec`.
