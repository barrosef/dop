# Separação `dop-cmd` × `dop-cli` — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extrair a ferramenta operacional em uso do repositório `dop-cli` para um repositório novo `dop-cmd`, deixando o `dop-cli` como esqueleto da CLI definitiva do DOP 1.0.

**Architecture:** Três repositórios são tocados. O `dop-cmd` nasce limpo com uma cópia dos arquivos versionados do `main` do `dop-cli`, mudando apenas a identidade da distribuição. O `dop-cli` é reduzido a `README.md` + `.gitignore`. O meta-repositório passa a documentar o `dop-cmd` como componente não-submodule, ignorado pelo git.

**Tech Stack:** Python 3.11+ (setuptools), git, `gh` CLI, pytest.

**Spec:** [`docs/superpowers/specs/2026-08-26-separacao-dop-cmd-dop-cli-design.md`](../specs/2026-08-26-separacao-dop-cmd-dop-cli-design.md)

## Nota sobre método

**Este plano não é TDD.** Nenhum código de produção é escrito: `src/` e `tests/` são
copiados byte a byte, sem alteração funcional. O ciclo vermelho-verde é substituído por
**verificação de paridade** — a suíte existente precisa produzir no destino exatamente o
mesmo resultado que produzia na origem. Toda tarefa termina numa checagem concreta.

## Global Constraints

- Distribuição: `dop-cmd`. Pacote Python: `dop`. Executável: `dop`. Versão: `0.7.1`.
- Nenhuma alteração funcional em `src/` ou `tests/`. Só `pyproject.toml`, `README.md` e `docs/adr/` mudam.
- Remote do novo repositório: `git@github.com:Digital-Business-One/dop-cmd.git`, **privado**.
- Caminho local do novo repositório: `/opt/wks/dbo/dop/repos/dop-cmd`.
- O `dop-cmd` **não é submodule**. `.gitmodules` da raiz permanece com **exatamente três** entradas.
- Comando de teste: `python3 -m pytest tests/ -p no:playwright` (o `-p no:playwright` é obrigatório; sem ele a coleta aborta com `ModuleNotFoundError: No module named 'playwright'`).
- Baseline esperado: **143 testes coletados**, com **uma falha conhecida e não relacionada** — `tests/test_handlers.py::TestPrPublish::test_commits_pushes_and_creates_prs` (`TypeError: Object of type MagicMock is not JSON serializable`).
- Diretório de trabalho temporário: `/tmp/claude-1000/-opt-wks-dbo-dop/18641555-f07e-4cd9-a851-9d9427340b49/scratchpad`.
- **Toda publicação (`gh repo create`, `git push`) é confirmada com o usuário antes de acontecer.**

---

### Task 1: Baseline de verificação do `dop-cli`

Captura o estado de referência **antes** de qualquer arquivo se mover. Sem isso, a
comparação de paridade da Task 3 é impossível e o esvaziamento da Task 4 é irreversível
sem consulta ao histórico.

**Files:**
- Create: `<scratchpad>/baseline-files.txt`
- Create: `<scratchpad>/baseline-pytest.txt`

**Interfaces:**
- Produces: `<scratchpad>/baseline-files.txt` (lista ordenada dos arquivos versionados) e `<scratchpad>/baseline-pytest.txt` (saída completa da suíte), consumidos pelas Tasks 2 e 3.

- [ ] **Step 1: Registrar a lista exata de arquivos versionados**

```bash
SP=/tmp/claude-1000/-opt-wks-dbo-dop/18641555-f07e-4cd9-a851-9d9427340b49/scratchpad
git -C /opt/wks/dbo/dop/repos/dop-cli ls-files | sort > "$SP/baseline-files.txt"
wc -l < "$SP/baseline-files.txt"
```

Esperado: `99`.

- [ ] **Step 2: Rodar a suíte e salvar a saída**

```bash
SP=/tmp/claude-1000/-opt-wks-dbo-dop/18641555-f07e-4cd9-a851-9d9427340b49/scratchpad
cd /opt/wks/dbo/dop/repos/dop-cli
python3 -m pytest tests/ -p no:playwright 2>&1 | tee "$SP/baseline-pytest.txt" | tail -5
```

- [ ] **Step 3: Conferir que o baseline bate com o esperado**

```bash
SP=/tmp/claude-1000/-opt-wks-dbo-dop/18641555-f07e-4cd9-a851-9d9427340b49/scratchpad
grep -E "^(FAILED|ERROR)" "$SP/baseline-pytest.txt"
tail -1 "$SP/baseline-pytest.txt"
```

Esperado: exatamente uma linha `FAILED tests/test_handlers.py::TestPrPublish::test_commits_pushes_and_creates_prs`, e um resumo do tipo `1 failed, 142 passed`.

Se aparecer **mais de uma** falha, **pare** e reporte ao usuário antes de seguir — o
baseline precisa ser conhecido para que a paridade signifique alguma coisa.

- [ ] **Step 4: Confirmar o ponto de partida do git**

```bash
git -C /opt/wks/dbo/dop/repos/dop-cli log --oneline -1
git -C /opt/wks/dbo/dop/repos/dop-cli status --short
```

Esperado: `19fa56a chore: bump version to 0.7.1` e árvore limpa. Se houver modificações
não commitadas, **pare** e reporte — elas se perderiam no esvaziamento.

Sem commit nesta tarefa: nada no repositório mudou.

---

### Task 2: Materializar `repos/dop-cmd`

Cria o repositório local completo — cópia, identidade nova e a ADR que registra a
decisão — num **commit inicial único**, conforme §4.1 da spec.

**Files:**
- Create: `repos/dop-cmd/**` (99 arquivos, cópia do `main` do `dop-cli`)
- Modify: `repos/dop-cmd/pyproject.toml`
- Modify: `repos/dop-cmd/README.md`
- Create: `repos/dop-cmd/docs/adr/0015-separacao-dop-cmd-e-dop-cli.md`
- Modify: `repos/dop-cmd/docs/adr/README.md`

**Interfaces:**
- Consumes: `<scratchpad>/baseline-files.txt` (Task 1), para conferir paridade de arquivos.
- Produces: repositório git em `/opt/wks/dbo/dop/repos/dop-cmd` com um commit, branch `main`, sem remote.

- [ ] **Step 1: Extrair os arquivos versionados**

`git archive` entrega exatamente os arquivos rastreados no `main`, sem `.git`, sem
`.pytest_cache`, sem `.venv`.

```bash
mkdir -p /opt/wks/dbo/dop/repos/dop-cmd
git -C /opt/wks/dbo/dop/repos/dop-cli archive main | tar -x -C /opt/wks/dbo/dop/repos/dop-cmd
```

- [ ] **Step 2: Copiar as preferências locais e mantê-las fora do versionamento**

O `.gitignore` herdado do `dop-cli` cobre `__pycache__/`, `*.pyc`, `.venv/`, `dist/`,
`*.egg-info/` e `.env` — **não cobre `.claude/`**. Como a spec (§4.1) determina que
`settings.local.json` seja copiado *sem entrar no commit*, a regra de exclusão precisa
ser criada aqui; sem ela o `git add -A` do Step 9 versionaria o arquivo.

```bash
mkdir -p /opt/wks/dbo/dop/repos/dop-cmd/.claude
cp /opt/wks/dbo/dop/repos/dop-cli/.claude/settings.local.json \
   /opt/wks/dbo/dop/repos/dop-cmd/.claude/settings.local.json
printf '.claude/\n' >> /opt/wks/dbo/dop/repos/dop-cmd/.gitignore
tail -2 /opt/wks/dbo/dop/repos/dop-cmd/.gitignore
```

Esperado: a última linha do `.gitignore` é `.claude/`.

- [ ] **Step 3: Conferir paridade de arquivos com o baseline**

```bash
SP=/tmp/claude-1000/-opt-wks-dbo-dop/18641555-f07e-4cd9-a851-9d9427340b49/scratchpad
cd /opt/wks/dbo/dop/repos/dop-cmd
find . -type f -not -path './.claude/*' | sed 's|^\./||' | sort > "$SP/copied-files.txt"
diff "$SP/baseline-files.txt" "$SP/copied-files.txt" && echo "PARIDADE OK"
```

Esperado: `PARIDADE OK`, sem nenhuma linha de diferença.

- [ ] **Step 4: Inicializar o repositório**

```bash
cd /opt/wks/dbo/dop/repos/dop-cmd
git init -q -b main
```

- [ ] **Step 5: Ajustar o nome da distribuição no `pyproject.toml`**

Trocar a linha `name = "dop"` por `name = "dop-cmd"`. Nada mais no arquivo muda —
`version`, `[tool.setuptools.packages.find]` e `[project.scripts]` ficam intactos.

```bash
cd /opt/wks/dbo/dop/repos/dop-cmd
sed -i 's/^name = "dop"$/name = "dop-cmd"/' pyproject.toml
grep -n 'name = \|^version\|^dop = ' pyproject.toml
```

Esperado:
```
name = "dop-cmd"
version = "0.7.1"
dop = "dop.cli:main"
```

- [ ] **Step 6: Reescrever o cabeçalho do `README.md`**

Substituir as **nove primeiras linhas** do arquivo — de `# dop` (linha 1) até a crase
tripla que fecha o bloco `pip install` (linha 9), inclusive — por:

```markdown
# dop-cmd

DevOps Pipeline CLI - IA-First development workflow, multi-workspace, multi-platform.

Ferramenta operacional do DOP: **responde pelo ambiente**. Acessa a workspace
diretamente e executa operações git, PRs multi-plataforma, runtime docker-compose,
testes e2e/AAA e relatórios Allure.

> **`dop-cmd` × `dop-cli`.** Este repositório é a ferramenta em uso hoje — estável,
> instalável e mantida. O repositório `dop-cli` foi reservado para a **CLI definitiva**
> do DOP 1.0, que não acessa a workspace e conversa com a plataforma. Enquanto a
> plataforma é construída, o `dop-cmd` segue como ferramenta de trabalho e como
> **referência conceitual** do domínio: o que o DOP faz, validado em produção.
>
> A distribuição chama-se `dop-cmd`, mas o pacote Python e o executável continuam
> sendo `dop`. Por isso `dop-cmd` e a futura `dop-cli` **não podem ser instalados no
> mesmo ambiente Python**.

## Install

```bash
pip install git+ssh://git@github.com/Digital-Business-One/dop-cmd.git
```
```

Conferir que o resto do README (`## Configuration` em diante) permaneceu intacto:

```bash
cd /opt/wks/dbo/dop/repos/dop-cmd
grep -c '' README.md && grep -n '^## ' README.md
```

Esperado: as seções `## Install`, `## Configuration`, `## CLI Commands`, `## Plan branch
table requirement`, `## Multi-platform support` e `## Auth methods` continuam presentes,
nessa ordem.

- [ ] **Step 7: Escrever a ADR 0015**

Criar `docs/adr/0015-separacao-dop-cmd-e-dop-cli.md` com o conteúdo abaixo. O formato
segue as ADRs existentes (MADR: Contexto / Decisão / Consequências).

```markdown
# ADR-0015 — Separação `dop-cmd` (ferramenta de ambiente) e `dop-cli` (CLI definitiva)

- **Status:** Aceito
- **Data:** 2026-08-26
- **Spec:** `docs/superpowers/specs/2026-08-26-separacao-dop-cmd-dop-cli-design.md` (meta-repositório `dop`)

## Contexto

O repositório `dop-cli` acumulava **dois papéis sobrepostos**:

1. A **ferramenta operacional em uso** (v0.7.1) — esta base de código, que acessa a
   workspace diretamente e responde pelo ambiente.
2. O **nome reservado para a CLI definitiva** do DOP 1.0, que segundo o PRD deixa de
   acessar a workspace e passa a ser cliente da plataforma.

Com os dois papéis no mesmo repositório, construir a CLI definitiva significava mexer
no repositório de uma ferramenta em produção, e qualquer conversa sobre "o dop-cli"
era ambígua.

Em paralelo, a arquitetura do 1.0 foi redirecionada para uma plataforma com núcleo
gRPC (`dop-core`) e BFF multiprotocolo (`dop-api`), com persistência em banco. Isso
mudou o papel desta base de código: **ela deixa de ser o ancestral do qual o núcleo
seria extraído e passa a ser referência conceitual** — o acervo de conhecimento
operacional validado que informa o desenho da plataforma.

## Decisão

1. **Mover** esta implementação para um repositório próprio, `dop-cmd`. O nome é mais
   apropriado ao papel: *comando de ambiente*, não interface de um cliente.
2. **Esvaziar** o `dop-cli`, que passa a ser o esqueleto da CLI definitiva.
3. **Nascer limpo:** o `dop-cmd` recebe os arquivos do `main` do `dop-cli` num commit
   inicial único. A história de decisão permanece acessível no `dop-cli` (tags
   `v0.1.0`, `v0.5.0` e commit `19fa56a`).
4. **Preservar a identidade de execução:** a distribuição passa a chamar-se `dop-cmd`,
   mas o **pacote Python e o executável continuam `dop`**, e a versão continua `0.7.1`.
   Nenhum workspace em uso precisa mudar de comando.
5. **Não ser submodule** do meta-repositório: o `dop-cmd` mora em `repos/dop-cmd` e
   convive com os demais componentes, mas o meta-repo agrega apenas os componentes do
   produto 1.0.

## Consequências

- ➕ A CLI definitiva pode ser construída do zero sem colocar em risco a ferramenta em
  produção.
- ➕ Cada nome passa a designar um papel só; some a ambiguidade de "o dop-cli".
- ➕ Zero ruptura operacional: `dop <subcomando>` continua funcionando como antes.
- ➖ `dop-cmd` e a futura `dop-cli` disputam o executável `dop` e **não podem coexistir
  no mesmo ambiente Python**. Quando a CLI 1.0 assumir o nome, será em ambiente
  separado ou com o `dop-cmd` já aposentado.
- ➖ Quem instalava de `dop-cli.git` precisa trocar a origem para `dop-cmd.git`.
- ➖ Por não ser submodule, o `dop-cmd` não vem no clone recursivo do meta-repositório;
  exige clone explícito, documentado no README da raiz.
```

- [ ] **Step 8: Acrescentar a ADR ao índice**

Em `docs/adr/README.md`, adicionar a linha da 0015 ao final da tabela, logo após a
linha da 0014:

```markdown
| [0015](0015-separacao-dop-cmd-e-dop-cli.md) | Separação `dop-cmd` (ferramenta de ambiente) e `dop-cli` (CLI definitiva) | Aceito |
```

E acrescentar, ao bloco de citação "Nota de proveniência" que já existe no topo do
arquivo, uma linha final esclarecendo a numeração:

```markdown
> O "ADR-16" citado em `docs/workspace-migration-adr16.md` e nas specs de
> `docs/superpowers/` é um documento **do lado da workspace**, fora deste índice.
```

Conferir:

```bash
cd /opt/wks/dbo/dop/repos/dop-cmd
tail -3 docs/adr/README.md
ls docs/adr/0015-*.md
```

- [ ] **Step 9: Commit inicial único**

```bash
cd /opt/wks/dbo/dop/repos/dop-cmd
git add -A
git status --short | wc -l
git commit -q -F - <<'MSG'
chore: importa a CLI operacional do dop-cli como dop-cmd (v0.7.1)

Cópia do main do dop-cli em commit inicial único. Só a identidade da
distribuição muda: name = "dop-cmd" no pyproject; pacote e executável
continuam sendo `dop`, versão 0.7.1. Registra a decisão na ADR-0015.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
git log --oneline
git ls-files | wc -l
```

Esperado: um único commit e **100 arquivos versionados** — os 99 do baseline mais a
ADR-0015. O `.claude/settings.local.json` fica de fora pela regra acrescentada no
Step 2, e o `.gitignore` continua contando como um dos 99 (foi modificado, não criado).

- [ ] **Step 10: Conferir que nenhum arquivo indesejado entrou**

```bash
cd /opt/wks/dbo/dop/repos/dop-cmd
git ls-files | grep -E '\.venv/|__pycache__|\.pytest_cache|settings\.local\.json' && echo "PROBLEMA: arquivo indesejado versionado" || echo "LIMPO"
```

Esperado: `LIMPO`.

Se `settings.local.json` aparecer versionado, o Step 2 não acrescentou `.claude/` ao
`.gitignore`. Corrigir: `git rm --cached .claude/settings.local.json`, acrescentar a
linha ao `.gitignore` e emendar o commit com `git commit -q --amend --no-edit`.

---

### Task 3: Verificar e publicar o `dop-cmd`

Prova de que a cópia é funcionalmente idêntica, e só então publicação.

**Files:**
- Create: `repos/dop-cmd/.venv/` (ambiente descartável, coberto pelo `.gitignore`)

**Interfaces:**
- Consumes: `<scratchpad>/baseline-pytest.txt` (Task 1); repositório da Task 2.
- Produces: repositório publicado em `git@github.com:Digital-Business-One/dop-cmd.git`, branch `main`.

- [ ] **Step 1: Rodar a suíte no `dop-cmd`**

```bash
SP=/tmp/claude-1000/-opt-wks-dbo-dop/18641555-f07e-4cd9-a851-9d9427340b49/scratchpad
cd /opt/wks/dbo/dop/repos/dop-cmd
python3 -m pytest tests/ -p no:playwright 2>&1 | tee "$SP/dopcmd-pytest.txt" | tail -5
```

- [ ] **Step 2: Comparar com o baseline**

```bash
SP=/tmp/claude-1000/-opt-wks-dbo-dop/18641555-f07e-4cd9-a851-9d9427340b49/scratchpad
diff <(grep -E "^(FAILED|ERROR)" "$SP/baseline-pytest.txt") \
     <(grep -E "^(FAILED|ERROR)" "$SP/dopcmd-pytest.txt") && echo "FALHAS IDÊNTICAS"
diff <(tail -1 "$SP/baseline-pytest.txt" | sed 's/in [0-9.]*s//') \
     <(tail -1 "$SP/dopcmd-pytest.txt"   | sed 's/in [0-9.]*s//') && echo "RESUMO IDÊNTICO"
```

Esperado: `FALHAS IDÊNTICAS` e `RESUMO IDÊNTICO`. Qualquer divergência **interrompe** o
plano — significa que a cópia não é fiel.

- [ ] **Step 3: Verificar instalabilidade e o executável**

```bash
cd /opt/wks/dbo/dop/repos/dop-cmd
python3 -m venv .venv
./.venv/bin/pip install -q -e . 2>&1 | tail -3
./.venv/bin/dop --version
./.venv/bin/pip show dop-cmd | grep -E '^(Name|Version)'
```

Esperado: `dop --version` imprime `0.7.1`; `pip show` reporta `Name: dop-cmd`,
`Version: 0.7.1`. Isso prova a decisão D-3: distribuição rebatizada, executável intacto.

- [ ] **Step 4: Confirmar a publicação com o usuário**

Apresentar ao usuário: nome do repositório, visibilidade e o que será empurrado
(1 commit, 100 arquivos). **Aguardar o "pode ir" antes do próximo passo.**

- [ ] **Step 5: Criar o repositório no GitHub**

```bash
gh repo create Digital-Business-One/dop-cmd --private \
  --description "DOP — ferramenta operacional de ambiente (CLI Python, v0.7.1)"
```

- [ ] **Step 6: Empurrar**

```bash
cd /opt/wks/dbo/dop/repos/dop-cmd
git remote add origin git@github.com:Digital-Business-One/dop-cmd.git
git push -u origin main
```

- [ ] **Step 7: Conferir a publicação**

```bash
gh repo view Digital-Business-One/dop-cmd --json name,visibility,defaultBranchRef \
  | python3 -m json.tool
git -C /opt/wks/dbo/dop/repos/dop-cmd status -sb | head -1
```

Esperado: `"visibility": "PRIVATE"`, branch padrão `main`, e o status local
mostrando `## main...origin/main` sem divergência.

---

### Task 4: Esvaziar e publicar o `dop-cli`

**Files:**
- Delete: `repos/dop-cli/src/`, `repos/dop-cli/tests/`, `repos/dop-cli/docs/`, `repos/dop-cli/pyproject.toml`
- Modify: `repos/dop-cli/README.md`

**Interfaces:**
- Consumes: publicação do `dop-cmd` (Task 3) — o esvaziamento só é seguro depois que a cópia está publicada.
- Produces: `dop-cli` com dois arquivos versionados, história e tags preservadas.

- [ ] **Step 1: Confirmar que o `dop-cmd` já está publicado**

```bash
git -C /opt/wks/dbo/dop/repos/dop-cmd ls-remote --exit-code origin main >/dev/null \
  && echo "dop-cmd publicado, seguro esvaziar" \
  || echo "PARE: dop-cmd ainda não publicado"
```

Se imprimir `PARE`, voltar à Task 3.

- [ ] **Step 2: Remover o conteúdo migrado**

```bash
cd /opt/wks/dbo/dop/repos/dop-cli
git rm -r -q src tests docs pyproject.toml
git status --short | head
```

- [ ] **Step 3: Reescrever o `README.md`**

Substituir o arquivo inteiro por:

```markdown
# dop-cli — CLI definitiva do DOP

Porta de entrada do **Claude** para a plataforma DOP. **Não acessa a workspace
diretamente**: traduz cada comando `dop ...` em chamadas à plataforma, que executa as
operações e detém o estado.

- **Papel:** cliente da plataforma. Nunca tem capacidade que a plataforma não tenha.
- **Protocolo e stack:** a definir na rodada de arquitetura (núcleo `dop-core` + BFF
  `dop-api`).
- **Ergonomia:** requisito do Dev; implementação do Claude.

## Implementação anterior

Até agosto de 2026 este repositório continha a **ferramenta operacional em uso**
(v0.7.1) — a CLI que acessa a workspace diretamente. Ela foi movida para
**[`dop-cmd`](https://github.com/Digital-Business-One/dop-cmd)**, onde segue instalável
e mantida:

```bash
pip install git+ssh://git@github.com/Digital-Business-One/dop-cmd.git
```

O código anterior permanece acessível na história **deste** repositório: tags `v0.1.0`
e `v0.5.0`, e o commit `19fa56a` (último estado antes do esvaziamento). Os ADRs e a
documentação daquela implementação viajaram junto com o código, e vivem em
`dop-cmd/docs/`.

Ver a decisão em `ADR-0015` (`dop-cmd/docs/adr/0015-separacao-dop-cmd-e-dop-cli.md`).

Status: 🚧 em construção (1.0 MVP).
```

- [ ] **Step 4: Conferir que só sobraram dois arquivos**

```bash
cd /opt/wks/dbo/dop/repos/dop-cli
git add -A
git ls-files
```

Esperado, exatamente:
```
.gitignore
README.md
```

- [ ] **Step 5: Commit**

```bash
cd /opt/wks/dbo/dop/repos/dop-cli
git commit -q -F - <<'MSG'
chore!: esvazia o dop-cli; implementação migra para dop-cmd

A ferramenta operacional (v0.7.1) foi movida para o repositório dop-cmd.
Este repositório passa a ser o esqueleto da CLI definitiva do 1.0, cliente
da plataforma. A história e as tags v0.1.0/v0.5.0 permanecem aqui; o último
estado da implementação anterior é o commit 19fa56a.

Ver ADR-0015 em dop-cmd/docs/adr/.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
git log --oneline -2
```

- [ ] **Step 6: Confirmar a publicação com o usuário**

Este push é o passo de maior impacto do plano — remove 97 arquivos do `main` de um
repositório publicado. **Aguardar confirmação explícita.**

- [ ] **Step 7: Empurrar**

```bash
git -C /opt/wks/dbo/dop/repos/dop-cli push origin main
```

- [ ] **Step 8: Conferir que a história e as tags sobreviveram**

```bash
cd /opt/wks/dbo/dop/repos/dop-cli
git log --oneline | wc -l
git tag -l
git cat-file -t 19fa56a
git show --stat 19fa56a | head -3
```

Esperado: contagem de commits maior que 30 (nada foi reescrito); tags `v0.1.0` e
`v0.5.0` presentes; `19fa56a` resolve como `commit`.

---

### Task 5: Atualizar e publicar o meta-repositório

**Files:**
- Modify: `/opt/wks/dbo/dop/.gitignore`
- Modify: `/opt/wks/dbo/dop/README.md`

**Interfaces:**
- Consumes: `dop-cmd` publicado (Task 3) e `dop-cli` esvaziado e publicado (Task 4).
- Produces: meta-repositório com ponteiro de submodule atualizado e `repos/dop-cmd` ignorado.

- [ ] **Step 1: Ignorar o `repos/dop-cmd`**

Acrescentar ao final do `.gitignore` da raiz:

```
# dop-cmd é componente do projeto, mas NÃO é submodule deste meta-repositório.
# Obtenha-o com: git clone git@github.com:Digital-Business-One/dop-cmd.git repos/dop-cmd
repos/dop-cmd/
```

Conferir que ele some do status:

```bash
cd /opt/wks/dbo/dop
git status --short | grep dop-cmd && echo "PROBLEMA: ainda aparece" || echo "IGNORADO OK"
```

Esperado: `IGNORADO OK`.

- [ ] **Step 2: Atualizar a árvore de estrutura no `README.md`**

Substituir o bloco das linhas 14–17 por:

```
└── repos/                # componentes do produto
    ├── dop-cmd/          # ferramenta operacional em uso (v0.7.1) — NÃO é submodule
    ├── dop-cli/          # CLI definitiva do 1.0 (submodule) — em construção
    ├── dop-api/          # API do produto (submodule) — em construção
    └── dop-app/          # frontend (React/Vite) (submodule) — construído pelo Replit + Claude
```

- [ ] **Step 3: Documentar a obtenção do `dop-cmd` na seção `## Clonar`**

Acrescentar ao final da seção (logo antes de `## Componentes`):

```markdown
O **`dop-cmd` não é submodule** e por isso **não vem no clone recursivo**. Obtenha-o
separadamente:

```bash
git clone git@github.com:Digital-Business-One/dop-cmd.git repos/dop-cmd
```
```

- [ ] **Step 4: Reescrever as entradas de `## Componentes`**

Substituir as três linhas da entrada `dop-cli` (linhas 40–42) por estas duas entradas,
mantendo `dop-api` e `dop-app` inalterados:

```markdown
- **dop-cmd** (`repos/dop-cmd`) — a **ferramenta operacional em uso** (v0.7.1). Acessa
  a workspace diretamente e responde pelo ambiente: git/PR multi-plataforma, runtime
  docker-compose, e2e/AAA e Allure. Permanece instalável e mantida durante toda a
  construção do 1.0, e serve de **referência conceitual** para a plataforma.
  **Não é submodule** — ver [Clonar](#clonar).
  Instalação: `pip install 'git+ssh://git@github.com/Digital-Business-One/dop-cmd.git'`.
- **dop-cli** (`repos/dop-cli`) — a **CLI definitiva** do 1.0, cliente da plataforma e
  porta de entrada do Claude. Não acessa a workspace. Em construção.
```

> Nota para quem executa: a descrição de `dop-api` ("núcleo do produto + API HTTP,
> única fonte de verdade") ficará desatualizada quando ele virar BFF sobre o
> `dop-core`. **Não a altere aqui** — está fora do escopo desta spec e pertence à
> rodada de arquitetura.

- [ ] **Step 5: Corrigir o ponteiro de docs internos**

Na seção `## Documentação`, trocar a linha:

```markdown
- Docs internos da CLI 0.5.x vivem em `repos/dop-cli/docs/` (ADRs, referências).
```

por:

```markdown
- Docs internos da ferramenta operacional (ADRs, referências, arquitetura) vivem em
  `repos/dop-cmd/docs/`.
```

- [ ] **Step 6: Atualizar a seção `## Estado`**

Substituir as duas linhas por:

```markdown
- ✅ `dop-cmd` v0.7.1 — ferramenta operacional em uso, instalável e mantida.
- 🚧 `dop-cli`, `dop-api` e `dop-app` — em construção para o **1.0 (MVP)**.
```

- [ ] **Step 7: Fixar o ponteiro do submodule e conferir**

```bash
cd /opt/wks/dbo/dop
git add .gitignore README.md repos/dop-cli
git status --short
git diff --cached --stat
```

Esperado: três caminhos no índice — `.gitignore`, `README.md` e `repos/dop-cli`.
`repos/dop-cmd` **não** deve aparecer.

- [ ] **Step 8: Conferir que os submodules continuam sendo três**

```bash
cd /opt/wks/dbo/dop
git config -f .gitmodules --get-regexp path
git submodule status
```

Esperado: exatamente três entradas — `dop-cli`, `dop-api`, `dop-app`. Se `dop-cmd`
aparecer, algum passo o adicionou por engano: desfazer com
`git rm --cached repos/dop-cmd` e conferir o `.gitignore`.

- [ ] **Step 9: Commit**

```bash
cd /opt/wks/dbo/dop
git commit -q -F - <<'MSG'
chore: registra o dop-cmd como componente não-submodule

Acrescenta repos/dop-cmd ao .gitignore, documenta sua obtenção por clone
próprio e atualiza estrutura, componentes e estado no README. Fixa o
ponteiro do submodule dop-cli no commit do esvaziamento.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
git log --oneline -3
```

- [ ] **Step 10: Confirmar e empurrar**

Confirmar com o usuário e então:

```bash
git -C /opt/wks/dbo/dop push origin main
```

---

### Task 6: Verificação final e atualização da memória

**Files:**
- Modify: `/home/edbarros/.claude/projects/-opt-wks-dbo-dop/memory/dop-cli-test-running.md` → renomeado para `dop-cmd-test-running.md`
- Modify: `/home/edbarros/.claude/projects/-opt-wks-dbo-dop/memory/MEMORY.md`

**Interfaces:**
- Consumes: estado final das Tasks 3, 4 e 5.

- [ ] **Step 1: Verificação §7.3 — limpeza do meta-repositório**

```bash
cd /opt/wks/dbo/dop
git status --short
git submodule status | wc -l
```

Esperado: nenhuma linha mencionando `repos/dop-cmd`; contagem de submodules igual a `3`.
(Os não-rastreados `docs/dop-screenshot.png` e `docs/prompts/` podem permanecer —
estão fora do escopo desta spec.)

- [ ] **Step 2: Verificação §7.4 — integridade do `dop-cli`**

```bash
cd /opt/wks/dbo/dop/repos/dop-cli
git ls-files
git tag -l
git log --oneline -1
```

Esperado: só `.gitignore` e `README.md`; tags `v0.1.0` e `v0.5.0` presentes; HEAD no
commit do esvaziamento.

- [ ] **Step 3: Verificação cruzada — o `dop-cmd` continua funcional**

```bash
cd /opt/wks/dbo/dop/repos/dop-cmd
./.venv/bin/dop --version
python3 -m pytest tests/ -p no:playwright 2>&1 | tail -1
```

Esperado: `0.7.1` e o mesmo resumo do baseline (`1 failed, 142 passed`).

- [ ] **Step 4: Reescrever a memória de projeto**

Criar `/home/edbarros/.claude/projects/-opt-wks-dbo-dop/memory/dop-cmd-test-running.md`:

```markdown
---
name: dop-cmd-test-running
description: How to run the dop-cmd (repos/dop-cmd) Python test suite without the pytest-playwright collection error
metadata:
  type: project
---

In `/opt/wks/dbo/dop/repos/dop-cmd`, run tests with `python3 -m pytest tests/ -p no:playwright`.

**Why:** the `pytest-playwright` plugin auto-loads and fails at COLLECTION with
`ModuleNotFoundError: No module named 'playwright'` (playwright isn't installed in the
host venv), which aborts the whole run before any test executes. `-p no:playwright`
disables that plugin so the pure-Python unit tests run.

**How to apply:** always append `-p no:playwright` when running pytest here. Green
baseline is 143 collected, "all pass except one": the PRE-EXISTING unrelated failure
`tests/test_handlers.py::TestPrPublish::test_commits_pushes_and_creates_prs`
(`TypeError: Object of type MagicMock is not JSON serializable`). The relevant unit
files are `test_config_schema_v05.py`, `test_runtime_handlers.py`, `test_cli_parsing.py`.

This suite lived in `repos/dop-cli` until 2026-08-26; that repository is now the empty
skeleton of the 1.0 thin client and has no tests.
```

Remover o arquivo antigo:

```bash
rm /home/edbarros/.claude/projects/-opt-wks-dbo-dop/memory/dop-cli-test-running.md
```

- [ ] **Step 5: Atualizar o índice de memória**

Em `MEMORY.md`, trocar a linha existente por:

```markdown
- [dop-cmd test running](dop-cmd-test-running.md) — run pytest with `-p no:playwright`; 143 tests, one known unrelated PR-publish failure
```

- [ ] **Step 6: Relatório final ao usuário**

Reportar: URL do `dop-cmd`, resultado da paridade de testes, contagem de arquivos em
cada repositório e os três commits criados. Mencionar explicitamente o risco R-1
(colisão futura no comando `dop`) e o R-2 (mudança da origem de instalação para quem
já usa a ferramenta).

---

## Cobertura da spec

| Seção da spec | Tarefa |
|---|---|
| §4.1 Conteúdo do `dop-cmd` | Task 2, steps 1–3 |
| §4.2 Alterações sobre a cópia | Task 2, steps 5–8 |
| §4.3 Numeração da ADR | Task 2, steps 7–8 |
| §5 Esqueleto do `dop-cli` | Task 4, steps 2–5 |
| §6 Meta-repositório raiz | Task 5, steps 1–9 |
| §7.1 Paridade de suíte | Task 1 steps 2–3; Task 3 steps 1–2 |
| §7.2 Instalabilidade | Task 3, step 3 |
| §7.3 Limpeza do meta-repo | Task 5 step 8; Task 6 step 1 |
| §7.4 Integridade do `dop-cli` | Task 4 step 8; Task 6 step 2 |
| §8 C-1 Memória de sessão | Task 6, steps 4–5 |
| §10 Ordem de execução | Ordem das tarefas 1 → 6 |
