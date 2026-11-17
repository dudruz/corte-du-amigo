# Corte DÚ Amigo · Sistema de agendamento e gestão

Site do cliente para marcar horário e painel da equipe: início com o resumo do mês, agenda ao vivo, fechar agenda, finalizar e receber (com Pix copia e cola), caixa, clientes, planos mensais e ajustes.
É feito em HTML, CSS e JavaScript puro, sem build, com hospedagem no **GitHub Pages** e banco no **Supabase**.

O passo a passo abaixo é pra colocar no ar do zero. Leva uns 30 minutos.

---

## 1. Banco de dados (Supabase)

1. Crie um projeto em https://supabase.com. Use a região **South America (São Paulo)**.
2. Abra **SQL Editor** e rode os arquivos de `supabase/migrations/` **um por vez, na ordem**:
   - `001_schema.sql`: tabelas.
   - `002_funcoes.sql`: regras de negócio.
   - `003_seguranca.sql`: permissões (RLS).
   - `004_dados_iniciais.sql`: Duim, serviços, horários e formas de pagamento. **Os preços são de exemplo.**
   - `006_correcoes_revisao.sql`: correções de segurança e regras.
   - `007_gestao.sql`: planos, clientes, painel do mês, comissão, Pix e logins da equipe.
   - `008_seguranca_funcoes.sql`: fecha as funções auxiliares pra quem chama pela API.
   - `009_mensagens_automaticas.sql`: fila das mensagens automáticas do WhatsApp (nasce desligada; ver passo 8).
3. Recomendado: em **Database › Extensions**, ative `pg_cron` e rode o `005_tarefas_automaticas.sql` (marca planos vencidos como atrasados toda madrugada). A ordem dele não importa. Se for ativar as mensagens automáticas, pule este item: o script do passo 8 já faz isso.

> Projeto que já estava no ar com a Fase 1: rode só a `006` (se ainda não rodou), a `007`, a `008` e a `009`, nessa ordem. **Rode o banco antes de publicar o site novo**, senão a Minha área, o Caixa e as telas novas quebram.

## 2. Login do Duim

1. **Authentication › Users › Add user › Create new user.** Coloque e-mail e senha e marque **Auto Confirm User**.
2. Copie o **UID** do usuário criado e rode no SQL Editor:
   ```sql
   insert into perfis (id, nome, papel, barbeiro_id)
   select 'COLE-O-UID-AQUI', 'Duim', 'dono', id from barbeiros where nome = 'Duim';
   ```
3. **Importante:** em **Authentication › Sign In / Providers › Email**, desligue **"Allow new users to sign up"**. Assim ninguém cria conta sozinho. Mesmo sem isso, uma conta sem perfil não vê nada, mas é melhor fechar.

### Barbeiro novo (quando contratar)
1. No painel, em **Ajustes › Equipe**, adicione o barbeiro, configure a comissão e os dias e horários dele.
2. No Supabase, em **Authentication › Users › Add user**, crie o login dele (e-mail e senha, **Auto Confirm User**).
3. No painel, em **Ajustes › Logins da equipe**, coloque o mesmo e-mail e escolha o barbeiro. Pronto: ele já entra.

O barbeiro vê só a própria agenda. Início, caixa, clientes, planos e ajustes ficam só para o dono. Pra tirar o acesso de alguém: **Ajustes › Logins da equipe › Desligar acesso**.

## 3. Ligar o site ao banco

Em **Project Settings › API**, copie a **Project URL** e a **anon public key** para `js/config.js`:
```js
export const SUPABASE_URL = 'https://xxxx.supabase.co';
export const SUPABASE_ANON_KEY = 'eyJ...';
```
A anon key pode ficar no código, porque ela é pública por natureza. Quem protege os dados é o RLS.
**Nunca** coloque a `service_role` key no site.

## 4. Publicar no GitHub Pages

1. Crie um repositório **público** no GitHub (o Pages grátis exige) e suba todos os arquivos desta pasta, com o `index.html` na raiz. Não há segredo no código.
2. Em **Settings › Pages**, escolha **Deploy from a branch**, branch `main`, pasta `/ (root)`.
3. Em 1 ou 2 minutos o site fica no ar:
   - **Clientes:** `https://SEU-USUARIO.github.io/NOME-DO-REPO/`
   - **Equipe:** `https://SEU-USUARIO.github.io/NOME-DO-REPO/equipe/`
4. No Supabase, em **Authentication › URL Configuration**, coloque a URL do site em **Site URL**.

**Domínio próprio (opcional):** registre o domínio (`.com.br` no registro.br) em nome do Duim, crie um arquivo `CNAME` na raiz com ele (ex.: `agenda.corteduamigo.com.br`) e configure o DNS como o GitHub mostra em Settings › Pages. Marque **Enforce HTTPS**.

**App no celular do Duim:** abra `/equipe/` no Chrome do celular › menu › **Adicionar à tela inicial**. Abre direto no Início.

**Atualizar depois:** é só subir os arquivos novos no `main`. O app instalado pega a versão nova na próxima vez que abrir com internet.

## 5. Backup semanal automático

O Supabase grátis não faz backup. O arquivo `.github/workflows/backup.yml` faz um toda segunda às 6h (horário de Brasília), criptografado, e guarda por 90 dias no próprio GitHub.

1. No Supabase, clique em **Connect** (no topo) › **Session pooler** e copie a connection string (`postgresql://postgres.xxxx:[SENHA]@aws-0-sa-east-1.pooler.supabase.com:5432/postgres`). Troque `[SENHA]` pela senha do banco (a que você criou junto com o projeto; dá pra trocar em **Project Settings › Database**).
2. No GitHub, em **Settings › Secrets and variables › Actions › New repository secret**, crie dois segredos:
   - `SUPABASE_DB_URL`: a connection string do passo 1.
   - `BACKUP_SENHA`: uma senha longa só pro backup. **Guarde num lugar seguro**: sem ela o backup não abre.
3. Em **Actions › Backup semanal do banco › Run workflow**, rode uma vez pra testar. O arquivo aparece em **Artifacts** no fim da execução.

O repositório é público e qualquer pessoa logada no GitHub consegue baixar o arquivo, por isso ele sai criptografado. Pra abrir:
```bash
gpg --decrypt backup-AAAA-MM-DD.sql.gz.gpg | gunzip > backup.sql
```

## 6. Primeiros ajustes no painel (logado como Duim)

Em **Início › engrenagem (Ajustes)**. O que aparece como **"Definir"** precisa ser preenchido:
- **Serviços e preços:** preços e durações reais.
- **Formas de pagamento:** taxa da maquininha (InfinitePay) no crédito e no débito.
- **Recebimento por Pix:** chave Pix, nome e cidade. Com isso o finalizar e a cobrança de plano já mostram o Pix copia e cola com o valor.
- **Dados da barbearia:** WhatsApp, endereço e prazo de cancelamento (padrão de 2 horas, a confirmar com o Duim).
- **Dias e horário:** já vem de terça a sábado, das 9h às 19h30.
- **Equipe:** comissão de cada barbeiro (% do serviço ou valor por atendimento).

Em **Planos**: crie os planos mensais (preço, cortes por mês e serviços que cobrem).

Para a pausa de almoço: **Agenda › cadeado › Um período › Repetir toda semana**.

Regras com valor padrão que dá pra mudar direto no banco (tabela `configuracoes`): `agendar_ate_dias` (60, até quantos dias pra frente o cliente marca) e `limite_agendamentos_hora` (20, teto de marcações pelo site por hora, contra abuso).

## 7. Testar no computador

```bash
python -m http.server 8000
# abrir http://localhost:8000
```
É preciso servir por HTTP, porque os módulos JS não funcionam abrindo o arquivo direto (com dois cliques aparece um aviso).

## 8. Mensagens automáticas do WhatsApp (quando o Duim aprovar)

Já está tudo pronto e **desligado**: a fila no banco (`009`), a função de envio `whatsapp-enviar` publicada no Supabase e a tela em **Ajustes › Mensagens automáticas**. Sem a chave da Meta nada é enviado. Custo: a Meta cobra por mensagem (cerca de R$ 0,035 as de utilidade e R$ 0,32 as de marketing).

**1. Conta e número na Meta**
1. Crie (ou use) o portfólio da empresa em business.facebook.com.
2. Em developers.facebook.com › Meus apps › Criar app (tipo **Empresa**), adicione o produto **WhatsApp**.
3. Em **WhatsApp › Configuração da API**, adicione o número da barbearia. Se a Meta oferecer a **coexistência**, dá pra manter o mesmo número no app WhatsApp Business; se não, use um número só pras mensagens automáticas.
4. Adicione uma forma de pagamento no WhatsApp Manager (a Meta cobra por mensagem).

**2. Modelos de mensagem:** cadastre os 6 modelos de `supabase/functions/whatsapp-enviar/MODELOS.md`, com o nome exato, e espere a aprovação.

**3. Chave permanente**
1. Em **Configurações do negócio › Usuários do sistema**, crie um usuário de sistema (Admin), dê acesso ao app e à conta do WhatsApp.
2. **Gerar token**: escolha o app, validade **Nunca** e as permissões `whatsapp_business_messaging` e `whatsapp_business_management`. Guarde o token (ele aparece uma vez só).
3. Copie o **Phone number ID** em **WhatsApp › Configuração da API** (é um número comprido, não o telefone).

**4. Ligar no Supabase**
1. No **SQL Editor**, rode `supabase/ativar_mensagens.sql`. Ele liga o pg_cron e o pg_net, agenda as rotinas e mostra no fim um `cron_secret`: copie.
2. Em **Edge Functions › whatsapp-enviar › Secrets**, crie: `WHATSAPP_TOKEN` (o token), `WHATSAPP_PHONE_NUMBER_ID` (o ID) e `CRON_SECRET` (o valor copiado). **Nunca** coloque esses valores em arquivo do repositório.

**5. Ligar no painel:** em **Ajustes › Mensagens automáticas**, coloque o endereço do site, marque **Ligar mensagens automáticas**, escolha os tipos e salve. Em até 5 minutos a situação muda para **Conectado**. Teste marcando um horário com o seu número.

Erros aparecem na mesma tela (as últimas mensagens e o último erro da Meta). Pra pausar, desmarque **Ligar** e salve: o que estava na fila é cancelado.

**Republicar a função** (só se mudar o código): com a CLI do Supabase, `supabase functions deploy whatsapp-enviar --no-verify-jwt`. Ela precisa do `--no-verify-jwt` porque quem chama é o pg_cron, com a senha `CRON_SECRET`.

---

## Testes

**Banco (rodam sozinhos):** ficam em `supabase/testes/`. O `rodar.mjs` sobe um Postgres embutido (PGlite) na memória, aplica as migrations (menos a 005, que precisa do pg_cron) e roda os arquivos de teste. O passo a passo está no topo do `rodar.mjs`; o PGlite é instalado numa pasta fora do projeto. São 59 testes:
- Agendamento: dois clientes no mesmo horário (só um consegue), grade, horizonte, teto por hora, telefone, acesso só pelo token.
- Agenda: bloqueios (inclusive semanal) e atraso.
- Finalizar: troco, taxa, fiado, plano com serviço fora da lista.
- Caixa: despesa no dia certo, "deve ter na gaveta", fechamento desatualizado.
- Gestão: planos (assinar, renovar em dia e atrasado, pagamento repetido, cancelar), clientes (sumidos, assinantes, fiado, busca, ficha), painel do mês e comissão, horários, logins da equipe, Pix.
- Mensagens automáticas: nascem desligadas; confirmação e lembrete ao marcar; lembrete cancelado ou remarcado junto com o horário; aviso de agenda fechada e de horário mudado; envio com 3 tentativas; nada sai atrasado; cobrança de plano e sumido uma vez só; ligar e desligar pelo painel.
- Permissões: o público não lê tabela nenhuma, barbeiro não vê o financeiro nem a fila de mensagens, funções internas não são chamáveis de fora, e só a função do Supabase pega mensagens pra enviar.

**Telas:** todas abertas no navegador contra um banco de teste com as migrations reais: fluxo do cliente completo, login do dono e do barbeiro, início, agenda, finalizar com Pix, caixa, clientes (busca, filtros, ficha), planos (criar, assinar, renovar com Pix) e ajustes (Pix, horários, logins).

**Antes de usar de verdade, no Supabase:** repetir o teste de aceite com dois navegadores tentando o mesmo horário ao mesmo tempo (o banco embutido tem uma conexão só, então a concorrência real só se testa lá).

## Próxima fase (opcional, ver CLAUDE.md)

- Mensagens automáticas: prontas, falta só ativar (passo 8).
- Cobrança recorrente do plano (Pix automático ou link de pagamento).
