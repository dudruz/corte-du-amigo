-- Corte DÚ Amigo · testes · 50 · Permissões (o público não lê tabela nem roda função da equipe)

-- TESTE: toda tabela tem RLS ligado
do $$
declare v_sem text;
begin
  select string_agg(c.relname, ', ') into v_sem
  from pg_class c
  where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and not c.relrowsecurity;
  perform teste.igual(v_sem, null::text, 'tabelas sem RLS');
end $$;

-- TESTE: anon não lê nem grava nenhuma tabela
do $$
declare t text;
begin
  perform teste.como_anon();
  for t in select tablename from pg_tables where schemaname = 'public' loop
    perform teste.espera_erro(format('select 1 from public.%I limit 1', t), 'permission denied');
    perform teste.confere(not has_table_privilege('anon', format('public.%I', t), 'select, insert, update, delete'),
                          'anon sem nenhum privilégio em ' || t);
  end loop;
  perform teste.espera_erro($q$insert into clientes (nome, telefone) values ('X', '5531999990001')$q$, 'permission denied');
  perform teste.espera_erro($q$update configuracoes set valor = '999'$q$, 'permission denied');
  perform teste.espera_erro($q$delete from agendamentos$q$, 'permission denied');
end $$;

-- TESTE: anon executa só as funções do agendamento público
do $$
declare
  v_liberadas text;
begin
  select string_agg(p.proname, ', ' order by p.proname) into v_liberadas
  from pg_proc p
  where p.pronamespace = 'public'::regnamespace and has_function_privilege('anon', p.oid, 'execute');
  perform teste.igual(v_liberadas,
    'agendamento_por_token, agendamentos_por_tokens, cancelar_por_token, criar_agendamento, '
    || 'dados_publicos, dias_disponiveis, horarios_livres, remarcar_por_token',
    'funções liberadas pro público');
end $$;

-- TESTE: anon chamando função da equipe leva permissão negada
do $$
declare
  v_ag uuid;
  v_ter timestamptz := teste.em(teste.dia(2), '10:00');
begin
  perform teste.como_anon();
  v_ag := teste.marcar(teste.duim(), v_ter, '31999990001');
  perform teste.espera_erro(format('select caixa_resumo(%L)', teste.hoje()), 'permission denied');
  perform teste.espera_erro(format('select lancar_despesa(''Café'', 800, %L)', teste.forma('pix')), 'permission denied');
  perform teste.espera_erro(format('select lancar_despesa(''Café'', 800, %L, %L)', teste.forma('pix'), teste.hoje()), 'permission denied');
  perform teste.espera_erro(format('select fechar_caixa(%L, 0)', teste.hoje()), 'permission denied');
  perform teste.espera_erro(format('select agenda_do_dia(%L, %L)', teste.duim(), teste.dia(2)), 'permission denied');
  perform teste.espera_erro(format('select info_finalizar(%L)', v_ag), 'permission denied');
  perform teste.espera_erro(format('select finalizar_atendimento(%L, %L)', v_ag, teste.forma('pix')), 'permission denied');
  perform teste.espera_erro(format('select mudar_status(%L, ''cancelado'')', v_ag), 'permission denied');
  perform teste.espera_erro(format('select * from criar_bloqueio(%L, %L, %L)', teste.duim(), v_ter, v_ter + interval '1 hour'), 'permission denied');
  perform teste.espera_erro(format('select * from aplicar_atraso(%L, 30)', teste.duim()), 'permission denied');
  perform teste.espera_erro(format('select plano_do_cliente(%L)', gen_random_uuid()), 'permission denied');
  perform teste.espera_erro(format('select resumo_agendamento(%L)', v_ag), 'permission denied');
  perform teste.espera_erro(format('select pode_barbeiro(%L)', teste.duim()), 'permission denied');
  perform teste.espera_erro(format('select na_grade(%L, %L)', teste.duim(), v_ter), 'permission denied');
  perform teste.espera_erro(format('select validar_inicio(%L, %L)', teste.duim(), v_ter), 'permission denied');
  perform teste.espera_erro(format('select um_bloqueio_conflita(null, %L, %L, false, %L, %L, %L)',
    v_ter, v_ter, teste.duim(), v_ter, v_ter), 'permission denied');
  perform teste.espera_erro($q$select normalizar_telefone('31999990001')$q$, 'permission denied');
  perform teste.igual(teste.status(v_ag), 'marcado', 'agendamento intacto');
end $$;

-- TESTE: anon usa o fluxo público inteiro sem tocar em tabela
do $$
declare
  v_corte uuid;
  v_dia date := teste.dia(2);
  v_ini timestamptz;
  v_token uuid;
begin
  perform teste.como_anon();
  v_corte := (select (s ->> 'id')::uuid from jsonb_array_elements(dados_publicos() -> 'servicos') s where s ->> 'nome' = 'Corte');
  perform teste.confere(v_corte is not null, 'dados_publicos lista os serviços');
  perform teste.confere(exists (select 1 from dias_disponiveis(array[v_corte], null) d where d.livre), 'tem dia livre');
  select min(inicio) into v_ini from horarios_livres(array[v_corte], null, v_dia);
  perform teste.igual(v_ini, teste.em(v_dia, '09:00'), 'primeiro horário do dia');
  v_token := criar_agendamento(array[v_corte], null, v_ini, 'Ana', '31999990001');
  perform teste.igual(agendamento_por_token(v_token) -> 'atual' ->> 'status', 'marcado', 'marcado');
  perform teste.igual(jsonb_array_length(agendamentos_por_tokens(array[v_token])), 1, 'aparece pelos tokens do aparelho');
  perform remarcar_por_token(v_token, teste.em(v_dia, '15:00'));
  perform cancelar_por_token(v_token);
  perform teste.igual(agendamentos_por_tokens(array[v_token]) -> 0 ->> 'status', 'cancelado', 'cancelado');
end $$;

-- TESTE: logado sem perfil da equipe não enxerga nada
do $$
declare t text; v_qtd bigint;
begin
  perform teste.como_anon();
  perform teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31999990001');
  perform teste.como(teste.dono());
  perform lancar_despesa('Café', 800, teste.forma('pix'));

  perform teste.como(teste.sem_perfil());
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('select count(*) from public.%I', t) into v_qtd;
    perform teste.igual(v_qtd, 0::bigint, 'linhas visíveis em ' || t);
  end loop;
  perform teste.espera_erro(format('select agenda_do_dia(%L, %L)', teste.duim(), teste.dia(2)), 'Sem permissão');
  perform teste.espera_erro(format('select * from bloqueios_do_dia(%L, %L)', teste.duim(), teste.dia(2)), 'Acesso só para a equipe');
end $$;

-- TESTE: barbeiro vê só a própria agenda e nada do financeiro
do $$
declare v_dele uuid;
begin
  perform teste.como_anon();
  v_dele := teste.marcar(teste.zeca(), teste.em(teste.dia(2), '10:00'), '31999990001', array['Corte'], 'Ana');
  perform teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31999990002', array['Corte'], 'Beto');
  perform teste.como(teste.dono());
  perform lancar_despesa('Café', 800, teste.forma('pix'));
  perform teste.igual((select count(*) from agendamentos), 2::bigint, 'dono vê os dois');
  perform teste.igual((select count(*) from caixa_movimentos), 1::bigint, 'dono vê o caixa');

  perform teste.como(teste.barbeiro());
  perform teste.igual((select count(*) from agendamentos), 1::bigint, 'barbeiro vê um agendamento');
  perform teste.igual((select id from agendamentos), v_dele, 'o dele');
  perform teste.igual((select string_agg(nome, ',') from clientes), 'Ana', 'só o cliente dele');
  perform teste.igual((select count(*) from caixa_movimentos), 0::bigint, 'caixa fechado pro barbeiro');
  perform teste.igual((select count(*) from pagamentos), 0::bigint, 'pagamentos fechados pro barbeiro');
  -- gravação direta do barbeiro não muda nada: o RLS não dá nenhuma linha pra ele alterar
  update agendamentos set status = 'cancelado';
  update servicos set preco_centavos = 1;
  perform teste.igual(teste.status(v_dele), 'marcado', 'agendamento não mudou por update direto');
  perform teste.como_admin();
  perform teste.igual((select count(*) from servicos where preco_centavos = 1), 0::bigint, 'preço não mudou por update direto');
end $$;
