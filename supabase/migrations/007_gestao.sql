-- Corte DÚ Amigo · 007 · Gestão (Fase 2)
-- Planos e assinaturas, clientes, painel do mês, comissão, Pix, horários e logins da equipe.
-- Rodar depois da 006. Pode rodar mais de uma vez sem estragar nada.

-- ───────────────────────── configurações ─────────────────────────

-- Pix da barbearia: com a chave preenchida, o finalizar e a cobrança de plano mostram o
-- "copia e cola" já com o valor. Nome e cidade entram no código Pix (o banco do cliente mostra).
insert into configuracoes (chave, valor) values
  ('pix_chave', '""'),                       -- pendente: chave Pix do Duim (CPF, CNPJ, celular, e-mail ou aleatória)
  ('pix_nome', '"CORTE DU AMIGO"'),
  ('pix_cidade', '"BELO HORIZONTE"')
on conflict (chave) do nothing;

-- Comissão do barbeiro (barbeiros.comissao_tipo / comissao_valor):
--   'percentual'     → comissao_valor é a porcentagem inteira (40 = 40% do valor dos serviços)
--   'fixo_por_corte' → comissao_valor é em centavos por atendimento
comment on column barbeiros.comissao_valor is
  'percentual: porcentagem inteira (40 = 40%); fixo_por_corte: centavos por atendimento';

create or replace function cfg_texto(p_chave text) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(cfg(p_chave) #>> '{}', '')
$$;

create or replace function hoje_local() returns date
language sql stable as $$ select (now() at time zone fuso())::date $$;

-- ───────────────────────── planos ─────────────────────────

-- Cortes usados no mês corrente da assinatura. O mês começa um mês antes do vencimento,
-- à meia-noite de Brasília (e não de Greenwich, que cortaria 3 horas do dia anterior).
create or replace function usos_no_ciclo(p_assinatura uuid, p_vence date) returns integer
language sql stable security definer set search_path = public as $$
  select count(*)::integer from usos_plano u
  where u.assinatura_id = p_assinatura
    and u.usado_em >= ((p_vence - interval '1 month')::date)::timestamp at time zone fuso()
$$;

-- Situação vista pela tela: atrasada (venceu), vencendo (até 3 dias) ou em dia.
create or replace function situacao_assinatura(p_status text, p_vence date) returns text
language sql stable as $$
  select case
    when p_status = 'cancelada' then 'cancelada'
    when p_vence < hoje_local() then 'atrasada'
    when p_vence <= hoje_local() + 3 then 'vencendo'
    else 'em_dia' end
$$;

create or replace function plano_do_cliente(p_cliente uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'assinatura_id', a.id, 'nome', p.nome, 'usos_por_mes', p.usos_por_mes,
    'usados', usos_no_ciclo(a.id, a.vence_em),
    'vence_em', a.vence_em,
    'status', case when a.status = 'ativa' and a.vence_em < hoje_local() then 'atrasada' else a.status end,
    'preco_centavos', p.preco_centavos,
    'servicos_incluidos', to_jsonb(p.servicos_incluidos))
  from assinaturas a join planos p on p.id = a.plano_id
  where a.cliente_id = p_cliente and a.status in ('ativa', 'atrasada')
  order by a.vence_em desc
  limit 1
$$;

create or replace function salvar_plano(
  p_id uuid, p_nome text, p_descricao text, p_preco integer, p_usos integer,
  p_servicos uuid[] default null, p_ativo boolean default true)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_nome text := btrim(coalesce(p_nome, ''));
  v_serv uuid[];
begin
  perform exigir_dono();
  if length(v_nome) < 2 or length(v_nome) > 60 then
    raise exception 'Dá um nome pro plano (de 2 a 60 letras).';
  end if;
  if p_preco is null or p_preco <= 0 then raise exception 'Coloca o preço do plano.'; end if;
  if p_usos is not null and (p_usos < 1 or p_usos > 31) then
    raise exception 'Cortes por mês: de 1 a 31, ou deixa em branco pra ilimitado.';
  end if;
  -- Lista vazia = o plano cobre qualquer serviço
  select array_agg(s.id order by s.ordem) into v_serv from servicos s where s.id = any(coalesce(p_servicos, '{}'));
  if coalesce(cardinality(p_servicos), 0) > 0 and v_serv is null then
    raise exception 'Escolhe serviços que existem.';
  end if;

  if p_id is null then
    insert into planos (nome, descricao, preco_centavos, usos_por_mes, servicos_incluidos, ativo)
    values (v_nome, nullif(btrim(p_descricao), ''), p_preco, p_usos, v_serv, coalesce(p_ativo, true))
    returning id into v_id;
  else
    update planos set nome = v_nome, descricao = nullif(btrim(p_descricao), ''), preco_centavos = p_preco,
                      usos_por_mes = p_usos, servicos_incluidos = v_serv, ativo = coalesce(p_ativo, true)
    where id = p_id
    returning id into v_id;
    if v_id is null then raise exception 'Plano não encontrado.'; end if;
  end if;
  return v_id;
end $$;

-- Entrada no caixa pelo pagamento de um mês de plano (com a taxa da forma escolhida).
-- Plano não se paga com plano nem fica no fiado.
create or replace function entrada_plano(p_assinatura uuid, p_forma_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  f formas_pagamento;
  v_preco integer;
  v_desc text;
  v_taxa integer;
begin
  select * into f from formas_pagamento where id = p_forma_id and ativa and tipo not in ('plano', 'fiado');
  if not found then raise exception 'Escolhe como ele pagou o plano.'; end if;
  select p.preco_centavos,
         case when p.nome ilike 'plano%' then p.nome else 'Plano ' || p.nome end || ' · ' || c.nome
    into v_preco, v_desc
  from assinaturas a join planos p on p.id = a.plano_id join clientes c on c.id = a.cliente_id
  where a.id = p_assinatura;
  v_taxa := round(v_preco * f.taxa_percentual / 100.0);
  insert into caixa_movimentos (tipo, origem, descricao, forma_pagamento_id, bruto_centavos, liquido_centavos,
                                referencia_id, criado_por)
  values ('entrada', 'plano', v_desc, f.id, v_preco, v_preco - v_taxa, p_assinatura, auth.uid());
end $$;

-- Assina um plano pra um cliente (que já existe, ou novo pelo nome e WhatsApp) e registra
-- o pagamento do primeiro mês. Um cliente tem no máximo um plano valendo.
create or replace function assinar_plano(
  p_plano_id uuid, p_forma_id uuid, p_cliente_id uuid default null,
  p_nome text default null, p_telefone text default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_plano planos;
  v_cli uuid := p_cliente_id;
  v_nome text := btrim(coalesce(p_nome, ''));
  v_hoje date := hoje_local();
  v_ass uuid;
begin
  perform exigir_dono();
  select * into v_plano from planos where id = p_plano_id and ativo;
  if not found then raise exception 'Escolhe um plano ativo.'; end if;

  if v_cli is null then
    if length(v_nome) < 2 or length(v_nome) > 80 then raise exception 'Coloca o nome do cliente.'; end if;
    insert into clientes (nome, telefone) values (v_nome, normalizar_telefone(p_telefone))
    on conflict (telefone) do update set telefone = excluded.telefone
    returning id into v_cli;
  elsif not exists (select 1 from clientes where id = v_cli) then
    raise exception 'Cliente não encontrado.';
  end if;

  -- Dois cliques ao mesmo tempo não podem criar duas assinaturas
  perform pg_advisory_xact_lock(hashtext('assinatura:' || v_cli::text));
  if exists (select 1 from assinaturas where cliente_id = v_cli and status in ('ativa', 'atrasada')) then
    raise exception 'Esse cliente já tem plano. Renova ou cancela o atual antes.';
  end if;

  insert into assinaturas (cliente_id, plano_id, inicio, vence_em, status)
  values (v_cli, v_plano.id, v_hoje, (v_hoje + interval '1 month')::date, 'ativa')
  returning id into v_ass;
  perform entrada_plano(v_ass, p_forma_id);
  return v_ass;
end $$;

-- Pagamento de mais um mês. Em dia, o mês novo começa onde o anterior termina; atrasado,
-- começa hoje (não cobra o tempo em que ele ficou sem plano). Pagamento repetido sem querer
-- (plano já pago com folga) é recusado.
create or replace function registrar_pagamento_plano(p_assinatura_id uuid, p_forma_id uuid)
returns date
language plpgsql security definer set search_path = public as $$
declare
  a assinaturas;
  v_hoje date := hoje_local();
  v_novo date;
begin
  perform exigir_dono();
  select * into a from assinaturas where id = p_assinatura_id for update;
  if not found or a.status = 'cancelada' then raise exception 'Esse plano não está valendo.'; end if;
  if a.vence_em > v_hoje + 10 then
    raise exception 'Esse plano já está pago até %.', to_char(a.vence_em, 'DD/MM');
  end if;
  v_novo := ((case when a.vence_em >= v_hoje then a.vence_em else v_hoje end) + interval '1 month')::date;
  update assinaturas set vence_em = v_novo, status = 'ativa' where id = a.id;
  perform entrada_plano(a.id, p_forma_id);
  return v_novo;
end $$;

create or replace function cancelar_assinatura(p_assinatura_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform exigir_dono();
  update assinaturas set status = 'cancelada' where id = p_assinatura_id and status <> 'cancelada';
  if not found then raise exception 'Esse plano já estava cancelado.'; end if;
end $$;

-- Tudo que a tela Planos precisa numa chamada
create or replace function planos_painel() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_dono();
  return jsonb_build_object(
    'planos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', p.id, 'nome', p.nome, 'descricao', p.descricao, 'preco_centavos', p.preco_centavos,
               'usos_por_mes', p.usos_por_mes, 'servicos_incluidos', to_jsonb(p.servicos_incluidos), 'ativo', p.ativo,
               'assinantes', (select count(*) from assinaturas a where a.plano_id = p.id and a.status in ('ativa', 'atrasada')))
             order by p.ativo desc, p.preco_centavos)
      from planos p), '[]'::jsonb),
    'assinaturas', coalesce((
      select jsonb_agg(x.j order by x.ordem, x.vence_em, x.cliente)
      from (
        select jsonb_build_object(
                 'id', a.id, 'cliente_id', c.id, 'cliente', c.nome, 'telefone', c.telefone,
                 'plano_id', p.id, 'plano', p.nome, 'preco_centavos', p.preco_centavos,
                 'usos_por_mes', p.usos_por_mes, 'usados', usos_no_ciclo(a.id, a.vence_em),
                 'vence_em', a.vence_em, 'dias', a.vence_em - hoje_local(),
                 'situacao', situacao_assinatura(a.status, a.vence_em)) as j,
               case situacao_assinatura(a.status, a.vence_em) when 'atrasada' then 0 when 'vencendo' then 1 else 2 end as ordem,
               a.vence_em, c.nome as cliente
        from assinaturas a join planos p on p.id = a.plano_id join clientes c on c.id = a.cliente_id
        where a.status in ('ativa', 'atrasada')) x), '[]'::jsonb),
    'servicos', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.nome) order by s.ordem)
                          from servicos s where s.ativo), '[]'::jsonb),
    'formas', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'nome', f.nome, 'tipo', f.tipo) order by f.ordem)
                        from formas_pagamento f where f.ativa and f.tipo not in ('plano', 'fiado')), '[]'::jsonb),
    'pix', jsonb_build_object('chave', cfg_texto('pix_chave'), 'nome', cfg_texto('pix_nome'), 'cidade', cfg_texto('pix_cidade')));
end $$;

-- ───────────────────────── clientes ─────────────────────────

-- Lista com busca e filtros. "Sumido" = veio pelo menos uma vez, a última faz mais de 30 dias
-- e não tem horário marcado.
create or replace function clientes_lista(p_busca text default null, p_filtro text default 'todos')
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_busca text := lower(btrim(coalesce(p_busca, '')));
  v_digitos text := regexp_replace(coalesce(p_busca, ''), '\D', '', 'g');
  v_filtro text := coalesce(nullif(p_filtro, ''), 'todos');
begin
  perform exigir_dono();
  if v_filtro not in ('todos', 'sumidos', 'assinantes', 'fiado') then
    raise exception 'Filtro inválido.';
  end if;
  return (
    with base as (
      select c.id, c.nome, c.telefone, c.criado_em,
             (select max(t.finalizado_em) from atendimentos t where t.cliente_id = c.id) as ultima,
             exists (select 1 from assinaturas s where s.cliente_id = c.id and s.status in ('ativa', 'atrasada')) as assinante,
             coalesce((select sum(p.bruto_centavos) from pagamentos p join atendimentos t on t.id = p.atendimento_id
                       where t.cliente_id = c.id and p.pendente), 0)::integer as fiado,
             exists (select 1 from agendamentos g where g.cliente_id = c.id and g.status = 'marcado'
                     and lower(g.periodo) > now()) as tem_horario
      from clientes c
    ), marcado as (
      select b.*, (b.ultima is not null and b.ultima < now() - interval '30 days' and not b.tem_horario) as sumido
      from base b
    ), escolhidos as (
      select m.* from marcado m
      where (v_filtro = 'todos'
             or (v_filtro = 'sumidos' and m.sumido)
             or (v_filtro = 'assinantes' and m.assinante)
             or (v_filtro = 'fiado' and m.fiado > 0))
        and (v_busca = '' or position(v_busca in lower(m.nome)) > 0
             or (length(v_digitos) >= 3 and position(v_digitos in m.telefone) > 0))
      order by case when v_filtro = 'sumidos' then m.ultima end asc nulls last,
               m.ultima desc nulls last, m.nome
      limit 300
    )
    select jsonb_build_object(
      'contagens', (select jsonb_build_object(
                      'todos', count(*),
                      'sumidos', count(*) filter (where sumido),
                      'assinantes', count(*) filter (where assinante),
                      'fiado', count(*) filter (where fiado > 0)) from marcado),
      'clientes', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', e.id, 'nome', e.nome, 'telefone', e.telefone,
                 'ultima_visita', e.ultima,
                 'dias_sem_vir', case when e.ultima is not null
                                      then hoje_local() - (e.ultima at time zone fuso())::date end,
                 'ultimo_servico', (select string_agg(s.nome, ' + ' order by s.nome)
                                    from atendimentos t join agendamento_servicos s on s.agendamento_id = t.agendamento_id
                                    where t.cliente_id = e.id and t.finalizado_em = e.ultima),
                 'assinante', e.assinante, 'fiado_centavos', e.fiado, 'sumido', e.sumido,
                 'tem_horario', e.tem_horario))
        from escolhidos e), '[]'::jsonb))
  );
end $$;

create or replace function ficha_cliente(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c clientes;
begin
  perform exigir_dono();
  select * into c from clientes where id = p_id;
  if not found then raise exception 'Cliente não encontrado.'; end if;
  return jsonb_build_object(
    'cliente', jsonb_build_object('id', c.id, 'nome', c.nome, 'telefone', c.telefone, 'observacoes', c.observacoes,
                                  'aceita_lembrete', c.aceita_lembrete, 'faltas', c.faltas, 'criado_em', c.criado_em),
    'plano', plano_do_cliente(c.id),
    'resumo', (select jsonb_build_object('visitas', count(*),
                                         'gasto_centavos', coalesce(sum(t.total_centavos - t.desconto_centavos), 0))
               from atendimentos t where t.cliente_id = c.id),
    'fiados', coalesce((
      select jsonb_agg(jsonb_build_object('pagamento_id', p.id, 'valor', p.bruto_centavos, 'data', t.finalizado_em)
                       order by t.finalizado_em)
      from pagamentos p join atendimentos t on t.id = p.atendimento_id
      where t.cliente_id = c.id and p.pendente), '[]'::jsonb),
    'historico', coalesce((
      select jsonb_agg(h.j order by h.quando desc)
      from (
        select t.finalizado_em as quando, jsonb_build_object(
                 'data', t.finalizado_em,
                 'servicos', (select string_agg(s.nome, ' + ' order by s.nome) from agendamento_servicos s
                              where s.agendamento_id = t.agendamento_id),
                 'barbeiro', coalesce(b.apelido, b.nome),
                 'total_centavos', t.total_centavos - t.desconto_centavos,
                 'gorjeta_centavos', t.gorjeta_centavos,
                 'forma', (select string_agg(f.nome, ' + ') from pagamentos p join formas_pagamento f on f.id = p.forma_pagamento_id
                           where p.atendimento_id = t.id),
                 'pendente', exists (select 1 from pagamentos p where p.atendimento_id = t.id and p.pendente)) as j
        from atendimentos t join barbeiros b on b.id = t.barbeiro_id
        where t.cliente_id = c.id
        order by t.finalizado_em desc
        limit 20) h), '[]'::jsonb),
    'proximos', coalesce((
      select jsonb_agg(jsonb_build_object('inicio', lower(a.periodo), 'barbeiro', coalesce(b.apelido, b.nome),
                                          'servicos', (select string_agg(s.nome, ' + ' order by s.nome)
                                                       from agendamento_servicos s where s.agendamento_id = a.id))
                       order by lower(a.periodo))
      from agendamentos a join barbeiros b on b.id = a.barbeiro_id
      where a.cliente_id = c.id and a.status = 'marcado' and lower(a.periodo) > now()), '[]'::jsonb),
    'formas', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'nome', f.nome) order by f.ordem)
                        from formas_pagamento f where f.ativa and f.tipo not in ('plano', 'fiado')), '[]'::jsonb));
end $$;

create or replace function salvar_cliente(
  p_id uuid, p_nome text, p_observacoes text, p_aceita_lembrete boolean default true)
returns void
language plpgsql security definer set search_path = public as $$
declare v_nome text := btrim(coalesce(p_nome, ''));
begin
  perform exigir_dono();
  if length(v_nome) < 2 or length(v_nome) > 80 then raise exception 'Coloca o nome (de 2 a 80 letras).'; end if;
  if length(coalesce(p_observacoes, '')) > 500 then raise exception 'Observação muito longa (até 500 letras).'; end if;
  update clientes set nome = v_nome, observacoes = nullif(btrim(p_observacoes), ''),
                      aceita_lembrete = coalesce(p_aceita_lembrete, true)
  where id = p_id;
  if not found then raise exception 'Cliente não encontrado.'; end if;
end $$;

-- ───────────────────────── painel do mês (Início) ─────────────────────────

-- Faturamento pelo que entrou no caixa (o fiado só conta quando é acertado).
-- Ticket médio e comissão pelo valor dos serviços atendidos no mês, com desconto,
-- inclusive os pagos pelo plano. Gorjeta é do barbeiro e fica à parte.
create or replace function painel_mes(p_mes date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_hoje date := hoje_local();
  v_ini date := date_trunc('month', coalesce(p_mes, v_hoje))::date;
  v_fim date := (v_ini + interval '1 month')::date;
  v_ini_ts timestamptz := v_ini::timestamp at time zone fuso();
  v_fim_ts timestamptz := v_fim::timestamp at time zone fuso();
  v_segunda date := v_hoje - (extract(isodow from v_hoje)::integer - 1);
begin
  perform exigir_dono();
  return (
    with mov as (
      select * from caixa_movimentos where data >= v_ini and data < v_fim
    ), atend as (
      select * from atendimentos where finalizado_em >= v_ini_ts and finalizado_em < v_fim_ts
    )
    select jsonb_build_object(
      'mes', v_ini,
      'bruto', coalesce((select sum(bruto_centavos) from mov where tipo = 'entrada'), 0),
      'liquido', coalesce((select sum(liquido_centavos) from mov where tipo = 'entrada'), 0),
      'despesas', coalesce((select sum(bruto_centavos) from mov where tipo = 'saida'), 0),
      'atendimentos', (select count(*) from atend),
      'ticket_medio', (select case when count(*) > 0
                                   then round(sum(total_centavos - desconto_centavos)::numeric / count(*))::integer end
                       from atend),
      'gorjetas', coalesce((select sum(gorjeta_centavos) from atend), 0),
      'fiado_aberto', coalesce((select sum(bruto_centavos) from pagamentos where pendente), 0),
      'hoje', jsonb_build_object(
        'entradas', coalesce((select sum(bruto_centavos) from caixa_movimentos where data = v_hoje and tipo = 'entrada'), 0),
        'atendidos', (select count(*) from agendamentos a
                      where a.status = 'finalizado'
                        and (lower(a.periodo) at time zone fuso())::date = v_hoje),
        'marcados', (select count(*) from agendamentos a
                     where a.status not in ('cancelado')
                       and (lower(a.periodo) at time zone fuso())::date = v_hoje)),
      'semana', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'dia', d::date,
                 'valor', coalesce((select sum(bruto_centavos) from caixa_movimentos m
                                    where m.data = d::date and m.tipo = 'entrada'), 0),
                 'hoje', d::date = v_hoje, 'futuro', d::date > v_hoje) order by d)
        from generate_series(v_segunda::timestamp, (v_segunda + 6)::timestamp, interval '1 day') d
        where exists (select 1 from horarios_trabalho h join barbeiros b on b.id = h.barbeiro_id
                      where b.ativo and h.dia_semana = extract(dow from d))), '[]'::jsonb),
      'formas', coalesce((
        select jsonb_agg(jsonb_build_object('nome', x.nome, 'tipo', x.tipo, 'bruto', x.bruto, 'liquido', x.liquido)
                         order by x.bruto desc)
        from (select f.nome, f.tipo, sum(m.bruto_centavos)::integer as bruto, sum(m.liquido_centavos)::integer as liquido
              from mov m join formas_pagamento f on f.id = m.forma_pagamento_id
              where m.tipo = 'entrada' group by f.nome, f.tipo) x), '[]'::jsonb),
      'pelo_plano', (select count(*) from atend t
                     where exists (select 1 from pagamentos p join formas_pagamento f on f.id = p.forma_pagamento_id
                                   where p.atendimento_id = t.id and f.tipo = 'plano')),
      'comissoes', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'barbeiro_id', y.id, 'barbeiro', y.nome, 'atendimentos', y.qtd, 'base_centavos', y.base,
                 'gorjetas_centavos', y.gorjetas, 'tipo', y.comissao_tipo, 'valor', y.comissao_valor,
                 'comissao_centavos', case y.comissao_tipo
                                        when 'percentual' then round(y.base * coalesce(y.comissao_valor, 0) / 100.0)::integer
                                        when 'fixo_por_corte' then y.qtd * coalesce(y.comissao_valor, 0)
                                      end)
                         order by y.nome)
        from (select b.id, coalesce(b.apelido, b.nome) as nome, b.comissao_tipo, b.comissao_valor,
                     count(t.id)::integer as qtd,
                     coalesce(sum(t.total_centavos - t.desconto_centavos), 0)::integer as base,
                     coalesce(sum(t.gorjeta_centavos), 0)::integer as gorjetas
              from barbeiros b left join atend t on t.barbeiro_id = b.id
              group by b.id
              having b.ativo or count(t.id) > 0) y), '[]'::jsonb),
      'planos', jsonb_build_object(
        'vencendo', (select count(*) from assinaturas
                     where status = 'ativa' and vence_em >= v_hoje and vence_em <= v_hoje + 7),
        'atrasados', (select count(*) from assinaturas
                      where status in ('ativa', 'atrasada') and vence_em < v_hoje))
    )
  );
end $$;

-- ───────────────────────── ajustes ─────────────────────────

-- Troca os horários de um barbeiro de uma vez só: ou grava tudo, ou não mexe em nada
-- (apagar e inserir em duas chamadas deixava o barbeiro sem horário se a segunda falhasse).
create or replace function salvar_horarios(p_barbeiro uuid, p_horarios jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform exigir_dono();
  if not exists (select 1 from barbeiros where id = p_barbeiro) then raise exception 'Barbeiro não encontrado.'; end if;
  if jsonb_typeof(coalesce(p_horarios, '[]'::jsonb)) <> 'array' then raise exception 'Horários inválidos.'; end if;
  if exists (
    select 1 from jsonb_to_recordset(coalesce(p_horarios, '[]'::jsonb)) as x(dia_semana integer, inicio time, fim time)
    where x.dia_semana is null or x.dia_semana not between 0 and 6
       or x.inicio is null or x.fim is null or x.fim <= x.inicio) then
    raise exception 'Confere os horários: o fim precisa ser depois do início.';
  end if;
  if (select count(*) <> count(distinct x.dia_semana)
      from jsonb_to_recordset(coalesce(p_horarios, '[]'::jsonb)) as x(dia_semana integer)) then
    raise exception 'Tem dia repetido nos horários.';
  end if;
  delete from horarios_trabalho where barbeiro_id = p_barbeiro;
  insert into horarios_trabalho (barbeiro_id, dia_semana, inicio, fim)
  select p_barbeiro, x.dia_semana, x.inicio, x.fim
  from jsonb_to_recordset(coalesce(p_horarios, '[]'::jsonb)) as x(dia_semana integer, inicio time, fim time);
end $$;

-- Logins da equipe. Criar o usuário (e-mail e senha) continua sendo no painel do Supabase,
-- porque precisa da chave de administrador, que nunca vai pro site. Daqui o dono só liga
-- o login ao barbeiro e liga/desliga o acesso.
create or replace function equipe_logins() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_dono();
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', p.id, 'email', u.email, 'nome', p.nome, 'papel', p.papel,
                                        'barbeiro_id', p.barbeiro_id, 'ativo', p.ativo, 'eu', p.id = auth.uid())
                     order by p.papel, p.nome)
    from perfis p left join auth.users u on u.id = p.id), '[]'::jsonb);
end $$;

create or replace function vincular_login(p_email text, p_barbeiro_id uuid) returns void
language plpgsql security definer set search_path = public, auth as $$
declare
  v_user uuid;
  v_nome text;
begin
  perform exigir_dono();
  select u.id into v_user from auth.users u where lower(u.email) = lower(btrim(coalesce(p_email, '')));
  if v_user is null then
    raise exception 'Não achei login com esse e-mail. Cria primeiro no Supabase, em Authentication › Users.';
  end if;
  if v_user = auth.uid() then raise exception 'Esse é o seu próprio login.'; end if;
  select coalesce(apelido, nome) into v_nome from barbeiros where id = p_barbeiro_id;
  if v_nome is null then raise exception 'Barbeiro não encontrado.'; end if;
  -- Quem já é dono continua dono; só muda o barbeiro ligado
  insert into perfis (id, nome, papel, barbeiro_id, ativo)
  values (v_user, v_nome, 'barbeiro', p_barbeiro_id, true)
  on conflict (id) do update set nome = excluded.nome, barbeiro_id = excluded.barbeiro_id, ativo = true;
end $$;

create or replace function mudar_login_ativo(p_perfil uuid, p_ativo boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform exigir_dono();
  if p_perfil = auth.uid() then raise exception 'Você não pode desligar o seu próprio acesso.'; end if;
  update perfis set ativo = coalesce(p_ativo, false) where id = p_perfil;
  if not found then raise exception 'Login não encontrado.'; end if;
end $$;

-- ───────────────────────── finalizar (com Pix) ─────────────────────────

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
                          from servicos s where s.ativo), '[]'::jsonb),
    'pix', jsonb_build_object('chave', cfg_texto('pix_chave'), 'nome', cfg_texto('pix_nome'), 'cidade', cfg_texto('pix_cidade')));
end $$;

-- ───────────────────────── permissões ─────────────────────────

-- Funções novas nascem liberadas pra todo mundo (no Supabase, inclusive direto pra anon e
-- authenticated): fecha pra todos e libera só o que a equipe chama.
-- (info_finalizar e plano_do_cliente mantêm a assinatura e as permissões de antes.)
revoke execute on function
  cfg_texto(text), hoje_local(), usos_no_ciclo(uuid, date), situacao_assinatura(text, date),
  salvar_plano(uuid, text, text, integer, integer, uuid[], boolean),
  entrada_plano(uuid, uuid),
  assinar_plano(uuid, uuid, uuid, text, text),
  registrar_pagamento_plano(uuid, uuid),
  cancelar_assinatura(uuid),
  planos_painel(),
  clientes_lista(text, text),
  ficha_cliente(uuid),
  salvar_cliente(uuid, text, text, boolean),
  painel_mes(date),
  salvar_horarios(uuid, jsonb),
  equipe_logins(),
  vincular_login(text, uuid),
  mudar_login_ativo(uuid, boolean)
from public, anon, authenticated;

-- As auxiliares (cfg_texto, hoje_local, usos_no_ciclo, situacao_assinatura e entrada_plano)
-- ficam sem grant: só rodam por dentro das outras. entrada_plano não confere papel e lança
-- dinheiro no caixa, então nunca pode ser chamada direto.
grant execute on function
  salvar_plano(uuid, text, text, integer, integer, uuid[], boolean),
  assinar_plano(uuid, uuid, uuid, text, text),
  registrar_pagamento_plano(uuid, uuid),
  cancelar_assinatura(uuid),
  planos_painel(),
  clientes_lista(text, text),
  ficha_cliente(uuid),
  salvar_cliente(uuid, text, text, boolean),
  painel_mes(date),
  salvar_horarios(uuid, jsonb),
  equipe_logins(),
  vincular_login(text, uuid),
  mudar_login_ativo(uuid, boolean)
to authenticated;
