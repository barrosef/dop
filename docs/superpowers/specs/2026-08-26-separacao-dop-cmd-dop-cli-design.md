# Separação `dop-cmd` × `dop-cli`

> **Status:** Aprovado para implementação
> **Data:** 2026-08-26
> **Escopo:** meta-repositório `dop`, repositório `dop-cli`, novo repositório `dop-cmd`
> **Não-escopo:** arquitetura do `dop-core`/`dop-api`, revisão do PRD 1.0, adoção de specs

## 1. Contexto e motivação

O repositório `dop-cli` contém hoje **duas coisas sobrepostas**:

1. A **ferramenta operacional em uso** (v0.7.1) — uma CLI Python que acessa a workspace
   diretamente e responde pelo ambiente: operações git, PRs multi-plataforma, runtime
   docker-compose, testes e2e/AAA, relatórios Allure e máquina de estado por demanda.
   É usada diariamente em workspaces reais.
2. O **nome reservado para a CLI definitiva** do DOP 1.0, que segundo o PRD deixa de
   acessar a workspace e passa a ser cliente da plataforma.

Manter as duas identidades no mesmo repositório impede que a CLI definitiva seja
construída sem colocar em risco a ferramenta em produção, e torna ambígua qualquer
conversa sobre "o dop-cli".

A separação resolve isso dando **um nome a cada papel**:

- **`dop-cmd`** — responde pelo ambiente. É o que existe e funciona hoje.
- **`dop-cli`** — a CLI definitiva do produto, cliente da plataforma. Nasce vazia.

O nome `dop-cmd` é mais apropriado para o primeiro papel: *comando* de ambiente, não
*interface de linha de comando de um cliente*.

### 1.1 Relação com a arquitetura da plataforma

Em paralelo a esta separação, a arquitetura do DOP 1.0 foi redirecionada: a plataforma
passa a ter um núcleo gRPC (`dop-core`), com o `dop-api` assumindo o papel de **BFF**
multiprotocolo (REST para o frontend, gRPC para a CLI), persistência em banco e
implantação em cluster.

Essa rodada de arquitetura **não faz parte desta spec** e será registrada em ADR
própria. Ela tem, porém, uma consequência que reforça a decisão aqui tomada:

> **O `dop-cmd` deixa de ser a base de código a partir da qual o núcleo seria extraído
> e passa a ser referência conceitual** — o acervo de conhecimento operacional validado
> em produção que informa o desenho do `dop-core`, sem ser herdado linha a linha.

Isso torna a separação mais necessária, não menos: o `dop-cmd` precisa continuar
estável e disponível como referência e como ferramenta, enquanto a plataforma é
desenhada do zero.

## 2. Decisões

| # | Decisão | Justificativa |
|---|---|---|
| D-1 | `dop-cmd` nasce **limpo**, com o código copiado do `main` do `dop-cli` em commit inicial único | A história de decisão continua acessível no `dop-cli`; um começo limpo evita arrastar tags e branches que já não descrevem o novo papel |
| D-2 | `dop-cli` é **esvaziado** e reduzido ao esqueleto do cliente definitivo | Libera o nome para o papel do 1.0 sem perder a história, que permanece no próprio repositório |
| D-3 | Distribuição `dop-cmd`; **pacote `dop` e executável `dop` inalterados** | Zero ruptura para os workspaces em uso e zero refactor de imports. Ver risco R-1 |
| D-4 | Versão permanece **0.7.1** | É o mesmo código; só a distribuição foi rebatizada. Reiniciar a numeração criaria uma regressão aparente |
| D-5 | **Toda a documentação** (ADRs, PRDs da era CLI, referências, arquitetura, specs e plans) acompanha o código para o `dop-cmd` | São o registro de decisão daquela implementação; separá-los do código torna ambos menos úteis |
| D-6 | `dop-cmd` mora em `repos/dop-cmd`, mas **não é submodule** do meta-repo | Faz parte do projeto e convive com os demais componentes na mesma árvore, sem ser rastreado pelo meta-repo, que agrega apenas os componentes do produto 1.0 |
| D-7 | `dop-core` **não é criado nesta rodada** | Depende da rodada de arquitetura; criar o repositório antes de decidir seu conteúdo produziria README desatualizado |

## 3. Topologia final

```
/opt/wks/dbo/dop/            meta-repo do produto
├── .gitmodules              3 entradas: dop-cli, dop-api, dop-app  (inalterado)
├── .gitignore               + repos/dop-cmd/
├── docs/                    docs de produto 1.0
├── infra/                   stack local
└── repos/
    ├── dop-cmd/             NOVO — repo git independente, remote próprio.
    │                        NÃO é submodule. Motor operacional (v0.7.1).
    ├── dop-cli/             submodule — esvaziado → esqueleto da CLI definitiva
    ├── dop-api/             submodule — inalterado
    └── dop-app/             submodule — inalterado
```

Remote do novo componente: `git@github.com:Digital-Business-One/dop-cmd.git` (privado).

## 4. Componente A — `dop-cmd`

### 4.1 Conteúdo

Cópia dos 99 arquivos versionados no `main` do `dop-cli` (`src/`, `tests/`, `docs/`,
`pyproject.toml`, `README.md`, `.gitignore`), em **commit inicial único**.

`.claude/settings.local.json` não é versionado no `dop-cli`; é copiado localmente para
preservar as preferências de sessão, sem entrar no commit.

### 4.2 Alterações sobre a cópia

| Arquivo | Mudança |
|---|---|
| `pyproject.toml` | `name = "dop"` → `name = "dop-cmd"`. `version`, `[tool.setuptools.packages.find]` e `[project.scripts] dop = "dop.cli:main"` permanecem intactos |
| `README.md` | Título e URL de instalação apontam para `dop-cmd.git`; parágrafo novo explicando a divisão `dop-cmd` × `dop-cli` e o papel de referência conceitual para a plataforma |
| `docs/adr/0015-separacao-dop-cmd-e-dop-cli.md` | ADR novo registrando esta decisão |
| `docs/adr/README.md` | Linha de índice para a ADR 0015 + nota de rodapé esclarecendo que o "ADR-16" citado em `docs/workspace-migration-adr16.md` e nas specs de superpowers é documento **do lado da workspace**, fora deste índice |

Todo o restante é copiado sem alteração.

### 4.3 Numeração da ADR

O índice de ADRs vai até 0014. Existe um "ADR-16" informal, referente ao setup de
camadas de teste da workspace Optum, que nunca entrou no índice. A nova ADR recebe
**0015** (o próximo número livre do índice) e a nota de rodapé desfaz a ambiguidade.

## 5. Componente B — `dop-cli`

Um commit removendo `src/`, `tests/`, `docs/` e `pyproject.toml`, e reescrevendo o
`README.md` no molde dos esqueletos de `dop-api` e `dop-app`:

- o que é: a **CLI definitiva do DOP**, cliente da plataforma, porta de entrada do
  Claude;
- status: 🚧 em construção (1.0 MVP);
- ponteiro explícito de que a implementação anterior vive em `dop-cmd` e continua
  acessível na história deste repositório (tags `v0.1.0`, `v0.5.0`, commit `19fa56a`).

O repositório fica com **`README.md` e `.gitignore`**, nada mais. Sem `pyproject.toml`:
o nome do executável e o protocolo de comunicação com a plataforma são decisões da
rodada de arquitetura.

**Nada de trabalho se perde:** as duas branches locais
(`feat/runtime-orchestrator-abstraction`, `fix/allure-aggregation-headed-x11`) já estão
integralmente mergeadas em `main`, e a história completa permanece no repositório.

## 6. Componente C — meta-repositório raiz

| Alvo | Mudança |
|---|---|
| `.gitmodules` | **Sem alteração.** Permanece com três entradas |
| `.gitignore` | Acrescenta `repos/dop-cmd/`, para que o novo repositório não apareça como não-rastreado nem seja confundido com submodule |
| `README.md` | Árvore de estrutura e seção **Componentes** passam a listar o `dop-cmd`, explicitando que ele é obtido por clone próprio e não por `git submodule update`. A instrução de instalação, hoje apontando para `dop-cli.git@v0.5.0`, passa a apontar para `dop-cmd`. A seção **Estado** é atualizada |
| ponteiro `repos/dop-cli` | Fixado no commit do esvaziamento (hoje já está defasado em relação ao checkout local) |

O README da raiz documenta a obtenção do componente não-submodule:

```bash
git clone git@github.com:Digital-Business-One/dop-cmd.git repos/dop-cmd
```

O PRD 1.0 (`docs/prd/dop-1.0-mvp/`) **não é reescrito** nesta rodada — recebe apenas
uma nota curta de nomenclatura. Sua revisão de conteúdo pertence à rodada de
arquitetura.

## 7. Verificação

1. **Paridade de suíte:** `pytest -p no:playwright` dentro do `dop-cmd`, comparado com
   o baseline do `dop-cli`. Espera-se resultado idêntico, incluindo a falha conhecida e
   não relacionada em PR-publish.
2. **Instalabilidade:** `pip install -e .` no `dop-cmd` gera o executável `dop`;
   `dop --version` retorna `0.7.1`.
3. **Limpeza do meta-repo:** `git status` na raiz não reporta `repos/dop-cmd` como
   não-rastreado, e `git submodule status` continua listando exatamente três submodules.
4. **Integridade do `dop-cli`:** `git log` preserva a história completa e as tags
   `v0.1.0` e `v0.5.0` continuam resolvendo.

## 8. Consequências e riscos assumidos

- **R-1 — Colisão no comando `dop`.** `dop-cmd` e a futura CLI definitiva disputam o
  mesmo executável e **não poderão coexistir no mesmo ambiente Python**. É uma escolha
  consciente, feita para não quebrar os workspaces em uso. Quando a CLI 1.0 assumir o
  nome, será em ambiente separado ou com o `dop-cmd` já aposentado.
- **R-2 — Mudança de origem de instalação.** Quem instala de `dop-cli.git` precisa
  trocar a URL para `dop-cmd.git`. O código instalado é idêntico.
- **R-3 — Clone recursivo não traz o `dop-cmd`.** Por não ser submodule, exige clone
  explícito. Mitigado pela documentação no README da raiz.
- **C-1 — Memória de sessão.** A memória que referencia "dop-cli test running" passa a
  apontar para o `dop-cmd`.

## 9. Fora de escopo

- Criação do repositório `dop-core` e definição da arquitetura núcleo/BFF.
- Revisão do PRD 1.0 à luz dos 20 prompts de ajuste e da adoção de specs.
- Revisão do modelo de etapas da demanda.
- Qualquer alteração funcional no código do `dop-cmd`.

## 10. Ordem de execução

1. Criar `Digital-Business-One/dop-cmd` (privado) e preparar `repos/dop-cmd` local com
   a cópia, as alterações da §4.2 e o commit inicial.
2. Verificação §7.1 e §7.2.
3. Publicar o `dop-cmd`.
4. Esvaziar o `dop-cli` conforme §5 e publicar.
5. Atualizar o meta-repo conforme §6, fixar os ponteiros e publicar.
6. Verificação §7.3 e §7.4; atualizar a memória de sessão (C-1).

Cada publicação é confirmada antes de acontecer.
