# Modelos de mensagem para cadastrar na Meta

Cadastre em **WhatsApp Manager › Modelos de mensagem › Criar modelo**, com o **nome exato** abaixo, idioma **Português (BR)** e a categoria indicada. Os `{{1}}`, `{{2}}`… são preenchidos pelo sistema, na ordem da tabela.

A Meta pede um exemplo para cada variável: use os da coluna "Exemplo". A aprovação costuma levar de minutos a 1 dia.

| Nome do modelo | Categoria | Quando sai | Variáveis |
|---|---|---|---|
| `corte_confirmacao` | Utilidade | assim que o cliente marca | 1 nome · 2 dia e hora · 3 barbeiro · 4 link da Minha área |
| `corte_lembrete` | Utilidade | X horas antes do horário | 1 nome · 2 hora · 3 barbeiro |
| `corte_horario_mudou` | Utilidade | atraso ou remarcação | 1 nome · 2 dia e hora novos · 3 link da Minha área |
| `corte_cancelado` | Utilidade | agenda fechada ou cancelado pela barbearia | 1 nome · 2 dia e hora · 3 link pra marcar de novo |
| `corte_cobranca_plano` | Utilidade | 1 dia depois do plano vencer | 1 nome · 2 plano · 3 valor · 4 data de vencimento |
| `corte_sumido` | **Marketing** | cliente sem vir há 30+ dias | 1 nome · 2 link pra marcar |

## Textos

**corte_confirmacao**
> Tá marcado, {{1}}! Seu horário na Corte DÚ Amigo é {{2}}, com {{3}}. Pra ver, remarcar ou cancelar: {{4}}

Exemplo: Lucas · terça, 17/11 às 10:00 · Duim · https://dudruz.github.io/corte-du-amigo/minha-area.html?t=exemplo

**corte_lembrete**
> Fala, {{1}}! Passando pra lembrar do seu horário hoje às {{2}} com {{3}} na Corte DÚ Amigo. Te esperamos!

Exemplo: Lucas · 10:00 · Duim

**corte_horario_mudou**
> Fala, {{1}}! Seu horário na Corte DÚ Amigo mudou para {{2}}. Se não der pra você, remarque por aqui: {{3}}

Exemplo: Lucas · terça, 17/11 às 10:30 · https://dudruz.github.io/corte-du-amigo/minha-area.html?t=exemplo

**corte_cancelado**
> Fala, {{1}}! Aqui é da Corte DÚ Amigo. Precisamos fechar a agenda e seu horário de {{2}} foi cancelado. Desculpa o transtorno! Escolhe outro horário aqui: {{3}}

Exemplo: Lucas · terça, 17/11 às 10:00 · https://dudruz.github.io/corte-du-amigo/index.html

**corte_cobranca_plano**
> Fala, {{1}}! Aqui é da Corte DÚ Amigo. Seu {{2}} venceu em {{4}} ({{3}}). Pra renovar, responde aqui que a gente manda o Pix, ou acerta no próximo corte.

Exemplo: Thiago · Plano Corte · R$ 120,00 · 08/11

**corte_sumido** (Marketing)
> Fala, {{1}}! Faz tempo que você não aparece na Corte DÚ Amigo. E aí, bora cortar? Marca seu horário aqui: {{2}}

Exemplo: Marcelo · https://dudruz.github.io/corte-du-amigo/index.html

## Observações

- O lembrete diz "hoje" porque, com a antecedência padrão (1 hora), ele sai no mesmo dia. Se o Duim quiser lembrete na véspera, mude a antecedência em Ajustes (por exemplo, 24 horas) e o texto do modelo para "amanhã".
- Mudou um texto depois de aprovado? A Meta revisa de novo. Mudou o **nome** do modelo? Tem que mudar também em `supabase/migrations/009_mensagens_automaticas.sql`, numa migration nova.
- Mensagem de Marketing custa cerca de 9 vezes a de Utilidade. Por isso "Chamar sumido" nasce desligado.
