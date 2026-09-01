# ADR-0025 — Comunicação: o gatilho e o canal nascem juntos

- **Status:** Aceita
- **Data:** 2026-08-31
- **Resolve:** P-11 (serviço de comunicação), no recorte de e-mail

## Contexto

A plataforma precisa avisar gente por fora do cockpit: convite, verificação de
conta, integração quebrada, orçamento estourado, thread esperando resposta.

O projeto irmão (spartacus) resolve isso escrevendo um documento numa coleção do
Firestore, o que dispara uma função que manda pelo SendGrid. Três coisas de lá
transferem — o ensaio local sem chave (imprime em vez de enviar), o estado no
registro (`sent` / `sent_local` / `error`) e templates versionados no repositório.
O gatilho não transfere: aqui a espinha de eventos já existe (ADR-0019), e a spec
diz que comunicação é *"consumidor da espinha de eventos, não um sistema à parte"*.

## Decisão

### O gatilho e o canal são coisas separadas, e nascem juntos

Nas palavras do dono do produto: *"Mailer viver sem o Notifier seria como se uma
bala pudesse ser disparada sem o gatilho."*

O ponto não é que o `Mailer` **possa** viver sozinho — é que **o gatilho existe de
qualquer jeito**. Se não for projetado, alguém improvisa: o caso de uso de convite
chama o `Mailer` direto e vira o gatilho, sem nome e sem lugar, espalhado por
quantos casos de uso mandarem e-mail. O risco não é "canal sem gatilho", é
**gatilho difuso**.

```
consumidor de evento
   └─ Notifier: decide O QUE notificar e PARA QUEM   ← o gatilho
        └─ comando: (tipo, destinatário, dados)
             └─ Mailer (porta de canal)              ← o disparo
                  └─ SendGrid | SMTP
```

O caso de uso de convite não conhece nenhum dos dois: publica evento e acabou.

### A porta é por CANAL, não uma só para tudo

Canais não têm a mesma forma: e-mail tem assunto, HTML e anexo; push tem título,
badge e link profundo; SMS tem 160 caracteres e nenhuma formatação. Uma porta
única teria a união de tudo — com a maioria dos campos nunca usada — ou o mínimo
denominador comum, perdendo o que cada canal faz bem.

Vale a regra de sempre: o que não é cumprível por todos os adaptadores fica fora
da porta. Então `Mailer` hoje; `Pusher` e `SMSer` quando houver push e SMS. Um
fornecedor pode implementar vários — o OneSignal seria um pacote com dois ou três
adaptadores, o que é normal, não estranho.

### O adaptador é grande: índice, resolução e envio

Decisão explícita do dono do produto, e ela corrige a proposta inicial de renderizar
no domínio. **O índice de templates, a resolução e o envio moram no ADAPTADOR.**

A porta fala INTENÇÃO — "convite criado, para este endereço, com estes dados" — e
cada adaptador decide o que isso vira:

| Adaptador | Como resolve o template |
|---|---|
| SendGrid | mapeia tipo → `template_id`, manda `dynamic_template_data` |
| SMTP | renderiza local, dos arquivos do repositório |
| OneSignal (futuro) | mapeia tipo → template dele |

Renderizar no domínio pareceria mais limpo e seria pior: a plataforma nunca poderia
usar template de provedor (perdendo editor, versionamento e localização), e a porta
passaria a carregar um blob de HTML — artefato de renderização, não intenção.

É a mesma separação que o roteador de custo já faz: `routingTable` é POLÍTICA,
`ModelCatalog` é CATÁLOGO. Aqui, a política é "que notificação existe e quando"; o
catálogo é "qual template dela neste fornecedor". Trocar de fornecedor troca o
catálogo, não a política.

**Consequência que exige teste:** um tipo de notificação pode existir na política e
não ter template no fornecedor, e isso falharia em SILÊNCIO — o evento acontece, o
consumidor roda, ninguém recebe. A suíte de contrato exige de TODO adaptador que
resolva TODOS os tipos que o domínio sabe emitir.

### Dois adaptadores reais: SendGrid e SMTP

SMTP é o caminho do self-hosted — o mesmo par GCP/OKD das outras portas. E é ele que
**força a resolução local de template**, provando que a porta fala intenção e não
`template_id`. Com SendGrid sozinho, nada impediria a porta de vazar o vocabulário
dele.

### Transacional e aviso de atenção são coisas diferentes

- **Transacional** — convite, verificação de conta. Dispara na hora, sempre, um por
  evento.
- **Aviso de atenção** — thread bloqueada, PR esperando revisão, orçamento estourado.
  Isso **já tem mapa**: a caixa de atenção (ADR-0006, projeção) decide o que exige
  decisão humana. O e-mail se liga à CAIXA, não aos eventos crus — dois mapas
  divergem no primeiro ajuste.

E aí o risco vira spam. A spec já avisa disso sobre a própria caixa: *"caixa
barulhenta vira ruído e é ignorada"*. Um e-mail por item torna a caixa de entrada
inútil.

**Resumo com atraso, padrão de 15 minutos, configurável.** O item abre, espera, e só
vira e-mail se ainda estiver aberto — quem estava no cockpit já resolveu. Quinze
minutos é curto o bastante para o urgente não esperar e longo o bastante para o
trivial se resolver sozinho; é palpite informado, e vira número calibrado quando
houver telemetria, como a tabela do roteador.

### A idempotência é por (evento, regra, ação)

A caixa de atenção usa índice único por EVENTO, e funciona porque a relação é 1:1.

Com reação declarativa (P-29), um evento poderá disparar N ações. Chave só pelo
evento descartaria a segunda como duplicata — e descarte por idempotência é
silencioso por desenho. A chave nasce composta, mesmo com uma ação só hoje.

### Roda no núcleo

A chave do SendGrid é credencial, mora no cofre, e o BFF não tem segredo (ADR-0023).
É mais um consumidor no worker, ao lado da timeline e da caixa de atenção.

## Consequências

- ➕ Trocar SendGrid por OneSignal é escrever um adaptador; a política não muda.
- ➕ Quando a reação virar dado (P-29), troca-se o decisor — não quem chama.
- ➖ Perde-se o editor visual do SendGrid para os templates do SMTP, que são
  arquivos do repositório.
- ➖ Dois lugares para o template do mesmo aviso enquanto os dois adaptadores
  existirem. É o preço de a porta não vazar vocabulário de fornecedor, e a suíte
  de contrato é quem impede que um fique para trás.
- ➖ O atraso de 15 minutos é palpite. Aviso urgente demais espera; trivial demais
  incomoda. Só telemetria resolve.
