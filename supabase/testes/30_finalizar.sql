-- Corte DÚ Amigo · testes · 30 · Finalizar e receber

-- TESTE: dinheiro com desconto, gorjeta e troco
do $$
declare
  v_ag uuid;
  v_r jsonb;
  p pagamentos;
  m caixa_movimentos;
begin
  perform teste.como_anon();
  v_ag := teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31999990001', array['Corte'], 'Ana');
  perform teste.como(teste.dono());
  -- Corte 35,00 - 5,00 de desconto + 2,00 de gorjeta = 32,00
  perform teste.espera_erro(format('select finalizar_atendimento(%L, %L, ''{}'', 500, 200, 3100)', v_ag, teste.forma('dinheiro')),
                            'recebido é menor');
  perform teste.espera_erro(format('select finalizar_atendimento(%L, %L, ''{}'', 500, 200, null)', v_ag, teste.forma('dinheiro')),
                            'recebido é menor');
  perform teste.espera_erro(format('select finalizar_atendimento(%L, %L, ''{}'', 3600, 0, 5000)', v_ag, teste.forma('dinheiro')),
                            'desconto é maior');
  perform teste.espera_erro(format('select finalizar_atendimento(%L, %L, ''{}'', -1, 0, 5000)', v_ag, teste.forma('dinheiro')),
                            'negativos');
  perform teste.espera_erro(format('select finalizar_atendimento(%L, %L)', v_ag, gen_random_uuid()), 'forma de pagamento');

  v_r := finalizar_atendimento(v_ag, teste.forma('dinheiro'), '{}', 500, 200, 5000);
  perform teste.igual((v_r ->> 'total_centavos')::integer, 3200, 'total cobrado');
  perform teste.igual((v_r ->> 'troco_centavos')::integer, 1800, 'troco');
  perform teste.igual(teste.status(v_ag), 'finalizado', 'agendamento finalizado');
  perform teste.espera_erro(format('select finalizar_atendimento(%L, %L, ''{}'', 0, 0, 5000)', v_ag, teste.forma('dinheiro')),
                            'já foi fechado');

  perform teste.como_admin();
  select * into p from pagamentos;
  perform teste.igual(p.bruto_centavos, 3200, 'pagamento bruto');
  perform teste.igual(p.taxa_centavos, 0, 'sem taxa');
  perform teste.igual(p.liquido_centavos, 3200, 'pagamento líquido');
  perform teste.igual(p.recebido_dinheiro_centavos, 5000, 'recebido');
  perform teste.igual(p.troco_centavos, 1800, 'troco gravado');
  perform teste.igual(p.pendente, false, 'não é fiado');
  select * into m from caixa_movimentos;
  perform teste.igual(m.tipo || '/' || m.origem, 'entrada/atendimento', 'entrada no caixa');
  perform teste.igual(m.bruto_centavos, 3200, 'caixa bruto');
  perform teste.igual(m.data, teste.hoje(), 'no dia de hoje');
  perform teste.igual(m.descricao, 'Corte · Ana', 'descrição');
  perform teste.igual((select total_centavos || '/' || desconto_centavos || '/' || gorjeta_centavos from atendimentos),
                      '3500/500/200', 'atendimento gravado');
end $$;

-- TESTE: cartão desconta a taxa, com serviço extra na hora
do $$
declare
  v_ag uuid;
  v_r jsonb;
  p pagamentos;
begin
  update formas_pagamento set taxa_percentual = 3.19 where tipo = 'credito';
  perform teste.como_anon();
  v_ag := teste.marcar(teste.zeca(), teste.em(teste.dia(2), '10:00'), '31999990001');
  perform teste.como(teste.barbeiro());
  -- Corte 35,00 + Barba 25,00 = 60,00; 3,19% = 1,914 → 1,91
  v_r := finalizar_atendimento(v_ag, teste.forma('credito'), array[teste.servico('Barba')]);
  perform teste.igual((v_r ->> 'total_centavos')::integer, 6000, 'total com o extra');
  perform teste.confere(v_r ->> 'troco_centavos' is null, 'cartão não tem troco');

  perform teste.como_admin();
  select * into p from pagamentos;
  perform teste.igual(p.taxa_centavos, 191, 'taxa arredondada em centavos');
  perform teste.igual(p.liquido_centavos, 5809, 'líquido');
  perform teste.igual((select bruto_centavos || '/' || liquido_centavos from caixa_movimentos), '6000/5809', 'caixa com bruto e líquido');
  perform teste.igual((select count(*) from agendamento_servicos where agendamento_id = v_ag), 2::bigint, 'extra gravado');
  perform teste.igual((select finalizado_por from atendimentos), teste.barbeiro(), 'quem finalizou');
end $$;

-- TESTE: taxa de meio centavo arredonda pra cima
do $$
declare
  v_ag uuid;
begin
  update formas_pagamento set taxa_percentual = 1.30 where tipo = 'debito';
  perform teste.como_anon();
  v_ag := teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31999990001');
  perform teste.como(teste.dono());
  -- 35,00 × 1,30% = 0,455 → 0,46
  perform finalizar_atendimento(v_ag, teste.forma('debito'));
  perform teste.como_admin();
  perform teste.igual((select taxa_centavos || '/' || liquido_centavos from pagamentos), '46/3454', 'taxa e líquido');
end $$;

-- TESTE: fiado fica pendente e só entra no caixa quando acerta
do $$
declare
  v_ag uuid;
  v_pag uuid;
  v_r jsonb;
begin
  perform teste.como_anon();
  v_ag := teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31999990001', array['Corte'], 'Ana');
  perform teste.como(teste.dono());
  perform finalizar_atendimento(v_ag, teste.forma('fiado'));
  v_r := caixa_resumo(teste.hoje());
  perform teste.igual(jsonb_array_length(v_r -> 'movimentos'), 0, 'fiado não entra no caixa');
  perform teste.igual(jsonb_array_length(v_r -> 'fiados'), 1, 'aparece na lista de fiados');
  perform teste.igual((v_r -> 'fiados' -> 0 ->> 'valor')::integer, 3500, 'valor do fiado');
  v_pag := (v_r -> 'fiados' -> 0 ->> 'pagamento_id')::uuid;

  perform teste.espera_erro(format('select quitar_fiado(%L, %L)', v_pag, teste.forma('fiado')), 'Escolha como ele pagou');
  perform quitar_fiado(v_pag, teste.forma('pix'));
  v_r := caixa_resumo(teste.hoje());
  perform teste.igual(jsonb_array_length(v_r -> 'fiados'), 0, 'saiu da lista');
  perform teste.igual((v_r ->> 'entradas')::integer, 3500, 'entrou no caixa');
  perform teste.igual(v_r -> 'movimentos' -> 0 ->> 'origem', 'fiado_quitado', 'como fiado acertado');
  perform teste.espera_erro(format('select quitar_fiado(%L, %L)', v_pag, teste.forma('pix')), 'já foi acertado');

  perform teste.como_admin();
  perform teste.confere((select not pendente and quitado_em is not null from pagamentos where id = v_pag), 'pagamento quitado');
end $$;

-- TESTE: Plano recusa serviço fora dos incluídos e aceita quando cobre
do $$
declare
  v_plano uuid;
  v_ass uuid;
  v_ag1 uuid; v_ag2 uuid; v_ag3 uuid;
  v_r jsonb;
begin
  perform teste.como_anon();
  v_ag1 := teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31999990001');
  v_ag2 := teste.marcar(teste.duim(), teste.em(teste.dia(2), '11:00'), '31999990001');
  v_ag3 := teste.marcar(teste.duim(), teste.em(teste.dia(2), '12:00'), '31999990001');
  perform teste.como_admin();
  insert into planos (nome, preco_centavos, usos_por_mes, servicos_incluidos)
  values ('Só corte', 9000, 2, array[teste.servico('Corte')]) returning id into v_plano;
  insert into assinaturas (cliente_id, plano_id, vence_em)
  values ((select id from clientes where telefone = '5531999990001'), v_plano, teste.hoje() + 20) returning id into v_ass;

  perform teste.como(teste.dono());
  v_r := info_finalizar(v_ag1) -> 'plano';
  perform teste.igual(v_r -> 'servicos_incluidos', jsonb_build_array(teste.servico('Corte')), 'info_finalizar leva os serviços do plano');

  -- a mensagem é parte do contrato com a tela
  begin
    perform finalizar_atendimento(v_ag1, teste.forma('plano'), array[teste.servico('Barba'), teste.servico('Sobrancelha')]);
    raise exception 'FALHOU: Plano com serviço fora devia ser recusado';
  exception when others then
    perform teste.igual(sqlerrm, 'Tem serviço fora do plano: Barba, Sobrancelha. Tira o extra ou cobra tudo em outra forma.',
                        'mensagem de serviço fora do plano');
  end;
  perform teste.igual(teste.status(v_ag1), 'marcado', 'recusa não mexe no agendamento');

  v_r := finalizar_atendimento(v_ag1, teste.forma('plano'));
  perform teste.igual((v_r ->> 'total_centavos')::integer, 0, 'coberto pelo plano sai de graça');
  -- a gorjeta de quem usa o plano entra no caixa
  v_r := finalizar_atendimento(v_ag2, teste.forma('plano'), '{}', 0, 300);
  perform teste.igual((v_r ->> 'total_centavos')::integer, 300, 'só a gorjeta');
  perform teste.espera_erro(format('select finalizar_atendimento(%L, %L)', v_ag3, teste.forma('plano')), 'já usou todos os cortes');

  perform teste.como_admin();
  perform teste.igual((select count(*) from usos_plano where assinatura_id = v_ass), 2::bigint, 'dois usos gravados');
  perform teste.igual((select count(*) from agendamentos where usa_plano), 2::bigint, 'agendamentos marcados como plano');
  perform teste.igual((select count(*) || '/' || sum(bruto_centavos) from caixa_movimentos), '1/300', 'no caixa só a gorjeta');
  perform teste.igual((select count(*) from agendamento_servicos where agendamento_id = v_ag1), 1::bigint,
                      'extra da tentativa recusada não ficou gravado');
end $$;

-- TESTE: plano sem lista de serviços (nula ou vazia) cobre tudo
do $$
declare
  v_plano uuid;
  v_ag1 uuid; v_ag2 uuid;
begin
  perform teste.como_anon();
  v_ag1 := teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31999990001', array['Corte', 'Barba']);
  v_ag2 := teste.marcar(teste.duim(), teste.em(teste.dia(2), '11:00'), '31999990001');
  perform teste.como_admin();
  insert into planos (nome, preco_centavos) values ('Livre', 15000) returning id into v_plano;
  insert into assinaturas (cliente_id, plano_id, vence_em)
  values ((select id from clientes where telefone = '5531999990001'), v_plano, teste.hoje() + 20);

  perform teste.como(teste.dono());
  perform teste.confere(info_finalizar(v_ag1) -> 'plano' ? 'servicos_incluidos', 'chave presente mesmo nula');
  perform teste.igual(info_finalizar(v_ag1) -> 'plano' -> 'servicos_incluidos', 'null'::jsonb, 'nula quando cobre tudo');
  perform teste.igual((finalizar_atendimento(v_ag1, teste.forma('plano')) ->> 'total_centavos')::integer, 0, 'lista nula cobre tudo');

  perform teste.como_admin();
  update planos set servicos_incluidos = '{}' where id = v_plano;
  perform teste.como(teste.dono());
  perform teste.igual((finalizar_atendimento(v_ag2, teste.forma('plano'), array[teste.servico('Sobrancelha')]) ->> 'total_centavos')::integer,
                      0, 'lista vazia cobre tudo');
end $$;

-- TESTE: Plano só vale com assinatura ativa e em dia
do $$
declare
  v_plano uuid;
  v_ag uuid;
begin
  perform teste.como_anon();
  v_ag := teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31999990001');
  perform teste.como(teste.dono());
  perform teste.espera_erro(format('select finalizar_atendimento(%L, %L)', v_ag, teste.forma('plano')), 'não tem plano ativo');

  perform teste.como_admin();
  insert into planos (nome, preco_centavos) values ('Livre', 15000) returning id into v_plano;
  insert into assinaturas (cliente_id, plano_id, inicio, vence_em)
  values ((select id from clientes where telefone = '5531999990001'), v_plano, teste.hoje() - 40, teste.hoje() - 1);
  perform teste.como(teste.dono());
  perform teste.espera_erro(format('select finalizar_atendimento(%L, %L)', v_ag, teste.forma('plano')), 'não tem plano ativo');
  perform teste.igual(teste.status(v_ag), 'marcado', 'continua em aberto');
end $$;

-- TESTE: barbeiro só finaliza atendimento da própria agenda
do $$
declare
  v_ag uuid;
begin
  perform teste.como_anon();
  v_ag := teste.marcar(teste.duim(), teste.em(teste.dia(2), '10:00'), '31999990001');
  perform teste.como(teste.barbeiro());
  perform teste.espera_erro(format('select finalizar_atendimento(%L, %L)', v_ag, teste.forma('pix')), 'Sem permissão');
  perform teste.espera_erro(format('select info_finalizar(%L)', v_ag), 'Sem permissão');
  perform teste.como(teste.sem_perfil());
  perform teste.espera_erro(format('select finalizar_atendimento(%L, %L)', v_ag, teste.forma('pix')), 'Sem permissão');
  perform teste.igual(teste.status(v_ag), 'marcado', 'continua em aberto');
end $$;
