// @ts-check
import { h } from './dom.js';

/** @param {string} texto @param {'ok' | 'erro' | 'neutro'} [tipo] */
export function toast(texto, tipo = 'neutro') {
  let area = document.querySelector('.toast-area');
  if (!area) {
    area = h('div', { class: 'toast-area', role: 'status', 'aria-live': 'polite' });
    document.body.append(area);
  }
  const t = h('div', { class: `toast toast--${tipo}` }, texto);
  area.append(t);
  setTimeout(() => t.remove(), tipo === 'erro' ? 6000 : 3500);
}

/** @param {unknown} e */
export const mostrarErro = (e) =>
  toast(e instanceof Error && e.message ? e.message : 'Algo deu errado. Confere a internet e tenta de novo.', 'erro');
