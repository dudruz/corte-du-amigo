-- Corte DÚ Amigo · testes · 01 · Apoio (roda DEPOIS das migrations)
-- Logins de teste e funções de ajuda. Cada teste roda numa transação que é desfeita no fim,
-- então o que está aqui é o ponto de partida de todos eles.

create schema teste;
grant usage on schema teste to public;

-- ───────────────────────── logins ─────────────────────────

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000d', 'dono@teste'),
  ('00000000-0000-0000-0000-00000000000b', 'barbeiro@teste'),
  ('00000000-0000-0000-0000-00000000000c', 'sem-agenda@teste'),
  ('00000000-0000-0000-0000-00000000000e', 'sem-perfil@teste');

insert into barbeiros (id, nome, apelido) values
  ('00000000-0000-0000-0000-0000000000b2', 'Zeca', 'Zeca');
insert into horarios_trabalho (barbeiro_id, dia_semana, inicio, fim)
select '00000000-0000-0000-0000-0000000000b2', d, '09:00', '19:30' from generate_series(2, 6) d;

insert into perfis (id, nome, papel, barbeiro_id) values
  ('00000000-0000-0000-0000-00000000000d', 'Duim', 'dono', (select id from barbeiros where nome = 'Duim')),
  ('00000000-0000-0000-0000-00000000000b', 'Zeca', 'barbeiro', '00000000-0000-0000-0000-0000000000b2'),
  ('00000000-0000-0000-0000-00000000000c', 'Novato', 'barbeiro', null);

create function teste.dono() returns uuid language sql immutable as
  $$ select '00000000-0000-0000-0000-00000000000d'::uuid $$;
create function teste.barbeiro() returns uuid language sql immutable as
  $$ select '00000000-0000-0000-0000-00000000000b'::uuid $$;
create function teste.barbeiro_sem_agenda() returns uuid language sql immutable as
  $$ select '00000000-0000-0000-0000-00000000000c'::uuid $$;
create function teste.sem_perfil() returns uuid language sql immutable as
  $$ select '00000000-0000-0000-0000-00000000000e'::uuid $$;

-- ───────────────────────── quem está chamando ─────────────────────────

-- Visitante do site: papel anon, sem login.
create function teste.como_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  set local role anon;
end $$;

-- Alguém logado: papel authenticated com o id no claim.
create function teste.como(p_usuario uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_usuario::text, true);
  set local role authenticated;
end $$;

-- Volta a ser o dono do banco, pra conferir as tabelas direto (sem RLS).
create function teste.como_admin() returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- ───────────────────────── atalhos de dados ─────────────────────────

create function teste.duim() returns uuid language sql stable security definer set search_path = public as
  $$ select id from barbeiros where nome = 'Duim' $$;
create function teste.zeca() returns uuid language sql immutable as
  $$ select '00000000-0000-0000-0000-0000000000b2'::uuid $$;
create function teste.servico(p_nome text) returns uuid language sql stable security definer set search_path = public as
  $$ select id from servicos where nome = p_nome $$;
create function teste.forma(p_tipo text) returns uuid language sql stable security definer set search_path = public as
  $$ select id from formas_pagamento where tipo = p_tipo $$;

create function teste.hoje() returns date language sql stable as
  $$ select (now() at time zone 'America/Sao_Paulo')::date $$;

-- Próximo dia da semana pedido (0 = domingo ... 6 = sábado), sempre depois de hoje.
-- p_semanas pula semanas inteiras pra frente.
create function teste.dia(p_dow integer, p_semanas integer default 0) returns date language sql stable as $$
  select teste.hoje() + (((p_dow - extract(dow from teste.hoje())::integer + 6) % 7) + 1) + 7 * p_semanas
$$;

-- Dia + hora de Belo Horizonte.
create function teste.em(p_dia date, p_hora time) returns timestamptz language sql stable as
  $$ select (p_dia + p_hora) at time zone 'America/Sao_Paulo' $$;

-- Marca um horário e devolve o id do agendamento (o público só recebe o token).
create function teste.marcar(p_barbeiro uuid, p_inicio timestamptz, p_telefone text,
                             p_servicos text[] default array['Corte'], p_nome text default 'Cliente Teste')
returns uuid language plpgsql security definer set search_path = public as $$
declare v_token uuid;
begin
  v_token := criar_agendamento(
    (select array_agg(id) from servicos where nome = any(p_servicos)), p_barbeiro, p_inicio, p_nome, p_telefone);
  return (select id from agendamentos where token = v_token);
end $$;

create function teste.status(p_agendamento uuid) returns text
language sql stable security definer set search_path = public as
  $$ select status::text from agendamentos where id = p_agendamento $$;

-- ───────────────────────── conferências ─────────────────────────

create function teste.confere(p_ok boolean, p_o_que text) returns void language plpgsql as $$
begin
  if p_ok is not true then
    raise exception 'FALHOU: %', p_o_que;
  end if;
end $$;

create function teste.igual(p_veio anyelement, p_esperado anyelement, p_o_que text) returns void language plpgsql as $$
begin
  if p_veio is distinct from p_esperado then
    raise exception 'FALHOU: % (esperado %, veio %)', p_o_que, coalesce(p_esperado::text, 'nulo'), coalesce(p_veio::text, 'nulo');
  end if;
end $$;

-- O comando precisa dar erro, e a mensagem precisa conter o trecho esperado.
create function teste.espera_erro(p_sql text, p_trecho text) returns void language plpgsql as $$
declare v_msg text;
begin
  begin
    execute p_sql;
  exception when others then
    v_msg := sqlerrm;
  end;
  if v_msg is null then
    raise exception 'FALHOU: devia dar erro com "%" e passou: %', p_trecho, p_sql;
  end if;
  if position(p_trecho in v_msg) = 0 then
    raise exception 'FALHOU: esperava erro com "%" e veio "%" em: %', p_trecho, v_msg, p_sql;
  end if;
end $$;

-- pode_barbeiro() não é chamável pela API (008); o teste pergunta por aqui, como dono do banco,
-- com o login do teste ainda valendo (auth.uid() lê o claim).
create function teste.pode_barbeiro(p_barbeiro uuid) returns boolean
language sql stable security definer set search_path = public as
  $$ select pode_barbeiro(p_barbeiro) $$;
grant execute on function teste.pode_barbeiro(uuid) to public;

-- A função de envio do Supabase roda como service_role.
create function teste.como_servico() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  set local role service_role;
end $$;

-- Liga as mensagens automáticas direto na configuração (sem passar pela tela).
create function teste.ligar_mensagens(p_extra jsonb default '{}') returns void
language sql security definer set search_path = public as $$
  update configuracoes set valor = valor || '{"ativo": true}'::jsonb || p_extra where chave = 'mensagens_automaticas';
  update configuracoes set valor = '"https://corte.test/"' where chave = 'site_url';
$$;
grant execute on function teste.ligar_mensagens(jsonb) to public;

create function teste.fila(p_tipo text default null) returns bigint
language sql stable security definer set search_path = public as
  $$ select count(*) from mensagens where status = 'pendente' and (p_tipo is null or tipo = p_tipo) $$;
grant execute on function teste.fila(text) to public;
