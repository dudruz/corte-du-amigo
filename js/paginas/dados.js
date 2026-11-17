// @ts-check
import { rpc } from '../supabase.js';
import { h, montar, poste, carregando, telaErro } from '../ui/dom.js';
import { icone } from '../ui/icones.js';
import { mostrarErro, toast } from '../ui/toast.js';
import { hora, dataLonga, dinheiro } from '../lib/formatar.js';
import { rascunho, guardarToken, guardarCliente, clienteSalvo } from '../lib/armazenamento.js';

const app = /** @type {HTMLElement} */ (document.getElementById('app'));
const r = rascunho.ler();

/** @type {any} */ let dados;
let enviando = false;

/**
 * Mesma regra do banco (normalizar_telefone), pra avisar antes de enviar:
 * só dígitos, sem zero na frente, DDD + número (com ou sem o 55).
 * @param {string} texto
 */
function whatsappValido(texto) {
  let d = texto.replace(/\D/g, '').replace(/^0+/, '');
  if (d.length === 10 || d.length === 11) d = '55' + d;
  return /^55\d{10,11}$/.test(d);
}

async function enviar(/** @type {SubmitEvent} */ ev) {
  ev.preventDefault();
  if (enviando) return;
  const form = /** @type {HTMLFormElement} */ (ev.target);
  const fd = new FormData(form);
  const nome = String(fd.get('nome') || '').trim();
  const telefone = String(fd.get('telefone') || '');
  if (!whatsappValido(telefone)) {
    toast('Confere o WhatsApp: coloca o DDD + número, tipo (31) 9 0000-0000.', 'erro');
    /** @type {HTMLInputElement} */ (form.elements.namedItem('telefone')).focus();
    return;
  }
  enviando = true;
  const botao = /** @type {HTMLButtonElement} */ (form.querySelector('button[type=submit]'));
  botao.disabled = true; botao.textContent = 'Marcando…';
  try {
    const token = await rpc('criar_agendamento', {
      p_servico_ids: r?.servicos, p_barbeiro_id: r?.barbeiro_id ?? null, p_inicio: r?.inicio,
      p_nome: nome, p_telefone: telefone, p_aceita_lembrete: fd.get('lembrete') === 'on',
    });
    guardarToken(token);
    guardarCliente({ nome, telefone });
    rascunho.limpar();
    location.href = `agendado.html?t=${token}`;
  } catch (e) {
    mostrarErro(e);
    enviando = false; botao.disabled = false; botao.textContent = 'Confirmar agendamento';
    if (e instanceof Error && /pego|disponível|não existe na agenda|antecedência/.test(e.message)) {
      setTimeout(() => { location.href = 'horario.html'; }, 2200);
    }
  }
}

function render() {
  const escolhidos = dados.servicos.filter((/** @type {any} */ s) => r?.servicos.includes(s.id));
  const total = escolhidos.reduce((/** @type {number} */ t, /** @type {any} */ s) => t + s.preco_centavos, 0);
  const barbeiro = dados.barbeiros.find((/** @type {any} */ b) => b.id === r?.barbeiro_id)?.nome;
  const salvo = clienteSalvo();

  montar(app,
    poste(),
    h('header', { class: 'topo', style: 'justify-content:flex-start' },
      h('a', { class: 'btn-icone', href: 'horario.html', 'aria-label': 'Voltar' }, icone('voltar')),
      h('div', { class: 'topo-textos' }, h('span', { class: 'sub' }, 'Passo 3 de 3'), h('strong', null, 'Quase lá')),
    ),
    h('form', { onSubmit: enviar, style: 'display:contents' },
      h('main', { class: 'conteudo' },
        h('div', { class: 'card' },
          h('div', { class: 'secao-cabeca', style: 'align-items:flex-start' },
            h('div', { class: 'topo-textos' },
              h('span', { class: 'titulo-m' }, `${dataLonga(r?.inicio ?? '')} · ${hora(r?.inicio ?? '')}`),
              h('span', { class: 'sub' }, `${escolhidos.map((/** @type {any} */ s) => s.nome).join(' + ')}${barbeiro ? ` com ${barbeiro}` : ''}`),
            ),
            h('strong', null, dinheiro(total)),
          ),
          h('div', { class: 'divisor' }),
          h('span', { class: 'sub' }, 'Você paga na barbearia: Pix, dinheiro ou cartão.'),
        ),
        h('section', { class: 'secao' },
          h('h1', { class: 'secao-titulo', style: 'font-size:17px' }, 'Como a gente te chama?'),
          h('div', { class: 'campo' },
            h('label', { for: 'nome' }, 'Seu nome'),
            h('input', { id: 'nome', name: 'nome', class: 'entrada', required: true, minlength: 2, maxlength: 80,
                         autocomplete: 'given-name', placeholder: 'Ex.: Gabriel', value: salvo?.nome ?? '' }),
          ),
          h('div', { class: 'campo' },
            h('label', { for: 'telefone' }, 'WhatsApp'),
            h('input', { id: 'telefone', name: 'telefone', class: 'entrada', type: 'tel', required: true,
                         inputmode: 'tel', autocomplete: 'tel-national', placeholder: '(31) 9 0000-0000', value: salvo?.telefone ?? '' }),
            h('span', { class: 'ajuda' }, 'Com DDD. A barbearia usa pra falar com você sobre o horário.'),
          ),
          h('label', { class: 'check' },
            h('input', { type: 'checkbox', name: 'lembrete', checked: true }),
            h('span', null, 'Quero receber lembrete do horário no WhatsApp'),
          ),
        ),
        h('p', { class: 'aviso' }, `Imprevisto? Dá pra cancelar ou remarcar até ${dados.cancelamento_horas} horas antes.`),
      ),
      h('div', { class: 'rodape' },
        h('button', { type: 'submit', class: 'btn btn--primario btn--bloco' }, 'Confirmar agendamento'),
      ),
    ),
  );
}

async function iniciar() {
  if (!r || !r.inicio || !r.servicos?.length) { location.replace('index.html'); return; }
  try {
    montar(app, poste(), carregando());
    dados = await rpc('dados_publicos');
    render();
  } catch (e) {
    telaErro(app, e, iniciar);
  }
}

// Voltando da tela de confirmado, o navegador pode devolver esta página da memória com o
// formulário ainda preenchido. Sem rascunho o horário já foi marcado: não deixa marcar de novo.
window.addEventListener('pageshow', (ev) => {
  if (ev.persisted && !rascunho.ler()?.inicio) location.replace('index.html');
});

iniciar();
