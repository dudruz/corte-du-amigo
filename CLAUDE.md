# Corte DÚ Amigo — Sistema de agendamento e gestão

Barbearia de bairro em Minaslândia (BH), R. Santa Clara de Assis, 20. Dono e barbeiro: **Duim**. Pode contratar mais barbeiros. Funciona de terça a sábado, das 9h às 19h30.
Dev: Dudu (PX Forge). Idioma de tudo (UI, código de domínio, commits): **pt-BR**.

Design aprovado (canvas com 14 telas mobile): https://claude.ai/artifact/X18YqZLqCVC6cqLorwZCuC
O canvas é a referência visual. Se algo aqui contradizer o canvas, o que vale é este arquivo.

---

## 1. Stack e restrições

- **Front:** HTML + CSS + JavaScript puro (ES modules com `<script type="module">`), **sem framework e sem build**.
- **Supabase JS via CDN, com versão fixa:**
  `import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm'`
- **Back: Supabase.** Usar:
  - **Postgres e funções RPC:** toda a regra de negócio.
  - **Auth:** login da equipe.
  - **RLS:** permissões por papel.
  - **Realtime:** a agenda da equipe atualiza sozinha quando um cliente marca ou cancela.
  - **pg_cron:** tarefas automáticas, como marcar assinatura vencida como atrasada.
  - **Storage:** fotos dos barbeiros.
- **Hospedagem: GitHub Pages servindo o repositório direto** (Settings › Pages › branch `main`, pasta raiz). Não precisa de GitHub Actions.
- **PWA:** `manifest.webmanifest` e `sw.js` escritos à mão, só para a área da equipe.

Consequências obrigatórias de não ter servidor:
- **Toda regra de negócio crítica fica no banco**, em funções `security definer` chamadas via `supabase.rpc()`. Exemplos: impedir dois agendamentos no mesmo horário, finalizar atendimento, debitar plano, mexer no caixa. O front nunca grava direto nessas tabelas.
- **RLS ligado em todas as tabelas.** A URL do projeto e a `anon key` ficam em `js/config.js`. Elas são públicas por natureza, e a segurança vem da RLS. A `service_role` **nunca** vai para o repositório.
- **Multipágina:** cada tela é um arquivo `.html`. Assim as URLs são normais e funcionam no Pages sem truque de rota.
- **Caminhos sempre relativos** (`./css/...`, `../js/...`), para funcionar tanto em `usuario.github.io/repo/` quanto em domínio próprio (com o arquivo `CNAME` na raiz).

Estrutura de pastas:
```
/index.html              serviço (início do cliente)
/horario.html
/dados.html
/agendado.html
/minha-area.html
/equipe/login.html
/equipe/index.html       início (dashboard do dono)
/equipe/agenda.html
/equipe/bloquear.html
/equipe/finalizar.html
/equipe/caixa.html
/equipe/clientes.html
/equipe/planos.html
/equipe/config.html
/css/tokens.css          variáveis de cor, fonte e espaçamento
/css/base.css            reset, tipografia, faixa do poste
/css/componentes.css     botão, card, chip, input, tab bar, toast
/js/config.js            SUPABASE_URL, SUPABASE_ANON_KEY, WHATSAPP_BARBEARIA
/js/supabase.js          cria e exporta o client
/js/auth.js              exigirEquipe(papel?) para proteger as páginas /equipe
/js/lib/                 formatar.js (dinheiro, datas), mensagens.js (WhatsApp), escapar.js
/js/ui/                  componentes: icones.js, tabbar.js, toast.js, modal.js
/js/paginas/             um módulo por página (agenda.js, finalizar.js...)
/supabase/migrations/    SQL versionado
/manifest.webmanifest, /sw.js, /CNAME (se tiver domínio)
```

Avisos para o Dudu:
- No plano gratuito, o GitHub Pages exige repositório **público**. Não há segredo no código, mas convém saber disso.
- O Supabase gratuito **pausa o projeto depois de 7 dias sem uso**. Com uso diário isso não acontece, mas vale considerar o plano pago quando a barbearia estiver dependendo do sistema.

---

## 2. Convenções

- **Dinheiro em centavos** (`integer`). Nunca usar float. Formatar com `Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' })`.
- **Datas em `timestamptz`.** Exibir sempre em `America/Sao_Paulo`.
- **Telefone** salvo só com dígitos e DDI: `5531999998888`.
- **Mobile-first**, com 390px de largura como referência. Botões com no mínimo 44px de altura.
- O tom dos textos é de amigo de bairro ("Bora marcar seu corte?", "Tá marcado!"). Copiar os textos do canvas.

- **JS com `// @ts-check` e JSDoc** nos módulos. É a forma de ter checagem de tipo sem build.
- **Segurança no DOM:** dado vindo do usuário ou do banco entra só por `textContent` ou passando por `escapar()`. **Nunca** usar `innerHTML` com nome de cliente, observação ou dado parecido.
- **Estado entre as páginas do agendamento** fica em `sessionStorage` (chave `rascunho_agendamento`). Se o cliente abrir `/horario.html` direto, sem rascunho, volta para o início.
- **Componentes de UI** são funções que criam e retornam elementos (`criarBotao({...})`), sempre com estados de carregando, vazio e erro.

---

## 3. Design tokens

```
--fundo:      #F3EEE5   (creme)
--superficie: #FFFFFF
--superficie-2: #FBF8F3
--tinta:      #1A1714   (texto / header escuro)
--tinta-2:    #2A2621
--muted:      #6B635A   (texto secundário, passa 4.5:1 no creme)
--linha:      #DDD5C8 / #E3DBCF / #EDE6DA
--vermelho:   #B3261E   (ação principal)
--azul:       #1E3557   (planos / assinante)
--ok:         #1F6B3A  bg #E3F1E6
--alerta:     #7A4100  bg #FBEBD3
--erro:       #9E2019  bg #F8E1DE
```

Fontes do Google Fonts:
- **Anton** nos títulos, sempre em caixa alta.
- **DM Sans** (400/500/700) no resto.

Assinatura visual: uma faixa listrada (poste de barbeiro) de 8px no topo das telas:
`repeating-linear-gradient(135deg, #B3261E 0 14px, #F3EEE5 14px 28px, #1E3557 28px 42px, #F3EEE5 42px 56px)`

Bordas arredondadas: 12–16px nos cards e 999px nos chips e pills. Os ícones são SVG de traço no estilo Lucide, copiados para `js/ui/icones.js`.

Cores e fontes **podem mudar** quando chegar a identidade real (Instagram @barbeariacorteduamigo). Por isso tudo vem de tokens: nada de hex solto nos componentes.

---

## 4. Telas e rotas

Público (cliente, sem login):

| Página | Tela do canvas |
|---|---|
| `/index.html` | Main: escolher serviço(s) |
| `/horario.html` | Horario: barbeiro ("tanto faz" = primeiro livre), dia, horário |
| `/dados.html` | Identificacao: nome, WhatsApp, aceite de lembrete |
| `/agendado.html?t=TOKEN` | Confirmado |
| `/minha-area.html?t=TOKEN` | MinhaArea: próximo horário, remarcar/cancelar, plano, histórico |

Equipe (Supabase Auth com e-mail e senha). Toda página em `/equipe/` chama `exigirEquipe()` antes de carregar o conteúdo:

| Página | Tela | Quem acessa |
|---|---|---|
| `/equipe/login.html` | Login | todos |
| `/equipe/agenda.html` | Agenda do dia, com Realtime ligado | barbeiro vê a própria; dono escolhe o barbeiro |
| `/equipe/bloquear.html` | Fechar agenda (dia, período, atraso) | barbeiro (a própria agenda) e dono |
| `/equipe/finalizar.html?id=AGENDAMENTO` | Finalizar e receber | barbeiro e dono |
| `/equipe/index.html` | Início (dashboard) | dono |
| `/equipe/caixa.html` | Caixa | dono |
| `/equipe/clientes.html` | Clientes | dono (o barbeiro vê só nome e telefone dos próprios clientes) |
| `/equipe/planos.html` | Planos | dono |
| `/equipe/config.html` | Configurações | dono |

### Acesso do cliente sem login
Não usar "digite seu WhatsApp e veja seus agendamentos", porque qualquer pessoa veria os dados de outra.
- Cada agendamento gera um **`token` (uuid aleatório)**. A Minha área é acessada por `/minha-area.html?t=TOKEN`.
- O token também é salvo no `localStorage`, para o cliente voltar sem precisar do link.
- Na tela Confirmado, trocar o texto "a confirmação foi pro seu WhatsApp" por um botão **"Mandar o link pro meu WhatsApp"**. O botão abre `wa.me/<numero_do_cliente>?text=...` com o link da Minha área. O próprio cliente envia para si mesmo e isso é grátis.

---

## 5. Modelo de dados (Postgres)

Habilitar `btree_gist` (anti-sobreposição) e `pgcrypto` (tokens).

```
perfis            id (= auth.users.id), nome, papel ('dono'|'barbeiro'), barbeiro_id null, ativo
barbeiros         id, nome, apelido, foto_url, comissao_tipo ('percentual'|'fixo_por_corte'), comissao_valor, ativo
servicos          id, nome, preco_centavos, duracao_min, ativo, ordem
horarios_trabalho id, barbeiro_id, dia_semana (0-6), inicio time, fim time        -- padrão Ter–Sáb 09:00–19:30
bloqueios         id, barbeiro_id null (null = barbearia toda), periodo tstzrange, motivo, recorrente_semanal bool, criado_por
clientes          id, nome, telefone unique, aceita_lembrete bool, observacoes, criado_em
agendamentos      id, token uuid unique default gen_random_uuid(), cliente_id, barbeiro_id,
                  periodo tstzrange, status ('marcado'|'em_atendimento'|'finalizado'|'cancelado'|'faltou'),
                  usa_plano bool, criado_em
                  EXCLUDE USING gist (barbeiro_id WITH =, periodo WITH &&) WHERE (status IN ('marcado','em_atendimento'))
agendamento_servicos agendamento_id, servico_id, preco_centavos (congelado), duracao_min
formas_pagamento  id, nome ('Pix','Dinheiro','Crédito','Débito','Plano','Fiado'), taxa_percentual numeric, ativa
atendimentos      id, agendamento_id null (permite encaixe sem agendamento), cliente_id, barbeiro_id,
                  total_centavos, desconto_centavos, gorjeta_centavos, finalizado_em
pagamentos        id, atendimento_id, forma_pagamento_id, bruto_centavos, taxa_centavos, liquido_centavos,
                  recebido_dinheiro_centavos null, troco_centavos null, pendente bool (fiado), quitado_em null
planos            id, nome, descricao, preco_centavos, usos_por_mes int null (null = ilimitado), servicos_incluidos uuid[], ativo
assinaturas       id, cliente_id, plano_id, inicio date, vence_em date, status ('ativa'|'atrasada'|'cancelada')
usos_plano        id, assinatura_id, atendimento_id, usado_em
caixa_movimentos  id, data date, tipo ('entrada'|'saida'), origem ('atendimento'|'plano'|'despesa'|'fiado_quitado'|'ajuste'),
                  descricao, forma_pagamento_id, bruto_centavos, liquido_centavos, referencia_id, criado_por, criado_em
fechamentos_caixa id, data date unique, troco_inicial_centavos, esperado_dinheiro_centavos, contado_dinheiro_centavos,
                  diferenca_centavos, fechado_por, fechado_em
configuracoes     chave text pk, valor jsonb
```

Defaults em `configuracoes`. Todos são editáveis na tela Config. Os marcados como `pendente` aparecem como "Definir":

```
cancelamento_antecedencia_horas: 2          (pendente)
politica_falta: {"bloquear_apos": null}     (pendente)
plano_acumula: false                        (pendente)
comissao_padrao: null                       (pendente)
intervalo_slots_min: 30
lembrete_horas_antes: 1
whatsapp_barbearia: "55319XXXXXXXX"
```

---

## 6. Funções RPC (lógica crítica no banco)

Todas são `security definer`, validam as entradas e retornam erros com mensagens em pt-BR.

- **`horarios_livres(servico_ids uuid[], barbeiro_id uuid null, dia date)`**: devolve os slots livres considerando a duração somada dos serviços, o horário de trabalho, os bloqueios (inclusive os recorrentes) e os agendamentos ativos. Com `barbeiro_id` null, devolve o slot livre de qualquer barbeiro. **Não expõe dados de outros clientes.**
- **`criar_agendamento(servico_ids, barbeiro_id null, inicio timestamptz, nome, telefone, aceita_lembrete)`**: faz upsert do cliente pelo telefone e cria o agendamento. A constraint `EXCLUDE` garante que não há conflito. Se der conflito, retorna "Esse horário acabou de ser pego, escolhe outro". Retorna o `token`.
- **`agendamento_por_token(token)`, `cancelar_por_token(token)`, `remarcar_por_token(token, novo_inicio)`**: respeitam `cancelamento_antecedencia_horas`.
- **`finalizar_atendimento(agendamento_id, itens, forma_pagamento_id, desconto, gorjeta, recebido_dinheiro null)`**: roda em **uma única transação** e faz:
  1. Cria o atendimento e o pagamento, calculando taxa e líquido pela `formas_pagamento.taxa_percentual` e o troco quando for dinheiro.
  2. Se a forma for Plano, valida a assinatura ativa e os usos restantes, grava em `usos_plano` e não gera entrada de caixa (a gorjeta, se houver, entra).
  3. Se for Fiado, grava `pendente = true` e não gera entrada no caixa até quitar.
  4. Nos demais casos, cria `caixa_movimentos` de entrada.
  5. Marca o agendamento como `finalizado`.
- **`criar_bloqueio(barbeiro_id null, periodo, motivo, recorrente)`**: retorna a **lista de agendamentos afetados**, com nome, telefone e horário, para o front montar os links de aviso.
- **`aplicar_atraso(barbeiro_id, minutos)`**: empurra os agendamentos de hoje a partir de agora e retorna os afetados com o horário antigo e o novo.
- **`quitar_fiado(pagamento_id, forma_pagamento_id)`**, **`registrar_pagamento_plano(assinatura_id, forma_pagamento_id)`** (renova o `vence_em` e gera entrada no caixa), **`fechar_caixa(data, contado_dinheiro)`**.

### RLS (resumo)
- `anon`: **nenhum acesso direto às tabelas**. Só executa as RPCs públicas: `horarios_livres`, `criar_agendamento` e as funções `*_por_token`. As tabelas `servicos`, `barbeiros` (campos públicos) e `planos` ativos podem ter `select` liberado.
- `barbeiro`: lê e atualiza os próprios agendamentos e bloqueios, e lê os clientes que já atendeu.
- `dono`: tudo.
- Usar uma função auxiliar `papel_atual()` que lê `perfis`.

---

## 7. WhatsApp (MVP grátis, sem API)

Sempre usar o link `https://wa.me/<telefone>?text=<mensagem codificada>`, que abre o WhatsApp do aparelho com a mensagem pronta.
- **Avisos de bloqueio ou atraso:** depois de `criar_bloqueio` ou `aplicar_atraso`, mostrar a lista de afetados com um botão **"Avisar"** por cliente. Marcar "avisado" localmente ao clicar.
- **Lembretes:** uma seção "Lembretes de amanhã" na Agenda, com um botão por cliente que aceitou lembrete.
- **Clientes sumidos:** o botão "Chamar" usa o mesmo mecanismo.
- **Cobrança de plano atrasado:** o botão "Cobrar no Zap", também com o mesmo mecanismo.
- Os modelos de mensagem ficam em `js/lib/mensagens.js`, copiando os textos do canvas.

Fase 3, opcional: API oficial do WhatsApp via Edge Function e cron, se o Duim aceitar o custo por mensagem.

---

## 8. Fases e critérios de pronto

**Fase 1 — MVP (para usar na barbearia)**
- [x] Setup: estrutura de pastas, `tokens.css` e componentes base, `js/supabase.js`, `exigirEquipe()`, deploy no Pages e PWA.
- [x] Migrations SQL e seed: Duim, os 4 serviços com preço e duração placeholder, horários, formas de pagamento e configurações.
- [x] Fluxo do cliente completo: serviço → horário → dados → confirmado → minha área (remarcar e cancelar).
- [x] Login da equipe e roteamento por papel.
- [x] Agenda do dia: livres, bloqueados, em atendimento e finalizados, atualizando ao vivo via Realtime.
- [x] Fechar agenda: dia inteiro, período com repetição e atraso, com a lista de avisos.
- [x] Finalizar e receber: Pix, dinheiro com troco, crédito/débito com taxa, fiado e gorjeta.
- [x] Caixa do dia: entradas, saídas, despesa, "deve ter na gaveta" e fechamento.
- [x] Configurações: serviços, horários, formas de pagamento com taxas e regras.
- **Teste de aceite principal:** dois navegadores tentando o mesmo horário ao mesmo tempo. Só um consegue.

**Fase 2 — Gestão**
- [x] Planos e assinaturas: uso no finalizar (o agendamento não marca o plano; o barbeiro escolhe "Plano" ao finalizar), renovação, status atrasado e "Cobrar no Zap".
- [x] Clientes: busca, filtros (sumidos 30+ dias, assinantes, fiado), ficha com histórico e quitação de fiado.
- [x] Dashboard (Início) e relatório mensal: bruto, taxas, líquido, ticket médio, formas de pagamento e comissões.
- [x] Multi-barbeiro: convite, comissão e agenda do dono por barbeiro.

**Fase 3 — Automação (opcional)**
- [ ] Lembretes e avisos automáticos pela API do WhatsApp.
- [ ] Cobrança recorrente do plano (Pix automático ou link de pagamento).

---

## 9. Regras de trabalho para o Claude Code

- Planejar antes de executar: em tarefas grandes, apresentar o plano e esperar o OK do Dudu.
- Não refazer o que já está pronto. Ler o código existente antes de criar coisa nova.
- Toda mudança no banco vira uma migration versionada em `supabase/migrations/`.
- Escrever testes para as RPCs críticas (`criar_agendamento`, `finalizar_atendimento`, `horarios_livres`) com pgTAP ou scripts SQL.
- Componentes pequenos e reutilizáveis, ligados aos tokens de `tokens.css`. Nada de cor hardcoded.
- Sem dependências além do supabase-js via CDN. Se algo parecer exigir uma biblioteca, perguntar antes.

---

## 10. Estado atual (Fases 1 e 2 entregues)

Pronto e testado (48 testes de banco em `supabase/testes/`, telas abertas contra um banco de teste com as migrations reais):
- **Banco:** migrations 001 a 008 (aplicadas no Supabase real em 17/11/2026).
  - 006: correções da revisão (acesso só pelo token, grade e horizonte no agendamento, teto por hora, telefone com DDI, bloqueio que cancela só o que bate, plano com `servicos_incluidos`, despesa no dia certo, fechamento desatualizado).
  - 007: planos (`salvar_plano`, `assinar_plano`, `registrar_pagamento_plano`, `cancelar_assinatura`, `planos_painel`), clientes (`clientes_lista`, `ficha_cliente`, `salvar_cliente`), `painel_mes` (faturamento, ticket, formas, semana, comissão), `salvar_horarios` (atômico), logins da equipe (`equipe_logins`, `vincular_login`, `mudar_login_ativo`) e Pix (`pix_chave`, `pix_nome`, `pix_cidade` em `configuracoes`).
- **Telas do cliente:** `index`, `horario`, `dados`, `agendado`, `minha-area`.
- **Telas da equipe:** `login`, `index` (Início), `agenda` (Realtime), `bloquear`, `finalizar` (com Pix copia e cola), `caixa`, `clientes` (lista e ficha em `?id=`), `planos`, `config`.
- **Entrega:** `LEIA-ME.md` (passo a passo do zero), `GUIA-DO-DUIM.md` (uso do dia a dia), backup semanal criptografado em `.github/workflows/backup.yml`.

Diferenças em relação ao plano original:
- **"É assinante? Entre com WhatsApp" virou "Já tem horário marcado?".** O acesso por telefone sem login exporia dados de outra pessoa. A Minha área lista os horários pelos tokens salvos no aparelho (`agendamentos_por_tokens`) e não mostra plano nem histórico de quem só informou o telefone.
- **Bloqueio de dia ou período cancela os agendamentos afetados** (`cancelado_motivo = 'bloqueio'`) e a mensagem leva o cliente para marcar de novo.
- **Pausa de almoço** é um bloqueio semanal recorrente, e não um campo do horário de trabalho.
- **Menu do dono:** Início, Agenda, Clientes, Caixa e Planos (como no canvas). Ajustes e Sair ficam na engrenagem do Início. Barbeiro vê Agenda e Sair.
- **Plano com serviço fora da lista é recusado no finalizar** (sem pagamento dividido em duas formas).
- **Comissão:** `comissao_valor` é a porcentagem inteira (`percentual`) ou centavos por atendimento (`fixo_por_corte`), sobre o valor dos serviços com desconto. Gorjeta fica à parte.
- **Pix:** BR Code estático gerado no front (`js/lib/pix.js`), sem biblioteca e sem QR Code.
- **Login de barbeiro:** o usuário é criado no painel do Supabase (precisa da chave de administrador) e ligado ao barbeiro em Ajustes › Logins da equipe.
- **Service worker** vale só para `/equipe/` e se desfaz do registro antigo na raiz.

  - 008: caminho de busca fixo nas funções simples e auxiliares fechadas pra API (ficam só `eh_dono`, `eh_equipe` e `barbeiro_atual`, que o RLS usa).

Pendente: repetir no Supabase real o teste de aceite dos dois navegadores (o banco de teste tem uma conexão só).
