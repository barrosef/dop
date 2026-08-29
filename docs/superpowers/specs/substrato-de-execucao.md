# Substrato de execução de demandas

> **Status:** Aprovada para revisão · **Data:** 2026-08-29 · **Projeto:** plataforma DOP
>
> **Responde:** onde e como uma demanda executa — sandbox, ciclo de vida, credenciais,
> segurança e as portas que o suportam.
>
> **Não responde:** o ciclo de vida da spec/demanda (núcleo do SP-4, pendente);
> verificação e merge → [`verificacao-e-entrega.md`](verificacao-e-entrega.md);
> threads e atenção → [`conversacao-e-atencao.md`](conversacao-e-atencao.md).

Decisões de base: [ADR-0001](../../adr/0001-infraestrutura-atras-de-portas.md),
[ADR-0003](../../adr/0003-credencial-de-organizacao-autoria-humana.md),
[ADR-0010](../../adr/0010-multi-agente-por-demanda.md),
[ADR-0011](../../adr/0011-governanca-de-custo-llm.md).

## 1. Uma demanda, um sandbox

Cada demanda ativa recebe um **sandbox**: uma microVM contendo o(s) agente(s), o
workspace de código e um Docker interno que sobe a pilha daquela demanda para teste e QA.

O Kubernetes é a superfície de orquestração: **um namespace por demanda**
(`dop-<id-curto>`, com conta/workspace/projeto/demanda em labels — identificação
hierárquica é label, não nome). O isolamento sobe de container para VM por uma linha:

| Ambiente | `runtimeClassName` | `isolationTier` |
|---|---|---|
| Cluster com KVM | `kata-fc` (Kata + Firecracker) | `hardware` |
| Cluster com gVisor/Edera | `gvisor` | `kernel-emulated` |
| Sem nenhum dos dois | securityContext estrito | `namespace` |

Duas demandas com os mesmos repositórios em branches diferentes correm sem
interferência: cada sandbox tem seu workspace, sua pilha e sua rede de compose.

## 2. A porta `ExecutionTarget`

```
provision(demanda, spec) → Sandbox
resume(id) · suspend(id) · destroy(id)
describe(id) → { estado, isolationTier, endpoints }
```

- **`isolationTier` é declarado, não presumido.** O cliente vê o que recebeu.
- **`minIsolationTier` é política da conta**: exigência não atendida = **recusa com
  mensagem**, nunca degradação silenciosa.
- Adaptadores (dois, pela ADR-0001): **Kubernetes** — que serve os dois modos do
  produto, SaaS no cluster do DOP e infra do cliente, mudando kubeconfig e limites, não
  implementação — e **local** sobre Docker do host, para desenvolvimento da plataforma.
- O devbox roda como **usuário arbitrário não-root** desde a primeira imagem — OKD/
  OpenShift recusam root por SCC, e é requisito de imagem, não de implantação.

## 3. Ciclo de vida

`ativo → suspenso → destruído`. Sem trabalho de agente e sem dev conectado por N
minutos, o sandbox **suspende**: o pod morre, o workspace sobrevive num PVC. Retomar
recria o pod sobre o workspace existente. Demandas esperam humanos por horas — sandbox
ocioso é o que separa paralelismo real de máquina afogada.

Snapshot/restauração de microVM fica como otimização a avaliar (suporte no Kata é
limitado); o desenho não depende dele.

## 4. Dentro do sandbox

| | |
|---|---|
| **Agentes** | 1 principal + N subagentes (ADR-0010), via porta `AgentRuntime` (§7) |
| **Workspace** | Worktrees das branches da demanda, em PVC |
| **Docker interno** | `docker compose -p <demanda>`: rede e DNS próprios — `backend` resolve dentro daquela composição. Constrói localmente; dispensa BuildKit/registry compartilhados |
| **Pacote de contexto** | Montado no provisionamento ([`contexto-e-conhecimento.md`](contexto-e-conhecimento.md)), leitura |
| **Caches** | Volume **por conta** — nunca global: cache compartilhado entre contas é canal lateral |

## 5. Acesso e credenciais

- **Dev:** terminal (PTY, já existente no dop-app) e logs por streaming; aplicações
  expostas por ingress `<serviço>--<demanda>.<domínio>`.
- **Agente → plataforma:** sempre de dentro para fora, via BFF. O sandbox não precisa
  ser alcançável para o agente trabalhar.
- **Credenciais:** nada assado em imagem, nada persistido. O `SecretStore` resolve a
  credencial da conta e o sandbox recebe **token derivado de curta duração** (token de
  instalação de 1h por repositórios selecionados — ADR-0003), como volume projetado.

## 6. Segurança do sandbox

O agente tem a tríade completa — lê conteúdo não confiável, porta credencial, tem saída
via git (F-10). Defesa em camadas, obrigatória:

1. **Egress allowlist por sandbox**: só o git do provedor da demanda, o BFF e os
   endpoints de modelo. Todo o resto, negado por NetworkPolicy.
2. **Card e conteúdo de repositório são entrada não confiável** — marcados como tal no
   contexto de todo agente.
3. **Redação de segredos em toda saída** de agente e de log.
4. **Detecção em runtime**: ação anômala vira evento (ADR-0006) e alerta.
5. Token mínimo e curto (§5) — a camada que já existia, mantida.

## 7. A porta `AgentRuntime`

A ADR-0001 aplicada ao próprio motor (F-14): o domínio não conhece SDK de agente.

```
open(sandbox, ficha) → Session      // N sessões por sandbox (subagentes)
send(session, msg) · cancel(session)
events(session) → stream            // ações, perguntas, custo (→ ADR-0006/0011)
```

Primeiro adaptador: Claude Agent SDK. A ficha (propósito, ferramentas, modelo,
orçamento) vem da ADR-0010; o modelo, do router (ADR-0011).

A porta expõe os botões de economia (ADR-0012), preenchidos pela ficha: **modelo**,
**effort**, **orçamento** (task budget — o agente vê o teto e se ritma) e **política de
cache** (layout de prefixo estável; intervenção do operador via mensagem `system`
mid-conversation, nunca editando o topo do prompt). O stream de eventos reporta
`cache_read`/`cache_creation` para a telemetria da ADR-0011.

## 8. Riscos

| # | |
|---|---|
| R-1 | Docker em microVM sem cache repuxa imagens a cada demanda — cache por conta é mitigação obrigatória |
| R-2 | Retomada re-sobe a pilha do compose: latência real percebida pelo dev |
| R-3 | Ingress por demanda multiplica objetos/certificados no controlador |
| R-4 | `RuntimeClass` Kata ausente em muitas distribuições — o adaptador detecta e aplica a política de tier (§2), nunca degrada em silêncio |
| R-5 | Egress allowlist quebra dependência legítima inesperada (ex.: registry de pacotes) — a lista é por projeto, editável, com mudanças auditadas |
