-- Corte DÚ Amigo · testes · 60 · Gestão (planos, clientes, painel do mês, horários e logins)

-- TESTE: dono cria plano, assina pra cliente novo e o primeiro mês entra no caixa
do $$
declare
  v_plano uuid; v_ass uuid; v_r jsonb;
begin
  perform teste.como_admin();
  update formas_pagamento set taxa_percentual = 4 where tipo = 'credito';
  perform teste.como(teste.dono());
  v_plano := salvar_plano(null, 'Plano Corte', '4 cortes no mês', 12000, 4, array[teste.servico('Corte')]);
  v_ass := assinar_plano(v_plano, teste.forma('credito'), null, 'Lucas', '(31) 98888-0001');

  v_r := planos_painel();
  perform teste.igual(jsonb_array_length(v_r -> 'assinaturas'), 1, 'uma assinatura');
  perform teste.igual(v_r -> 'assinaturas' -> 0 ->> 'cliente', 'Lucas', 'nome do cliente');
  perform teste.igual(v_r -> 'assinaturas' -> 0 ->> 'situacao', 'em_dia', 'em dia');
  perform teste.igual((v_r -> 'assinaturas' -> 0 ->> 'vence_em')::date, (teste.hoje() + interval '1 month')::date, 'vence em um mês');
  perform teste.igual((v_r -> 'planos' -> 0 ->> 'assinantes')::integer, 1, 'plano com um assinante');
  perform teste.confere(not exists (select 1 from jsonb_array_elements(v_r -> 'formas') f where f ->> 'tipo' in ('plano', 'fiado')),
                        'plano não se paga com plano nem fiado');

  perform teste.como_admin();
  perform teste.igual((select telefone from clientes where nome = 'Lucas'), '5531988880001', 'telefone normalizado');
  perform teste.igual((select bruto_centavos from caixa_movimentos where origem = 'plano'), 12000, 'bruto do plano');
  perform teste.igual((select liquido_centavos from caixa_movimentos where origem = 'plano'), 11520, 'líquido com 4% de taxa');
  perform teste.igual((select referencia_id from caixa_movimentos where origem = 'plano'), v_ass, 'movimento aponta pra assinatura');
end $$;

-- TESTE: cliente com plano valendo não assina outro, e plano não se paga com fiado
do $$
declare v_plano uuid; v_cli uuid;
begin
  perform teste.como(teste.dono());
  v_plano := salvar_plano(null, 'Plano Corte', null, 12000, 4);
  perform assinar_plano(v_plano, teste.forma('pix'), null, 'Lucas', '31988880001');
  perform teste.como_admin();
  v_cli := (select id from clientes where telefone = '5531988880001');
  perform teste.como(teste.dono());
  perform teste.espera_erro(format('select assinar_plano(%L, %L, %L)', v_plano, teste.forma('pix'), v_cli), 'já tem plano');
  perform teste.espera_erro(format('select assinar_plano(%L, %L, null, %L, %L)', v_plano, teste.forma('pix'), 'Lucas', '31988880001'), 'já tem plano');
  perform teste.espera_erro(format('select assinar_plano(%L, %L, null, %L, %L)', v_plano, teste.forma('fiado'), 'Ana', '31988880002'), 'como ele pagou');
  perform teste.espera_erro(format('select assinar_plano(%L, %L, null, %L, %L)', v_plano, teste.forma('pix'), 'Ana', '123'), 'WhatsApp inválido');
  perform teste.espera_erro('select salvar_plano(null, ''X'', null, 1000, 4)', 'nome pro plano');
  perform teste.espera_erro('select salvar_plano(null, ''Plano'', null, 0, 4)', 'preço do plano');
  perform teste.espera_erro('select salvar_plano(null, ''Plano'', null, 1000, 0)', 'Cortes por mês');
  perform teste.espera_erro(format('select salvar_plano(null, %L, null, 1000, 4, array[%L]::uuid[])', 'Plano', gen_random_uuid()), 'serviços que existem');
end $$;

-- TESTE: renovação em dia emenda o mês, atrasada começa hoje, e pagamento repetido é recusado
do $$
declare v_plano uuid; v_ass uuid; v_novo date;
begin
  perform teste.como(teste.dono());
  v_plano := salvar_plano(null, 'Plano Corte', null, 12000, 4);
  v_ass := assinar_plano(v_plano, teste.forma('pix'), null, 'Lucas', '31988880001');

  -- Pago com folga: segunda cobrança no mesmo dia é engano
  perform teste.espera_erro(format('select registrar_pagamento_plano(%L, %L)', v_ass, teste.forma('pix')), 'já está pago até');

  -- Vence daqui a 2 dias: renova a partir do vencimento
  perform teste.como_admin();
  update assinaturas set vence_em = teste.hoje() + 2 where id = v_ass;
  perform teste.como(teste.dono());
  v_novo := registrar_pagamento_plano(v_ass, teste.forma('dinheiro'));
  perform teste.igual(v_novo, ((teste.hoje() + 2) + interval '1 month')::date, 'emenda no vencimento');

  -- Atrasado 10 dias: renova a partir de hoje
  perform teste.como_admin();
  update assinaturas set vence_em = teste.hoje() - 10, status = 'atrasada' where id = v_ass;
  perform teste.como(teste.dono());
  perform teste.igual((planos_painel() -> 'assinaturas' -> 0 ->> 'situacao'), 'atrasada', 'aparece como atrasada');
  v_novo := registrar_pagamento_plano(v_ass, teste.forma('pix'));
  perform teste.igual(v_novo, (teste.hoje() + interval '1 month')::date, 'atrasado começa hoje');

  perform teste.como_admin();
  perform teste.igual((select status from assinaturas where id = v_ass), 'ativa', 'volta a ficar ativa');
  perform teste.igual((select count(*) from caixa_movimentos where origem = 'plano'), 3::bigint, 'três meses pagos no caixa');
end $$;

-- TESTE: cancelar tira o plano do cliente e libera assinar de novo
do $$
declare v_plano uuid; v_ass uuid; v_cli uuid;
begin
  perform teste.como(teste.dono());
  v_plano := salvar_plano(null, 'Plano Corte', null, 12000, 4);
  v_ass := assinar_plano(v_plano, teste.forma('pix'), null, 'Lucas', '31988880001');
  perform cancelar_assinatura(v_ass);
  perform teste.espera_erro(format('select cancelar_assinatura(%L)', v_ass), 'já estava cancelado');
  perform teste.igual(jsonb_array_length(planos_painel() -> 'assinaturas'), 0, 'sai da lista');
  perform teste.como_admin();
  v_cli := (select cliente_id from assinaturas where id = v_ass);
  perform teste.igual(plano_do_cliente(v_cli), null::jsonb, 'cliente sem plano');
  perform teste.como(teste.dono());
  perform assinar_plano(v_plano, teste.forma('pix'), v_cli);
  perform teste.igual(jsonb_array_length(planos_painel() -> 'assinaturas'), 1, 'assinou de novo');
end $$;

-- TESTE: uso do plano conta no mês certo, pela meia-noite de Brasília
do $$
declare v_plano uuid; v_ass uuid; v_vence date := teste.hoje() + 5; v_inicio_ciclo date;
begin
  perform teste.como(teste.dono());
  v_plano := salvar_plano(null, 'Plano Corte', null, 12000, 4);
  v_ass := assinar_plano(v_plano, teste.forma('pix'), null, 'Lucas', '31988880001');
  perform teste.como_admin();
  update assinaturas set vence_em = v_vence where id = v_ass;
  v_inicio_ciclo := (v_vence - interval '1 month')::date;
  -- 22h do dia anterior ao início do ciclo, em Brasília: ainda é o mês passado
  insert into usos_plano (assinatura_id, usado_em) values (v_ass, teste.em(v_inicio_ciclo - 1, '22:00'));
  -- 00h30 do primeiro dia do ciclo: já conta
  insert into usos_plano (assinatura_id, usado_em) values (v_ass, teste.em(v_inicio_ciclo, '00:30'));
  perform teste.igual(usos_no_ciclo(v_ass, v_vence), 1, 'só o uso do ciclo atual');
end $$;

-- TESTE: lista de clientes separa sumidos, assinantes e fiado, e busca por nome e telefone
do $$
declare
  v_sumido uuid; v_fiado uuid; v_ag uuid; v_plano uuid; v_r jsonb;
begin
  perform teste.como_admin();
  insert into clientes (nome, telefone) values ('Marcelo Sumido', '5531977770001') returning id into v_sumido;
  insert into atendimentos (cliente_id, barbeiro_id, total_centavos, finalizado_em)
  values (v_sumido, teste.duim(), 3500, now() - interval '47 days');

  perform teste.como_anon();
  v_ag := teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31977770002', array['Corte'], 'Gabriel Fiado');
  perform teste.como(teste.dono());
  perform finalizar_atendimento(v_ag, teste.forma('fiado'));
  v_plano := salvar_plano(null, 'Plano Corte', null, 12000, 4);
  perform assinar_plano(v_plano, teste.forma('pix'), null, 'Pedro Assinante', '31977770003');

  v_r := clientes_lista();
  perform teste.igual((v_r -> 'contagens' ->> 'todos')::integer, 3, 'três clientes');
  perform teste.igual((v_r -> 'contagens' ->> 'sumidos')::integer, 1, 'um sumido');
  perform teste.igual((v_r -> 'contagens' ->> 'assinantes')::integer, 1, 'um assinante');
  perform teste.igual((v_r -> 'contagens' ->> 'fiado')::integer, 1, 'um no fiado');

  v_r := clientes_lista(null, 'sumidos');
  perform teste.igual(v_r -> 'clientes' -> 0 ->> 'nome', 'Marcelo Sumido', 'filtro sumidos');
  perform teste.igual((v_r -> 'clientes' -> 0 ->> 'dias_sem_vir')::integer >= 46, true, 'dias sem vir');
  v_r := clientes_lista(null, 'fiado');
  perform teste.igual(v_r -> 'clientes' -> 0 ->> 'nome', 'Gabriel Fiado', 'filtro fiado');
  perform teste.igual((v_r -> 'clientes' -> 0 ->> 'fiado_centavos')::integer, 3500, 'quanto deve');
  perform teste.igual(v_r -> 'clientes' -> 0 ->> 'ultimo_servico', 'Corte', 'último serviço');
  v_r := clientes_lista('pedro', 'todos');
  perform teste.igual(jsonb_array_length(v_r -> 'clientes'), 1, 'busca por nome sem acento de caixa');
  v_r := clientes_lista('7770001', 'todos');
  perform teste.igual(v_r -> 'clientes' -> 0 ->> 'nome', 'Marcelo Sumido', 'busca por telefone');
  perform teste.espera_erro('select clientes_lista(null, ''qualquer'')', 'Filtro inválido');
end $$;

-- TESTE: ficha do cliente mostra histórico, fiado e próximos, e o dono edita observações
do $$
declare v_ag uuid; v_ag2 uuid; v_cli uuid; v_r jsonb;
begin
  perform teste.como_anon();
  v_ag := teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31977770002', array['Corte', 'Barba'], 'Gabriel');
  v_ag2 := teste.marcar(teste.duim(), teste.em(teste.dia(2, 1), '10:00'), '31977770002', array['Corte'], 'Gabriel');
  perform teste.como(teste.dono());
  perform finalizar_atendimento(v_ag, teste.forma('fiado'), '{}', 500, 1000);
  perform teste.como_admin();
  v_cli := (select cliente_id from agendamentos where id = v_ag);
  perform teste.como(teste.dono());

  v_r := ficha_cliente(v_cli);
  perform teste.igual((v_r -> 'resumo' ->> 'visitas')::integer, 1, 'uma visita');
  perform teste.igual((v_r -> 'resumo' ->> 'gasto_centavos')::integer, 5500, 'gasto com desconto');
  perform teste.igual(v_r -> 'historico' -> 0 ->> 'servicos', 'Barba + Corte', 'serviços do atendimento');
  perform teste.igual((v_r -> 'historico' -> 0 ->> 'pendente')::boolean, true, 'ainda no fiado');
  perform teste.igual((v_r -> 'fiados' -> 0 ->> 'valor')::integer, 6500, 'fiado com gorjeta');
  perform teste.igual(jsonb_array_length(v_r -> 'proximos'), 1, 'um horário marcado');

  perform salvar_cliente(v_cli, 'Gabriel Rocha', '  Gosta de máquina 2  ', false);
  perform teste.como_admin();
  perform teste.igual((select observacoes from clientes where id = v_cli), 'Gosta de máquina 2', 'observação sem espaço sobrando');
  perform teste.igual((select aceita_lembrete from clientes where id = v_cli), false, 'lembrete desligado');
  perform teste.como(teste.dono());
  perform teste.espera_erro(format('select salvar_cliente(%L, %L, null)', v_cli, 'G'), 'Coloca o nome');
  perform teste.espera_erro(format('select ficha_cliente(%L)', gen_random_uuid()), 'Cliente não encontrado');
end $$;

-- TESTE: painel do mês soma o caixa, ticket médio, formas e comissão
do $$
declare v_ag1 uuid; v_ag2 uuid; v_r jsonb; v_duim jsonb;
begin
  perform teste.como_admin();
  update barbeiros set comissao_tipo = 'percentual', comissao_valor = 40 where id = teste.duim();
  update barbeiros set comissao_tipo = 'fixo_por_corte', comissao_valor = 1500 where id = teste.zeca();
  update formas_pagamento set taxa_percentual = 5 where tipo = 'credito';
  perform teste.como_anon();
  v_ag1 := teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31977770011', array['Corte']);
  v_ag2 := teste.marcar(teste.duim(), teste.em(teste.dia(2), '11:00'), '31977770012', array['Corte + Barba']);
  perform teste.como(teste.dono());
  perform finalizar_atendimento(v_ag1, teste.forma('pix'), '{}', 0, 500);
  perform finalizar_atendimento(v_ag2, teste.forma('credito'), '{}', 500, 0);
  perform lancar_despesa('Lâminas', 2000, teste.forma('dinheiro'));

  v_r := painel_mes();
  perform teste.igual((v_r ->> 'bruto')::integer, 4000 + 5000, 'bruto: 35 + 5 de gorjeta, 55 - 5 de desconto');
  perform teste.igual((v_r ->> 'liquido')::integer, 4000 + 4750, 'líquido com 5% no crédito');
  perform teste.igual((v_r ->> 'despesas')::integer, 2000, 'despesas');
  perform teste.igual((v_r ->> 'atendimentos')::integer, 2, 'dois atendimentos');
  perform teste.igual((v_r ->> 'ticket_medio')::integer, 4250, 'ticket: (35 + 50) / 2');
  perform teste.igual((v_r ->> 'gorjetas')::integer, 500, 'gorjetas à parte');
  perform teste.igual((v_r -> 'hoje' ->> 'entradas')::integer, 9000, 'entrou hoje');
  perform teste.igual(v_r -> 'formas' -> 0 ->> 'nome', 'Crédito', 'forma que mais entrou primeiro');
  perform teste.confere(jsonb_array_length(v_r -> 'semana') between 1 and 7, 'semana com os dias de trabalho');

  select c into v_duim from jsonb_array_elements(v_r -> 'comissoes') c where c ->> 'barbeiro' = 'Duim';
  perform teste.igual((v_duim ->> 'base_centavos')::integer, 8500, 'base da comissão sem gorjeta');
  perform teste.igual((v_duim ->> 'comissao_centavos')::integer, 3400, '40% de 85');
  perform teste.igual((select (c ->> 'comissao_centavos')::integer from jsonb_array_elements(v_r -> 'comissoes') c
                       where c ->> 'barbeiro' = 'Zeca'), 0, 'Zeca sem atendimento, sem comissão');
end $$;

-- TESTE: horários salvam tudo de uma vez ou nada
do $$
begin
  perform teste.como(teste.dono());
  perform salvar_horarios(teste.zeca(), '[{"dia_semana":2,"inicio":"10:00","fim":"18:00"},{"dia_semana":6,"inicio":"08:00","fim":"14:00"}]');
  perform teste.como_admin();
  perform teste.igual((select count(*) from horarios_trabalho where barbeiro_id = teste.zeca()), 2::bigint, 'dois dias');
  perform teste.como(teste.dono());
  perform teste.espera_erro(format('select salvar_horarios(%L, %L)', teste.zeca(), '[{"dia_semana":3,"inicio":"10:00","fim":"09:00"}]'), 'fim precisa ser depois');
  perform teste.espera_erro(format('select salvar_horarios(%L, %L)', teste.zeca(), '[{"dia_semana":3,"inicio":"10:00","fim":"12:00"},{"dia_semana":3,"inicio":"13:00","fim":"18:00"}]'), 'dia repetido');
  perform teste.como_admin();
  perform teste.igual((select count(*) from horarios_trabalho where barbeiro_id = teste.zeca()), 2::bigint, 'erro não apagou nada');
  perform teste.como(teste.dono());
  perform salvar_horarios(teste.zeca(), '[]');
  perform teste.como_admin();
  perform teste.igual((select count(*) from horarios_trabalho where barbeiro_id = teste.zeca()), 0::bigint, 'lista vazia = não trabalha');
end $$;

-- TESTE: dono liga login ao barbeiro e desliga o acesso; não mexe no próprio
do $$
declare v_novo uuid := gen_random_uuid();
begin
  perform teste.como_admin();
  insert into auth.users (id, email) values (v_novo, 'Novo@Teste');
  perform teste.como(teste.dono());
  perform vincular_login('  novo@teste ', teste.zeca());
  perform teste.como_admin();
  perform teste.igual((select papel::text from perfis where id = v_novo), 'barbeiro', 'virou barbeiro');
  perform teste.igual((select barbeiro_id from perfis where id = v_novo), teste.zeca(), 'ligado ao Zeca');
  perform teste.como(teste.dono());
  perform teste.confere(exists (select 1 from jsonb_array_elements(equipe_logins()) l where l ->> 'email' = 'Novo@Teste'), 'aparece na lista');
  perform mudar_login_ativo(v_novo, false);
  perform teste.espera_erro(format('select mudar_login_ativo(%L, false)', teste.dono()), 'seu próprio acesso');
  perform teste.espera_erro(format('select vincular_login(%L, %L)', 'dono@teste', teste.zeca()), 'seu próprio login');
  perform teste.espera_erro(format('select vincular_login(%L, %L)', 'ninguem@teste', teste.zeca()), 'Não achei login');
  perform teste.como_admin();
  perform teste.igual((select ativo from perfis where id = v_novo), false, 'acesso desligado');
end $$;

-- TESTE: finalizar mostra a chave Pix configurada
do $$
declare v_ag uuid;
begin
  perform teste.como_admin();
  update configuracoes set valor = '"31999998888"' where chave = 'pix_chave';
  perform teste.como_anon();
  v_ag := teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31977770021');
  perform teste.como(teste.dono());
  perform teste.igual(info_finalizar(v_ag) -> 'pix' ->> 'chave', '31999998888', 'chave Pix');
  perform teste.igual(info_finalizar(v_ag) -> 'pix' ->> 'cidade', 'BELO HORIZONTE', 'cidade');
end $$;

-- TESTE: só o dono usa as funções de gestão, e as auxiliares não são chamáveis de fora
do $$
declare
  v_chamada text;
begin
  foreach v_chamada in array array[
    'select planos_painel()', 'select clientes_lista()', 'select painel_mes()', 'select equipe_logins()',
    format('select ficha_cliente(%L)', gen_random_uuid()),
    format('select salvar_plano(null, %L, null, 1000, 4)', 'Plano'),
    format('select salvar_horarios(%L, %L)', teste.zeca(), '[]'),
    format('select registrar_pagamento_plano(%L, %L)', gen_random_uuid(), teste.forma('pix'))
  ] loop
    perform teste.como(teste.barbeiro());
    perform teste.espera_erro(v_chamada, 'Só o dono');
    perform teste.como(teste.sem_perfil());
    perform teste.espera_erro(v_chamada, 'Só o dono');
    perform teste.como_anon();
    perform teste.espera_erro(v_chamada, 'permission denied');
  end loop;

  foreach v_chamada in array array[
    format('select entrada_plano(%L, %L)', gen_random_uuid(), teste.forma('pix')),
    format('select usos_no_ciclo(%L, %L)', gen_random_uuid(), teste.hoje()),
    'select cfg_texto(''pix_chave'')'
  ] loop
    perform teste.como(teste.dono());
    perform teste.espera_erro(v_chamada, 'permission denied');
    perform teste.como(teste.barbeiro());
    perform teste.espera_erro(v_chamada, 'permission denied');
  end loop;
end $$;
