// @ts-check
import { sb, traduzirErro } from '../supabase.js';
import { h, montar, poste, param } from '../ui/dom.js';
import { mostrarErro } from '../ui/toast.js';

const app = /** @type {HTMLElement} */ (document.getElementById('app'));

// Se não der pra conferir a sessão (sem internet, por exemplo), o formulário aparece do mesmo jeito
try {
  const { data: { session } } = await sb.auth.getSession();
  if (session) location.replace('index.html');
} catch (e) {
  console.error('Não deu pra conferir a sessão:', e);
}

/**
 * Só credencial errada vira "não conferem". Internet caída ou servidor fora do ar têm
 * mensagem própria, pra pessoa não ficar trocando uma senha que está certa.
 * @param {any} error
 */
function erroDeLogin(error) {
  if (error?.code === 'invalid_credentials' || error?.status === 400) return new Error('E-mail ou senha não conferem.');
  const erro = traduzirErro(error);
  return erro.rede ? erro : new Error('Não deu pra entrar agora. Tenta de novo daqui a pouco.');
}

async function entrar(/** @type {SubmitEvent} */ ev) {
  ev.preventDefault();
  const fd = new FormData(/** @type {HTMLFormElement} */ (ev.target));
  const botao = /** @type {HTMLButtonElement} */ (app.querySelector('button[type=submit]'));
  botao.disabled = true; botao.textContent = 'Entrando…';
  /** @type {any} */ let error;
  try {
    ({ error } = await sb.auth.signInWithPassword({
      email: String(fd.get('email') || '').trim(),
      password: String(fd.get('senha') || ''),
    }));
  } catch (e) {
    error = e;
  }
  if (error) {
    mostrarErro(erroDeLogin(error));
    botao.disabled = false; botao.textContent = 'Entrar';
    return;
  }
  location.replace('index.html');
}

montar(app,
  poste(),
  h('main', { class: 'conteudo tela-escura', style: 'padding:64px 24px 24px;gap:32px' },
    h('div', { class: 'topo-textos', style: 'gap:10px' },
      h('span', { class: 'sub', style: 'color:var(--muted-escuro)' }, 'Área da equipe'),
      h('h1', { class: 'titulo-xl', style: 'font-size:54px;line-height:.98' }, 'Corte', h('br'), 'DÚ Amigo'),
    ),
    param('erro') === 'perfil' && h('p', { class: 'aviso aviso--erro' }, 'Esse login não tem perfil ativo na equipe. Fala com o dono.'),
    h('form', { onSubmit: entrar, class: 'secao', style: 'gap:16px' },
      h('div', { class: 'campo' },
        h('label', { for: 'email' }, 'E-mail'),
        h('input', { id: 'email', name: 'email', type: 'email', class: 'entrada', required: true, autocomplete: 'username' })),
      h('div', { class: 'campo' },
        h('label', { for: 'senha' }, 'Senha'),
        h('input', { id: 'senha', name: 'senha', type: 'password', class: 'entrada', required: true, autocomplete: 'current-password' })),
      h('button', { type: 'submit', class: 'btn btn--primario btn--bloco' }, 'Entrar'),
    ),
    h('p', { class: 'ajuda', style: 'text-align:center;margin-top:auto' },
      'Barbeiro vê a própria agenda. O dono vê tudo: agenda, caixa e ajustes.'),
  ),
);
document.body.style.background = 'var(--tinta)';
app.style.background = 'var(--tinta)';
app.style.color = 'var(--sobre-escuro)';
