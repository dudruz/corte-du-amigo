// @ts-check
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js';

export const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

/** Erro já com mensagem em português. `rede` é true quando a falha foi de conexão. */
export class ErroApp extends Error {
  /** @param {string} mensagem @param {{ rede?: boolean, codigo?: string }} [extra] */
  constructor(mensagem, { rede = false, codigo = '' } = {}) {
    super(mensagem);
    this.name = 'ErroApp';
    this.rede = rede;
    this.codigo = codigo;
  }
}

const SEM_REDE = /failed to fetch|networkerror|load failed|network request failed|fetch failed/i;

/**
 * Converte um erro do supabase-js em mensagem pra mostrar na tela.
 * As mensagens escritas nas funções do banco (raise exception) já vêm em português e passam direto;
 * erro de rede e erro interno do Postgres viram um texto amigável (o original vai pro console).
 * @param {{ message?: string, code?: string } | null | undefined} error
 * @returns {ErroApp}
 */
export function traduzirErro(error) {
  const mensagem = String(error?.message || '');
  const codigo = String(error?.code || '');
  if (SEM_REDE.test(mensagem) || (typeof navigator !== 'undefined' && navigator.onLine === false)) {
    return new ErroApp('Sem internet agora. Confere a conexão e tenta de novo.', { rede: true, codigo });
  }
  // P0001 = raise exception das nossas funções; 42501 = sem permissão (também levantado por elas)
  if (codigo === 'P0001' && mensagem) return new ErroApp(mensagem, { codigo });
  if (codigo === '42501') {
    // As nossas funções mandam o texto em português; o Postgres e o RLS mandam em inglês
    const doPostgres = !mensagem || /permission denied|row-level security/i.test(mensagem);
    return new ErroApp(doPostgres ? 'Sem permissão pra fazer isso.' : mensagem, { codigo });
  }
  // Sessão vencida ou token recusado pela API
  if (codigo === 'PGRST301' || /jwt/i.test(mensagem)) {
    return new ErroApp('Seu login venceu. Recarrega a página e entra de novo.', { codigo });
  }
  if (codigo === '23P01') return new ErroApp('Esse horário bate com outro que já está marcado.', { codigo });
  if (codigo === '22P02') return new ErroApp('Algum dado veio em formato inválido. Confere e tenta de novo.', { codigo });
  console.error('Erro do banco:', error);
  return new ErroApp('Deu um erro do nosso lado. Tenta de novo daqui a pouco.', { codigo });
}

/**
 * Chama uma função do banco e lança o erro já traduzido (ver traduzirErro).
 * @param {string} nome
 * @param {Record<string, any>} [args]
 */
export async function rpc(nome, args) {
  let resposta;
  try {
    resposta = await sb.rpc(nome, args);
  } catch (e) {
    throw traduzirErro(/** @type {any} */ (e));
  }
  if (resposta.error) throw traduzirErro(resposta.error);
  return resposta.data;
}
