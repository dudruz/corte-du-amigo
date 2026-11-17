-- Corte DÚ Amigo · ativar as mensagens automáticas do WhatsApp
-- Rodar UMA vez, no SQL Editor do Supabase, no dia da ativação (LEIA-ME, passo 8).
-- Não é migration: liga as rotinas que chamam a função de envio. Pode rodar de novo sem duplicar nada.
-- Se o projeto do Supabase mudar, troque o endereço da função lá embaixo.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Senha que a rotina manda pra função no cabeçalho x-cron-secret. Gerada aqui e guardada no Vault.
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'whatsapp_cron_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(24), 'hex'), 'whatsapp_cron_secret');
  end if;
end $$;

-- Tira as rotinas antigas com esses nomes, pra não duplicar
select cron.unschedule(jobid) from cron.job
where jobname in ('whatsapp-enviar', 'whatsapp-mensagens-do-dia', 'assinaturas-atrasadas');

-- A cada 5 minutos: manda o que está na fila
select cron.schedule('whatsapp-enviar', '*/5 * * * *', $$
  select net.http_post(
    url := 'https://zbatdzorctfhhumewqub.supabase.co/functions/v1/whatsapp-enviar',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'whatsapp_cron_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000)
$$);

-- Todo dia às 9h de Brasília (12h UTC): cobranças de plano e clientes sumidos (saem às 10h)
select cron.schedule('whatsapp-mensagens-do-dia', '0 12 * * *', $$ select public.enfileirar_mensagens_do_dia() $$);

-- Todo dia às 3h de Brasília: marca plano vencido como atrasado (o mesmo da 005)
select cron.schedule('assinaturas-atrasadas', '0 6 * * *', $$
  update public.assinaturas set status = 'atrasada'
  where status = 'ativa' and vence_em < (now() at time zone 'America/Sao_Paulo')::date
$$);

-- COPIE o valor que aparece abaixo e cole no segredo CRON_SECRET da função
-- (Supabase › Edge Functions › whatsapp-enviar › Secrets). Não mande pra ninguém.
select decrypted_secret as cron_secret from vault.decrypted_secrets where name = 'whatsapp_cron_secret';
