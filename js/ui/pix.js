// @ts-check
import { h } from './dom.js';
import { icone } from './icones.js';
import { toast } from './toast.js';
import { codigoPix } from '../lib/pix.js';
import { dinheiro } from '../lib/formatar.js';

/** @typedef {{ chave: string, nome: string, cidade: string }} ConfigPix */

/**
 * Código Pix pronto pra cobrar um valor, ou null se a barbearia ainda não cadastrou a chave.
 * @param {ConfigPix | null | undefined} pix @param {number} valorCentavos
 */
export const codigoDoValor = (pix, valorCentavos) =>
  pix?.chave ? codigoPix({ chave: pix.chave, nome: pix.nome, cidade: pix.cidade, valorCentavos }) : null;

/** Copia um texto; em navegador antigo, cai na seleção manual. @param {string} texto @param {HTMLTextAreaElement} campo */
async function copiar(texto, campo) {
  try {
    await navigator.clipboard.writeText(texto);
  } catch {
    campo.select();
    // execCommand é o caminho que sobra em navegador sem a API de área de transferência
    if (!document.execCommand('copy')) throw new Error('sem cópia');
  }
}

/**
 * Bloco com o Pix copia e cola do valor e o botão de copiar. Sem chave cadastrada,
 * mostra onde cadastrar.
 * @param {ConfigPix | null | undefined} pix @param {number} valorCentavos
 */
export function blocoPix(pix, valorCentavos) {
  const codigo = codigoDoValor(pix, valorCentavos);
  if (!codigo) {
    return h('p', { class: 'aviso' }, 'Pix sem taxa. Pra mostrar o copia e cola aqui, o dono cadastra a chave Pix em Ajustes › Recebimento por Pix.');
  }
  const campo = /** @type {HTMLTextAreaElement} */ (h('textarea', { class: 'codigo-pix', readonly: true, rows: 3, 'aria-label': `Pix copia e cola de ${dinheiro(valorCentavos)}`, value: codigo }));
  return h('div', { class: 'card', style: 'gap:10px' },
    h('div', { class: 'secao-cabeca' },
      h('strong', null, `Pix de ${dinheiro(valorCentavos)}`),
      h('span', { class: 'ajuda' }, 'sem taxa')),
    campo,
    h('button', { type: 'button', class: 'btn btn--claro btn--peq', onClick: async () => {
        try { await copiar(codigo, campo); toast('Código Pix copiado. Manda pro cliente colar no app do banco.', 'ok'); }
        catch { toast('Não deu pra copiar sozinho. Segura o dedo no código e copia.', 'erro'); }
      } }, icone('copiar', 18), 'Copiar código Pix'),
    h('p', { class: 'ajuda' }, 'Confere no seu app se o Pix caiu antes de confirmar.'),
  );
}
