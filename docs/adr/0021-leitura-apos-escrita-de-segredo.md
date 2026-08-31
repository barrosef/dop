# ADR-0021 — Leitura-após-escrita de segredo não é grátis no GCP

- **Status:** Aceita
- **Data:** 2026-08-31
- **Resolve:** a garantia 1 de `ports.SecretStore`, que o adaptador GCP não consegue cumprir como escrita

## Contexto

A porta `SecretStore` promete **leitura-após-escrita**: um `Get` logo depois de um
`Put` devolve o valor recém-gravado. A promessa nasceu do adaptador k8s, onde ela é
verdade — por isso o cabeçalho dele diz, com razão, que lê pela API e nunca por volume
montado (volume é eventualmente consistente).

Ao escrever o segundo adaptador de produção — GCP Secret Manager, exigido pela
ADR-0001 — a promessa não se sustentou.

A documentação do Google é explícita: só `AddSecretVersion` seguido de acesso **pelo
número da versão** é fortemente consistente. Acesso por alias — inclusive `latest` — é
eventualmente consistente, e converge *"typically within minutes, but may take a few
hours"*.

O único caminho forte exige carregar o número da versão de uma escrita para a leitura
seguinte. E `SecretRef` é **plano**: conta, tipo e dono. Não há onde guardar versão.

**A consequência é a pior possível para um cofre:** no GCP real, `Get` logo após `Put`
pode devolver `(nil, nil)` — que, pela porta, significa "não existe". Uma credencial
recém-gravada apareceria como ausente, em silêncio, e o chamador concluiria que a
integração não foi configurada.

No emulador local o mesmo caso passa em 0,01 s. Foi exatamente esse tipo de divergência
— o ambiente local escondendo o caminho de produção — que já custou duas falhas de
autenticação nesta plataforma.

## Decisão

**A garantia continua valendo, e o adaptador paga o preço dela.**

O adaptador GCP confirma a escrita **pelo número da versão** (caminho forte) e depois
**espera o alias `latest` alcançar**, com teto configurável (`SECRET_PROPAGATION_SECONDS`,
padrão 30 s). Se não convergir dentro do teto, ele recusa com `KindUnavailable`
explícito.

Recusar é a parte que importa: um `Put` que devolve sucesso enquanto o `Get` seguinte
diz "não existe" é pior que um `Put` que falha. O primeiro produz uma integração
silenciosamente quebrada; o segundo produz um erro que alguém lê.

## Alternativas consideradas

**Fazer `Get` ler pelo número da versão.** É o caminho fortemente consistente, e exigiria
`SecretRef` carregar a versão — ou seja, `Put` passaria a devolver um identificador que o
chamador guarda. É provavelmente a solução certa a longo prazo, e muda a PORTA, não um
adaptador. Fica registrada como evolução, não descartada.

**Afrouxar a garantia para "eventualmente consistente".** Descartada: empurraria para
todo chamador a lógica de reler até aparecer, e o chamador não tem como distinguir "ainda
não propagou" de "não existe". Garantia fraca em porta de cofre é garantia que ninguém
usa direito.

**Cache local do valor após o `Put`.** Descartada: guardar segredo em memória do processo
para contornar consistência é criar um segundo lugar onde a credencial existe, com
invalidação própria — troca um problema de consistência por um de segurança.

## Consequências

- ➕ A porta continua com uma promessa forte, e ela vale nos dois adaptadores.
- ➕ A divergência entre emulador e GCP real está escrita, e não vira surpresa em produção.
- ➖ `Put` no GCP é mais lento e pode falhar por não-convergência — comportamento que o
  emulador nunca reproduz. O teste local **não** cobre esse caminho.
- ➖ Se alguém desabilitar ou destruir versão por fora, `latest` diverge entre os dois
  (o emulador cai para trás; o GCP real falha). Documentado em `dop-infra/docs/ambiente-local.md`.
- ➖ Enquanto a porta não carregar versão, a garantia depende de espera, não de contrato.
