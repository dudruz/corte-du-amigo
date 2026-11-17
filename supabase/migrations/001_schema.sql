-- Corte DÚ Amigo · 001 · Estrutura do banco
-- Rodar no SQL Editor do Supabase, na ordem dos arquivos (001 → 004).

create extension if not exists btree_gist with schema extensions;

create type papel_t as enum ('dono', 'barbeiro');
create type status_ag as enum ('marcado', 'em_atendimento', 'finalizado', 'cancelado', 'faltou');

create table barbeiros (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  apelido text,
  foto_url text,
  comissao_tipo text check (comissao_tipo in ('percentual', 'fixo_por_corte')),
  comissao_valor integer,
  ativo boolean not null default true,
  criado_em timestamptz not null default now()
);

-- Um perfil por login da equipe (id = auth.users.id)
create table perfis (
  id uuid primary key references auth.users on delete cascade,
  nome text not null,
  papel papel_t not null,
  barbeiro_id uuid references barbeiros,
  ativo boolean not null default true
);

create table servicos (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  preco_centavos integer not null check (preco_centavos >= 0),
  duracao_min integer not null check (duracao_min > 0),
  ativo boolean not null default true,
  ordem integer not null default 0
);

-- dia_semana: 0 = domingo ... 6 = sábado
create table horarios_trabalho (
  id uuid primary key default gen_random_uuid(),
  barbeiro_id uuid not null references barbeiros on delete cascade,
  dia_semana smallint not null check (dia_semana between 0 and 6),
  inicio time not null,
  fim time not null,
  check (fim > inicio)
);

-- barbeiro_id nulo = barbearia toda fechada.
-- recorrente_semanal: repete toda semana no mesmo dia e horário, a partir de "inicio".
create table bloqueios (
  id uuid primary key default gen_random_uuid(),
  barbeiro_id uuid references barbeiros on delete cascade,
  inicio timestamptz not null,
  fim timestamptz not null,
  recorrente_semanal boolean not null default false,
  motivo text,
  criado_por uuid references auth.users,
  criado_em timestamptz not null default now(),
  check (fim > inicio)
);

create table clientes (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  telefone text not null unique,          -- só dígitos com DDI: 5531999998888
  aceita_lembrete boolean not null default true,
  observacoes text,
  faltas integer not null default 0,
  criado_em timestamptz not null default now()
);

create table agendamentos (
  id uuid primary key default gen_random_uuid(),
  token uuid not null unique default gen_random_uuid(),   -- link secreto do cliente
  cliente_id uuid not null references clientes,
  barbeiro_id uuid not null references barbeiros,
  periodo tstzrange not null,
  status status_ag not null default 'marcado',
  cancelado_motivo text,
  usa_plano boolean not null default false,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  -- Garante no banco que o mesmo barbeiro nunca tem dois horários sobrepostos
  constraint agendamentos_sem_conflito
    exclude using gist (barbeiro_id with =, periodo with &&)
    where (status in ('marcado', 'em_atendimento'))
    deferrable initially immediate
);
create index on agendamentos (cliente_id);
create index on agendamentos using gist (periodo);

-- Preço e duração congelados no momento do agendamento
create table agendamento_servicos (
  agendamento_id uuid not null references agendamentos on delete cascade,
  servico_id uuid not null references servicos,
  nome text not null,
  preco_centavos integer not null,
  duracao_min integer not null,
  primary key (agendamento_id, servico_id)
);

create table formas_pagamento (
  id uuid primary key default gen_random_uuid(),
  nome text not null unique,
  tipo text not null check (tipo in ('pix', 'dinheiro', 'credito', 'debito', 'plano', 'fiado')),
  taxa_percentual numeric(5, 2) not null default 0,
  ativa boolean not null default true,
  ordem integer not null default 0
);

create table atendimentos (
  id uuid primary key default gen_random_uuid(),
  agendamento_id uuid unique references agendamentos,
  cliente_id uuid not null references clientes,
  barbeiro_id uuid not null references barbeiros,
  total_centavos integer not null,
  desconto_centavos integer not null default 0,
  gorjeta_centavos integer not null default 0,
  finalizado_em timestamptz not null default now(),
  finalizado_por uuid references auth.users
);

create table pagamentos (
  id uuid primary key default gen_random_uuid(),
  atendimento_id uuid not null references atendimentos on delete cascade,
  forma_pagamento_id uuid not null references formas_pagamento,
  bruto_centavos integer not null,
  taxa_centavos integer not null default 0,
  liquido_centavos integer not null,
  recebido_dinheiro_centavos integer,
  troco_centavos integer,
  pendente boolean not null default false,   -- fiado em aberto
  quitado_em timestamptz,
  quitado_forma_id uuid references formas_pagamento
);

create table planos (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  descricao text,
  preco_centavos integer not null,
  usos_por_mes integer,                      -- nulo = ilimitado
  ativo boolean not null default true
);

create table assinaturas (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references clientes,
  plano_id uuid not null references planos,
  inicio date not null default current_date,
  vence_em date not null,
  status text not null default 'ativa' check (status in ('ativa', 'atrasada', 'cancelada'))
);

create table usos_plano (
  id uuid primary key default gen_random_uuid(),
  assinatura_id uuid not null references assinaturas,
  atendimento_id uuid references atendimentos,
  usado_em timestamptz not null default now()
);

create table caixa_movimentos (
  id uuid primary key default gen_random_uuid(),
  data date not null default ((now() at time zone 'America/Sao_Paulo')::date),
  tipo text not null check (tipo in ('entrada', 'saida')),
  origem text not null check (origem in ('atendimento', 'plano', 'despesa', 'fiado_quitado', 'ajuste')),
  descricao text not null,
  forma_pagamento_id uuid references formas_pagamento,
  bruto_centavos integer not null,
  liquido_centavos integer not null,
  referencia_id uuid,
  criado_por uuid references auth.users,
  criado_em timestamptz not null default now()
);
create index on caixa_movimentos (data);

create table caixa_dia (
  data date primary key,
  troco_inicial_centavos integer not null default 0,
  esperado_dinheiro_centavos integer,
  contado_dinheiro_centavos integer,
  diferenca_centavos integer,
  fechado_em timestamptz,
  fechado_por uuid references auth.users
);

create table configuracoes (
  chave text primary key,
  valor jsonb
);
