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
3. Recomendado: em **Database › Extensions**, ative `pg_cron` e rode o `005_tarefas_automaticas.sql` (marca planos vencidos como atrasados toda madrugada). A ordem dele não importa.

> Projeto que já estava no ar com a Fase 1: rode só a `006` (se ainda não rodou), a `007` e a `008`, nessa ordem. **Rode o banco antes de publicar o site novo**, senão a Minha área, o Caixa e as telas novas quebram.

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

---

## Testes

**Banco (rodam sozinhos):** ficam em `supabase/testes/`. O `rodar.mjs` sobe um Postgres embutido (PGlite) na memória, aplica as migrations (menos a 005, que precisa do pg_cron) e roda os arquivos de teste. O passo a passo está no topo do `rodar.mjs`; o PGlite é instalado numa pasta fora do projeto. São 48 testes:
- Agendamento: dois clientes no mesmo horário (só um consegue), grade, horizonte, teto por hora, telefone, acesso só pelo token.
- Agenda: bloqueios (inclusive semanal) e atraso.
- Finalizar: troco, taxa, fiado, plano com serviço fora da lista.
- Caixa: despesa no dia certo, "deve ter na gaveta", fechamento desatualizado.
- Gestão: planos (assinar, renovar em dia e atrasado, pagamento repetido, cancelar), clientes (sumidos, assinantes, fiado, busca, ficha), painel do mês e comissão, horários, logins da equipe, Pix.
- Permissões: o público não lê tabela nenhuma, barbeiro não vê o financeiro, funções internas não são chamáveis de fora.

**Telas:** todas abertas no navegador contra um banco de teste com as migrations reais: fluxo do cliente completo, login do dono e do barbeiro, início, agenda, finalizar com Pix, caixa, clientes (busca, filtros, ficha), planos (criar, assinar, renovar com Pix) e ajustes (Pix, horários, logins).

**Antes de usar de verdade, no Supabase:** repetir o teste de aceite com dois navegadores tentando o mesmo horário ao mesmo tempo (o banco embutido tem uma conexão só, então a concorrência real só se testa lá).

## Próxima fase (opcional, ver CLAUDE.md)

- Lembretes automáticos pela API oficial do WhatsApp (custo por mensagem).
- Cobrança recorrente do plano (Pix automático ou link de pagamento).
