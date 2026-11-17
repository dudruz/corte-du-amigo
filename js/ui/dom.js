// @ts-check
// Monta elementos sem innerHTML. Texto sempre entra como nó de texto, então dado de
// cliente nunca vira HTML (proteção contra injeção de código).

/**
 * @param {string} tag
 * @param {Record<string, any> | null} [attrs]
 * @param {...any} filhos
 * @returns {HTMLElement}
 */
export function h(tag, attrs, ...filhos) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v == null || v === false) continue;
    if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2).toLowerCase(), v);
    else if (k === 'class') el.className = v;
    else if (k === 'value') /** @type {any} */ (el).value = v;
    else if (k === 'checked') /** @type {any} */ (el).checked = !!v;
    else el.setAttribute(k, v === true ? '' : String(v));
  }
  anexar(el, filhos);
  return el;
}

/** @param {Element} el @param {any[]} filhos */
function anexar(el, filhos) {
  for (const f of filhos.flat(Infinity)) {
    if (f == null || f === false) continue;
    el.append(f instanceof Node ? f : document.createTextNode(String(f)));
  }
}

/** Troca todo o conteúdo de um elemento. @param {Element} el @param {...any} filhos */
export function montar(el, ...filhos) {
  el.replaceChildren();
  anexar(el, filhos);
}

/** Lê um parâmetro da URL. @param {string} nome */
export const param = (nome) => new URLSearchParams(location.search).get(nome);

export const carregando = (texto = 'Carregando…') => h('div', { class: 'carregando', role: 'status' }, texto);

/** Faixa do poste de barbeiro no topo. */
export const poste = () => h('div', { class: 'poste', 'aria-hidden': 'true' });

/**
 * Tela cheia de erro, no lugar do "Carregando…", com botão pra tentar de novo.
 * Usar quando a carga inicial de uma página falha (toast sozinho deixa a tela presa).
 * @param {Element} el onde montar (normalmente #app)
 * @param {unknown} erro
 * @param {(() => void) | null} [aoTentar] sem isso, o botão recarrega a página
 */
export function telaErro(el, erro, aoTentar) {
  const texto = erro instanceof Error && erro.message
    ? erro.message
    : 'Não deu pra carregar agora. Confere a internet e tenta de novo.';
  montar(el,
    poste(),
    h('div', { class: 'vazio', role: 'alert' },
      h('p', null, texto),
      h('button', { type: 'button', class: 'btn btn--contorno', onClick: aoTentar || (() => location.reload()) }, 'Tentar de novo'),
    ),
  );
}
