# dop — meta-repositório do produto

**DOP** é uma ferramenta auxiliar ao desenvolvimento de software *IA-first*, onde um
**Dev** e o agente **Claude** colaboram para conduzir demandas de ponta a ponta. Este
repositório **raiz** orquestra o produto (infra local + docs) e agrega os componentes
como repositórios independentes em `repos/`.

## Estrutura

```
dop/
├── docs/                 # docs de PRODUTO 1.0 (PRD, specs, prompt Replit, decisões)
├── infra/                # stack LOCAL do DOP (docker-compose + Dockerfiles)
└── repos/                # componentes como SUBMODULES git (repos independentes, fixados por commit)
    ├── dop-cli/          # CLI Python — congelada em v0.5.0, instalável e funcional
    ├── dop-api/          # núcleo + API HTTP (Python) — onde a lógica migra da CLI
    └── dop-app/          # frontend (React/Vite) — construído pelo Replit + Claude
```

## Clonar

Os componentes são **submodules git** (cada um fixado num commit específico). Clone
com `--recursive`:

```bash
git clone --recursive git@github.com:Digital-Business-One/dop.git
# ou, após um clone simples:
git submodule update --init --recursive
```

Para atualizar um componente ao último commit do seu `main` e fixar o novo ponteiro:

```bash
git -C repos/<componente> pull origin main
git add repos/<componente> && git commit -m "chore: bump <componente>"
```

## Componentes

- **dop-cli** (`repos/dop-cli`) — a CLI atual (v0.5.0). Permanece **instalável e
  funcionando** para os projetos que já a usam, durante toda a reestruturação 1.0.
  Instalação: `pip install 'git+ssh://git@github.com/Digital-Business-One/dop-cli.git@v0.5.0'`.
- **dop-api** (`repos/dop-api`) — núcleo do produto + API HTTP. **Única fonte de
  verdade**; acessa workspace/ferramentas e detém o estado. A lógica de negócio migra
  da CLI para cá; a CLI 1.0 vira **cliente fino** desta API.
- **dop-app** (`repos/dop-app`) — frontend onde o Dev trabalha (workspaces, demandas,
  tela de execução, chat). Mock-first; ver o prompt em
  [`docs/prd/dop-1.0-mvp/replit-frontend-prompt.md`](docs/prd/dop-1.0-mvp/replit-frontend-prompt.md).

## Documentação

- **PRD base do 1.0:** [`docs/prd/dop-1.0-mvp/README.md`](docs/prd/dop-1.0-mvp/README.md)
- **Prompt do frontend (Replit):** [`docs/prd/dop-1.0-mvp/replit-frontend-prompt.md`](docs/prd/dop-1.0-mvp/replit-frontend-prompt.md)
- Docs internos da CLI 0.5.x vivem em `repos/dop-cli/docs/` (ADRs, referências).

## Ambiente local

A stack roda **exclusivamente local** via `docker compose` (sem deploy em nuvem nem
CI/CD nesta fase). Ver [`infra/`](infra/). O `infra/docker-compose.yml` é um
**esqueleto** que será finalizado conforme as stacks de `dop-api`/`dop-app`.

## Estado

- ✅ `dop-cli` v0.5.0 (congelada, instalável).
- 🚧 `dop-api` e `dop-app` — em construção para o **1.0 (MVP)**.
