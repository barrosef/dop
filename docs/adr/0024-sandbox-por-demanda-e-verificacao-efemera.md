# ADR-0024 — microVM por demanda, worktree único, verificação em pod efêmero

- **Status:** Aceita
- **Data:** 2026-08-31
- **Resolve:** P-24 (provisionamento de sandbox) e a questão de isolamento entre threads

## Contexto

Uma demanda tem 1 agente principal e N subagentes (ADR-0010) — um investigando log,
outro o banco, outro o código, com o principal orquestrando. Precisávamos decidir onde
cada um desses agentes roda, e onde a aplicação sob teste roda.

Três problemas apareceram juntos:

1. **Isolamento entre threads.** Uma microVM por thread daria isolamento forte, ao custo
   de 20 microVMs num projeto com 5 demandas paralelas de 4 threads — cada uma com
   kernel próprio e centenas de MB de sobrecarga.
2. **Portas.** Subir a mesma aplicação mais de uma vez no mesmo ambiente exige arbitrar
   porta, e ainda expor rota para o humano avaliar. Dentro de um sandbox compartilhado
   isso vira coordenação manual.
3. **De qual código o teste fala.** Este foi o que decidiu.

## Decisão

**Uma microVM por DEMANDA**, com **um worktree**, e **um pod efêmero por execução de
verificação**.

### microVM por demanda

A fronteira que precisa ser dura é entre **contas** e entre **demandas** — e é essa que
o sandbox por demanda garante. As threads de uma demanda são agentes da mesma conta
trabalhando no mesmo problema: mutuamente confiáveis. Gastar microVM entre elas seria
usar ferramenta de segurança para resolver um problema de coordenação.

Já é o que a constraint do banco impõe: `UNIQUE (demand_id) WHERE state <> 'destroyed'`.

### Um worktree, compartilhado

As threads compartilham `/workspace`. A alternativa — um worktree do git por thread —
resolveria colisão de arquivo, mas acrescenta complexidade real: `ExecRequest` passaria a
carregar o conceito de thread, e cada comando precisaria saber em qual árvore roda.

**O risco aceito, explicitamente:** duas threads que EDITEM o mesmo arquivo se atropelam.
Isso é tolerável porque, no desenho de multi-agente, a maioria das threads LÊ — investigar
log, consultar banco e analisar fonte não escrevem no repositório — e quem edita é
tipicamente o principal. Se a prática mostrar duas threads editando com frequência, a
saída já está mapeada: worktree por thread, e o custo estará documentado aqui.

### Pod efêmero por execução de verificação

**O argumento que decidiu, e ele vem do nosso próprio código.** `VerificationRun.Commit`
é obrigatório, e a recusa diz: *"evidência que não diz sobre qual código rodou não é
evidência"*.

Teste rodando dentro do sandbox do agente roda contra a **árvore de trabalho suja**, que
não é commit nenhum. Ele não consegue produzir evidência honesta sob a regra da ADR-0007.
Um pod construído **a partir de um commit** produz — e testa exatamente o que vai ser
mergeado.

O pod vive só durante a execução e é descartado. Porta e rota deixam de ser problema do
sandbox: cada pod tem rede própria, e Service e Ingress dão ao humano uma URL viva
enquanto o teste roda.

## Consequências

- ➕ Cinco microVMs num projeto de cinco demandas, em vez de vinte.
- ➕ A evidência de verde passa a ser honesta por construção: ela fala de um commit
  porque rodou num ambiente construído daquele commit.
- ➕ Portas e rotas viram responsabilidade do cluster, que é o que ele faz bem.
- ➖ **Threads que editam o mesmo arquivo se atropelam.** Aceito acima, com a saída
  mapeada.
- ➖ Passam a existir DOIS tipos de computação: o sandbox longo do agente e o pod curto
  da verificação. São ciclos de vida diferentes de propósito, mas é mais uma coisa para
  operar.
- ➖ O teste passa a exigir **commit publicado** antes de rodar. Isso muda o fluxo do
  agente: editar, commitar, e só então verificar — o que é mais próximo do que um humano
  faz, e o que a fila de merge já pressupõe.
- ➖ `VerificationRun.SandboxID` hoje aponta para "onde rodou". Com a verificação em pod
  efêmero, ele passa a apontar para um ambiente que já não existe — o campo continua
  valendo como rastro, mas o nome ficou impreciso.
- ➖ `EndpointURL` é `<serviço>--<demanda>.<domínio>`, pensado para o sandbox. O ambiente
  de verificação precisa do seu próprio endereço, por EXECUÇÃO, senão duas verificações
  da mesma demanda colidem.

## Fica em aberto

**Quando provisionar.** A opção discutida — provisionar quando a demanda entra numa etapa
cujo tipo exige execução, em vez de ao iniciar — não foi decidida. Hoje o
provisionamento é por chamada explícita, e continua assim.

**Onde validar o microVM.** O cluster local não oferece: `SupportedTiers` devolve só
`namespace`, porque o k3d não tem RuntimeClass de Kata. A suíte de contrato prova o nível
`namespace` nos dois adaptadores; o nível `hardware` só será exercitado onde houver Kata.
Enquanto isso, a recusa é honesta — pedir `hardware` onde não há devolve erro, e não um
isolamento menor em silêncio.
