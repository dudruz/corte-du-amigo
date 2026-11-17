-- Corte DÚ Amigo · 005 · Tarefas automáticas (opcional)
-- Antes: Supabase › Database › Extensions › ativar "pg_cron".

-- Todo dia às 03:00 (horário de Brasília = 06:00 UTC):
-- marca como atrasadas as assinaturas vencidas
select cron.schedule('assinaturas-atrasadas', '0 6 * * *', $$
  update public.assinaturas set status = 'atrasada'
  where status = 'ativa' and vence_em < (now() at time zone 'America/Sao_Paulo')::date
$$);
