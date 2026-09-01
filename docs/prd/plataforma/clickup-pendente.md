# ClickUp — o que falta subir para o board

**Criado em 2026-09-01.** O espaço `DOP` foi montado com as 13 pastas de épico e a
lista `Backlog` em cada uma (com descrição do épico: do que responde, o que já
existe em código, quais ADRs e pendências governam).

Das 50 histórias, **36 foram criadas**. As 14 abaixo bateram no **rate limit da API
do ClickUp** (bloqueio de ~23h a partir de 2026-09-01 15:30 -04). Nada além disso
falhou — é só retomar.

Apagar este arquivo quando terminar.

## Épico 08 ✅ Verificação e Entrega — lista `1000350000004927`
- US-8.1.4 — Etapa de finalização com passos visíveis e estado por passo
- US-8.2.1 — Visão git completa: repos → branches → PRs → arquivos com diff
- US-8.2.2 — Fila de merge por repositório, com conflitos escalados
- US-8.4.1 — Grupos de qualidade do produto (aceitação, testes, cobertura, Allure)
- US-8.4.2 — Grupos de qualidade de código (padrões, duplicação, dependências)

## Épico 09 🧠 Conhecimento e Contexto — lista `1000350000004928`
- US-7.4 — Regras do projeto e conhecimento acumulado na configuração
- US-8.5.1 — Diagramas arquiteturais e de fluxo sob demanda, em canvas
- US-8.5.2 — Análise forense virando parecer (diagramas + documento)
- US-8.5.3 — Artefatos arquiteturais filtrados pelo task header

## Épico 10 🔔 Atenção e Comunicação — lista `1000350000004929`
- US-8.0.2 — Caixa de atenção global, cada item levando ao lugar da resolução

## Épico 12 🖥️ Cockpit — lista `1000350000004931`
- US-8.0.1 — Selecionar card restringe barra, painel e centro à demanda
- US-8.0.3 — Paleta ⌘K para pular a qualquer projeto/demanda
- US-8.0.4 — Overview acima do task header, imune ao filtro de cards

## Épico 13 ⚙️ Espinha, Ambiente e Operação — lista `1000350000004932`
- US-8.6.1 — Linha do tempo da demanda, filtrável por agentes, git, portões e custo

## Ainda sem história escrita
O épico **11 💰 Custo e Governança** ficou VAZIO de propósito: existe domínio no
núcleo e existe a ADR-0011, mas ninguém escreveu o que o dev vê, o que configura e
o que acontece quando o orçamento acaba. É o maior descompasso entre construído e
especificado — e a organização por épicos serviu justamente para expor isso.

Os épicos 06 (agentes), 07 (substrato), 10 (comunicação) e 13 (operação) ficaram com
1 ou 2 histórias cada: são as áreas mais decididas nesta semana e as menos escritas.
