-- Corte DÚ Amigo · 002 · Regras de negócio (funções RPC)
-- Toda escrita importante passa por aqui. O front nunca grava direto nas tabelas.

-- ───────────────────────── utilitários ─────────────────────────

create or replace function fuso() returns text
language sql immutable as $$ select 'America/Sao_Paulo' $$;

create or replace function cfg(p_chave text) returns jsonb
language sql stable security definer set search_path = public as $$
  select valor from configuracoes where chave = p_chave
$$;

create or replace function cfg_int(p_chave text, p_padrao integer) returns integer
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select case when jsonb_typeof(valor) = 'number' then (valor)::numeric::integer end
       from configuracoes where chave = p_chave),
    p_padrao)
$$;

create or replace function eh_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfis where id = auth.uid() and ativo)
$$;

create or replace function eh_dono() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfis where id = auth.uid() and ativo and papel = 'dono')
$$;

create or replace function barbeiro_atual() returns uuid
language sql stable security definer set search_path = public as $$
  select barbeiro_id from perfis where id = auth.uid() and ativo
$$;

create or replace function pode_barbeiro(p_barbeiro uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select eh_dono() or (eh_equipe() and barbeiro_atual() = p_barbeiro)
$$;

create or replace function exigir_equipe() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not eh_equipe() then
    raise exception 'Acesso só para a equipe.' using errcode = '42501';
  end if;
end $$;

create or replace function exigir_dono() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not eh_dono() then
    raise exception 'Só o dono pode fazer isso.' using errcode = '42501';
  end if;
end $$;

create or replace function normalizar_telefone(p text) returns text
language plpgsql immutable as $$
declare d text := regexp_replace(coalesce(p, ''), '\D', '', 'g');
begin
  if length(d) in (10, 11) then d := '55' || d; end if;
  if length(d) not in (12, 13) then
    raise exception 'WhatsApp inválido. Coloca DDD + número.';
  end if;
  return d;
end $$;

create or replace function duracao_servicos(p_ids uuid[]) returns integer
language sql stable security definer set search_path = public as $$
  select case when count(*) = 0 then null else sum(duracao_min)::integer end
  from servicos where id = any(p_ids) and ativo
$$;

-- ───────────────────────── disponibilidade ─────────────────────────

create or replace function bloqueio_conflita(p_barbeiro uuid, p_ini timestamptz, p_fim timestamptz)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from bloqueios k
    where (k.barbeiro_id is null or k.barbeiro_id = p_barbeiro)
      and (
        (not k.recorrente_semanal and tstzrange(k.inicio, k.fim) && tstzrange(p_ini, p_fim))
        or (
          k.recorrente_semanal
          and extract(dow from k.inicio at time zone fuso()) = extract(dow from p_ini at time zone fuso())
          and (p_ini at time zone fuso())::date >= (k.inicio at time zone fuso())::date
          and tstzrange(
                ((p_ini at time zone fuso())::date + (k.inicio at time zone fuso())::time) at time zone fuso(),
                ((p_ini at time zone fuso())::date + (k.fim at time zone fuso())::time) at time zone fuso()
              ) && tstzrange(p_ini, p_fim)
        )
      )
  )
$$;

-- Horário dentro do expediente, no futuro e sem bloqueio (não olha outros agendamentos)
create or replace function slot_valido(p_barbeiro uuid, p_ini timestamptz, p_fim timestamptz)
returns boolean
language sql stable security definer set search_path = public as $$
  select p_ini > now()
    and exists (select 1 from barbeiros b where b.id = p_barbeiro and b.ativo)
    and exists (
      select 1 from horarios_trabalho h
      where h.barbeiro_id = p_barbeiro
        and h.dia_semana = extract(dow from p_ini at time zone fuso())
        and (p_ini at time zone fuso())::date = ((p_fim - interval '1 second') at time zone fuso())::date
        and (p_ini at time zone fuso())::time >= h.inicio
        and (p_fim at time zone fuso())::time <= h.fim
    )
    and not bloqueio_conflita(p_barbeiro, p_ini, p_fim)
$$;

create or replace function horarios_livres(p_servico_ids uuid[], p_barbeiro_id uuid, p_dia date)
returns table (inicio timestamptz, barbeiro_id uuid)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_dur integer := duracao_servicos(p_servico_ids);
  v_passo integer := cfg_int('intervalo_slots_min', 30);
begin
  if v_dur is null then
    raise exception 'Escolha pelo menos um serviço.';
  end if;
  return query
  select distinct on (s.ini) s.ini, s.bid
  from (
    select gs as ini, b.id as bid, b.nome as bnome
    from barbeiros b
    join horarios_trabalho h on h.barbeiro_id = b.id and h.dia_semana = extract(dow from p_dia)
    cross join lateral generate_series(
      (p_dia + h.inicio) at time zone fuso(),
      ((p_dia + h.fim) at time zone fuso()) - make_interval(mins => v_dur),
      make_interval(mins => v_passo)
    ) gs
    where b.ativo and (p_barbeiro_id is null or b.id = p_barbeiro_id)
  ) s
  where slot_valido(s.bid, s.ini, s.ini + make_interval(mins => v_dur))
    and not exists (
      select 1 from agendamentos a
      where a.barbeiro_id = s.bid
        and a.status in ('marcado', 'em_atendimento')
        and a.periodo && tstzrange(s.ini, s.ini + make_interval(mins => v_dur))
    )
  order by s.ini, s.bnome;
end $$;

create or replace function dias_disponiveis(p_servico_ids uuid[], p_barbeiro_id uuid, p_qtd integer default 14)
returns table (dia date, livre boolean)
language sql stable security definer set search_path = public as $$
  select d::date,
         exists (select 1 from horarios_livres(p_servico_ids, p_barbeiro_id, d::date))
  from generate_series(
         (now() at time zone fuso())::date::timestamp,
         ((now() at time zone fuso())::date + (least(greatest(p_qtd, 1), 31) - 1))::timestamp,
         interval '1 day') d
  where exists (
    select 1 from horarios_trabalho h join barbeiros b on b.id = h.barbeiro_id
    where b.ativo and h.dia_semana = extract(dow from d)
      and (p_barbeiro_id is null or h.barbeiro_id = p_barbeiro_id)
  )
  order by 1
$$;

create or replace function dados_publicos() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'servicos', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'nome', nome, 'preco_centavos', preco_centavos,
                                          'duracao_min', duracao_min) order by ordem, nome)
      from servicos where ativo), '[]'::jsonb),
    'barbeiros', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'nome', coalesce(apelido, nome), 'foto_url', foto_url) order by nome)
      from barbeiros where ativo), '[]'::jsonb),
    'whatsapp', cfg('whatsapp_barbearia'),
    'endereco', cfg('endereco'),
    'horario_texto', cfg('horario_texto'),
    'cancelamento_horas', cfg_int('cancelamento_antecedencia_horas', 2)
  )
$$;

-- ───────────────────────── cliente (público) ─────────────────────────

create or replace function plano_do_cliente(p_cliente uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'assinatura_id', a.id, 'nome', p.nome, 'usos_por_mes', p.usos_por_mes,
    'usados', (select count(*) from usos_plano u
               where u.assinatura_id = a.id and u.usado_em >= (a.vence_em - interval '1 month')),
    'vence_em', a.vence_em,
    'status', case when a.status = 'ativa' and a.vence_em < (now() at time zone fuso())::date
                   then 'atrasada' else a.status end,
    'preco_centavos', p.preco_centavos)
  from assinaturas a join planos p on p.id = a.plano_id
  where a.cliente_id = p_cliente and a.status in ('ativa', 'atrasada')
  order by a.vence_em desc
  limit 1
$$;

create or replace function resumo_agendamento(p_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', a.id, 'token', a.token, 'status', a.status,
    'inicio', lower(a.periodo), 'fim', upper(a.periodo),
    'barbeiro_id', a.barbeiro_id, 'barbeiro', coalesce(b.apelido, b.nome),
    'servicos', coalesce((select jsonb_agg(s.nome order by s.nome) from agendamento_servicos s where s.agendamento_id = a.id), '[]'::jsonb),
    'servico_ids', coalesce((select jsonb_agg(s.servico_id) from agendamento_servicos s where s.agendamento_id = a.id), '[]'::jsonb),
    'total_centavos', coalesce((select sum(s.preco_centavos) from agendamento_servicos s where s.agendamento_id = a.id), 0))
  from agendamentos a join barbeiros b on b.id = a.barbeiro_id
  where a.id = p_id
$$;

create or replace function criar_agendamento(
  p_servico_ids uuid[], p_barbeiro_id uuid, p_inicio timestamptz,
  p_nome text, p_telefone text, p_aceita_lembrete boolean default true)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_nome text := btrim(coalesce(p_nome, ''));
  v_tel text;
  v_dur integer;
  v_fim timestamptz;
  v_barbeiro uuid := p_barbeiro_id;
  v_cli uuid;
  v_ag uuid;
  v_token uuid;
begin
  if length(v_nome) < 2 or length(v_nome) > 80 then
    raise exception 'Coloca seu nome (de 2 a 80 letras).';
  end if;
  v_tel := normalizar_telefone(p_telefone);
  v_dur := duracao_servicos(p_servico_ids);
  if v_dur is null then raise exception 'Escolha pelo menos um serviço.'; end if;
  v_fim := p_inicio + make_interval(mins => v_dur);

  if v_barbeiro is null then
    select hl.barbeiro_id into v_barbeiro
    from horarios_livres(p_servico_ids, null, (p_inicio at time zone fuso())::date) hl
    where hl.inicio = p_inicio limit 1;
    if v_barbeiro is null then raise exception 'Esse horário acabou de ser pego. Escolhe outro.'; end if;
  elsif not slot_valido(v_barbeiro, p_inicio, v_fim) then
    raise exception 'Esse horário não está disponível. Escolhe outro.';
  end if;

  insert into clientes (nome, telefone, aceita_lembrete)
  values (v_nome, v_tel, coalesce(p_aceita_lembrete, true))
  on conflict (telefone) do update set aceita_lembrete = excluded.aceita_lembrete
  returning id into v_cli;

  if (select count(*) from agendamentos
      where cliente_id = v_cli and status = 'marcado' and lower(periodo) > now()) >= 3 then
    raise exception 'Você já tem 3 horários marcados. Cancela um antes de marcar outro.';
  end if;

  begin
    insert into agendamentos (cliente_id, barbeiro_id, periodo)
    values (v_cli, v_barbeiro, tstzrange(p_inicio, v_fim))
    returning id, token into v_ag, v_token;
  exception when exclusion_violation then
    raise exception 'Esse horário acabou de ser pego. Escolhe outro.';
  end;

  insert into agendamento_servicos (agendamento_id, servico_id, nome, preco_centavos, duracao_min)
  select v_ag, s.id, s.nome, s.preco_centavos, s.duracao_min
  from servicos s where s.id = any(p_servico_ids) and s.ativo;

  return v_token;
end $$;

create or replace function agendamento_por_token(p_token uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v agendamentos;
begin
  select * into v from agendamentos where token = p_token;
  if not found then return null; end if;
  return jsonb_build_object(
    'atual', resumo_agendamento(v.id),
    'cliente', (select jsonb_build_object('nome', c.nome, 'telefone', c.telefone) from clientes c where c.id = v.cliente_id),
    'proximos', coalesce((
      select jsonb_agg(resumo_agendamento(a.id) order by lower(a.periodo))
      from agendamentos a
      where a.cliente_id = v.cliente_id and a.status = 'marcado' and lower(a.periodo) > now()), '[]'::jsonb),
    'historico', coalesce((
      select jsonb_agg(t.r order by (t.r ->> 'inicio') desc)
      from (select resumo_agendamento(a.id) as r from agendamentos a
            where a.cliente_id = v.cliente_id and a.status = 'finalizado'
            order by lower(a.periodo) desc limit 5) t), '[]'::jsonb),
    'plano', plano_do_cliente(v.cliente_id),
    'cancelamento_horas', cfg_int('cancelamento_antecedencia_horas', 2));
end $$;

create or replace function cancelar_por_token(p_token uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v agendamentos;
  v_h integer := cfg_int('cancelamento_antecedencia_horas', 2);
begin
  select * into v from agendamentos where token = p_token for update;
  if not found or v.status <> 'marcado' then
    raise exception 'Esse horário não pode mais ser cancelado.';
  end if;
  if lower(v.periodo) - now() < make_interval(hours => v_h) then
    raise exception 'Faltam menos de % horas. Pra cancelar, chama a barbearia no WhatsApp.', v_h;
  end if;
  update agendamentos set status = 'cancelado', cancelado_motivo = 'cliente', atualizado_em = now()
  where id = v.id;
end $$;

create or replace function remarcar_por_token(p_token uuid, p_novo_inicio timestamptz) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v agendamentos;
  v_h integer := cfg_int('cancelamento_antecedencia_horas', 2);
  v_dur interval;
begin
  select * into v from agendamentos where token = p_token for update;
  if not found or v.status <> 'marcado' then
    raise exception 'Esse horário não pode mais ser remarcado.';
  end if;
  if lower(v.periodo) - now() < make_interval(hours => v_h) then
    raise exception 'Faltam menos de % horas. Pra remarcar, chama a barbearia no WhatsApp.', v_h;
  end if;
  v_dur := upper(v.periodo) - lower(v.periodo);
  if not slot_valido(v.barbeiro_id, p_novo_inicio, p_novo_inicio + v_dur) then
    raise exception 'Esse horário não está disponível. Escolhe outro.';
  end if;
  begin
    update agendamentos set periodo = tstzrange(p_novo_inicio, p_novo_inicio + v_dur), atualizado_em = now()
    where id = v.id;
  exception when exclusion_violation then
    raise exception 'Esse horário acabou de ser pego. Escolhe outro.';
  end;
  return v.token;
end $$;

-- ───────────────────────── equipe: agenda ─────────────────────────

create or replace function mudar_status(p_id uuid, p_status status_ag) returns void
language plpgsql security definer set search_path = public as $$
declare v agendamentos;
begin
  select * into v from agendamentos where id = p_id for update;
  if not found then raise exception 'Agendamento não encontrado.'; end if;
  if not pode_barbeiro(v.barbeiro_id) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if not (
    (v.status = 'marcado' and p_status in ('em_atendimento', 'faltou', 'cancelado'))
    or (v.status = 'em_atendimento' and p_status = 'marcado')
  ) then
    raise exception 'Não dá pra mudar de % para %.', v.status, p_status;
  end if;
  update agendamentos
  set status = p_status,
      cancelado_motivo = case when p_status = 'cancelado' then 'equipe' else cancelado_motivo end,
      atualizado_em = now()
  where id = v.id;
  if p_status = 'faltou' then
    update clientes set faltas = faltas + 1 where id = v.cliente_id;
  end if;
end $$;

create or replace function bloqueios_do_dia(p_barbeiro uuid, p_dia date)
returns table (id uuid, inicio timestamptz, fim timestamptz, motivo text, recorrente boolean, barbearia boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform exigir_equipe();
  return query
  select k.id,
         case when k.recorrente_semanal
              then (p_dia + (k.inicio at time zone fuso())::time) at time zone fuso() else k.inicio end,
         case when k.recorrente_semanal
              then (p_dia + (k.fim at time zone fuso())::time) at time zone fuso() else k.fim end,
         k.motivo, k.recorrente_semanal, k.barbeiro_id is null
  from bloqueios k
  where (k.barbeiro_id is null or k.barbeiro_id = p_barbeiro)
    and (
      (not k.recorrente_semanal and tstzrange(k.inicio, k.fim)
         && tstzrange(p_dia::timestamp at time zone fuso(), (p_dia + 1)::timestamp at time zone fuso()))
      or (k.recorrente_semanal
          and extract(dow from k.inicio at time zone fuso()) = extract(dow from p_dia)
          and p_dia >= (k.inicio at time zone fuso())::date)
    )
  order by 2;
end $$;

-- Agenda pronta pra tela: agendamentos do dia (menos cancelados) + bloqueios
create or replace function agenda_do_dia(p_barbeiro uuid, p_dia date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not pode_barbeiro(p_barbeiro) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'itens', coalesce((
      select jsonb_agg(resumo_agendamento(a.id) || jsonb_build_object(
               'cliente', c.nome, 'telefone', c.telefone,
               'aceita_lembrete', c.aceita_lembrete, 'faltas', c.faltas)
             order by lower(a.periodo))
      from agendamentos a join clientes c on c.id = a.cliente_id
      where a.barbeiro_id = p_barbeiro and a.status <> 'cancelado'
        and a.periodo && tstzrange(p_dia::timestamp at time zone fuso(),
                                   (p_dia + 1)::timestamp at time zone fuso())), '[]'::jsonb),
    'bloqueios', coalesce((select jsonb_agg(to_jsonb(b)) from bloqueios_do_dia(p_barbeiro, p_dia) b), '[]'::jsonb));
end $$;

-- Cria o bloqueio, cancela quem estava marcado no período e devolve a lista pra avisar
create or replace function criar_bloqueio(
  p_barbeiro_id uuid, p_inicio timestamptz, p_fim timestamptz,
  p_recorrente boolean default false, p_motivo text default null)
returns table (nome text, telefone text, inicio timestamptz)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform exigir_equipe();
  if p_barbeiro_id is null and not eh_dono() then
    raise exception 'Só o dono pode fechar a barbearia toda.' using errcode = '42501';
  end if;
  if p_barbeiro_id is not null and not pode_barbeiro(p_barbeiro_id) then
    raise exception 'Você só pode fechar a sua própria agenda.' using errcode = '42501';
  end if;
  if p_fim <= p_inicio then
    raise exception 'O fim precisa ser depois do início.';
  end if;

  insert into bloqueios (barbeiro_id, inicio, fim, recorrente_semanal, motivo, criado_por)
  values (p_barbeiro_id, p_inicio, p_fim, coalesce(p_recorrente, false), nullif(btrim(p_motivo), ''), auth.uid());

  return query
  with afetados as (
    update agendamentos a
    set status = 'cancelado', cancelado_motivo = 'bloqueio', atualizado_em = now()
    where a.status = 'marcado'
      and lower(a.periodo) > now()
      and (p_barbeiro_id is null or a.barbeiro_id = p_barbeiro_id)
      and bloqueio_conflita(a.barbeiro_id, lower(a.periodo), upper(a.periodo))
    returning a.cliente_id, lower(a.periodo) as ini
  )
  select c.nome, c.telefone, af.ini
  from afetados af join clientes c on c.id = af.cliente_id
  order by af.ini;
end $$;

create or replace function remover_bloqueio(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare k bloqueios;
begin
  select * into k from bloqueios where id = p_id;
  if not found then return; end if;
  if not (eh_dono() or (k.barbeiro_id is not null and pode_barbeiro(k.barbeiro_id))) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  delete from bloqueios where id = p_id;
end $$;

-- Empurra os horários de hoje (a partir de agora) e devolve antes/depois pra avisar
create or replace function aplicar_atraso(p_barbeiro_id uuid, p_minutos integer)
returns table (nome text, telefone text, antes timestamptz, depois timestamptz)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not pode_barbeiro(p_barbeiro_id) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_minutos is null or p_minutos < 5 or p_minutos > 180 then
    raise exception 'O atraso precisa ser entre 5 e 180 minutos.';
  end if;
  set constraints agendamentos_sem_conflito deferred;

  return query
  with mov as (
    update agendamentos a
    set periodo = tstzrange(lower(a.periodo) + make_interval(mins => p_minutos),
                            upper(a.periodo) + make_interval(mins => p_minutos)),
        atualizado_em = now()
    where a.barbeiro_id = p_barbeiro_id
      and a.status = 'marcado'
      and lower(a.periodo) >= now() - interval '10 minutes'
      and (lower(a.periodo) at time zone fuso())::date = (now() at time zone fuso())::date
    returning a.cliente_id,
              lower(a.periodo) - make_interval(mins => p_minutos) as antes,
              lower(a.periodo) as depois
  )
  select c.nome, c.telefone, m.antes, m.depois
  from mov m join clientes c on c.id = m.cliente_id
  order by m.antes;
end $$;

-- ───────────────────────── equipe: finalizar ─────────────────────────

create or replace function info_finalizar(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v agendamentos;
begin
  select * into v from agendamentos where id = p_id;
  if not found then raise exception 'Agendamento não encontrado.'; end if;
  if not pode_barbeiro(v.barbeiro_id) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'agendamento', resumo_agendamento(v.id),
    'itens', coalesce((select jsonb_agg(jsonb_build_object('servico_id', s.servico_id, 'nome', s.nome,
                                                           'preco_centavos', s.preco_centavos) order by s.nome)
                       from agendamento_servicos s where s.agendamento_id = v.id), '[]'::jsonb),
    'cliente', (select jsonb_build_object('nome', c.nome, 'telefone', c.telefone) from clientes c where c.id = v.cliente_id),
    'plano', plano_do_cliente(v.cliente_id),
    'formas', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'nome', f.nome, 'tipo', f.tipo,
                                                            'taxa_percentual', f.taxa_percentual) order by f.ordem)
                        from formas_pagamento f where f.ativa), '[]'::jsonb),
    'servicos', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.nome,
                                                              'preco_centavos', s.preco_centavos) order by s.ordem)
                          from servicos s where s.ativo), '[]'::jsonb));
end $$;

create or replace function finalizar_atendimento(
  p_id uuid, p_forma_id uuid, p_extras uuid[] default '{}',
  p_desconto integer default 0, p_gorjeta integer default 0, p_recebido integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v agendamentos;
  f formas_pagamento;
  v_total integer;
  v_cobrar integer;
  v_devido integer;
  v_taxa integer;
  v_troco integer;
  v_at uuid;
  v_plano jsonb;
  v_desc integer := coalesce(p_desconto, 0);
  v_gorj integer := coalesce(p_gorjeta, 0);
begin
  select * into v from agendamentos where id = p_id for update;
  if not found then raise exception 'Agendamento não encontrado.'; end if;
  if not pode_barbeiro(v.barbeiro_id) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if v.status not in ('marcado', 'em_atendimento') then
    raise exception 'Esse atendimento já foi fechado.';
  end if;
  select * into f from formas_pagamento where id = p_forma_id and ativa;
  if not found then raise exception 'Escolha a forma de pagamento.'; end if;
  if v_desc < 0 or v_gorj < 0 then raise exception 'Valores não podem ser negativos.'; end if;

  insert into agendamento_servicos (agendamento_id, servico_id, nome, preco_centavos, duracao_min)
  select v.id, s.id, s.nome, s.preco_centavos, s.duracao_min
  from servicos s where s.id = any(coalesce(p_extras, '{}')) and s.ativo
  on conflict do nothing;

  select coalesce(sum(preco_centavos), 0) into v_total from agendamento_servicos where agendamento_id = v.id;
  if v_desc > v_total then raise exception 'O desconto é maior que o total.'; end if;
  v_cobrar := v_total - v_desc;

  if f.tipo = 'plano' then
    v_plano := plano_do_cliente(v.cliente_id);
    if v_plano is null or v_plano ->> 'status' <> 'ativa' then
      raise exception 'Esse cliente não tem plano ativo e em dia.';
    end if;
    if v_plano ->> 'usos_por_mes' is not null
       and (v_plano ->> 'usados')::integer >= (v_plano ->> 'usos_por_mes')::integer then
      raise exception 'O plano desse cliente já usou todos os cortes do mês.';
    end if;
    v_cobrar := 0;
  end if;

  v_devido := v_cobrar + v_gorj;
  v_taxa := round(v_devido * f.taxa_percentual / 100.0);

  if f.tipo = 'dinheiro' then
    if p_recebido is null or p_recebido < v_devido then
      raise exception 'O valor recebido é menor que o total.';
    end if;
    v_troco := p_recebido - v_devido;
  end if;

  insert into atendimentos (agendamento_id, cliente_id, barbeiro_id, total_centavos,
                            desconto_centavos, gorjeta_centavos, finalizado_por)
  values (v.id, v.cliente_id, v.barbeiro_id, v_total, v_desc, v_gorj, auth.uid())
  returning id into v_at;

  insert into pagamentos (atendimento_id, forma_pagamento_id, bruto_centavos, taxa_centavos, liquido_centavos,
                          recebido_dinheiro_centavos, troco_centavos, pendente)
  values (v_at, f.id, v_devido, v_taxa, v_devido - v_taxa,
          case when f.tipo = 'dinheiro' then p_recebido end, v_troco, f.tipo = 'fiado');

  if f.tipo = 'plano' then
    insert into usos_plano (assinatura_id, atendimento_id) values ((v_plano ->> 'assinatura_id')::uuid, v_at);
    update agendamentos set usa_plano = true where id = v.id;
  end if;

  if f.tipo <> 'fiado' and v_devido > 0 then
    insert into caixa_movimentos (tipo, origem, descricao, forma_pagamento_id,
                                  bruto_centavos, liquido_centavos, referencia_id, criado_por)
    values ('entrada', 'atendimento',
            (select string_agg(nome, ' + ' order by nome) from agendamento_servicos where agendamento_id = v.id)
              || ' · ' || (select nome from clientes where id = v.cliente_id),
            f.id, v_devido, v_devido - v_taxa, v_at, auth.uid());
  end if;

  update agendamentos set status = 'finalizado', atualizado_em = now() where id = v.id;

  return jsonb_build_object('atendimento_id', v_at, 'total_centavos', v_devido, 'troco_centavos', v_troco);
end $$;

-- ───────────────────────── equipe: caixa (dono) ─────────────────────────

create or replace function caixa_resumo(p_dia date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_troco integer;
begin
  perform exigir_dono();
  select troco_inicial_centavos into v_troco from caixa_dia where data = p_dia;
  v_troco := coalesce(v_troco, cfg_int('troco_inicial_padrao_centavos', 0));
  return jsonb_build_object(
    'troco_inicial', v_troco,
    'entradas', coalesce((select sum(bruto_centavos) from caixa_movimentos where data = p_dia and tipo = 'entrada'), 0),
    'entradas_liquido', coalesce((select sum(liquido_centavos) from caixa_movimentos where data = p_dia and tipo = 'entrada'), 0),
    'saidas', coalesce((select sum(bruto_centavos) from caixa_movimentos where data = p_dia and tipo = 'saida'), 0),
    'dinheiro_recebido', coalesce((select sum(m.bruto_centavos) from caixa_movimentos m
                                   join formas_pagamento f on f.id = m.forma_pagamento_id
                                   where m.data = p_dia and m.tipo = 'entrada' and f.tipo = 'dinheiro'), 0),
    'dinheiro_saidas', coalesce((select sum(m.bruto_centavos) from caixa_movimentos m
                                 join formas_pagamento f on f.id = m.forma_pagamento_id
                                 where m.data = p_dia and m.tipo = 'saida' and f.tipo = 'dinheiro'), 0),
    'fechamento', (select to_jsonb(c) from caixa_dia c where c.data = p_dia and c.fechado_em is not null),
    'movimentos', coalesce((
      select jsonb_agg(jsonb_build_object('id', m.id, 'hora', m.criado_em, 'tipo', m.tipo, 'origem', m.origem,
                                          'descricao', m.descricao, 'forma', f.nome, 'forma_tipo', f.tipo,
                                          'bruto', m.bruto_centavos, 'liquido', m.liquido_centavos)
                       order by m.criado_em)
      from caixa_movimentos m left join formas_pagamento f on f.id = m.forma_pagamento_id
      where m.data = p_dia), '[]'::jsonb),
    'fiados', coalesce((
      select jsonb_agg(jsonb_build_object('pagamento_id', p.id, 'cliente', c.nome, 'telefone', c.telefone,
                                          'valor', p.bruto_centavos, 'data', a.finalizado_em)
                       order by a.finalizado_em)
      from pagamentos p join atendimentos a on a.id = p.atendimento_id join clientes c on c.id = a.cliente_id
      where p.pendente), '[]'::jsonb));
end $$;

create or replace function definir_troco_inicial(p_dia date, p_valor integer) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform exigir_dono();
  if p_valor < 0 then raise exception 'Valor inválido.'; end if;
  insert into caixa_dia (data, troco_inicial_centavos) values (p_dia, p_valor)
  on conflict (data) do update set troco_inicial_centavos = excluded.troco_inicial_centavos;
end $$;

create or replace function lancar_despesa(p_descricao text, p_valor integer, p_forma_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform exigir_dono();
  if coalesce(btrim(p_descricao), '') = '' then raise exception 'Diz do que foi a despesa.'; end if;
  if p_valor is null or p_valor <= 0 then raise exception 'Coloca o valor da despesa.'; end if;
  insert into caixa_movimentos (tipo, origem, descricao, forma_pagamento_id, bruto_centavos, liquido_centavos, criado_por)
  values ('saida', 'despesa', btrim(p_descricao), p_forma_id, p_valor, p_valor, auth.uid());
end $$;

create or replace function quitar_fiado(p_pagamento_id uuid, p_forma_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare p pagamentos; f formas_pagamento; v_taxa integer; v_desc text;
begin
  perform exigir_dono();
  select * into p from pagamentos where id = p_pagamento_id and pendente for update;
  if not found then raise exception 'Esse fiado já foi acertado.'; end if;
  select * into f from formas_pagamento where id = p_forma_id and ativa and tipo not in ('fiado', 'plano');
  if not found then raise exception 'Escolha como ele pagou.'; end if;
  v_taxa := round(p.bruto_centavos * f.taxa_percentual / 100.0);
  update pagamentos set pendente = false, quitado_em = now(), quitado_forma_id = f.id where id = p.id;
  select 'Fiado acertado · ' || c.nome into v_desc
  from atendimentos a join clientes c on c.id = a.cliente_id where a.id = p.atendimento_id;
  insert into caixa_movimentos (tipo, origem, descricao, forma_pagamento_id, bruto_centavos, liquido_centavos,
                                referencia_id, criado_por)
  values ('entrada', 'fiado_quitado', v_desc, f.id, p.bruto_centavos, p.bruto_centavos - v_taxa, p.id, auth.uid());
end $$;

create or replace function fechar_caixa(p_dia date, p_contado integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; v_esperado integer;
begin
  perform exigir_dono();
  if p_contado is null or p_contado < 0 then raise exception 'Coloca quanto tem na gaveta.'; end if;
  r := caixa_resumo(p_dia);
  v_esperado := (r ->> 'troco_inicial')::integer + (r ->> 'dinheiro_recebido')::integer - (r ->> 'dinheiro_saidas')::integer;
  insert into caixa_dia (data, troco_inicial_centavos, esperado_dinheiro_centavos, contado_dinheiro_centavos,
                         diferenca_centavos, fechado_em, fechado_por)
  values (p_dia, (r ->> 'troco_inicial')::integer, v_esperado, p_contado, p_contado - v_esperado, now(), auth.uid())
  on conflict (data) do update set
    esperado_dinheiro_centavos = excluded.esperado_dinheiro_centavos,
    contado_dinheiro_centavos = excluded.contado_dinheiro_centavos,
    diferenca_centavos = excluded.diferenca_centavos,
    fechado_em = excluded.fechado_em,
    fechado_por = excluded.fechado_por;
  return jsonb_build_object('esperado', v_esperado, 'contado', p_contado, 'diferenca', p_contado - v_esperado);
end $$;
