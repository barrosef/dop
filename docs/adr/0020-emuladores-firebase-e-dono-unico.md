# ADR-0020 — Emuladores Firebase no ambiente local; Terraform como dono único

- **Status:** Aceita
- **Data:** 2026-08-30
- **Refina:** a spec `dop-infra` (substitui o MinIO no ambiente local)

## Contexto

O ambiente local precisa de identidade e de armazenamento de objetos. A proposta inicial
era emulador Firebase para Auth e **MinIO** para objetos — dois clientes diferentes
(S3 local × GCS em produção), duas semânticas de URL assinada, e o risco clássico de
"funciona local, quebra na nuvem".

A experiência de um projeto irmão trouxe duas lições caras, ambas incorporadas aqui.

## Decisão

**1. Emulator Suite do Firebase cobre Auth e Storage no local.** Mesmo SDK que a
produção, resolvido por variável de ambiente. O MinIO deixa de entrar agora; fica como
terceiro adaptador da porta `ObjectStore` quando existir cliente self-hosted sem GCP.
`functions`, `pubsub` e `eventarc` estão disponíveis no mesmo emulador se algum caso
surgir — capacidade latente, não componente (nossa mensageria é NATS e o worker é o core).

**2. Persistência entre reinícios** — o combo que funciona:
- `--export-on-exit <dir>` **mais** `--import <dir>` **condicional** (só passa a flag se o
  diretório existir; senão o primeiro start falha);
- **`stop_grace_period: 30s`** no container — sem isso o SIGKILL chega antes de o export
  terminar e os dados se perdem justamente ao parar;
- `reset` remove o diretório **via container** (ele nasce root-owned e o usuário não
  consegue apagar).

**3. A configuração do emulador é a mesma do deploy.** `firebase.json`, `.firebaserc` e
as rules ficam **versionados no repositório** e são montados **read-only** no emulador —
os mesmos arquivos que o deploy usa. Emulador com configuração própria mente sobre a
produção.

**4. Ponte de variáveis de ambiente.** O SDK do Cloud Storage lê `STORAGE_EMULATOR_HOST`;
o Firebase CLI expõe `FIREBASE_STORAGE_EMULATOR_HOST`. **A aplicação faz a ponte no
boot** — sem isso, upload local vai para o bucket real.

**5. Terraform é dono único do que ele gerencia.** Recursos criados pelo console ou pela
CLI ficam fora do state e são revertidos ou apagados no `apply` seguinte — perda de
feature silenciosa, já observada em projeto irmão. Regra: **nada é criado pelo console**;
o que a CLI do Firebase publica (rules, índices) vive em arquivos versionados que o
Terraform referencia ou importa; onde a fronteira for ambígua (ex.: providers de Auth),
o `README` do `dop-infra` declara **um só dono** por recurso, numa tabela explícita.

## Consequências

- ➕ Local e produção compartilham SDK, configuração e semântica.
- ➕ Um container a menos (sem MinIO) e Auth+Storage no mesmo processo.
- ➕ A porta `ObjectStore` continua com dois adaptadores exercitados (GCS real × emulado).
- ➖ Dependência do Firebase CLI no ambiente de desenvolvimento.
- ➖ A tabela de propriedade de recursos precisa ser mantida — é ela que evita a perda
  silenciosa no `apply`.
