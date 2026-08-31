# Coleções de API — o padrão de organização

Toda pasta e todo arquivo desta árvore começa com um **índice de dois dígitos**:

```
00-dop-core-grpc/
  00-identity/
    00-ensure-user.bru
    01-list-accounts.bru
    02-create-invite.bru
  01-hierarchy/   02-resource/   03-demand/    04-workflow/
  05-cost/        06-delivery/   07-knowledge/ 08-execution/
  09-event/       10-attention/  11-agent/
01-dop-api-grpc/
02-dop-api-rest/
```

**Sem espaço no nome, e sem `folder.bru`.** A primeira versão usava
`00 - identity` e um `folder.bru` por pasta; o Bruno passou a acusar erro em
todas as requisições. Sem CLI para reproduzir aqui, as duas coisas saíram — o
espaço porque atravessa mal ferramenta e script, e o `folder.bru` porque é
recurso recente: uma versão que não o conheça o lê como REQUISIÇÃO sem método
nem URL. O índice, que é o que interessa, continua onde estava.

## Por que índice no NOME, e não só o `seq` do Bruno

O `seq` do Bruno ordena dentro da ferramenta e é invisível em todo o resto. O
índice no nome ordena no `ls`, no `git diff`, no navegador de arquivos do editor
e na revisão de PR — que é onde a maioria das pessoas encontra estes arquivos.

Os dois convivem: o `seq` de cada `.bru` **acompanha** o índice do nome, e cada
pasta tem um `folder.bru` com o mesmo número. Um lugar só decide a ordem; os
outros a repetem. Se divergirem, o nome é a verdade — ele é o que aparece na
revisão.

## A ordem não é alfabética: é a de execução

Dentro de uma pasta, o índice segue **a sequência em que alguém realmente
percorre** o fluxo. Em `identity`, `ensure-user` vem antes de `list-accounts`
porque não há conta para listar antes do primeiro login. Em `resource`,
`create-integration` vem antes de `set-credential` porque não há onde guardar a
credencial antes de o recurso existir.

Ordenar por alfabeto colocaria `create-invite` na frente de `ensure-user`, e a
primeira requisição da coleção falharia — ensinando a quem chega que a coleção
está quebrada, quando o quebrado é a ordem.

## A ordem das coleções

`00` é o **núcleo**, porque é a fonte da verdade: o contrato dele é o que as
bordas traduzem. Depois vêm as duas superfícies da borda, gRPC (`01`) e REST
(`02`) — as duas chamam o mesmo código no BFF, e há teste de paridade provando
isso.

## Os nomes de domínio são os do CÓDIGO

`identity`, `hierarchy`, `resource`, `demand` — os mesmos dos protos e dos
pacotes de domínio, mesmo onde a documentação ao redor está em português.
Índice numerado com rótulo que não bate com o código é meio padrão: quem procura
`hierarchy.proto` precisa achar a pasta correspondente sem traduzir.

## Ao acrescentar

- **Requisição nova no meio do fluxo:** renumere as seguintes. Índice com buraco
  ou repetido é pior que renumerar — ele sugere que falta alguma coisa.
- **Corpo copiado de chamada que rodou de verdade**, nunca inventado. Já houve
  nesta coleção requisição que o servidor recusava enquanto o exemplo parecia
  correto.
- **`docs {}` explica o PORQUÊ**, não o que a rota faz — isso o nome já diz.

## O que esta coleção AINDA não cobre

O **núcleo está completo**: os 12 domínios, com o corpo de cada requisição
validado contra o servidor rodando — nenhum foi inventado.

A **borda** expõe 12 serviços gRPC e 63 rotas REST; a coleção cobre 3 deles
(`identity`, `hierarchy`, `resource`). Faltam requisições para `workflow`,
`demand`, `delivery`, `knowledge`, `cost`, `execution`, `stream`, `runtime` e
`attention` — a lacuna é da COLEÇÃO, não da API.

Está escrito aqui de propósito: com o índice, a lacuna fica visível na própria
árvore, em vez de ser descoberta por quem procurou e não achou.
