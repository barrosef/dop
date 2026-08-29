# ADR-0004 — Verificação de organização por domínio, não por titularidade

- **Status:** Aceita
- **Data:** 2026-08-29

## Contexto

O requisito original pedia validar, na criação de uma organização, se o CPF do usuário
logado é dono da empresa ou possui procuração — citando GitHub e GCP como referência de
fluidez, com a instrução explícita de "não inventar, não dificultar".

**Fomos verificar o que essas referências realmente fazem:**

- **GitHub** cria organização de forma instantânea e gratuita, **sem nenhuma verificação
  de titularidade**. A verificação existe depois, é de **domínio** (registro TXT no DNS),
  e vale o selo de verificada.
- **GCP** exige, para criar o nó de organização, uma conta Cloud Identity ou Workspace
  ligada a um **domínio verificado** — também por DNS.

Nenhum dos dois pede CPF nem procuração. As duas metades do requisito puxam para lados
opostos: validar titularidade *é* dificultar, e as referências citadas não fazem isso.

## Decisão

Adotar o padrão que as duas referências de fato usam: **criar na hora, verificar controle
de domínio depois, condicionar capacidades sensíveis à verificação.**

1. **Criação instantânea.** Nome e CNPJ; o CNPJ preenche razão social e endereço
   automaticamente e já confirma que a empresa existe e está ativa. Sem espera, sem
   documento.
2. **Verificação de domínio opcional.** A plataforma gera um valor, o usuário publica um
   registro TXT no DNS do domínio da empresa, a plataforma confere.
3. **A verificação destrava três capacidades**, deliberadamente poucas:
   - entrada automática por domínio — qualquer e-mail `@dominio` entra sem convite;
   - selo de verificada, com o domínio à vista;
   - contestação de handle tomado por terceiro.

Todo o resto funciona sem verificação: integrações, convites individuais, workspaces,
projetos, execução. Organização não verificada é plenamente utilizável — apenas não pode
fazer afirmações sobre si mesma que não provou.

## Alternativas consideradas

**Validação de titularidade por CPF na criação** — checar se o CPF consta como sócio ou
administrador do CNPJ, ou exigir procuração. Descartada: exige integração com base de
quadro societário, trata mal procuração (documento a analisar por humano) e cria atrito
exatamente onde se pediu fluidez.

**Criação livre sem verificação alguma.** Máxima fluidez e menor esforço. Descartada por
deixar sem resposta a disputa de handle, que o espaço de nomes compartilhado da
[ADR-0002](0002-conta-como-unidade-de-posse.md) torna inevitável.

## Consequências

- ➕ Zero papelada e zero espera na criação; o autofill por CNPJ *ajuda* em vez de barrar.
- ➕ Controle de domínio corporativo é evidência organizacional forte, resolvida em
  minutos pelo próprio usuário.
- ➕ Dá resposta à disputa de handle sem processo manual.
- ➕ Reutilizável: a mesma verificação serve de prova em recuperação de conta órfã.
- ➖ **Não prova representação legal.** Quem controla o DNS não é necessariamente quem pode
  assinar pela empresa. Se algum dia houver obrigação contratual ou fiscal que exija isso,
  será outra decisão, em outra camada.
