// Corte DÚ Amigo · função "whatsapp-enviar" (Supabase Edge Function)
// Chamada a cada 5 minutos pelo pg_cron (supabase/ativar_mensagens.sql). Pega as mensagens que
// estão na hora, manda pela API oficial do WhatsApp e marca o resultado na fila.
//
// Segredos (Supabase › Edge Functions › Secrets), nunca no repositório:
//   WHATSAPP_TOKEN            token de acesso permanente da Meta (usuário do sistema)
//   WHATSAPP_PHONE_NUMBER_ID  id do número na Meta (não é o telefone)
//   CRON_SECRET               senha que o pg_cron manda no cabeçalho x-cron-secret
//   WHATSAPP_API_VERSION      opcional, padrão v23.0
// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY o Supabase já entrega sozinho.
//
// Sem WHATSAPP_TOKEN ou WHATSAPP_PHONE_NUMBER_ID a função não manda nada: só avisa o painel
// que está aguardando a ativação.
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { montarPedido, lerResposta, type Mensagem } from './mensagem.ts';

const env = (nome: string) => Deno.env.get(nome) ?? '';
const responder = (status: number, corpo: unknown) =>
  new Response(JSON.stringify(corpo), { status, headers: { 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  const segredo = env('CRON_SECRET');
  // Sem a senha configurada, ninguém chama: a função fica fechada até a ativação
  if (!segredo) return responder(503, { erro: 'CRON_SECRET não configurado.' });
  if (req.headers.get('x-cron-secret') !== segredo) return responder(401, { erro: 'Sem permissão.' });

  const sb = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false } });
  const token = env('WHATSAPP_TOKEN');
  const numero = env('WHATSAPP_PHONE_NUMBER_ID');
  if (!token || !numero) {
    await sb.rpc('registrar_contato_whatsapp', { p_ok: false, p_erro: 'Aguardando a chave da API do WhatsApp.' });
    return responder(200, { ativo: false, enviadas: 0 });
  }

  const { data: lista, error } = await sb.rpc('pegar_mensagens', { p_limite: 20 });
  if (error) return responder(500, { erro: error.message });

  const url = `https://graph.facebook.com/${env('WHATSAPP_API_VERSION') || 'v23.0'}/${numero}/messages`;
  let enviadas = 0;
  let erroDeChave: string | null = null;

  for (const m of (lista ?? []) as Mensagem[]) {
    if (erroDeChave) {
      // Chave ruim: nem tenta o resto da rodada. Volta pra fila (conta como tentativa) e o painel mostra o erro
      await sb.rpc('registrar_envio', { p_id: m.id, p_ok: false, p_erro: erroDeChave });
      continue;
    }
    let resultado;
    try {
      const resp = await fetch(url, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(montarPedido(m)),
      });
      resultado = lerResposta(resp.status, await resp.json().catch(() => null));
    } catch (e) {
      resultado = { ok: false, waId: null, erro: `Sem conexão com a Meta: ${(e as Error).message}`, chaveRuim: false };
    }
    if (resultado.chaveRuim) erroDeChave = resultado.erro;
    if (resultado.ok) enviadas++;
    await sb.rpc('registrar_envio', { p_id: m.id, p_ok: resultado.ok, p_wa_id: resultado.waId, p_erro: resultado.erro });
  }

  await sb.rpc('registrar_contato_whatsapp', { p_ok: !erroDeChave, p_erro: erroDeChave });
  return responder(200, { ativo: true, enviadas, total: (lista ?? []).length });
});
