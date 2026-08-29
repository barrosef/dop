# Separação `dop-cmd` × `dop-cli`

> **Status:** Aprovado para implementação
> **Data:** 2026-08-26
> **Escopo:** meta-repositório `dop`, repositório `dop-cli`, novo repositório `dop-cmd`
> **Não-escopo:** qualquer decisão sobre a plataforma DOP, que é outro projeto

## 1. Contexto e motivação

O repositório `dop-cli` contém hoje **duas coisas sobrepostas**:

1. A **ferramenta operacional em uso** (v0.7.1) — uma CLI Python que acessa a workspace
   diretamente e responde pelo ambiente: operações git, PRs multi-plataforma, runtime
   docker-compose, testes e2e/AAA, relatórios Allure e máquina de estado por demanda.
   É usada diariamente em workspaces reais.
2. O **nome `dop-cli`**, que pertence ao projeto da plataforma DOP e precisa estar
   livre para ele.

Manter as duas identidades no mesmo repositório impede que a CLI da plataforma seja
construída sem colocar em risco a ferramenta em produção, e torna ambígua qualquer
conversa sobre "o dop-cli".

A separação resolve isso devolvendo cada nome ao seu projeto:

- **`dop-cmd`** — a ferramenta que responde pelo ambiente. **Projeto próprio**, com
  ciclo de vida independente.
- **`dop-cli`** — o nome volta a ficar disponível para a plataforma DOP.

> **Os dois projetos são distintos.** O `dop-cmd` originou a ideia da plataforma, mas
> não é seu ancestral técnico nem referência de desenho. Nada nesta spec decide coisa
> alguma sobre a plataforma, e a plataforma não herda nada daqui.

O nome `dop-cmd` é mais apropriado para o primeiro papel: *comando* de ambiente, não
*interface de linha de comando de um cliente*.

## 2. Decisões

| # | Decisão | Justificativa |
|---|---|---|
| D-1 | `dop-cmd` nasce **limpo**, com o código copiado do `main` do `dop-cli` em commit inicial único | A história de decisão continua acessível no `dop-cli`; um começo limpo evita arrastar tags e branches que já não descrevem o novo papel |
| D-2 | `dop-cli` é **esvaziado**, ficando só com um marcador | Devolve o nome ao outro projeto sem perder a história, que permanece no próprio repositório |
| D-3 | Distribuição `dop-cmd`; **pacote `dop` e executável `dop` inalterados** | Zero ruptura para os workspaces em uso e zero refactor de imports. Ver risco R-1 |
| D-4 | Versão permanece **0.7.1** | É o mesmo código; só a distribuição foi rebatizada. Reiniciar a numeração criaria uma regressão aparente |
| D-5 | **Toda a documentação** (ADRs, PRDs da era CLI, referências, arquitetura, specs e plans) acompanha o código para o `dop-cmd` | São o registro de decisão daquela implementação; separá-los do código torna ambos menos úteis |
| D-6 | `dop-cmd` mora em `repos/dop-cmd`, mas **não é submodule** do meta-repo | Faz parte do projeto e convive com os demais componentes na mesma árvore, sem ser rastreado pelo meta-repo, que agrega apenas os componentes do produto 1.0 |

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
    ├── dop-cli/             submodule — esvaziado; nome devolvido à plataforma
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
| `README.md` | Título e URL de instalação apontam para `dop-cmd.git`; parágrafo novo explicando que `dop-cmd` é projeto próprio e que o nome `dop-cli` pertence a outro projeto |
| `docs/adr/0015-separacao-dop-cmd-e-dop-cli.md` | ADR novo registrando esta decisão |
| `docs/adr/README.md` | Linha de índice para a ADR 0015 + nota de rodapé esclarecendo que o "ADR-16" citado em `docs/workspace-migration-adr16.md` e nas specs de superpowers é documento **do lado da workspace**, fora deste índice |

Todo o restante é copiado sem alteração.

### 4.3 Numeração da ADR

O índice de ADRs vai até 0014. Existe um "ADR-16" informal, referente ao setup de
camadas de teste da workspace Optum, que nunca entrou no índice. A nova ADR recebe
**0015** (o próximo número livre do índice) e a nota de rodapé desfaz a ambiguidade.

## 5. Componente B — `dop-cli`

Um commit removendo `src/`, `tests/`, `docs/` e `pyproject.toml`, e reescrevendo o
`README.md` para um marcador curto: o repositório está reservado para a CLI da
plataforma DOP, ainda não tem implementação, e a ferramenta que antes vivia aqui
mudou-se para o projeto `dop-cmd`.

O repositório fica com **`README.md` e `.gitignore`**, nada mais. Sem `pyproject.toml`:
o conteúdo do `dop-cli` é assunto do projeto da plataforma, não desta spec.

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

A documentação da plataforma DOP (`docs/prd/`, `docs/superpowers/`) **não é tocada**:
pertence a outro projeto.

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

- **R-1 — Colisão no comando `dop`.** `dop-cmd` e a futura CLI da plataforma disputam o
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

- **Tudo o que diz respeito à plataforma DOP** — arquitetura, componentes, contrato,
  identidade, modelo de trabalho. É outro projeto, com specs próprias.
- O conteúdo futuro do repositório `dop-cli`.
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
