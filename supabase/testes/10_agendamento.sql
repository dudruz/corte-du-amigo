-- Corte DÚ Amigo · testes · 10 · Agendamento pelo público
-- Formato: cada "-- TESTE:" é um bloco que passa quando não dá erro (ver rodar.mjs).

-- TESTE: dois agendamentos no mesmo horário, só um passa
do $$
declare
  v_ini timestamptz := teste.em(teste.dia(2), '10:00');
  v_corte uuid := teste.servico('Corte');
begin
  perform teste.como_anon();
  perform criar_agendamento(array[v_corte], teste.duim(), v_ini, 'Ana', '31999990001');
  perform teste.espera_erro(format(
    'select criar_agendamento(array[%L::uuid], %L, %L, %L, %L)', v_corte, teste.duim(), v_ini, 'Beto', '31999990002'),
    'acabou de ser pego');
  -- Corte + Barba (60 min) começando 9h30 passaria por cima do das 10h
  perform teste.espera_erro(format(
    'select criar_agendamento(array[%L::uuid], %L, %L, %L, %L)',
    teste.servico('Corte + Barba'), teste.duim(), teste.em(teste.dia(2), '09:30'), 'Caio', '31999990003'),
    'acabou de ser pego');
  -- "Tanto faz" pega o outro barbeiro; quando os dois estão ocupados, recusa
  perform criar_agendamento(array[v_corte], null, v_ini, 'Beto', '31999990002');
  perform teste.espera_erro(format(
    'select criar_agendamento(array[%L::uuid], null, %L, %L, %L)', v_corte, v_ini, 'Caio', '31999990003'),
    'acabou de ser pego');

  perform teste.como_admin();
  perform teste.igual((select count(*) from agendamentos where lower(periodo) = v_ini and status = 'marcado'),
                      2::bigint, 'um agendamento por barbeiro nesse horário');
  perform teste.igual((select count(distinct barbeiro_id) from agendamentos where lower(periodo) = v_ini),
                      2::bigint, 'cada um com um barbeiro diferente');
  perform teste.confere(not exists (select 1 from horarios_livres(array[v_corte], null, teste.dia(2)) h
                                    where h.inicio = v_ini), 'horário ocupado some da lista de livres');
end $$;

-- TESTE: marcar com o telefone de outra pessoa não mostra nada dela
do $$
declare
  v_corte uuid := teste.servico('Corte');
  v_ana uuid;
  v_beto uuid;
  v_r jsonb;
  v_lista jsonb;
begin
  perform teste.como_anon();
  v_ana := criar_agendamento(array[v_corte], teste.duim(), teste.em(teste.dia(2), '10:00'), 'Ana Dona do Número', '31999990001');
  v_beto := criar_agendamento(array[v_corte], teste.duim(), teste.em(teste.dia(2), '11:00'), 'Beto Curioso', '(31) 99999-0001');

  v_r := agendamento_por_token(v_beto);
  perform teste.igual(v_r -> 'atual' ->> 'token', v_beto::text, 'atual é o próprio agendamento');
  perform teste.igual(v_r -> 'cliente' ->> 'nome', 'Beto Curioso', 'nome é o que ele digitou');
  perform teste.igual(v_r -> 'cliente' ->> 'telefone', '5531999990001', 'telefone normalizado');
  perform teste.igual((v_r ->> 'cancelamento_horas')::integer, 2, 'prazo de cancelamento');
  perform teste.confere(not (v_r ?| array['proximos', 'historico', 'plano']), 'sem próximos, histórico nem plano');
  perform teste.igual((select count(*) from jsonb_object_keys(v_r)), 3::bigint, 'só as três chaves do contrato');
  perform teste.confere(position(v_ana::text in v_r::text) = 0, 'não vaza o token da Ana');
  perform teste.confere(position('Ana' in v_r::text) = 0, 'não vaza o nome da Ana');

  perform teste.igual(agendamento_por_token(v_ana) -> 'cliente' ->> 'nome', 'Ana Dona do Número', 'Ana continua vendo o nome dela');
  perform teste.confere(agendamento_por_token(gen_random_uuid()) is null, 'token que não existe devolve nulo');

  v_lista := agendamentos_por_tokens(array[v_beto, gen_random_uuid()]);
  perform teste.igual(jsonb_array_length(v_lista), 1, 'só o token pedido que existe');
  perform teste.igual(v_lista -> 0 ->> 'token', v_beto::text, 'e é o do Beto');
  perform teste.confere(v_lista -> 0 ?& array['id', 'token', 'status', 'inicio', 'fim', 'barbeiro_id', 'barbeiro',
                                               'servicos', 'servico_ids', 'total_centavos'], 'formato do resumo');
  perform teste.confere(not (v_lista -> 0 ?| array['cliente', 'telefone', 'nome']), 'resumo não leva dado do cliente');

  v_lista := agendamentos_por_tokens(array[v_beto, v_ana]);
  perform teste.igual(jsonb_array_length(v_lista), 2, 'dois tokens, dois resumos');
  perform teste.igual(v_lista -> 0 ->> 'token', v_ana::text, 'ordenado pelo início');

  perform teste.igual(agendamentos_por_tokens('{}'), '[]'::jsonb, 'lista vazia devolve []');
  perform teste.igual(agendamentos_por_tokens(null), '[]'::jsonb, 'nulo devolve []');

  perform teste.como_admin();
  perform teste.igual((select nome from clientes where telefone = '5531999990001'), 'Ana Dona do Número',
                      'o cadastro do número não troca de nome');
  perform teste.igual((select count(*) from clientes where telefone = '5531999990001'), 1::bigint, 'um cadastro por telefone');
end $$;

-- TESTE: agendamentos_por_tokens olha no máximo 20 tokens
do $$
declare
  v_token uuid;
  v_muitos uuid[];
begin
  perform teste.como_anon();
  v_token := criar_agendamento(array[teste.servico('Corte')], teste.duim(), teste.em(teste.dia(2), '10:00'), 'Ana', '31999990001');
  select array_agg(gen_random_uuid()) into v_muitos from generate_series(1, 20);
  perform teste.igual(jsonb_array_length(agendamentos_por_tokens(v_muitos || v_token)), 0, 'o 21º token é ignorado');
  perform teste.igual(jsonb_array_length(agendamentos_por_tokens(v_muitos[1:19] || v_token)), 1, 'o 20º ainda vale');
end $$;

-- TESTE: início fora da grade, além do horizonte ou vazio é recusado
do $$
declare
  v_corte uuid := teste.servico('Corte');
  v_modelo text := 'select criar_agendamento(array[%L::uuid], %L, %L, ''Ana'', ''31999990001'')';
begin
  perform teste.como_anon();
  perform teste.espera_erro(format(v_modelo, v_corte, teste.duim(), teste.em(teste.dia(2), '10:10')), 'não existe na agenda');
  perform teste.espera_erro(format(v_modelo, v_corte, teste.duim(), teste.em(teste.dia(2), '10:00:01')), 'não existe na agenda');
  perform teste.espera_erro(format(v_modelo, v_corte, null, teste.em(teste.dia(2), '10:10')), 'Escolhe outro');
  perform teste.espera_erro(format(v_modelo, v_corte, teste.duim(), teste.em(teste.dia(2, 9), '10:00')), 'até 60 dias');
  perform teste.espera_erro(format(v_modelo, v_corte, null, teste.em(teste.dia(2, 9), '10:00')), 'até 60 dias');
  perform teste.espera_erro(format(v_modelo, v_corte, teste.duim(), null), 'Escolhe o dia e o horário');
  perform teste.espera_erro(format(v_modelo, v_corte, null, null), 'Escolhe o dia e o horário');
  -- domingo e fora do expediente continuam recusados
  perform teste.espera_erro(format(v_modelo, v_corte, teste.duim(), teste.em(teste.dia(0), '10:00')), 'Escolhe');
  perform teste.espera_erro(format(v_modelo, v_corte, teste.duim(), teste.em(teste.dia(2), '19:30')), 'não existe na agenda');
  -- 19h está na grade, mas Corte + Barba (60 min) passaria do fechamento
  perform teste.espera_erro(format(v_modelo, teste.servico('Corte + Barba'), teste.duim(), teste.em(teste.dia(2), '19:00')),
                            'não está disponível');
  perform teste.espera_erro(format(v_modelo, v_corte, teste.duim(), now() - interval '7 days'), 'Escolhe');

  -- o horizonte segue a configuração
  perform teste.como_admin();
  update configuracoes set valor = '3' where chave = 'agendar_ate_dias';
  perform teste.como_anon();
  perform teste.espera_erro(format(v_modelo, v_corte, teste.duim(), teste.em(teste.dia(2, 1), '10:00')), 'até 3 dias');

  perform teste.como_admin();
  perform teste.igual((select count(*) from agendamentos), 0::bigint, 'nada foi gravado');
end $$;

-- TESTE: todo horário devolvido por horarios_livres é aceito por criar_agendamento
do $$
declare
  v_sobrancelha uuid := teste.servico('Sobrancelha');
  v_qtd integer;
  v_ultimo timestamptz;
begin
  perform teste.como_anon();
  select count(*), max(inicio) into v_qtd, v_ultimo from horarios_livres(array[v_sobrancelha], teste.duim(), teste.dia(4));
  perform teste.igual(v_qtd, 21, 'das 9h às 19h de meia em meia hora');
  perform teste.igual(v_ultimo, teste.em(teste.dia(4), '19:00'), 'último slot do dia');
  perform criar_agendamento(array[v_sobrancelha], teste.duim(), v_ultimo, 'Ana', '31999990001');
end $$;

-- TESTE: teto de agendamentos por hora vale só para o público
do $$
declare
  v_corte uuid := teste.servico('Corte');
  v_dia date := teste.dia(2);
begin
  update configuracoes set valor = '2' where chave = 'limite_agendamentos_hora';
  perform teste.como_anon();
  perform criar_agendamento(array[v_corte], teste.duim(), teste.em(v_dia, '09:00'), 'Ana', '31999990001');
  perform criar_agendamento(array[v_corte], teste.duim(), teste.em(v_dia, '09:30'), 'Beto', '31999990002');
  perform teste.espera_erro(format(
    'select criar_agendamento(array[%L::uuid], %L, %L, ''Caio'', ''31999990003'')', v_corte, teste.duim(), teste.em(v_dia, '10:00')),
    'Muita gente marcando agora');

  -- a equipe logada marca pelo balcão sem entrar na conta
  perform teste.como(teste.dono());
  perform criar_agendamento(array[v_corte], teste.duim(), teste.em(v_dia, '10:00'), 'Caio', '31999990003');
  perform criar_agendamento(array[v_corte], teste.duim(), teste.em(v_dia, '10:30'), 'Davi', '31999990004');
  perform teste.como_anon();
  perform teste.espera_erro(format(
    'select criar_agendamento(array[%L::uuid], %L, %L, ''Enzo'', ''31999990005'')', v_corte, teste.duim(), teste.em(v_dia, '11:00')),
    'Muita gente marcando agora');

  -- conta criada no Auth sem perfil da equipe é público como qualquer outro
  perform teste.como(teste.sem_perfil());
  perform teste.espera_erro(format(
    'select criar_agendamento(array[%L::uuid], %L, %L, ''Enzo'', ''31999990005'')', v_corte, teste.duim(), teste.em(v_dia, '11:00')),
    'Muita gente marcando agora');

  -- o que foi marcado há mais de uma hora não conta
  perform teste.como_admin();
  update agendamentos set criado_em = now() - interval '61 minutes' where criado_por is null;
  perform teste.como_anon();
  perform criar_agendamento(array[v_corte], teste.duim(), teste.em(v_dia, '11:00'), 'Enzo', '31999990005');

  perform teste.como_admin();
  perform teste.igual((select count(*) from agendamentos where criado_por is null), 3::bigint, 'três pelo site');
  perform teste.igual((select count(*) from agendamentos where criado_por = teste.dono()), 2::bigint, 'dois pela equipe');
end $$;

-- TESTE: telefone é normalizado para 55 + DDD + número
do $$
begin
  perform teste.igual(normalizar_telefone('031 99999-8888'), '5531999998888', 'zero na frente do DDD');
  perform teste.igual(normalizar_telefone('(31) 99999-8888'), '5531999998888', 'celular com DDD');
  perform teste.igual(normalizar_telefone('+55 31 99999-8888'), '5531999998888', 'já com 55');
  perform teste.igual(normalizar_telefone('0055 31 99999-8888'), '5531999998888', '00 + 55');
  perform teste.igual(normalizar_telefone('31 3333-4444'), '553133334444', 'fixo com DDD');
  perform teste.espera_erro($q$select normalizar_telefone('319999988881')$q$, 'WhatsApp inválido');
  perform teste.espera_erro($q$select normalizar_telefone('1231999998888')$q$, 'WhatsApp inválido');
  perform teste.espera_erro($q$select normalizar_telefone('99999-8888')$q$, 'WhatsApp inválido');
  perform teste.espera_erro($q$select normalizar_telefone('')$q$, 'WhatsApp inválido');
  perform teste.espera_erro($q$select normalizar_telefone(null)$q$, 'WhatsApp inválido');

  perform teste.como_anon();
  perform teste.espera_erro(format(
    'select criar_agendamento(array[%L::uuid], %L, %L, ''Ana'', ''319999988881'')',
    teste.servico('Corte'), teste.duim(), teste.em(teste.dia(2), '10:00')), 'WhatsApp inválido');
  perform criar_agendamento(array[teste.servico('Corte')], teste.duim(), teste.em(teste.dia(2), '10:00'), 'Ana', '031 99999-8888');
  perform teste.como_admin();
  perform teste.igual((select telefone from clientes), '5531999998888', 'gravado normalizado');
end $$;

-- TESTE: nome, serviço e limite de três horários continuam valendo
do $$
declare
  v_corte uuid := teste.servico('Corte');
  v_dia date := teste.dia(2);
  v_modelo text := 'select criar_agendamento(%L::uuid[], %L, %L, %L, ''31999990001'')';
begin
  perform teste.como_anon();
  perform teste.espera_erro(format(v_modelo, array[v_corte], teste.duim(), teste.em(v_dia, '10:00'), ' A '), 'Coloca seu nome');
  perform teste.espera_erro(format(v_modelo, '{}', teste.duim(), teste.em(v_dia, '10:00'), 'Ana'), 'pelo menos um serviço');
  perform criar_agendamento(array[v_corte], teste.duim(), teste.em(v_dia, '10:00'), 'Ana', '31999990001');
  perform criar_agendamento(array[v_corte], teste.duim(), teste.em(v_dia, '11:00'), 'Ana', '31999990001');
  perform criar_agendamento(array[v_corte], teste.duim(), teste.em(v_dia, '12:00'), 'Ana', '31999990001');
  perform teste.espera_erro(format(v_modelo, array[v_corte], teste.duim(), teste.em(v_dia, '13:00'), 'Ana'), 'já tem 3 horários');
end $$;

-- TESTE: remarcar exige grade e horizonte, e respeita o horário dos outros
do $$
declare
  v_corte uuid := teste.servico('Corte');
  v_dia date := teste.dia(2);
  v_ana uuid;
  v_r jsonb;
begin
  perform teste.como_anon();
  v_ana := criar_agendamento(array[v_corte], teste.duim(), teste.em(v_dia, '10:00'), 'Ana', '31999990001');
  perform criar_agendamento(array[v_corte], teste.duim(), teste.em(v_dia, '11:00'), 'Beto', '31999990002');

  perform teste.espera_erro(format('select remarcar_por_token(%L, %L)', v_ana, teste.em(v_dia, '14:10')), 'não existe na agenda');
  perform teste.espera_erro(format('select remarcar_por_token(%L, %L)', v_ana, teste.em(teste.dia(2, 9), '14:00')), 'até 60 dias');
  perform teste.espera_erro(format('select remarcar_por_token(%L, null)', v_ana), 'Escolhe o dia e o horário');
  perform teste.espera_erro(format('select remarcar_por_token(%L, %L)', v_ana, teste.em(v_dia, '11:00')), 'acabou de ser pego');
  perform teste.espera_erro(format('select remarcar_por_token(%L, %L)', v_ana, teste.em(teste.dia(0), '10:00')), 'Escolhe');
  perform teste.espera_erro(format('select remarcar_por_token(%L, %L)', gen_random_uuid(), teste.em(v_dia, '14:00')), 'não pode mais ser remarcado');

  perform teste.igual(remarcar_por_token(v_ana, teste.em(v_dia, '14:00')), v_ana, 'devolve o mesmo token');
  v_r := agendamento_por_token(v_ana);
  perform teste.igual((v_r -> 'atual' ->> 'inicio')::timestamptz, teste.em(v_dia, '14:00'), 'novo início');
  perform teste.igual((v_r -> 'atual' ->> 'fim')::timestamptz, teste.em(v_dia, '14:30'), 'mesma duração');
end $$;

-- TESTE: cancelar e remarcar respeitam o prazo de antecedência
do $$
declare
  v_ana uuid;
begin
  perform teste.como_anon();
  v_ana := criar_agendamento(array[teste.servico('Corte')], teste.duim(), teste.em(teste.dia(2), '10:00'), 'Ana', '31999990001');
  perform teste.como_admin();
  update agendamentos set periodo = tstzrange(now() + interval '1 hour', now() + interval '90 minutes') where token = v_ana;
  perform teste.como_anon();
  perform teste.espera_erro(format('select cancelar_por_token(%L)', v_ana), 'Faltam menos de 2 horas');
  perform teste.espera_erro(format('select remarcar_por_token(%L, %L)', v_ana, teste.em(teste.dia(3), '10:00')), 'Faltam menos de 2 horas');

  perform teste.como_admin();
  update agendamentos set periodo = tstzrange(now() + interval '3 hours', now() + interval '210 minutes') where token = v_ana;
  perform teste.como_anon();
  perform cancelar_por_token(v_ana);
  perform teste.igual(agendamento_por_token(v_ana) -> 'atual' ->> 'status', 'cancelado', 'cancelado');
  perform teste.espera_erro(format('select cancelar_por_token(%L)', v_ana), 'não pode mais ser cancelado');
end $$;
