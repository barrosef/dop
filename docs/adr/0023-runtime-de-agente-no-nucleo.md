# ADR-0023 — O AgentRuntime vive no NÚCLEO

- **Status:** Aceita
- **Data:** 2026-08-31
- **Substitui:** a decisão da [ADR-0016](0016-stack-go-core-python-bff.md) de que *"o AgentRuntime vive no BFF"*

## Contexto

A ADR-0016 colocou o `AgentRuntime` no BFF: *"o core decide o quê (fluxo, ficha,
orçamento, roteamento); o BFF executa a conversa com o modelo"*. A divisão parecia
limpa — decisão de um lado, execução do outro.

Ao implementar, ela cobrou o preço.

O runtime precisa da credencial do provedor de agente. Credencial de recurso mora no
cofre, atrás de `ports.SecretStore`, **no núcleo** — e o núcleo **nunca devolve
segredo**, por desenho, com teste guardando. As saídas eram todas ruins:

- **BFF com acesso próprio ao cofre.** Foi a recomendação inicial da implementação, e o
  dono do produto vetou com razão: *"o BFF é uma camada muito insegura, aberta na
  internet"*. Comprometer o BFF passaria a entregar as credenciais de agente de TODAS
  as contas. A sessão em que isso foi discutido acabara de encontrar um **bypass total
  de autenticação** nessa mesma camada — o argumento não é hipotético.
- **Núcleo emitir token efêmero.** Elegante, e impossível hoje: chave de API da
  Anthropic é durável, não há token de curta duração para emitir.
- **Serviço separado só para o runtime.** Terceiro processo, terceira implantação,
  terceira fronteira de confiança — custo alto para o mesmo problema.
- **Ler de variável de ambiente.** Foi o provisório entregue, e não tem isolamento por
  conta, atribuição de custo por credencial, nem revogação por recurso.

## Decisão

**O `AgentRuntime` passa para o núcleo.** A credencial nunca atravessa fronteira de
rede: é lida do cofre e usada no mesmo processo.

O que a implementação revelou e pesou tanto quanto a segurança: **o runtime já era
quase inteiramente orquestração do núcleo.** As seis coisas que ele faz num turno —
montar contexto, rotear modelo, registrar consumo, postar mensagem, publicar achado,
respeitar orçamento — são todas operações do núcleo, feitas de fora por gRPC. Ele
estava do lado errado da fronteira.

Dois módulos existiam **só por causa da fronteira** e desaparecem:

- `credentials.py` — 115 linhas contornando um cofre inacessível;
- `catalog.py` — 73 linhas refazendo o caminho de volta do nome do modelo à classe,
  porque a decisão de roteamento cruzava a rede perdendo a classe.

O BFF continua sendo a borda: autentica, agrega e traduz protocolo. A execução de turno
vira uma chamada fina ao núcleo, e o acompanhamento ao vivo continua pelo SSE que já
existe — o núcleo emite evento, o BFF converte.

A porta `AgentProvider` e as divergências entre fornecedores (ADR-0022) **não mudam**:
mudam de linguagem, não de desenho. O que foi aprendido — dupla contagem de tokens,
contabilidade de cache ausente na OpenAI, canal do operador, rebaixamento de effort —
é conhecimento de contrato, e atravessa a reescrita.

## Consequências

- ➕ A credencial não cruza a rede. Comprometer o BFF não expõe credencial de agente.
- ➕ O BFF fica com uma invariante mais forte que "não tem banco": **não tem segredo**.
- ➕ Seis idas e voltas de gRPC por turno viram chamadas em processo.
- ➕ O núcleo já é isolado por NetworkPolicy e já carrega o cofre; nada novo a proteger.
- ➖ Os adaptadores de provedor são reescritos em Go. ~600 linhas; o desenho e as
  divergências documentadas atravessam.
- ➖ O núcleo passa a fazer chamadas externas longas. Go lida bem com isso, mas o
  orçamento de conexões e o tempo limite viram preocupação do núcleo.
- ➖ A ADR-0016 fica com uma decisão substituída; a fronteira "o BFF não tem banco"
  continua valendo, e ganha a segunda metade.
