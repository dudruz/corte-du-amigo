-- Corte DÚ Amigo · 006 · Correções da revisão
-- Rodar depois da 004 (a 005 é opcional e não interfere), num banco que já tem tudo.
-- Pode rodar mais de uma vez sem estragar nada.

-- ───────────────────────── colunas e configurações ─────────────────────────

-- Nome que a pessoa digitou naquele agendamento. O cadastro do cliente (por telefone)
-- não muda de nome quando outra pessoa marca com o mesmo número.
alter table agendamentos add column if not exists nome_informado text;

-- Quem da equipe criou o agendamento. Nulo = feito pelo site (entra no teto por hora).
alter table agendamentos add column if not exists criado_por uuid references auth.users;

-- Serviços que o plano cobre. Nulo ou vazio = cobre tudo.
alter table planos add column if not exists servicos_incluidos uuid[];

insert into configuracoes (chave, valor) values
  ('agendar_ate_dias', '60'),             -- até quantos dias pra frente dá pra marcar
  ('limite_agendamentos_hora', '20')      -- teto de agendamentos feitos pelo site por hora
on conflict (chave) do nothing;

-- ───────────────────────── utilitários ─────────────────────────

-- Sem perfil, barbeiro_atual() é nulo e a comparação daria nulo.
-- Permissão precisa ser sempre sim ou não.
create or replace function pode_barbeiro(p_barbeiro uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(eh_dono() or (eh_equipe() and barbeiro_atual() = p_barbeiro), false)
$$;

-- Telefone salvo sempre como 55 + DDD + número (12 ou 13 dígitos).
-- Zero na frente (0 31 ...) é prefixo de discagem, não faz parte do número.
create or replace function normalizar_telefone(p text) returns text
language plpgsql immutable as $$
declare d text := ltrim(regexp_replace(coalesce(p, ''), '\D', '', 'g'), '0');
begin
  if length(d) in (10, 11) then d := '55' || d; end if;
  if length(d) not in (12, 13) or left(d, 2) <> '55' then
    raise exception 'WhatsApp inválido. Coloca DDD + número.';
  end if;
  return d;
end $$;

-- ───────────────────────── disponibilidade ─────────────────────────

-- Regra de conflito de UM bloqueio com um período de um barbeiro.
-- Bloqueio sem barbeiro vale pra barbearia toda. O recorrente repete toda semana,
-- no mesmo dia e horário, a partir da data em que foi criado.
create or replace function um_bloqueio_conflita(
  p_k_barbeiro uuid, p_k_inicio timestamptz, p_k_fim timestamptz, p_k_recorrente boolean,
  p_barbeiro uuid, p_ini timestamptz, p_fim timestamptz)
returns boolean
language sql stable security definer set search_path = public as $$
  select (p_k_barbeiro is null or p_k_barbeiro = p_barbeiro)
    and (
      (not p_k_recorrente and tstzrange(p_k_inicio, p_k_fim) && tstzrange(p_ini, p_fim))
      or (
        p_k_recorrente
        and extract(dow from p_k_inicio at time zone fuso()) = extract(dow from p_ini at time zone fuso())
        and (p_ini at time zone fuso())::date >= (p_k_inicio at time zone fuso())::date
        and tstzrange(
              ((p_ini at time zone fuso())::date + (p_k_inicio at time zone fuso())::time) at time zone fuso(),
              ((p_ini at time zone fuso())::date + (p_k_fim at time zone fuso())::time) at time zone fuso()
            ) && tstzrange(p_ini, p_fim)
      )
    )
$$;

create or replace function bloqueio_conflita(p_barbeiro uuid, p_ini timestamptz, p_fim timestamptz)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from bloqueios k
    where um_bloqueio_conflita(k.barbeiro_id, k.inicio, k.fim, k.recorrente_semanal, p_barbeiro, p_ini, p_fim)
  )
$$;

-- O início precisa cair num slot da grade do barbeiro naquele dia:
-- minutos desde a abertura múltiplos do intervalo configurado (mesma conta de horarios_livres).
create or replace function na_grade(p_barbeiro uuid, p_ini timestamptz) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from horarios_trabalho h
    where h.barbeiro_id = p_barbeiro
      and h.dia_semana = extract(dow from p_ini at time zone fuso())
      and (p_ini at time zone fuso())::time >= h.inicio
      and (p_ini at time zone fuso())::time < h.fim
      and mod(extract(epoch from ((p_ini at time zone fuso())::time - h.inicio))::numeric,
              (greatest(cfg_int('intervalo_slots_min', 30), 1) * 60)::numeric) = 0
  )
$$;

-- Recusa início vazio, longe demais (agenda aberta só até agendar_ate_dias) ou fora da grade.
-- Com p_barbeiro nulo ("tanto faz") a grade já é garantida por horarios_livres.
create or replace function validar_inicio(p_barbeiro uuid, p_inicio timestamptz) returns void
language plpgsql stable security definer set search_path = public as $$
declare v_dias integer := cfg_int('agendar_ate_dias', 60);
begin
  if p_inicio is null then
    raise exception 'Escolhe o dia e o horário.';
  end if;
  if (p_inicio at time zone fuso())::date > (now() at time zone fuso())::date + v_dias then
    raise exception 'Só dá pra marcar com até % dias de antecedência.', v_dias;
  end if;
  if p_barbeiro is not null and not na_grade(p_barbeiro, p_inicio) then
    raise exception 'Esse horário não existe na agenda. Escolhe um da lista.';
  end if;
end $$;

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
    'preco_centavos', p.preco_centavos,
    'servicos_incluidos', to_jsonb(p.servicos_incluidos))
  from assinaturas a join planos p on p.id = a.plano_id
  where a.cliente_id = p_cliente and a.status in ('ativa', 'atrasada')
  order by a.vence_em desc
  limit 1
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
  v_equipe boolean := eh_equipe();
begin
  if length(v_nome) < 2 or length(v_nome) > 80 then
    raise exception 'Coloca seu nome (de 2 a 80 letras).';
  end if;
  v_tel := normalizar_telefone(p_telefone);
  v_dur := duracao_servicos(p_servico_ids);
  if v_dur is null then raise exception 'Escolha pelo menos um serviço.'; end if;
  perform validar_inicio(v_barbeiro, p_inicio);
  v_fim := p_inicio + make_interval(mins => v_dur);

  -- Fora da equipe não há como saber quem está marcando, então o freio é global:
  -- um teto por hora impede que alguém lote a agenda com números inventados.
  -- Vale pra quem não tem perfil ativo, e não só pra quem está sem login: criar uma conta
  -- qualquer no Auth não pode ser um jeito de escapar do teto.
  -- A trava faz as marcações do site entrarem uma por vez, pra contagem não furar.
  if not v_equipe then
    perform pg_advisory_xact_lock(hashtext('criar_agendamento_publico'));
    if (select count(*) from agendamentos
        where criado_por is null and criado_em > now() - interval '1 hour')
       >= cfg_int('limite_agendamentos_hora', 20) then
      raise exception 'Muita gente marcando agora. Tenta de novo daqui a pouco ou chama a barbearia no WhatsApp.';
    end if;
  end if;

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
    insert into agendamentos (cliente_id, barbeiro_id, periodo, nome_informado, criado_por)
    values (v_cli, v_barbeiro, tstzrange(p_inicio, v_fim), v_nome, case when v_equipe then auth.uid() end)
    returning id, token into v_ag, v_token;
  exception when exclusion_violation then
    raise exception 'Esse horário acabou de ser pego. Escolhe outro.';
  end;

  insert into agendamento_servicos (agendamento_id, servico_id, nome, preco_centavos, duracao_min)
  select v_ag, s.id, s.nome, s.preco_centavos, s.duracao_min
  from servicos s where s.id = any(p_servico_ids) and s.ativo;

  return v_token;
end $$;

-- O token dá acesso só ao próprio agendamento. Telefone não prova identidade:
-- quem marcasse com o WhatsApp de outra pessoa veria os horários, o histórico e o plano dela.
create or replace function agendamento_por_token(p_token uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v agendamentos;
begin
  select * into v from agendamentos where token = p_token;
  if not found then return null; end if;
  return jsonb_build_object(
    'atual', resumo_agendamento(v.id),
    'cliente', (select jsonb_build_object('nome', coalesce(v.nome_informado, c.nome), 'telefone', c.telefone)
                from clientes c where c.id = v.cliente_id),
    'cancelamento_horas', cfg_int('cancelamento_antecedencia_horas', 2));
end $$;

-- "Próximos" e "histórico" da Minha área: só os agendamentos cujos tokens o aparelho guarda.
-- Aceita no máximo 20 tokens por chamada e ignora os que não existem.
create or replace function agendamentos_por_tokens(p_tokens uuid[]) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(resumo_agendamento(a.id) order by lower(a.periodo)), '[]'::jsonb)
  from agendamentos a
  where a.token = any(p_tokens[1:20])
$$;

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
  perform validar_inicio(v.barbeiro_id, p_novo_inicio);
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

-- Cria o bloqueio e cancela só quem bate com ELE (inclusive nas semanas seguintes,
-- quando recorrente). Quem conflita com outro bloqueio mais antigo não é mexido aqui.
create or replace function criar_bloqueio(
  p_barbeiro_id uuid, p_inicio timestamptz, p_fim timestamptz,
  p_recorrente boolean default false, p_motivo text default null)
returns table (nome text, telefone text, inicio timestamptz)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare v_rec boolean := coalesce(p_recorrente, false);
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
  values (p_barbeiro_id, p_inicio, p_fim, v_rec, nullif(btrim(p_motivo), ''), auth.uid());

  return query
  with afetados as (
    update agendamentos a
    set status = 'cancelado', cancelado_motivo = 'bloqueio', atualizado_em = now()
    where a.status = 'marcado'
      and lower(a.periodo) > now()
      and um_bloqueio_conflita(p_barbeiro_id, p_inicio, p_fim, v_rec,
                               a.barbeiro_id, lower(a.periodo), upper(a.periodo))
    returning a.cliente_id, lower(a.periodo) as ini
  )
  select c.nome, c.telefone, af.ini
  from afetados af join clientes c on c.id = af.cliente_id
  order by af.ini;
end $$;

-- ───────────────────────── equipe: finalizar ─────────────────────────

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
  v_incluidos uuid[];
  v_fora text;
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

    -- O plano zera a conta inteira, então só vale quando cobre todos os itens.
    -- Senão um serviço extra sairia de graça.
    select p.servicos_incluidos into v_incluidos
    from assinaturas a join planos p on p.id = a.plano_id
    where a.id = (v_plano ->> 'assinatura_id')::uuid;
    if coalesce(cardinality(v_incluidos), 0) > 0 then
      select string_agg(s.nome, ', ' order by s.nome) into v_fora
      from agendamento_servicos s
      where s.agendamento_id = v.id and not (s.servico_id = any(v_incluidos));
      if v_fora is not null then
        raise exception 'Tem serviço fora do plano: %. Tira o extra ou cobra tudo em outra forma.', v_fora;
      end if;
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

-- 'esperado_dinheiro' é o que deve ter na gaveta agora. O fechamento guarda o esperado
-- da hora em que foi feito: se entrou lançamento depois, vem 'desatualizado' = true
-- pra tela pedir a recontagem.
create or replace function caixa_resumo(p_dia date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_troco integer;
  v_recebido integer;
  v_saidas integer;
  v_esperado integer;
begin
  perform exigir_dono();
  select troco_inicial_centavos into v_troco from caixa_dia where data = p_dia;
  v_troco := coalesce(v_troco, cfg_int('troco_inicial_padrao_centavos', 0));
  select coalesce(sum(m.bruto_centavos) filter (where m.tipo = 'entrada'), 0)::integer,
         coalesce(sum(m.bruto_centavos) filter (where m.tipo = 'saida'), 0)::integer
    into v_recebido, v_saidas
  from caixa_movimentos m join formas_pagamento f on f.id = m.forma_pagamento_id
  where m.data = p_dia and f.tipo = 'dinheiro';
  v_esperado := v_troco + v_recebido - v_saidas;
  return jsonb_build_object(
    'troco_inicial', v_troco,
    'entradas', coalesce((select sum(bruto_centavos) from caixa_movimentos where data = p_dia and tipo = 'entrada'), 0),
    'entradas_liquido', coalesce((select sum(liquido_centavos) from caixa_movimentos where data = p_dia and tipo = 'entrada'), 0),
    'saidas', coalesce((select sum(bruto_centavos) from caixa_movimentos where data = p_dia and tipo = 'saida'), 0),
    'dinheiro_recebido', v_recebido,
    'dinheiro_saidas', v_saidas,
    'esperado_dinheiro', v_esperado,
    'fechamento', (select to_jsonb(c) || jsonb_build_object(
                            'desatualizado', c.esperado_dinheiro_centavos is distinct from v_esperado)
                   from caixa_dia c where c.data = p_dia and c.fechado_em is not null),
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

-- A despesa entra no dia que o dono está olhando no caixa (nulo = hoje, no fuso da barbearia).
-- Dia futuro não: ainda não aconteceu.
drop function if exists lancar_despesa(text, integer, uuid);

create or replace function lancar_despesa(
  p_descricao text, p_valor integer, p_forma_id uuid, p_dia date default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_hoje date := (now() at time zone fuso())::date;
  v_dia date := coalesce(p_dia, v_hoje);
begin
  perform exigir_dono();
  if coalesce(btrim(p_descricao), '') = '' then raise exception 'Diz do que foi a despesa.'; end if;
  if p_valor is null or p_valor <= 0 then raise exception 'Coloca o valor da despesa.'; end if;
  if v_dia > v_hoje then raise exception 'Não dá pra lançar despesa em dia que ainda não chegou.'; end if;
  insert into caixa_movimentos (data, tipo, origem, descricao, forma_pagamento_id, bruto_centavos, liquido_centavos, criado_por)
  values (v_dia, 'saida', 'despesa', btrim(p_descricao), p_forma_id, p_valor, p_valor, auth.uid());
end $$;

-- ───────────────────────── permissões ─────────────────────────

-- Função nova nasce liberada pra todo mundo. Fecha e libera só pra equipe logada;
-- o público ganha apenas a consulta pelos tokens do próprio aparelho.
-- (As funções recriadas com a mesma assinatura mantêm as permissões da 003.)
revoke execute on function
  um_bloqueio_conflita(uuid, timestamptz, timestamptz, boolean, uuid, timestamptz, timestamptz),
  na_grade(uuid, timestamptz),
  validar_inicio(uuid, timestamptz),
  agendamentos_por_tokens(uuid[]),
  lancar_despesa(text, integer, uuid, date)
from public, anon;

grant execute on function
  um_bloqueio_conflita(uuid, timestamptz, timestamptz, boolean, uuid, timestamptz, timestamptz),
  na_grade(uuid, timestamptz),
  validar_inicio(uuid, timestamptz),
  agendamentos_por_tokens(uuid[]),
  lancar_despesa(text, integer, uuid, date)
to authenticated;

grant execute on function agendamentos_por_tokens(uuid[]) to anon;
