-- Corte DÚ Amigo · testes · 20 · Agenda da equipe (permissão por barbeiro e bloqueios)

-- TESTE: pode_barbeiro responde sempre sim ou não, nunca nulo
do $$
begin
  perform teste.igual(teste.pode_barbeiro(teste.duim()), false, 'sem login');
  perform teste.como(teste.sem_perfil());
  perform teste.igual(teste.pode_barbeiro(teste.duim()), false, 'logado sem perfil');
  perform teste.como(teste.barbeiro_sem_agenda());
  perform teste.igual(teste.pode_barbeiro(teste.duim()), false, 'barbeiro sem barbeiro_id');
  perform teste.igual(teste.pode_barbeiro(null), false, 'barbeiro sem barbeiro_id, pergunta sem barbeiro');
  perform teste.como(teste.barbeiro());
  perform teste.igual(teste.pode_barbeiro(teste.zeca()), true, 'barbeiro na própria agenda');
  perform teste.igual(teste.pode_barbeiro(teste.duim()), false, 'barbeiro na agenda de outro');
  perform teste.igual(teste.pode_barbeiro(null), false, 'barbeiro, pergunta sem barbeiro');
  perform teste.como(teste.dono());
  perform teste.igual(teste.pode_barbeiro(teste.zeca()), true, 'dono em qualquer agenda');
  perform teste.espera_erro(format('select pode_barbeiro(%L)', teste.zeca()), 'permission denied');
end $$;

-- TESTE: perfil de barbeiro sem barbeiro_id não entra na agenda de ninguém
do $$
declare
  v_ag uuid;
begin
  perform teste.como_anon();
  v_ag := teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31999990001');
  perform teste.como(teste.barbeiro_sem_agenda());
  perform teste.espera_erro(format('select agenda_do_dia(%L, %L)', teste.duim(), teste.dia(2)), 'Sem permissão');
  perform teste.espera_erro(format('select info_finalizar(%L)', v_ag), 'Sem permissão');
  perform teste.espera_erro(format('select mudar_status(%L, ''cancelado'')', v_ag), 'Sem permissão');
  perform teste.espera_erro(format('select finalizar_atendimento(%L, %L)', v_ag, teste.forma('pix')), 'Sem permissão');
  perform teste.espera_erro(format('select * from aplicar_atraso(%L, 30)', teste.duim()), 'Sem permissão');
  perform teste.espera_erro(format('select * from criar_bloqueio(%L, %L, %L)',
    teste.duim(), teste.em(teste.dia(2), '09:00'), teste.em(teste.dia(2), '12:00')), 'sua própria agenda');
  perform teste.igual(teste.status(v_ag), 'marcado', 'agendamento intacto');
end $$;

-- TESTE: bloqueio cancela só quem bate com ele, não com bloqueio antigo
do $$
declare
  v_ter date := teste.dia(2);
  v_qua date := teste.dia(3);
  v_a uuid; v_b uuid; v_c uuid; v_d uuid;
  v_qtd integer;
  v_tel text;
  v_ini timestamptz;
begin
  perform teste.como_anon();
  v_a := teste.marcar(teste.duim(), teste.em(v_ter, '10:00'), '31999990001');
  v_b := teste.marcar(teste.duim(), teste.em(v_qua, '14:00'), '31999990002');
  v_c := teste.marcar(teste.zeca(), teste.em(v_qua, '14:00'), '31999990003');
  v_d := teste.marcar(teste.duim(), teste.em(v_qua, '16:00'), '31999990004');

  -- bloqueio antigo que pega o agendamento A sem ter cancelado ele
  perform teste.como_admin();
  insert into bloqueios (barbeiro_id, inicio, fim) values (teste.duim(), teste.em(v_ter, '09:00'), teste.em(v_ter, '12:00'));

  perform teste.como(teste.dono());
  select count(*), min(telefone), min(inicio) into v_qtd, v_tel, v_ini
  from criar_bloqueio(teste.duim(), teste.em(v_qua, '13:00'), teste.em(v_qua, '15:00'));
  perform teste.igual(v_qtd, 1, 'um afetado');
  perform teste.igual(v_tel, '5531999990002', 'telefone do afetado');
  perform teste.igual(v_ini, teste.em(v_qua, '14:00'), 'horário do afetado');
  perform teste.igual(teste.status(v_a), 'marcado', 'A (só bate com o bloqueio antigo) continua marcado');
  perform teste.igual(teste.status(v_b), 'cancelado', 'B cancelado');
  perform teste.igual(teste.status(v_c), 'marcado', 'C é de outro barbeiro');
  perform teste.igual(teste.status(v_d), 'marcado', 'D é fora do período');

  -- fechar a barbearia toda na quarta pega os dois barbeiros, e só a quarta
  select count(*) into v_qtd from criar_bloqueio(null, teste.em(v_qua, '00:00'), teste.em(v_qua + 1, '00:00'), false, 'Feriado');
  perform teste.igual(v_qtd, 2, 'C e D afetados (B já estava cancelado)');
  perform teste.igual(teste.status(v_c), 'cancelado', 'C cancelado');
  perform teste.igual(teste.status(v_d), 'cancelado', 'D cancelado');
  perform teste.igual(teste.status(v_a), 'marcado', 'A continua marcado');

  perform teste.como_admin();
  perform teste.igual((select cancelado_motivo from agendamentos where id = v_b), 'bloqueio', 'motivo gravado');
  perform teste.igual((select count(*) from bloqueios where criado_por = teste.dono()), 2::bigint, 'bloqueios gravados com autor');
  perform teste.confere(not exists (select 1 from horarios_livres(array[teste.servico('Corte')], null, v_qua)),
                        'quarta fechada não tem horário livre');
end $$;

-- TESTE: bloqueio semanal cancela as semanas seguintes, no mesmo dia e horário
do $$
declare
  v_x uuid; v_y uuid; v_z uuid; v_w uuid; v_v uuid; v_u uuid; v_antes uuid;
  v_qtd integer;
  v_primeiro timestamptz;
begin
  perform teste.como_anon();
  v_x := teste.marcar(teste.duim(), teste.em(teste.dia(2, 1), '12:00'), '31999990001');
  v_y := teste.marcar(teste.duim(), teste.em(teste.dia(2, 2), '12:00'), '31999990002');
  v_z := teste.marcar(teste.duim(), teste.em(teste.dia(2, 3), '12:30'), '31999990003');
  v_w := teste.marcar(teste.duim(), teste.em(teste.dia(2, 2), '15:00'), '31999990004');   -- outro horário
  v_v := teste.marcar(teste.duim(), teste.em(teste.dia(3, 2), '12:00'), '31999990005');   -- outro dia da semana
  v_u := teste.marcar(teste.zeca(), teste.em(teste.dia(2, 2), '12:00'), '31999990006');   -- outro barbeiro
  v_antes := teste.marcar(teste.duim(), teste.em(teste.dia(2, 0), '12:00'), '31999990007'); -- semana antes de começar

  perform teste.como(teste.dono());
  select count(*), min(inicio) into v_qtd, v_primeiro
  from criar_bloqueio(teste.duim(), teste.em(teste.dia(2, 1), '12:00'), teste.em(teste.dia(2, 1), '13:00'), true, 'Almoço');
  perform teste.igual(v_qtd, 3, 'três afetados');
  perform teste.igual(v_primeiro, teste.em(teste.dia(2, 1), '12:00'), 'lista começa pelo mais próximo');
  perform teste.igual(teste.status(v_x), 'cancelado', 'primeira semana');
  perform teste.igual(teste.status(v_y), 'cancelado', 'semana seguinte');
  perform teste.igual(teste.status(v_z), 'cancelado', 'duas semanas depois, pegando só a segunda metade');
  perform teste.igual(teste.status(v_w), 'marcado', 'outro horário fica');
  perform teste.igual(teste.status(v_v), 'marcado', 'outro dia da semana fica');
  perform teste.igual(teste.status(v_u), 'marcado', 'outro barbeiro fica');
  perform teste.igual(teste.status(v_antes), 'marcado', 'semana anterior ao início fica');

  -- e o horário some pra quem for marcar nas semanas seguintes
  perform teste.como_anon();
  perform teste.espera_erro(format(
    'select criar_agendamento(array[%L::uuid], %L, %L, ''Hugo'', ''31999990008'')',
    teste.servico('Corte'), teste.duim(), teste.em(teste.dia(2, 4), '12:30')), 'não está disponível');
  perform teste.confere(not exists (
    select 1 from horarios_livres(array[teste.servico('Corte')], teste.duim(), teste.dia(2, 4)) h
    where h.inicio in (teste.em(teste.dia(2, 4), '12:00'), teste.em(teste.dia(2, 4), '12:30'))), 'almoço fora dos livres');
  perform teste.confere(exists (
    select 1 from horarios_livres(array[teste.servico('Corte')], teste.duim(), teste.dia(2, 4)) h
    where h.inicio = teste.em(teste.dia(2, 4), '13:00')), '13h continua livre');
end $$;

-- TESTE: cada um só fecha a agenda que pode
do $$
declare
  v_ini timestamptz := teste.em(teste.dia(2), '09:00');
  v_fim timestamptz := teste.em(teste.dia(2), '12:00');
begin
  perform teste.como(teste.barbeiro());
  perform teste.espera_erro(format('select * from criar_bloqueio(%L, %L, %L)', teste.duim(), v_ini, v_fim), 'sua própria agenda');
  perform teste.espera_erro(format('select * from criar_bloqueio(null, %L, %L)', v_ini, v_fim), 'Só o dono pode fechar a barbearia toda');
  perform teste.espera_erro(format('select * from criar_bloqueio(%L, %L, %L)', teste.zeca(), v_fim, v_ini), 'depois do início');
  perform * from criar_bloqueio(teste.zeca(), v_ini, v_fim);

  perform teste.como(teste.sem_perfil());
  perform teste.espera_erro(format('select * from criar_bloqueio(%L, %L, %L)', teste.duim(), v_ini, v_fim), 'Acesso só para a equipe');

  perform teste.como_admin();
  perform teste.igual((select count(*) from bloqueios), 1::bigint, 'só o bloqueio permitido foi gravado');
end $$;

-- TESTE: agenda do dia mostra marcados e bloqueios do barbeiro
do $$
declare
  v_dia date := teste.dia(2, 1);
  v_r jsonb;
begin
  perform teste.como_anon();
  perform teste.marcar(teste.zeca(), teste.em(v_dia, '10:00'), '31999990001', array['Corte'], 'Ana');
  perform teste.como(teste.barbeiro());
  perform * from criar_bloqueio(teste.zeca(), teste.em(v_dia, '12:00'), teste.em(v_dia, '13:00'), true, 'Almoço');
  v_r := agenda_do_dia(teste.zeca(), v_dia);
  perform teste.igual(jsonb_array_length(v_r -> 'itens'), 1, 'um agendamento');
  perform teste.igual(v_r -> 'itens' -> 0 ->> 'cliente', 'Ana', 'nome do cliente');
  perform teste.igual(jsonb_array_length(v_r -> 'bloqueios'), 1, 'um bloqueio');
  perform teste.espera_erro(format('select agenda_do_dia(%L, %L)', teste.duim(), v_dia), 'Sem permissão');
end $$;
