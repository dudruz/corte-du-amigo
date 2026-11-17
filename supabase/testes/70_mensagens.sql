-- Corte DÚ Amigo · testes · 70 · Mensagens automáticas (fila, gatilhos, envio e painel)

-- TESTE: tudo nasce desligado: marcar horário não põe nada na fila
do $$
begin
  perform teste.como_anon();
  perform teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31999990001');
  perform teste.igual(teste.fila(), 0::bigint, 'fila vazia com o automático desligado');
  perform teste.como_admin();
  perform teste.igual((select valor ->> 'ativo' from configuracoes where chave = 'mensagens_automaticas'), 'false', 'nasce desligado');
  perform teste.igual((select valor ->> 'sumido' from configuracoes where chave = 'mensagens_automaticas'), 'false', 'sumido nasce desligado');
end $$;

-- TESTE: ligado, marcar põe a confirmação e o lembrete na hora certa; sem aceite, só a confirmação
do $$
declare v_ag uuid; v_m mensagens;
begin
  perform teste.ligar_mensagens();
  perform teste.como_anon();
  v_ag := teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31999990001', array['Corte'], 'Lucas Ferreira');
  perform teste.como_admin();
  select * into v_m from mensagens where agendamento_id = v_ag and tipo = 'confirmacao';
  perform teste.igual(v_m.modelo, 'corte_confirmacao', 'modelo da confirmação');
  perform teste.igual(v_m.telefone, '5531999990001', 'telefone do cliente');
  perform teste.igual(v_m.parametros ->> 0, 'Lucas', 'primeiro nome');
  perform teste.confere(v_m.parametros ->> 1 like '%, __/__ às 10:00', 'quando: ' || (v_m.parametros ->> 1));
  perform teste.igual(v_m.parametros ->> 2, 'Duim', 'barbeiro');
  perform teste.confere(v_m.parametros ->> 3 like 'https://corte.test/minha-area.html?t=%', 'link da minha área');
  select * into v_m from mensagens where agendamento_id = v_ag and tipo = 'lembrete';
  perform teste.igual(v_m.enviar_em, teste.em(teste.dia(2), '09:00'), 'lembrete 1 hora antes');
  perform teste.igual(v_m.parametros ->> 1, '10:00', 'hora no lembrete');

  update clientes set aceita_lembrete = false where telefone = '5531999990002';
  perform teste.como_anon();
  perform criar_agendamento(array[teste.servico('Corte')], teste.duim(), teste.em(teste.dia(2), '11:00'), 'Ana', '31999990002', false);
  perform teste.como_admin();
  perform teste.igual((select count(*) from mensagens m join clientes c on c.id = m.cliente_id where c.telefone = '5531999990002' and m.tipo = 'lembrete'), 0::bigint, 'sem aceite, sem lembrete');
  perform teste.igual((select count(*) from mensagens m join clientes c on c.id = m.cliente_id where c.telefone = '5531999990002' and m.tipo = 'confirmacao'), 1::bigint, 'mas com confirmação');
end $$;

-- TESTE: cliente que cancela sozinho perde o lembrete e não recebe aviso
do $$
declare v_token uuid;
begin
  perform teste.ligar_mensagens();
  perform teste.como_anon();
  v_token := criar_agendamento(array[teste.servico('Corte')], teste.duim(), teste.em(teste.dia(2), '10:00'), 'Lucas', '31999990001');
  perform cancelar_por_token(v_token);
  perform teste.igual(teste.fila('lembrete'), 0::bigint, 'lembrete cancelado');
  perform teste.igual(teste.fila('cancelado'), 0::bigint, 'sem aviso de cancelamento');
end $$;

-- TESTE: agenda fechada ou cancelamento pela equipe avisa o cliente
do $$
declare v_ag1 uuid; v_ag2 uuid; v_m mensagens;
begin
  perform teste.ligar_mensagens();
  perform teste.como_anon();
  v_ag1 := teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31999990001');
  v_ag2 := teste.marcar(teste.duim(), teste.em(teste.dia(3), '10:00'), '31999990002');
  perform teste.como(teste.dono());
  perform criar_bloqueio(teste.duim(), teste.em(teste.dia(2), '09:00'), teste.em(teste.dia(2), '12:00'));
  perform mudar_status(v_ag2, 'cancelado');
  perform teste.como_admin();
  select * into v_m from mensagens where agendamento_id = v_ag1 and tipo = 'cancelado';
  perform teste.igual(v_m.modelo, 'corte_cancelado', 'aviso do bloqueio');
  perform teste.igual(v_m.parametros ->> 2, 'https://corte.test/index.html', 'link pra marcar de novo');
  perform teste.igual((select count(*) from mensagens where agendamento_id = v_ag2 and tipo = 'cancelado'), 1::bigint, 'aviso do cancelamento da equipe');
  perform teste.igual((select count(*) from mensagens where agendamento_id in (v_ag1, v_ag2) and tipo = 'lembrete' and status = 'pendente'), 0::bigint, 'lembretes cancelados');
end $$;

-- TESTE: atraso e remarcação trocam o lembrete e avisam a hora nova
do $$
declare v_token uuid; v_ag uuid;
begin
  perform teste.ligar_mensagens();
  perform teste.como_anon();
  v_token := criar_agendamento(array[teste.servico('Corte')], teste.duim(), teste.em(teste.dia(2), '10:00'), 'Lucas', '31999990001');
  perform remarcar_por_token(v_token, teste.em(teste.dia(2), '14:00'));
  perform teste.como_admin();
  v_ag := (select id from agendamentos where token = v_token);
  perform teste.igual((select count(*) from mensagens where agendamento_id = v_ag and tipo = 'lembrete' and status = 'pendente'), 1::bigint, 'um lembrete só');
  perform teste.igual((select enviar_em from mensagens where agendamento_id = v_ag and tipo = 'lembrete' and status = 'pendente'), teste.em(teste.dia(2), '13:00'), 'lembrete na hora nova');
  perform teste.confere((select parametros ->> 1 from mensagens where agendamento_id = v_ag and tipo = 'horario_mudou') like '%às 14:00', 'aviso com a hora nova');
end $$;

-- TESTE: atendido ou falta cancela o que estava pra sair
do $$
declare v_ag uuid;
begin
  perform teste.ligar_mensagens();
  perform teste.como_anon();
  v_ag := teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31999990001');
  perform teste.como(teste.dono());
  perform finalizar_atendimento(v_ag, teste.forma('pix'));
  perform teste.igual(teste.fila('lembrete'), 0::bigint, 'lembrete cancelado ao finalizar');
end $$;

-- TESTE: a função de envio pega o que está na hora, e erro tenta de novo até 3 vezes
do $$
declare v_ag uuid; v_id uuid; v_qtd integer;
begin
  perform teste.ligar_mensagens();
  perform teste.como_anon();
  v_ag := teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31999990001');
  perform teste.como_servico();
  select count(*) into v_qtd from pegar_mensagens(20);
  perform teste.igual(v_qtd, 1, 'só a confirmação está na hora (o lembrete é depois)');
  perform teste.como_admin();
  v_id := (select id from mensagens where agendamento_id = v_ag and tipo = 'confirmacao');
  perform teste.igual((select status from mensagens where id = v_id), 'enviando', 'marcada como enviando');

  perform teste.como_servico();
  perform registrar_envio(v_id, false, null, 'Número sem WhatsApp');
  perform teste.como_admin();
  perform teste.igual((select status from mensagens where id = v_id), 'pendente', 'volta pra fila');
  perform teste.confere((select enviar_em from mensagens where id = v_id) > now() + interval '9 minutes', 'tenta de novo depois');
  -- 2ª e 3ª tentativas
  update mensagens set enviar_em = now() where id = v_id;
  perform teste.como_servico();
  perform pegar_mensagens(); perform registrar_envio(v_id, false, null, 'falhou');
  perform teste.como_admin(); update mensagens set enviar_em = now() where id = v_id;
  perform teste.como_servico();
  perform pegar_mensagens(); perform registrar_envio(v_id, false, null, 'falhou de novo');
  perform teste.como_admin();
  perform teste.igual((select status from mensagens where id = v_id), 'erro', 'na 3ª fica como erro');
  perform teste.igual((select tentativas from mensagens where id = v_id), 3, 'três tentativas');

  -- Lembrete na hora: sai e fica como enviada
  update mensagens set enviar_em = now() where agendamento_id = v_ag and tipo = 'lembrete';
  perform teste.como_servico();
  select id into v_id from pegar_mensagens();
  perform registrar_envio(v_id, true, 'wamid.123');
  perform registrar_contato_whatsapp(true);
  perform teste.como_admin();
  perform teste.igual((select status from mensagens where id = v_id), 'enviada', 'enviada');
  perform teste.igual((select wa_id from mensagens where id = v_id), 'wamid.123', 'id da Meta guardado');
  perform teste.igual((select valor ->> 'conectado' from configuracoes where chave = 'whatsapp_status'), 'true', 'painel sabe que conectou');
end $$;

-- TESTE: lembrete que perdeu a hora não sai mais
do $$
declare v_ag uuid; v_qtd integer;
begin
  perform teste.ligar_mensagens();
  perform teste.como_anon();
  v_ag := teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31999990001');
  perform teste.como_admin();
  update mensagens set enviar_em = now() - interval '5 hours' where agendamento_id = v_ag;
  perform teste.como_servico();
  select count(*) into v_qtd from pegar_mensagens();
  perform teste.igual(v_qtd, 0, 'nada sai atrasado demais');
  perform teste.como_admin();
  perform teste.igual((select count(*) from mensagens where agendamento_id = v_ag and status = 'cancelada'), 2::bigint, 'confirmação e lembrete cancelados');
end $$;

-- TESTE: rotina do dia cobra plano vencido uma vez só e chama sumido só com o tipo ligado
do $$
declare v_plano uuid; v_ass uuid; v_sumido uuid;
begin
  perform teste.como(teste.dono());
  v_plano := salvar_plano(null, 'Plano Corte', null, 12000, 4);
  v_ass := assinar_plano(v_plano, teste.forma('pix'), null, 'Thiago Souza', '31977770005');
  perform teste.como_admin();
  update assinaturas set vence_em = teste.hoje() - 1 where id = v_ass;
  insert into clientes (nome, telefone) values ('Marcelo Dias', '5531977770001') returning id into v_sumido;
  insert into atendimentos (cliente_id, barbeiro_id, total_centavos, finalizado_em) values (v_sumido, teste.duim(), 3500, now() - interval '47 days');
  perform teste.ligar_mensagens();

  perform enfileirar_mensagens_do_dia();
  perform enfileirar_mensagens_do_dia();
  perform teste.igual(teste.fila('cobranca_plano'), 1::bigint, 'uma cobrança, mesmo rodando duas vezes');
  perform teste.igual((select parametros from mensagens where tipo = 'cobranca_plano'),
                      jsonb_build_array('Thiago', 'Plano Corte', 'R$ 120,00', to_char(teste.hoje() - 1, 'DD/MM')), 'textos da cobrança');
  perform teste.igual(teste.fila('sumido'), 0::bigint, 'sumido desligado por padrão');

  perform teste.ligar_mensagens('{"sumido": true}');
  perform enfileirar_mensagens_do_dia();
  perform enfileirar_mensagens_do_dia();
  perform teste.igual(teste.fila('sumido'), 1::bigint, 'chama o sumido uma vez');
  perform teste.igual((select parametros from mensagens where tipo = 'sumido'), '["Marcelo", "https://corte.test/index.html"]'::jsonb, 'textos do sumido');
end $$;

-- TESTE: no painel, ligar exige o site e cria lembretes dos já marcados; desligar limpa a fila
do $$
declare v_ag uuid; v_cfg jsonb := '{"ativo": true, "confirmacao": true, "lembrete": true, "horario_mudou": true, "cancelado": true, "cobranca_plano": true, "sumido": false}';
begin
  perform teste.como_anon();
  v_ag := teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31999990001');
  perform teste.como(teste.dono());
  perform teste.espera_erro(format('select salvar_mensagens_automaticas(%L, %L, 1)', v_cfg, ''), 'endereço do site antes de ligar');
  perform teste.espera_erro(format('select salvar_mensagens_automaticas(%L, %L, 1)', v_cfg, 'http://corte.test'), 'começar com https://');
  perform teste.espera_erro(format('select salvar_mensagens_automaticas(%L, %L, 0)', v_cfg, 'https://corte.test'), 'de 1 a 48 horas');

  perform salvar_mensagens_automaticas(v_cfg, 'https://corte.test/', 2);
  perform teste.igual(teste.fila('lembrete'), 1::bigint, 'horário já marcado ganhou lembrete');
  perform teste.como_admin();
  perform teste.igual((select enviar_em from mensagens where agendamento_id = v_ag and tipo = 'lembrete' and status = 'pendente'),
                      teste.em(teste.dia(2), '08:00'), '2 horas antes');
  perform teste.como(teste.dono());
  perform teste.igual((mensagens_painel() ->> 'lembrete_horas')::integer, 2, 'painel mostra a antecedência');
  perform teste.igual(mensagens_painel() -> 'semana' ->> 'na_fila', '1', 'painel conta a fila');

  perform salvar_mensagens_automaticas(v_cfg || '{"ativo": false}', 'https://corte.test/', 2);
  perform teste.igual(teste.fila(), 0::bigint, 'desligar cancela a fila');
end $$;

-- TESTE: ninguém além do dono vê a fila, e só a função do Supabase pega mensagens pra enviar
do $$
declare v_qtd bigint;
begin
  perform teste.ligar_mensagens();
  perform teste.como_anon();
  perform teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31999990001');

  perform teste.espera_erro('select count(*) from mensagens', 'permission denied');
  perform teste.espera_erro('select pegar_mensagens()', 'permission denied');
  perform teste.espera_erro('select mensagens_painel()', 'permission denied');

  perform teste.como(teste.barbeiro());
  select count(*) into v_qtd from mensagens;
  perform teste.igual(v_qtd, 0::bigint, 'barbeiro não vê a fila');
  perform teste.espera_erro('select mensagens_painel()', 'Só o dono');
  perform teste.espera_erro('select pegar_mensagens()', 'permission denied');
  perform teste.espera_erro(format('select registrar_envio(%L, true)', gen_random_uuid()), 'permission denied');
  perform teste.espera_erro('select enfileirar_mensagens_do_dia()', 'permission denied');

  perform teste.como(teste.dono());
  select count(*) into v_qtd from mensagens;
  perform teste.igual(v_qtd, 2::bigint, 'dono vê a fila');
  perform teste.espera_erro('select pegar_mensagens()', 'permission denied');
  perform teste.espera_erro(format('select enfileirar_mensagem(%L, %L, %L, %L)', 'sumido', gen_random_uuid(), 'x', '[]'), 'permission denied');
  perform teste.espera_erro('delete from mensagens', 'permission denied');
end $$;
