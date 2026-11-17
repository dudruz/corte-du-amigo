// Corte DÚ Amigo · montagem do pedido pra API do WhatsApp (Meta Cloud API).
// Sem nada do Supabase aqui, pra dar pra testar sozinho.

export type Mensagem = {
  id: string;
  telefone: string;      // só dígitos, com 55: 5531999998888
  modelo: string;        // nome do modelo aprovado na Meta
  parametros: unknown[]; // textos do {{1}}, {{2}}…
};

/** Corpo do POST /{phone-number-id}/messages pra um modelo (template) em português. */
export function montarPedido(m: Mensagem, idioma = 'pt_BR') {
  const parametros = (Array.isArray(m.parametros) ? m.parametros : []).map((p) => ({
    type: 'text',
    // A Meta recusa parâmetro vazio, com quebra de linha ou com mais de 4 espaços seguidos
    text: String(p ?? '').replace(/\s+/g, ' ').trim() || '-',
  }));
  return {
    messaging_product: 'whatsapp',
    to: String(m.telefone).replace(/\D/g, ''),
    type: 'template',
    template: {
      name: m.modelo,
      language: { code: idioma },
      components: parametros.length ? [{ type: 'body', parameters: parametros }] : [],
    },
  };
}

/**
 * Lê a resposta da Meta. `chaveRuim` = token inválido ou vencido: aí nem adianta continuar a rodada.
 * Códigos: 190 = token inválido; 10 e 200 = sem permissão.
 */
export function lerResposta(status: number, corpo: any): { ok: boolean; waId: string | null; erro: string | null; chaveRuim: boolean } {
  if (status >= 200 && status < 300 && corpo?.messages?.[0]?.id) {
    return { ok: true, waId: String(corpo.messages[0].id), erro: null, chaveRuim: false };
  }
  const e = corpo?.error ?? {};
  const codigo = Number(e.code);
  const detalhe = e.error_data?.details ? ` (${e.error_data.details})` : '';
  return {
    ok: false,
    waId: null,
    erro: `${e.message ?? `HTTP ${status}`}${detalhe}${codigo ? ` [${codigo}]` : ''}`,
    chaveRuim: [190, 10, 200].includes(codigo) || status === 401,
  };
}
