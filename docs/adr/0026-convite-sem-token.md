# ADR-0026 — O convite não tem segredo: identidade no lugar de portador

- **Status:** Aceita
- **Data:** 2026-09-01
- **Resolve:** P-30 (o convite não levava link de aceite)
- **Altera:** ADR-0025 (o e-mail de convite agora endereça a linha)

## Contexto

O convite nascia com um token opaco: gerado no serviço, devolvido **uma vez** ao
chamador, guardado no banco só como hash (`invites.token_hash`). O aceite conferia
esse hash, e mais nada. Quem tivesse o token entrava na conta.

Isso é **credencial de portador**, e ela tinha uma consequência prática que travou
o produto: o token não podia aparecer em lugar nenhum onde ficasse em repouso. E
"lugar nenhum" aqui é grande — o payload de `dop.identity.invite.created` viaja
para:

| destino | permanência |
|---|---|
| `events` | tabela particionada, indefinida |
| `outbox` | até o relay drenar |
| JetStream | `FileStorage`, `MaxAge` de 30 dias |
| `timeline` | projeção que assina `dop.>` e guarda o payload inteiro — **feita para ser exibida** |

Ou seja: pôr o token no evento o replicaria para quatro lugares, um deles uma tela.
Sem o token no evento, o notificador (ADR-0025 — só enxerga o evento) não tinha
como montar link de aceite. O e-mail anunciava o convite e apontava para
`/convites` — uma lista que o convidado, **que ainda não é usuário**, não tem.

Duas saídas ruins estavam na mesa: token no evento (credencial em repouso,
replicada) ou um caminho lateral levando o token ao notificador por fora do log
(um segundo mecanismo de entrega, só para não usar o primeiro).

A proposta que destravou veio do dono do produto: indexar o token por um uuid e
mandar só o índice. Ela não resolve sozinha — *se possuir o uuid basta para
completar o aceite, então o uuid **é** a credencial*, e ele estaria exatamente nos
mesmos quatro lugares. Mas ela aponta para a saída certa quando combinada com a
segunda metade, que o dono do produto acrescentou: **"o e-mail deve bater
também"**.

## Decisão

### O convite deixa de ter segredo

`invites.token_hash` cai (migração `0013`). `randomToken` e `hashToken` somem.
`CreateInvite` não devolve mais token — não há nada para devolver.

O que endereça o convite é o `id` da linha. Ele viaja em texto claro no payload do
evento, na timeline, no e-mail e no log, porque **sozinho ele não concede nada**.

### O aceite exige SER o convidado

`AcceptInvite(ctx, inviteID, userID)` recusa quando:

1. não há sessão — como antes;
2. o convite não está utilizável (vencido, revogado, já aceito) — como antes;
3. o e-mail do usuário logado **não está verificado**;
4. o e-mail verificado do usuário logado **não é o do convite**.

As duas últimas são novas, e (4) é a que muda a natureza da coisa: o link deixa de
ser credencial e passa a ser **endereço**. Antes o aceite exigia sessão mas nunca
conferia *de quem* — qualquer usuário autenticado com o link entrava na conta, com
o papel concedido a outra pessoa. Era um buraco independente do token, e ele
morre junto.

(3) e (4) são recusas **separadas** de propósito: "confirme seu e-mail" e "este
convite não é seu" mandam a pessoa fazer coisas diferentes, e um erro só faria as
duas parecerem a mesma parede.

A mensagem de (4) **não diz para quem era o convite**. Dizer transformaria o link
num oráculo de e-mail para quem o encontrasse — o segredo teria voltado pela porta
dos fundos.

### O link do e-mail endereça a linha, e isso continua sendo dado

`Rule.LinkPath` aceita `{campo}`, resolvido contra os mesmos dados que o template
recebe. A regra do convite virou `/convites/{invite_id}`.

Continua tabela, não código: ninguém escreve concatenação em Go para montar o
link. Um teste da tabela recusa `{campo}` que não esteja em `Data`, porque o preço
de errar é um e-mail com `{invite_id}` literal no meio da URL. Em tempo de
execução, campo ausente **apaga o link inteiro** — meio-link é pior que link
nenhum: o botão aparece e leva a lugar nenhum.

### TTL

Fica em 14 dias (`identity.InviteTTL`), como já era. O prazo não estava em questão:
ele limitava a janela de um segredo, e agora limita a janela de um endereço que só
funciona para uma pessoa. Se algum dia encurtar, é decisão de produto, não de
segurança.

## Consequências

**O que melhora.** Não há segredo de convite em repouso em lugar nenhum — nem no
evento, nem na projeção, nem no JetStream, nem no e-mail, nem no log. O convite
finalmente tem link clicável. E o buraco de "qualquer autenticado com o link
entra" fecha.

**O que fica mais restrito.** Quem for convidado num e-mail e entrar na plataforma
com outro (Google pessoal versus corporativo) **não consegue aceitar**. Isso é
correto — o convite é para uma pessoa —, mas é uma parede nova que antes não
existia, e a mensagem de erro precisa ser boa. Emissor que não informa
`email_verified` (garantia 5 do `IdentityProvider`) faz todo aceite cair em (3):
é a falha segura, e ela é ruidosa em vez de silenciosa.

**O que continua aberto.** Não existe endpoint de aceite ainda — nem no núcleo
(`AcceptInvite` existe, mas nada no cockpit chega nele) nem no BFF. O `/convites/:id`
do link ainda não tem tela. Fica registrado no roteiro.

**Cliente antigo.** `AcceptInviteRequest.token` virou `invite_id`, mesmo número de
campo. Um cliente que ainda mande o token simplesmente não acha a linha — falha
correta, e nada está em produção.

## Alternativas descartadas

- **Token no evento.** Credencial em repouso replicada para quatro destinos, um
  deles uma tela. Nenhuma revogação alcança JetStream e timeline.
- **Caminho lateral até o notificador.** Um segundo mecanismo de entrega existindo
  só para não usar o primeiro, e o segredo continuaria existindo — apenas em menos
  lugares.
- **UUID indexando o token.** Não muda nada enquanto possuir o índice bastar para
  aceitar: o índice passa a ser a credencial, nos mesmos quatro lugares.
- **Só exigir e-mail batendo, mantendo o token.** Funciona, mas guarda hash de um
  segredo que ninguém mais confere — superfície sem dono.
