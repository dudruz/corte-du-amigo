// @ts-check
// Rascunho do agendamento entre as páginas (sessionStorage) e dados lembrados no aparelho (localStorage).

const CHAVE_RASCUNHO = 'rascunho_agendamento';
const CHAVE_TOKENS = 'meus_agendamentos';
const CHAVE_CLIENTE = 'meus_dados';

/**
 * @typedef {{ servicos: string[], barbeiro_id?: string | null, inicio?: string, remarcar?: string | null }} Rascunho
 */

function ler(storage, chave, padrao) {
  try { return JSON.parse(storage.getItem(chave) || 'null') ?? padrao; } catch { return padrao; }
}
function gravar(storage, chave, valor) {
  try { storage.setItem(chave, JSON.stringify(valor)); } catch { /* modo privado: segue sem salvar */ }
}

export const rascunho = {
  /** @returns {Rascunho | null} */
  ler: () => ler(sessionStorage, CHAVE_RASCUNHO, null),
  /** @param {Rascunho} r */
  gravar: (r) => gravar(sessionStorage, CHAVE_RASCUNHO, r),
  limpar: () => { try { sessionStorage.removeItem(CHAVE_RASCUNHO); } catch { /* ignora */ } },
};

/** @param {string} token */
export function guardarToken(token) {
  const lista = ler(localStorage, CHAVE_TOKENS, []).filter((/** @type {string} */ t) => t !== token);
  gravar(localStorage, CHAVE_TOKENS, [token, ...lista].slice(0, 10));
}
/** @returns {string | null} */
export const ultimoToken = () => meusTokens()[0] || null;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** Diz se o texto tem formato de token (uuid). @param {unknown} t */
export const tokenValido = (t) => typeof t === 'string' && UUID.test(t);

/**
 * Tokens dos agendamentos feitos ou abertos neste aparelho, do mais recente pro mais antigo.
 * É por eles que a Minha área lista os horários: o banco só devolve o agendamento de quem tem o token.
 * @returns {string[]}
 */
export function meusTokens() {
  const lista = ler(localStorage, CHAVE_TOKENS, []);
  return Array.isArray(lista) ? lista.filter(tokenValido) : [];
}

/** @param {{ nome: string, telefone: string }} dados */
export const guardarCliente = (dados) => gravar(localStorage, CHAVE_CLIENTE, dados);
/** @returns {{ nome: string, telefone: string } | null} */
export const clienteSalvo = () => ler(localStorage, CHAVE_CLIENTE, null);
