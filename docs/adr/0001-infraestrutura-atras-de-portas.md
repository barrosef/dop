# ADR-0001 — Infraestrutura atrás de portas com adaptadores plugáveis

- **Status:** Aceita
- **Data:** 2026-08-29

## Contexto

A plataforma precisa rodar em **GCP Cloud Run** e em **cluster k3s/Rancher ou OKD**, e a
lista de serviços de infraestrutura vai crescer: segredos, identidade, armazenamento de
objetos, persistência, mensageria. Cada ambiente oferece um serviço diferente para a
mesma necessidade — Secret Manager de um lado, Secret do k8s do outro.

Acoplar o domínio a um fornecedor obrigaria a reescrever por ambiente, e amarraria o
projeto à primeira escolha feita sob pressão.

## Decisão

**Toda infraestrutura é alcançada exclusivamente por uma porta definida pelo domínio**,
com adaptadores específicos de fornecedor injetados num *composition root* e escolhidos
por configuração. O domínio não importa SDK de fornecedor.

### Duas famílias de portas

Elas se parecem e têm ciclos de vida opostos; confundi-las é o erro típico deste desenho.

| | **Portas de infraestrutura** | **Portas de provedor de domínio** |
|---|---|---|
| Exemplos | `SecretStore`, `IdentityProvider`, `ObjectStore`, repositórios, `EventBus` | `GitProvider`, `TaskManagerProvider`, `RuntimeOrchestrator` |
| Quem escolhe | O ambiente de implantação | A configuração da conta |
| Quando | Uma vez, no boot | A cada requisição |
| Quantos ativos | Um | Vários simultâneos |

A segunda família precisa suportar coexistência: uma mesma workspace tem repositório no
GitHub e no GitLab ao mesmo tempo.

### Três disciplinas obrigatórias

Sem elas, "hexagonal" vira nome de pasta:

1. **Dois adaptadores por porta desde o primeiro dia.** O adaptador local não é "para
   depois" — é a prova de que a porta está certa. Porta com um adaptador só é palpite, e
   sai no formato do fornecedor que a inspirou.
2. **Um conjunto de testes de contrato por porta**, que todo adaptador passa. É o que
   garante substituibilidade de fato, não de intenção.
3. **Porta estreita, em linguagem do domínio.** O domínio pede `SecretStore.get(ref)`,
   não `accessSecretVersion`.

### Tratamento de vazamento

Quando uma capacidade não mapeia entre adaptadores, ela fica **fora** da porta. Se um dia
for necessária, entra como capacidade opcional que o domínio nunca assume.

Casos já decididos:

- **Versionamento de segredo fica fora.** O Secret Manager tem versões e IAM por segredo;
  o Secret do k8s é plano e sem histórico.
- **Secret do k8s montado como volume é eventualmente consistente** — o kubelet sincroniza
  em torno de um minuto. Como a porta promete leitura-após-escrita, o adaptador k8s lê
  pela API, não pelo volume.
- **Claims de Firebase não cruzam a fronteira.** O `IdentityProvider` devolve um principal
  normalizado: `subject`, `email`, `emailVerified`, provedores vinculados.

## Alternativas consideradas

**Acoplar ao GCP e portar depois.** Mais rápido no começo. Descartada porque "depois" é
quando o acoplamento já está espalhado, e porque rodar localmente em k3s é requisito de
desenvolvimento, não ambição futura.

**Camada de abstração genérica de nuvem** (uma biblioteca multi-cloud pronta). Descartada
porque entrega o denominador comum *do fornecedor da biblioteca*, não o do domínio, e
troca um acoplamento por outro.

## Consequências

- ➕ A plataforma roda em Cloud Run e em cluster sem mudança no domínio — só fiação.
- ➕ O domínio fica testável sem infraestrutura: adaptador em memória é só mais um.
- ➕ Trocar Firebase por Keycloak, Zitadel ou Ory não toca no domínio.
- ➖ Custo real de escrever e manter **dois** adaptadores por porta desde o início.
- ➖ Uma camada de indireção a mais em toda chamada de infraestrutura.
- ➖ Capacidade forte de um fornecedor fica inacessível ao domínio por construção. É o
  preço, e é deliberado.
