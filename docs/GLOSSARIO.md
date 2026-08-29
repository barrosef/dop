# Glossário — plataforma DOP

Vocabulário do projeto. Quando um termo aqui colide com o de um provedor externo, a
convenção de desambiguação está registrada.

| Termo | Significado |
|---|---|
| **Plataforma** | O nível 0. Detém recursos globais que não pertencem a ninguém: catálogo de provedores, templates, skills |
| **Conta** | A unidade de posse e de isolamento. Tem `kind`: `personal` (PF) ou `organization` (PJ). Possui integrações, workspaces e projetos |
| **Conta ativa** | A conta sob a qual o usuário está operando no momento, escolhida no seletor. Toda chamada à API carrega uma |
| **Usuário** | A identidade da pessoa. Existe uma vez na plataforma, independentemente de quantas contas acesse |
| **Vínculo** (*membership*) | A ligação entre um usuário e uma conta, portando um papel. O papel mora no vínculo, não na pessoa |
| **Concessão** | Autorização de um usuário sobre uma integração específica, com nível `use` ou `manage`. Ortogonal ao papel |
| **Workspace** | Nível 1. Agrupa projetos. Tem nome, chave, descrição e schema de tags |
| **Projeto** | Nível 2. Onde vivem repositórios e o espaço do task manager, consumidos das integrações da conta dona |
| **Integração** | O vínculo configurado entre uma conta e um provedor externo — git ou task manager |
| **Card** | Item de trabalho vindo do task manager. Tem tipo dinâmico, definido pelo provedor |

## Desambiguações obrigatórias

**"Workspace" é o conceito do DOP e só ele.** Os task managers também usam a palavra — o
ClickUp chama assim o seu tenant. O lado de lá chama-se **espaço do provedor**, ou é
sempre qualificado: *workspace do ClickUp*. A palavra nua nunca se refere ao provedor.

**"Projeto" no DOP é o nível 2.** Quando se falar de projeto no Jira, no Azure DevOps ou
no GCP, qualifique sempre: *projeto do Jira*, *projeto do GCP*.

## Renomeação em curso

O que a documentação e o código anteriores chamavam de **workspace** passou a chamar-se
**projeto**, e o nome *workspace* foi reaproveitado para o agrupador acima dele. Material
antigo pode usar o sentido antigo — ver P-5 no [`ROADMAP.md`](ROADMAP.md).
