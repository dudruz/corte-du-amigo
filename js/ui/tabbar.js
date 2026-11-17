// @ts-check
import { h } from './dom.js';
import { icone } from './icones.js';
import { sair } from '../auth.js';

/**
 * Barra de navegação da equipe. O dono vê Início, Agenda, Clientes, Caixa e Planos
 * (Ajustes e Sair ficam na engrenagem do Início). O barbeiro vê só Agenda e Sair.
 * @param {'inicio' | 'agenda' | 'clientes' | 'caixa' | 'planos' | 'config'} ativo
 * @param {import('../auth.js').Perfil} perfil
 */
export function tabbar(ativo, perfil) {
  const item = (/** @type {string} */ id, /** @type {string} */ href, /** @type {any} */ ic, /** @type {string} */ rotulo) =>
    h('a', { href, 'aria-current': ativo === id ? 'page' : null }, icone(ic, 22), rotulo);
  if (perfil.papel !== 'dono') {
    return h('nav', { class: 'tabbar', 'aria-label': 'Menu' },
      item('agenda', 'agenda.html', 'agenda', 'Agenda'),
      h('button', { type: 'button', onClick: sair }, icone('sair', 22), 'Sair'),
    );
  }
  return h('nav', { class: 'tabbar', 'aria-label': 'Menu' },
    item('inicio', 'index.html', 'inicio', 'Início'),
    item('agenda', 'agenda.html', 'agenda', 'Agenda'),
    item('clientes', 'clientes.html', 'usuarios', 'Clientes'),
    item('caixa', 'caixa.html', 'caixa', 'Caixa'),
    item('planos', 'planos.html', 'planos', 'Planos'),
  );
}
