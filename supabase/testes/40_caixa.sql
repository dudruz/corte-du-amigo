-- Corte DÚ Amigo · testes · 40 · Caixa do dia (despesa, gaveta e fechamento)

-- TESTE: despesa cai no dia informado, e dia futuro é recusado
do $$
declare
  v_ontem date := teste.hoje() - 1;
  v_modelo text := 'select lancar_despesa(%L, %L, %L, %L)';
begin
  perform teste.como(teste.dono());
  perform lancar_despesa('Lâminas', 1200, teste.forma('dinheiro'), v_ontem);
  perform lancar_despesa('  Café  ', 800, teste.forma('pix'));
  perform lancar_despesa('Luz', 15000, teste.forma('pix'), teste.hoje());
  perform teste.espera_erro(format(v_modelo, 'Aluguel', 90000, teste.forma('pix'), teste.hoje() + 1), 'dia que ainda não chegou');
  perform teste.espera_erro(format(v_modelo, '   ', 1000, teste.forma('pix'), null), 'Diz do que foi');
  perform teste.espera_erro(format(v_modelo, 'Café', 0, teste.forma('pix'), null), 'Coloca o valor');
  perform teste.espera_erro(format(v_modelo, 'Café', null, teste.forma('pix'), null), 'Coloca o valor');

  perform teste.igual((caixa_resumo(v_ontem) ->> 'saidas')::integer, 1200, 'ontem só a despesa de ontem');
  perform teste.igual((caixa_resumo(v_ontem) ->> 'dinheiro_saidas')::integer, 1200, 'que saiu da gaveta de ontem');
  perform teste.igual((caixa_resumo(teste.hoje()) ->> 'saidas')::integer, 15800, 'hoje as duas de hoje');
  perform teste.igual((caixa_resumo(teste.hoje()) ->> 'dinheiro_saidas')::integer, 0, 'pix não sai da gaveta');

  perform teste.como_admin();
  perform teste.igual((select data from caixa_movimentos where descricao = 'Lâminas'), v_ontem, 'gravada em ontem');
  perform teste.igual((select data from caixa_movimentos where descricao = 'Café'), teste.hoje(), 'sem dia = hoje, e sem espaço sobrando');
  perform teste.igual((select count(*) from caixa_movimentos where tipo = 'saida' and origem = 'despesa' and criado_por = teste.dono()),
                      3::bigint, 'três saídas com autor');
  perform teste.igual((select count(*) from pg_proc where proname = 'lancar_despesa' and pronamespace = 'public'::regnamespace),
                      1::bigint, 'só existe a versão com o dia');
end $$;

-- TESTE: só o dono mexe no caixa
do $$
begin
  perform teste.como(teste.barbeiro());
  perform teste.espera_erro(format('select lancar_despesa(''Café'', 800, %L)', teste.forma('pix')), 'Só o dono');
  perform teste.espera_erro(format('select caixa_resumo(%L)', teste.hoje()), 'Só o dono');
  perform teste.espera_erro(format('select fechar_caixa(%L, 0)', teste.hoje()), 'Só o dono');
  perform teste.espera_erro(format('select definir_troco_inicial(%L, 0)', teste.hoje()), 'Só o dono');
  perform teste.como(teste.sem_perfil());
  perform teste.espera_erro(format('select caixa_resumo(%L)', teste.hoje()), 'Só o dono');
  perform teste.como_admin();
  perform teste.igual((select count(*) from caixa_movimentos), 0::bigint, 'nada gravado');
end $$;

-- TESTE: "deve ter na gaveta" soma troco inicial, dinheiro recebido e saídas em dinheiro
do $$
declare
  v_ag1 uuid; v_ag2 uuid;
  v_r jsonb;
begin
  perform teste.como_anon();
  v_ag1 := teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31999990001');
  v_ag2 := teste.marcar(teste.duim(), teste.em(teste.dia(2), '11:00'), '31999990002');
  perform teste.como(teste.dono());

  v_r := caixa_resumo(teste.hoje());
  perform teste.igual((v_r ->> 'esperado_dinheiro')::integer, 0, 'dia vazio');
  perform teste.igual(v_r -> 'fechamento', 'null'::jsonb, 'sem fechamento');

  perform definir_troco_inicial(teste.hoje(), 5000);
  perform finalizar_atendimento(v_ag1, teste.forma('dinheiro'), '{}', 0, 0, 5000);   -- 35,00 na gaveta
  perform finalizar_atendimento(v_ag2, teste.forma('pix'));                          -- 35,00 fora da gaveta
  perform lancar_despesa('Lâminas', 1000, teste.forma('dinheiro'));
  perform lancar_despesa('Luz', 15000, teste.forma('pix'));

  v_r := caixa_resumo(teste.hoje());
  perform teste.igual((v_r ->> 'troco_inicial')::integer, 5000, 'troco inicial');
  perform teste.igual((v_r ->> 'dinheiro_recebido')::integer, 3500, 'dinheiro recebido');
  perform teste.igual((v_r ->> 'dinheiro_saidas')::integer, 1000, 'saídas em dinheiro');
  perform teste.igual((v_r ->> 'esperado_dinheiro')::integer, 7500, '50,00 + 35,00 - 10,00');
  perform teste.igual((v_r ->> 'entradas')::integer, 7000, 'entradas de todas as formas');
  perform teste.igual((v_r ->> 'saidas')::integer, 16000, 'saídas de todas as formas');
  perform teste.igual(jsonb_array_length(v_r -> 'movimentos'), 4, 'quatro lançamentos');
end $$;

-- TESTE: lançamento depois do fechamento marca o fechamento como desatualizado
do $$
declare
  v_ag uuid;
  v_r jsonb;
begin
  perform teste.como_anon();
  v_ag := teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31999990001');
  perform teste.como(teste.dono());
  perform definir_troco_inicial(teste.hoje(), 5000);
  perform finalizar_atendimento(v_ag, teste.forma('dinheiro'), '{}', 0, 0, 3500);

  v_r := fechar_caixa(teste.hoje(), 8400);
  perform teste.igual((v_r ->> 'esperado')::integer, 8500, 'esperado no fechamento');
  perform teste.igual((v_r ->> 'diferenca')::integer, -100, 'faltou 1,00');
  v_r := caixa_resumo(teste.hoje());
  perform teste.igual((v_r -> 'fechamento' ->> 'desatualizado')::boolean, false, 'recém-fechado está em dia');
  perform teste.igual((v_r -> 'fechamento' ->> 'esperado_dinheiro_centavos')::integer, 8500, 'esperado gravado');
  perform teste.igual((v_r -> 'fechamento' ->> 'contado_dinheiro_centavos')::integer, 8400, 'contado gravado');

  -- o que não passa pela gaveta não pede recontagem
  perform lancar_despesa('Luz', 15000, teste.forma('pix'));
  perform teste.igual((caixa_resumo(teste.hoje()) -> 'fechamento' ->> 'desatualizado')::boolean, false, 'pix não mexe na gaveta');

  perform lancar_despesa('Lâminas', 1000, teste.forma('dinheiro'));
  v_r := caixa_resumo(teste.hoje());
  perform teste.igual((v_r -> 'fechamento' ->> 'desatualizado')::boolean, true, 'saiu dinheiro depois de fechar');
  perform teste.igual((v_r ->> 'esperado_dinheiro')::integer, 7500, 'esperado atual');
  perform teste.igual((v_r -> 'fechamento' ->> 'esperado_dinheiro_centavos')::integer, 8500, 'fechamento guarda o esperado antigo');

  -- fechar de novo o mesmo dia acerta a conta
  v_r := fechar_caixa(teste.hoje(), 7500);
  perform teste.igual((v_r ->> 'diferenca')::integer, 0, 'bateu');
  v_r := caixa_resumo(teste.hoje());
  perform teste.igual((v_r -> 'fechamento' ->> 'desatualizado')::boolean, false, 'em dia depois de recontar');
  perform teste.igual((v_r ->> 'troco_inicial')::integer, 5000, 'troco inicial preservado');

  -- mudar o troco inicial de um dia fechado também pede recontagem
  perform definir_troco_inicial(teste.hoje(), 6000);
  perform teste.igual((caixa_resumo(teste.hoje()) -> 'fechamento' ->> 'desatualizado')::boolean, true, 'troco inicial mudou');

  perform teste.como_admin();
  perform teste.igual((select count(*) from caixa_dia), 1::bigint, 'um fechamento por dia');
end $$;

-- TESTE: despesa lançada num dia já fechado desatualiza o fechamento daquele dia
do $$
declare
  v_ontem date := teste.hoje() - 1;
begin
  perform teste.como(teste.dono());
  perform fechar_caixa(v_ontem, 0);
  perform teste.igual((caixa_resumo(v_ontem) -> 'fechamento' ->> 'desatualizado')::boolean, false, 'ontem fechado zerado');
  perform lancar_despesa('Lâminas', 1000, teste.forma('dinheiro'), v_ontem);
  perform teste.igual((caixa_resumo(v_ontem) -> 'fechamento' ->> 'desatualizado')::boolean, true, 'ontem pede recontagem');
  perform teste.igual((caixa_resumo(v_ontem) ->> 'esperado_dinheiro')::integer, -1000, 'gaveta de ontem ficou devendo');
  perform teste.igual(caixa_resumo(teste.hoje()) -> 'fechamento', 'null'::jsonb, 'hoje não tem fechamento');
end $$;
