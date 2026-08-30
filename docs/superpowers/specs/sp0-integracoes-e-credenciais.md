# SP-0 — Integrações e credenciais

> **Status:** Aprovada para revisão · **Data:** 2026-08-29 · **Projeto:** plataforma DOP
>
> **Responde:** o que é uma integração, onde a credencial vive, quem pode usá-la, e como
> um projeto a consome.
>
> **Não responde:** contas, papéis e vínculos → [`sp0-identidade-e-tenancy.md`](sp0-identidade-e-tenancy.md).
> Decomposição e faseamento → [`ROADMAP.md`](../../ROADMAP.md). Justificativas →
> [`adr/`](../../adr/).

Decisões de base: [ADR-0001](../../adr/0001-infraestrutura-atras-de-portas.md) (portas),
[ADR-0003](../../adr/0003-credencial-de-organizacao-autoria-humana.md) (credencial de
organização e autoria), [ADR-0002](../../adr/0002-conta-como-unidade-de-posse.md) (conta
como unidade de posse).

## 1. A entidade

Integrações **não são configuradas dentro de um projeto**. Elas pertencem à conta, e o
projeto apenas consome o que já está integrado.

> **Integração é um tipo de recurso** (ADR-0013) — o único com credencial. O mecanismo
> de compartilhamento e concessão descrito aqui é o mecanismo geral de recursos.

**`Integration`:**

| Campo | |
|---|---|
| `accountId` | a conta dona — é o que decide compartilhamento |
| `category` | `git`, `task_manager` ou `agent` |
| `provider` | `github`, `gitlab`, `gitlab_self_hosted`, `azure_devops`, `bitbucket` / `jira`, `clickup`, `redmine` / `claude`, `codex`, `google_code_assist` |
| `baseUrl` | para instâncias self-hosted |
| `authMethod` | `oauth_app`, `oauth_user`, `token`, `ssh_key` |
| `credentialRef` | **referência lógica opaca** ao segredo — nunca o segredo |
| `connectedByUserId` | quem estabeleceu |
| `status` | `active`, `expired`, `revoked`, `error` |

## 2. A porta `SecretStore`

Primeira porta de infraestrutura da plataforma, sob a regra da ADR-0001.

### 2.1 Superfície

```
type SecretRef = {
  accountId: AccountId
  kind: 'integration_credential'
  ownerId: string            // id da Integration
}

interface SecretStore {
  put(ref: SecretRef, value: SecretValue): Promise<void>
  get(ref: SecretRef): Promise<SecretValue | null>
  delete(ref: SecretRef): Promise<void>
  exists(ref: SecretRef): Promise<boolean>
}
```

Quatro operações, e nada além disso. `SecretValue` é opaco: sem serialização implícita,
sem `toString` útil, sem aparecer em log, mensagem de erro ou stack trace.

O `credentialRef` guardado na `Integration` **é** o `SecretRef` — uma referência lógica
que só o adaptador sabe resolver. O domínio nunca conhece caminho, namespace nem nome de
segredo.

### 2.2 Garantias de contrato

O conjunto de testes de contrato exigido pela ADR-0001 verifica, em **todo** adaptador:

1. **Leitura-após-escrita** — `put` seguido de `get` devolve o mesmo valor, imediatamente.
2. `get` de referência inexistente devolve `null`, **não** lança.
3. `delete` é idempotente.
4. `put` sobre referência existente substitui.
5. **Isolamento** — referência da conta A jamais resolve segredo da conta B.
6. O valor nunca aparece em log, erro ou stack trace.

### 2.3 Adaptadores

Dois desde o primeiro dia, conforme a disciplina da ADR-0001:

| Adaptador | |
|---|---|
| **GCP Secret Manager** | Nome do segredo derivado da referência; autorização por service account via Workload Identity. Versionamento fica **oculto** — a porta sempre lê a versão corrente |
| **Secret do k8s** (k3s/Rancher, OKD) | Namespace por conta, nome derivado da referência. **Lê pela API, nunca pelo volume montado**: volume é eventualmente consistente (kubelet sincroniza em torno de um minuto) e violaria a garantia 1 |

O banco de dados guarda **apenas a referência**. Nenhum token, nenhuma chave privada, em
nenhuma hipótese.

## 3. Compartilhamento

**Integração de conta pessoal nunca é usada numa organização e nunca é vista por outros
membros dela. Somente integração de conta de organização é compartilhável.**

A regra decorre da ADR-0002 e não precisa de tratamento especial: a conta pessoal tem um
membro só.

**Concessão de integração** — por usuário, por integração:

| Nível | |
|---|---|
| `use` | Pode escolher aquela integração ao configurar projetos |
| `manage` | Pode editar, reconectar e revogar a integração |

`owner` e `admin` têm `manage` implícito em tudo. Os demais recebem o que foi composto no
convite e o que se editou depois — **não há default**.

**`use` controla configuração, não execução.** Revogar o `use` de alguém não derruba os
projetos já configurados: a credencial é da conta, não da pessoa. O que se perde é a
capacidade de escolher aquela integração ao montar projetos novos.

## 4. Titular da credencial

Conforme a ADR-0003:

- **Conta de organização** usa credencial de organização — GitHub App instalado na
  organização, *group access token* no GitLab, service principal no Azure DevOps. Token
  pessoal é permitido como saída, mas a interface **exibe de quem ele depende**, para que
  o risco fique visível em vez de ser descoberto no dia em que quebra.
- **Conta pessoal** usa qualquer método: a pessoa é a conta.

**Autoria no repositório:** o push e a abertura do PR usam a credencial da conta, mas cada
commit leva `author` com nome e e-mail do dev que conduziu o card, e o corpo do PR
identifica quem pediu.

### 4.1 Providers de agente

A categoria `agent` conecta a conta aos provedores de modelo/agente — **Claude, Codex,
Google Code Assist** e futuros. Métodos: **OAuth de conta pessoal** (assinatura do
provedor) ou **API key**, ambos guardados via `SecretStore` como qualquer credencial.

- **São o cardápio do router**: os modelos que a `ficha` de um agente (ADR-0010) pode
  usar são os das integrações de agente da conta, resolvidos pela porta `AgentRuntime`
  — um adaptador por provider (ADR-0001, segunda família).
- **Custo:** com credencial do cliente (BYO), o gasto de modelo cai na conta dele no
  provedor; a **medição da ADR-0011 não muda** — mede-se igual, quem paga é que varia.
- Numa PJ, valem as mesmas regras de titularidade da §4: preferir credencial que não
  morre com a pessoa; API key organizacional quando o provedor oferecer.

## 5. Como o projeto consome

O projeto guarda **referências**, jamais credenciais:

- para cada repositório: a integração de origem e o identificador do repositório nela,
  mais branch base e alvos de PR;
- para o task manager: a integração, o espaço do provedor e o projeto lá dentro.

Configurar um projeto passa a ser **escolher de uma lista já autenticada**, não preencher
credencial de novo.

O provedor é do **repositório**, não do projeto: um mesmo projeto tem repositório vindo de
uma integração GitHub e outro de uma integração GitLab, desde que ambas pertençam à conta
dona do workspace. É o caso de uso da segunda família de portas da ADR-0001 — vários
adaptadores de `GitProvider` ativos ao mesmo tempo.

## 6. Riscos

| # | |
|---|---|
| R-1 | **Credencial de organização é ponto único de falha.** App desinstalado ou token revogado para todos os projetos daquela conta. Exige monitoramento de `status` e alerta ao `owner` |
| R-2 | **Upload de chave SSH privada** trafega segredo pela borda. Exige TLS obrigatório, ausência de log do corpo da requisição, e escrita direta no `SecretStore` sem persistência intermediária |
| R-3 | **Adaptador k8s lendo por volume** quebraria a garantia de leitura-após-escrita de forma silenciosa — passa em teste local e falha sob carga. Coberto pelo teste de contrato |
| R-4 | **`baseUrl` de self-hosted é entrada controlada pelo usuário** apontando para onde a plataforma fará requisições. Exige validação contra alvos internos |

## 7. Pendências

Registradas no [`ROADMAP.md`](../../ROADMAP.md):

- **P-1** — trilha de auditoria: quem usou qual credencial, quando.
- **P-2** — transições de `status`: quem detecta `expired`, com que frequência, e o que
  acontece com trabalho em andamento.
