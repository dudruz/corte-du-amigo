-- Corte DÚ Amigo · 009 · Mensagens automáticas pelo WhatsApp (API oficial da Meta)
-- Rodar depois da 008. Pode rodar mais de uma vez sem estragar nada.
--
-- Como funciona: os gatilhos e a rotina diária põem mensagens numa fila (tabela mensagens).
-- A função do Supabase "whatsapp-enviar" pega o que está na hora, manda pela API da Meta
-- e marca o resultado. Tudo nasce DESLIGADO: com o interruptor geral desligado nada entra
-- na fila, e sem a chave da Meta a função não manda nada. Ativação: LEIA-ME, passo 8.

-- ───────────────────────── fila ─────────────────────────

create table if not exists mensagens (
  id uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('confirmacao', 'lembrete', 'horario_mudou', 'cancelado', 'cobranca_plano', 'sumido')),
  cliente_id uuid references clientes on delete cascade,
  agendamento_id uuid references agendamentos on delete cascade,
  assinatura_id uuid references assinaturas on delete cascade,
  telefone text not null,
  modelo text not null,                       -- nome do modelo aprovado na Meta
  parametros jsonb not null default '[]',     -- textos que entram no {{1}}, {{2}}… do modelo
  enviar_em timestamptz not null default now(),
  status text not null default 'pendente' check (status in ('pendente', 'enviando', 'enviada', 'erro', 'cancelada')),
  tentativas integer not null default 0,
  pego_em timestamptz,
  enviada_em timestamptz,
  wa_id text,                                 -- id da mensagem na Meta
  erro text,
  criado_em timestamptz not null default now()
);
create index if not exists mensagens_fila on mensagens (status, enviar_em);
create index if not exists mensagens_agendamento on mensagens (agendamento_id);
create index if not exists mensagens_cliente on mensagens (cliente_id, tipo);

alter table mensagens enable row level security;
drop policy if exists dono_le on mensagens;
create policy dono_le on mensagens for select to authenticated using (eh_dono());
-- Ninguém grava direto: só as funções abaixo
revoke all on mensagens from anon, authenticated;
grant select on mensagens to authenticated;

-- ───────────────────────── configurações ─────────────────────────

insert into configuracoes (chave, valor) values
  ('mensagens_automaticas', '{"ativo": false, "confirmacao": true, "lembrete": true, "horario_mudou": true, "cancelado": true, "cobranca_plano": true, "sumido": false}'),
  ('whatsapp_status', '{"conectado": false, "ultimo_contato": null, "erro": null}'),
  ('site_url', '""')                         -- endereço do site, pros links das mensagens
on conflict (chave) do nothing;

-- ───────────────────────── textos ─────────────────────────

-- 'terça, 17/11 às 17:00' no horário de Brasília
create or replace function quando_texto(p timestamptz) returns text
language sql stable set search_path = public as $$
  select (array['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'])[extract(dow from p at time zone fuso())::integer + 1]
         || ', ' || to_char(p at time zone fuso(), 'DD/MM') || ' às ' || to_char(p at time zone fuso(), 'HH24:MI')
$$;

-- 3500 → 'R$ 35,00'
create or replace function valor_texto(p_centavos integer) returns text
language sql immutable set search_path = public as $$
  select 'R$ ' || replace(to_char(p_centavos / 100, 'FM999,999,990'), ',', '.') || ',' || lpad((p_centavos % 100)::text, 2, '0')
$$;

create or replace function link_site(p_caminho text) returns text
language sql stable security definer set search_path = public as $$
  select rtrim(cfg_texto('site_url'), '/') || '/' || p_caminho
$$;

create or replace function primeiro_nome(p_nome text) returns text
language sql immutable set search_path = public as $$
  select split_part(btrim(coalesce(p_nome, '')), ' ', 1)
$$;

-- ───────────────────────── entrar na fila ─────────────────────────

-- Só entra se o automático e aquele tipo estiverem ligados.
create or replace function enfileirar_mensagem(
  p_tipo text, p_cliente uuid, p_modelo text, p_parametros jsonb,
  p_enviar_em timestamptz default now(), p_agendamento uuid default null, p_assinatura uuid default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_cfg jsonb := coalesce(cfg('mensagens_automaticas'), '{}'::jsonb);
  v_tel text;
begin
  if coalesce((v_cfg ->> 'ativo')::boolean, false) is not true
     or coalesce((v_cfg ->> p_tipo)::boolean, false) is not true then
    return;
  end if;
  select telefone into v_tel from clientes where id = p_cliente;
  if v_tel is null then return; end if;
  insert into mensagens (tipo, cliente_id, agendamento_id, assinatura_id, telefone, modelo, parametros, enviar_em)
  values (p_tipo, p_cliente, p_agendamento, p_assinatura, v_tel, p_modelo, p_parametros, greatest(coalesce(p_enviar_em, now()), now()));
end $$;

-- Lembrete de um agendamento marcado, X horas antes. Não marca se a hora já passou.
create or replace function enfileirar_lembrete(p_agendamento uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  a agendamentos;
  v_nome text;
  v_aceita boolean;
  v_barbeiro text;
  v_quando timestamptz;
begin
  select * into a from agendamentos where id = p_agendamento and status = 'marcado';
  if not found then return; end if;
  select coalesce(a.nome_informado, c.nome), c.aceita_lembrete into v_nome, v_aceita from clientes c where c.id = a.cliente_id;
  if not coalesce(v_aceita, false) then return; end if;
  v_quando := lower(a.periodo) - make_interval(hours => cfg_int('lembrete_horas_antes', 1));
  if v_quando <= now() then return; end if;
  select coalesce(b.apelido, b.nome) into v_barbeiro from barbeiros b where b.id = a.barbeiro_id;
  perform enfileirar_mensagem('lembrete', a.cliente_id, 'corte_lembrete',
    jsonb_build_array(primeiro_nome(v_nome), to_char(lower(a.periodo) at time zone fuso(), 'HH24:MI'), v_barbeiro),
    v_quando, a.id);
end $$;

-- Gatilho dos agendamentos: marcar, remarcar, cancelar, atender.
create or replace function agendamento_mensagens() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_nome text;
  v_barbeiro text;
begin
  select primeiro_nome(coalesce(new.nome_informado, c.nome)) into v_nome from clientes c where c.id = new.cliente_id;
  select coalesce(b.apelido, b.nome) into v_barbeiro from barbeiros b where b.id = new.barbeiro_id;

  if tg_op = 'INSERT' then
    if new.status = 'marcado' then
      perform enfileirar_mensagem('confirmacao', new.cliente_id, 'corte_confirmacao',
        jsonb_build_array(v_nome, quando_texto(lower(new.periodo)), v_barbeiro, link_site('minha-area.html?t=' || new.token)),
        now(), new.id);
      perform enfileirar_lembrete(new.id);
    end if;
    return new;
  end if;

  -- Saiu de marcado (cancelou, faltou, foi atendido): o que estava pra sair perde o sentido
  if old.status in ('marcado', 'em_atendimento') and new.status in ('cancelado', 'faltou', 'finalizado') then
    update mensagens set status = 'cancelada', erro = 'O horário não está mais marcado.'
    where agendamento_id = new.id and status = 'pendente';
    -- Cancelado pela barbearia (agenda fechada ou equipe): avisa. Quem cancelou sozinho já sabe.
    if new.status = 'cancelado' and new.cancelado_motivo in ('bloqueio', 'equipe') then
      perform enfileirar_mensagem('cancelado', new.cliente_id, 'corte_cancelado',
        jsonb_build_array(v_nome, quando_texto(lower(old.periodo)), link_site('index.html')),
        now(), new.id);
    end if;
  elsif new.status = 'marcado' and new.periodo is distinct from old.periodo then
    -- Horário mudou (atraso da barbearia ou remarcação): lembrete na hora nova e aviso
    update mensagens set status = 'cancelada', erro = 'O horário mudou.'
    where agendamento_id = new.id and status = 'pendente' and tipo in ('lembrete', 'horario_mudou');
    perform enfileirar_mensagem('horario_mudou', new.cliente_id, 'corte_horario_mudou',
      jsonb_build_array(v_nome, quando_texto(lower(new.periodo)), link_site('minha-area.html?t=' || new.token)),
      now(), new.id);
    perform enfileirar_lembrete(new.id);
  end if;
  return new;
end $$;

drop trigger if exists agendamentos_mensagens on agendamentos;
create trigger agendamentos_mensagens
  after insert or update of status, periodo on agendamentos
  for each row execute function agendamento_mensagens();

-- Rotina do dia (roda 1 vez por dia, pelo pg_cron, depois da ativação):
--   cobrança de plano: vencido há 1 a 3 dias, uma vez por vencimento;
--   chamar sumido: última visita entre 30 e 120 dias, sem horário marcado, no máximo 1 vez a cada 30 dias.
-- Saem às 10h (ou agora, se já passou).
create or replace function enfileirar_mensagens_do_dia() returns void
language plpgsql security definer set search_path = public as $$
declare
  v_hoje date := hoje_local();
  v_hora timestamptz := greatest(now(), (v_hoje + time '10:00') at time zone fuso());
  r record;
begin
  for r in
    select a.id, a.cliente_id, a.vence_em, p.nome as plano, p.preco_centavos, c.nome
    from assinaturas a join planos p on p.id = a.plano_id join clientes c on c.id = a.cliente_id
    where a.status in ('ativa', 'atrasada')
      and a.vence_em between v_hoje - 3 and v_hoje - 1
      and not exists (select 1 from mensagens m
                      where m.assinatura_id = a.id and m.tipo = 'cobranca_plano'
                        and m.criado_em >= a.vence_em::timestamp at time zone fuso())
  loop
    perform enfileirar_mensagem('cobranca_plano', r.cliente_id, 'corte_cobranca_plano',
      jsonb_build_array(primeiro_nome(r.nome), r.plano, valor_texto(r.preco_centavos), to_char(r.vence_em, 'DD/MM')),
      v_hora, null, r.id);
  end loop;

  for r in
    select c.id, c.nome
    from clientes c
    join lateral (select max(t.finalizado_em) as ultima from atendimentos t where t.cliente_id = c.id) u on true
    where u.ultima between now() - interval '120 days' and now() - interval '30 days'
      and not exists (select 1 from agendamentos g where g.cliente_id = c.id and g.status = 'marcado' and lower(g.periodo) > now())
      and not exists (select 1 from mensagens m where m.cliente_id = c.id and m.tipo = 'sumido' and m.criado_em > now() - interval '30 days')
    order by u.ultima
    limit 20
  loop
    perform enfileirar_mensagem('sumido', r.id, 'corte_sumido',
      jsonb_build_array(primeiro_nome(r.nome), link_site('index.html')), v_hora);
  end loop;
end $$;

-- ───────────────────────── envio (só a função do Supabase) ─────────────────────────

-- Pega as mensagens que estão na hora e marca como "enviando".
create or replace function pegar_mensagens(p_limite integer default 20) returns setof mensagens
language plpgsql security definer set search_path = public as $$
begin
  -- Envio que travou no meio volta pra fila
  update mensagens set status = 'pendente'
  where status = 'enviando' and pego_em < now() - interval '10 minutes';
  -- Confirmação e lembrete que perderam a hora não saem mais (o sistema ficou parado)
  update mensagens set status = 'cancelada', erro = 'Passou da hora de enviar.'
  where status = 'pendente' and tipo in ('confirmacao', 'lembrete') and enviar_em < now() - interval '3 hours';

  return query
  update mensagens m set status = 'enviando', tentativas = m.tentativas + 1, pego_em = now()
  where m.id in (
    select id from mensagens
    where status = 'pendente' and enviar_em <= now()
    order by enviar_em
    limit greatest(1, least(coalesce(p_limite, 20), 100))
    for update skip locked)
  returning m.*;
end $$;

-- Resultado de um envio. Erro tenta de novo daqui a 10, 20 minutos; na 3ª vez fica como erro.
create or replace function registrar_envio(p_id uuid, p_ok boolean, p_wa_id text default null, p_erro text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update mensagens set
    status = case when p_ok then 'enviada' when tentativas >= 3 then 'erro' else 'pendente' end,
    enviada_em = case when p_ok then now() end,
    wa_id = case when p_ok then p_wa_id end,
    erro = case when p_ok then null else left(coalesce(nullif(p_erro, ''), 'Erro sem detalhe.'), 500) end,
    enviar_em = case when p_ok or tentativas >= 3 then enviar_em else now() + make_interval(mins => 10 * tentativas) end
  where id = p_id and status = 'enviando';
end $$;

-- A função avisa a cada rodada se conseguiu falar com a Meta (o painel mostra).
create or replace function registrar_contato_whatsapp(p_ok boolean, p_erro text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into configuracoes (chave, valor)
  values ('whatsapp_status', jsonb_build_object('conectado', coalesce(p_ok, false), 'ultimo_contato', now(),
                                                'erro', case when p_ok then null else left(p_erro, 300) end))
  on conflict (chave) do update set valor = excluded.valor;
end $$;

-- ───────────────────────── painel do dono ─────────────────────────

create or replace function mensagens_painel() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_dono();
  return jsonb_build_object(
    'config', coalesce(cfg('mensagens_automaticas'), '{}'::jsonb),
    'status', coalesce(cfg('whatsapp_status'), '{}'::jsonb),
    'site_url', cfg_texto('site_url'),
    'lembrete_horas', cfg_int('lembrete_horas_antes', 1),
    'semana', (select jsonb_build_object(
                 'enviadas', count(*) filter (where status = 'enviada'),
                 'na_fila', count(*) filter (where status in ('pendente', 'enviando')),
                 'erros', count(*) filter (where status = 'erro'))
               from mensagens where criado_em > now() - interval '7 days'),
    'ultimas', coalesce((
      select jsonb_agg(x.j order by x.quando desc)
      from (select coalesce(m.enviada_em, m.enviar_em) as quando,
                   jsonb_build_object('tipo', m.tipo, 'cliente', c.nome, 'status', m.status,
                                      'quando', coalesce(m.enviada_em, m.enviar_em), 'erro', m.erro) as j
            from mensagens m left join clientes c on c.id = m.cliente_id
            order by coalesce(m.enviada_em, m.enviar_em) desc
            limit 30) x), '[]'::jsonb));
end $$;

-- Liga/desliga o automático e cada tipo, o endereço do site e a antecedência do lembrete.
-- Ao ligar, os horários já marcados ganham lembrete. Ao desligar, o que estava na fila é cancelado.
create or replace function salvar_mensagens_automaticas(
  p_config jsonb, p_site_url text, p_lembrete_horas integer)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_antes jsonb := coalesce(cfg('mensagens_automaticas'), '{}'::jsonb);
  v_horas_antes integer := cfg_int('lembrete_horas_antes', 1);
  v_novo jsonb;
  v_site text := btrim(coalesce(p_site_url, ''));
  v_tipo text;
  r record;
begin
  perform exigir_dono();
  v_novo := jsonb_build_object('ativo', coalesce((p_config ->> 'ativo')::boolean, false));
  foreach v_tipo in array array['confirmacao', 'lembrete', 'horario_mudou', 'cancelado', 'cobranca_plano', 'sumido'] loop
    v_novo := v_novo || jsonb_build_object(v_tipo, coalesce((p_config ->> v_tipo)::boolean, false));
  end loop;
  if v_site <> '' and v_site !~ '^https://[^\s]+$' then
    raise exception 'O endereço do site precisa começar com https://';
  end if;
  if (v_novo ->> 'ativo')::boolean and v_site = '' then
    raise exception 'Coloca o endereço do site antes de ligar: os links das mensagens usam ele.';
  end if;
  if p_lembrete_horas is null or p_lembrete_horas < 1 or p_lembrete_horas > 48 then
    raise exception 'Lembrete: de 1 a 48 horas antes.';
  end if;

  insert into configuracoes (chave, valor) values
    ('mensagens_automaticas', v_novo),
    ('site_url', to_jsonb(v_site)),
    ('lembrete_horas_antes', to_jsonb(p_lembrete_horas))
  on conflict (chave) do update set valor = excluded.valor;

  if not (v_novo ->> 'ativo')::boolean then
    update mensagens set status = 'cancelada', erro = 'Automático desligado.' where status = 'pendente';
    return;
  end if;
  -- Desligou só o lembrete: os da fila saem dela
  if not (v_novo ->> 'lembrete')::boolean then
    update mensagens set status = 'cancelada', erro = 'Lembrete desligado.' where status = 'pendente' and tipo = 'lembrete';
  end if;
  -- Acabou de ligar, ligou o lembrete ou mudou a antecedência: refaz os lembretes dos horários marcados
  if not coalesce((v_antes ->> 'ativo')::boolean, false)
     or not coalesce((v_antes ->> 'lembrete')::boolean, false)
     or v_horas_antes <> p_lembrete_horas then
    update mensagens set status = 'cancelada', erro = 'Lembrete refeito.' where status = 'pendente' and tipo = 'lembrete';
    for r in select id from agendamentos where status = 'marcado' and lower(periodo) > now() loop
      perform enfileirar_lembrete(r.id);
    end loop;
  end if;
end $$;

-- ───────────────────────── permissões ─────────────────────────

-- Fecha tudo que nasceu aqui e libera só o necessário:
--   painel e ajustes → equipe logada (as funções conferem se é o dono);
--   pegar/registrar envio → só a função do Supabase (service_role), nunca o site.
revoke execute on function
  quando_texto(timestamptz), valor_texto(integer), link_site(text), primeiro_nome(text),
  enfileirar_mensagem(text, uuid, text, jsonb, timestamptz, uuid, uuid),
  enfileirar_lembrete(uuid), agendamento_mensagens(), enfileirar_mensagens_do_dia(),
  pegar_mensagens(integer), registrar_envio(uuid, boolean, text, text), registrar_contato_whatsapp(boolean, text),
  mensagens_painel(), salvar_mensagens_automaticas(jsonb, text, integer)
from public, anon, authenticated;

grant execute on function mensagens_painel(), salvar_mensagens_automaticas(jsonb, text, integer) to authenticated;
grant execute on function
  pegar_mensagens(integer), registrar_envio(uuid, boolean, text, text), registrar_contato_whatsapp(boolean, text)
to service_role;
