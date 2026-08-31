# ADR-0022 — Provedor de agente é porta, com adaptadores por fornecedor

- **Status:** Aceita
- **Data:** 2026-08-31
- **Resolve:** o `AgentRuntime` acoplado a um fornecedor

## Contexto

Ao especificar o `AgentRuntime` — a peça que conversa com o modelo — o briefing
inicial dizia "escreva código que chama a API da Anthropic". Estava errado, e o dono
do produto pegou: *"a plataforma deve pensar em isolamento com múltiplas opções de
providers, inclusive de agentes; por exemplo Claude e Codex"*.

É a ADR-0001 aplicada ao lugar onde ela é mais fácil de esquecer, porque o fornecedor
de modelo parece "o produto" e não "a infraestrutura".

O modelo de dados já antecipava isso, e ninguém tinha ligado os pontos:

- **ADR-0013** define provedor de agente como **integração de categoria `agent`** —
  recurso com credencial, compartilhável mediante autorização. Claude e Codex são dois
  recursos, não duas versões do código.
- O **roteador de custo** (ADR-0011) já separa **política** de **catálogo**:
  `routingTable` escolhe a *classe* (barato/médio/forte) e `ModelCatalog` resolve o
  *nome concreto*, com o comentário dizendo o porquê — "política muda com telemetria,
  catálogo muda quando o fornecedor lança modelo".

## Decisão

**`AgentProvider` é porta, com um adaptador por fornecedor.** O runtime nunca vê tipo
de SDK: manda uma conversa (prefixo estável + mensagens + ferramentas) e recebe
resposta com uso (entrada, saída, leitura de cache, criação de cache) e motivo de
parada.

A escolha do adaptador é **por requisição**, não no boot — e essa é a diferença que
mais afeta a fiação:

| | Escolhido | Ativos ao mesmo tempo |
|---|---|---|
| `SecretStore`, `EventBus`, `SandboxLauncher` | no boot, por configuração | um |
| **`AgentProvider`** | **por requisição, pelo recurso** | **vários** |

É a mesma natureza das integrações de task manager: um projeto no Jira e outro no
ClickUp convivem na mesma conta. Aqui, uma conta pode ter Claude e Codex, e a demanda
escolhe.

A classe vem do roteador; o adaptador ativo resolve o nome concreto do modelo. Assim a
política de custo continua valendo para todos os fornecedores sem conhecer nenhum.

## Alternativas consideradas

**Um adaptador só, e trocar depois.** É o que a ADR-0001 existe para impedir: o
primeiro fornecedor vira a interface, e a troca depois é reescrita. Foi exatamente
assim que a porta `IdentityProvider` passou meses com um adaptador — e escondeu um
bypass de autenticação até alguém escrever o segundo.

**Camada de compatibilidade OpenAI.** Vários fornecedores expõem uma API "compatível
com OpenAI", e seria tentador tratar isso como o denominador comum. Descartada: a
compatibilidade cobre o caso simples e vaza justamente onde a plataforma precisa de
precisão — cache de prefixo, formato de ferramenta, contagem de tokens.

## Consequências

- ➕ Trocar ou acrescentar fornecedor é escrever um adaptador, não mexer no runtime.
- ➕ A economia de token (ADR-0012) fica explícita por fornecedor, em vez de suposta.
- ➖ **A semântica de cache de prefixo NÃO é igual entre fornecedores**, e a economia
  depende dela. É a divergência mais cara, e precisa estar documentada na porta.
- ➖ Formato de chamada de ferramenta, eventos de streaming e motivos de parada também
  divergem; o que não for cumprível por todos fica FORA da porta, explicitamente.
- ➖ Dois adaptadores e uma suíte de contrato desde o início — que é o custo que já se
  pagou três vezes nesta plataforma.
