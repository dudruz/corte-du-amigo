-- Corte DÚ Amigo · 004 · Dados iniciais
-- Preços, durações e taxas são EXEMPLOS: ajustar na tela Configurações depois.

insert into barbeiros (nome, apelido) values ('Duim', 'Duim');

-- Terça (2) a sábado (6), das 9h às 19h30
insert into horarios_trabalho (barbeiro_id, dia_semana, inicio, fim)
select b.id, d, '09:00', '19:30' from barbeiros b, generate_series(2, 6) d where b.nome = 'Duim';

insert into servicos (nome, preco_centavos, duracao_min, ordem) values
  ('Corte', 3500, 30, 1),
  ('Barba', 2500, 30, 2),
  ('Corte + Barba', 5500, 60, 3),
  ('Sobrancelha', 1500, 15, 4);

insert into formas_pagamento (nome, tipo, taxa_percentual, ordem) values
  ('Pix', 'pix', 0, 1),
  ('Dinheiro', 'dinheiro', 0, 2),
  ('Crédito', 'credito', 0, 3),     -- colocar a taxa da InfinitePay
  ('Débito', 'debito', 0, 4),       -- colocar a taxa da InfinitePay
  ('Plano', 'plano', 0, 5),
  ('Fiado', 'fiado', 0, 6);

insert into configuracoes (chave, valor) values
  ('whatsapp_barbearia', '"5531900000000"'),          -- trocar pelo WhatsApp da barbearia
  ('endereco', '"R. Santa Clara de Assis, 20 · Minaslândia, Belo Horizonte"'),
  ('horario_texto', '"Ter a Sáb, 9h às 19h30"'),
  ('cancelamento_antecedencia_horas', '2'),            -- pendente: confirmar com o Duim
  ('intervalo_slots_min', '30'),
  ('troco_inicial_padrao_centavos', '0'),
  ('lembrete_horas_antes', '1');

-- ─────────────────────────────────────────────────────────────
-- LOGIN DO DUIM (fazer depois de rodar os arquivos acima):
-- 1. Supabase › Authentication › Users › Add user (e-mail e senha).
-- 2. Copiar o UUID do usuário criado e rodar:
--
-- insert into perfis (id, nome, papel, barbeiro_id)
-- select 'COLE-O-UUID-AQUI', 'Duim', 'dono', id from barbeiros where nome = 'Duim';
-- ─────────────────────────────────────────────────────────────
