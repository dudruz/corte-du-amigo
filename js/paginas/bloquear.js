// @ts-check
import { sb, rpc } from '../supabase.js';
import { exigirEquipe } from '../auth.js';
import { h, montar, param } from '../ui/dom.js';
import { icone } from '../ui/icones.js';
import { mostrarErro } from '../ui/toast.js';
import { hora, hojeISO, somarDias, semanaLonga, diaMes, noFuso, dataLonga, diaDoTimestamp } from '../lib/formatar.js';
import { linkWhats, mensagens, urlDoSite } from '../lib/mensagens.js';

const app = /** @type {HTMLElement} */ (document.getElementById('app'));
const perfil = await exigirEquipe();
const ehDono = perfil.papel === 'dono';
const { data: barbeiros } = await sb.from('barbeiros').select('id, nome, apelido').eq('ativo', true).order('nome');

/** @type {'dia' | 'periodo' | 'atraso'} */ let modo = 'dia';
/** @type {string | null} null = barbearia toda */
let barbeiro = param('barbeiro') || perfil.barbeiro_id || barbeiros?.[0]?.id || null;
let data = hojeISO();
let motivo = 'Folga';
let de = '12:00';
let ate = '13:00';
let repetir = false;
let atraso = 30;
let enviando = false;

const linkSite = urlDoSite('index.html');

async function confirmar() {
  if (enviando) return;
  enviando = true; render();
  try {
    if (modo === 'atraso') {
      if (!barbeiro) throw new Error('Escolha de quem é a agenda.');
      const lista = await rpc('aplicar_atraso', { p_barbeiro_id: barbeiro, p_minutos: atraso });
      resultado(`Agenda de hoje andou ${atraso} minutos.`, lista.map((/** @type {any} */ x) => ({
        nome: x.nome, telefone: x.telefone, detalhe: `${hora(x.antes)} → ${hora(x.depois)}`,
        texto: mensagens.atraso(x.nome, atraso, hora(x.depois), linkSite),
      })));
      return;
    }
    const inicio = modo === 'dia' ? noFuso(data, '00:00') : noFuso(data, de);
    const fim = modo === 'dia' ? noFuso(somarDias(data, 1), '00:00') : noFuso(data, ate);
    // Com "repetir toda semana" a lista traz gente de outras semanas, então o dia da mensagem
    // sai do horário de cada cliente, e não do dia escolhido no formulário
    const quando = (/** @type {string} */ inicioCliente) => {
      const diaCliente = diaDoTimestamp(inicioCliente);
      const base = `na ${semanaLonga(diaCliente)} (${diaMes(diaCliente)})`;
      return modo === 'dia' ? base : `${base} das ${de} às ${ate}`;
    };
    const lista = await rpc('criar_bloqueio', {
      p_barbeiro_id: barbeiro, p_inicio: inicio, p_fim: fim,
      p_recorrente: modo === 'periodo' && repetir, p_motivo: modo === 'dia' ? motivo : (repetir ? 'Horário fixo' : null),
    });
    resultado(modo === 'dia' ? 'Agenda fechada.' : 'Horário bloqueado.', lista.map((/** @type {any} */ x) => ({
      nome: x.nome, telefone: x.telefone, detalhe: `${dataLonga(x.inicio)} · ${hora(x.inicio)}`,
      texto: mensagens.bloqueio(x.nome, quando(x.inicio), linkSite),
    })));
  } catch (e) {
    mostrarErro(e); enviando = false; render();
  }
}

/** @param {string} titulo @param {{nome: string, telefone: string, detalhe: string, texto: string}[]} afetados */
function resultado(titulo, afetados) {
  montar(app,
    h('header', { class: 'topo--escuro' },
      h('div', { class: 'topo-textos' }, h('span', { class: 'titulo' }, 'Pronto!'), h('span', { class: 'sub' }, titulo))),
    h('main', { class: 'conteudo' },
      afetados.length === 0
        ? h('p', { class: 'aviso aviso--info' }, 'Ninguém tinha horário marcado nesse período. Ninguém precisa ser avisado.')
        : h('section', { class: 'secao' },
            h('h2', { class: 'secao-titulo' }, `Avise ${afetados.length === 1 ? 'o cliente' : `os ${afetados.length} clientes`}`),
            h('p', { class: 'ajuda' }, 'Cada botão abre o WhatsApp com a mensagem pronta. É só apertar enviar.'),
            h('div', { class: 'lista' }, afetados.map((a) =>
              h('div', { class: 'linha' },
                h('div', { class: 'linha-textos' }, h('span', { class: 'linha-titulo' }, a.nome), h('span', { class: 'ajuda' }, a.detalhe)),
                h('a', { class: 'btn btn--zap btn--peq', href: linkWhats(a.telefone, a.texto), target: '_blank', rel: 'noopener',
                         onClick: (/** @type {Event} */ ev) => { /** @type {HTMLElement} */ (ev.currentTarget).textContent = 'Avisado ✓'; } }, 'Avisar'),
              ))),
            h('h3', { class: 'secao-titulo' }, 'Mensagem que vai'),
            h('div', { class: 'bolha-zap' }, afetados[0].texto),
          ),
    ),
    h('div', { class: 'rodape' }, h('a', { class: 'btn btn--escuro btn--bloco', href: 'agenda.html' }, 'Voltar pra agenda')),
  );
}

function render() {
  const escolha = (/** @type {boolean} */ ativo, /** @type {() => void} */ acao, /** @type {any} */ rotulo) =>
    h('button', { type: 'button', class: 'chip', 'aria-pressed': String(ativo), onClick: () => { acao(); render(); } }, rotulo);
  const textoBotao = modo === 'atraso' ? `Avisar atraso de ${atraso} min`
    : modo === 'dia' ? `Fechar ${semanaLonga(data)}, ${diaMes(data)}` : `Bloquear ${de}–${ate}${repetir ? ' toda semana' : ''}`;

  montar(app,
    h('header', { class: 'topo--escuro' },
      h('div', { class: 'topo-linha', style: 'justify-content:flex-start' },
        h('a', { class: 'btn-icone', href: 'agenda.html', 'aria-label': 'Voltar' }, icone('fechar')),
        h('div', { class: 'topo-textos' }, h('span', { class: 'titulo-m' }, 'Fechar agenda'), h('span', { class: 'sub' }, 'Ninguém consegue marcar no que você bloquear')),
      ),
      h('div', { class: 'segmentado', role: 'group', 'aria-label': 'Tipo de bloqueio' },
        [['dia', 'Dia inteiro'], ['periodo', 'Um período'], ['atraso', 'Vou atrasar']].map(([id, rotulo]) =>
          h('button', { type: 'button', 'aria-pressed': String(modo === id),
                        onClick: () => { modo = /** @type {any} */ (id); if (modo === 'atraso' && !barbeiro) barbeiro = perfil.barbeiro_id || barbeiros?.[0]?.id || null; render(); } }, rotulo))),
    ),
    h('main', { class: 'conteudo' },
      ehDono && h('section', { class: 'secao' },
        h('h2', { class: 'secao-titulo' }, 'De quem?'),
        h('div', { class: 'chips' },
          modo !== 'atraso' && escolha(barbeiro === null, () => { barbeiro = null; }, 'Barbearia toda'),
          barbeiros?.map((b) => escolha(barbeiro === b.id, () => { barbeiro = b.id; }, b.apelido || b.nome)),
        ),
      ),
      modo !== 'atraso' && h('section', { class: 'secao' },
        h('div', { class: 'campo' },
          h('label', { for: 'data' }, 'Dia'),
          h('input', { id: 'data', type: 'date', class: 'entrada', min: hojeISO(), value: data,
                       onChange: (/** @type {Event} */ ev) => { data = /** @type {HTMLInputElement} */ (ev.target).value || hojeISO(); render(); } })),
      ),
      modo === 'dia' && h('section', { class: 'secao' },
        h('h2', { class: 'secao-titulo' }, 'Motivo ', h('span', { class: 'ajuda' }, '(só a equipe vê)')),
        h('div', { class: 'chips' }, ['Folga', 'Feriado', 'Médico', 'Outro'].map((m) => escolha(motivo === m, () => { motivo = m; }, m))),
      ),
      modo === 'periodo' && h('section', { class: 'secao' },
        h('div', { class: 'grade g2' },
          h('div', { class: 'campo' }, h('label', { for: 'de' }, 'De'),
            h('input', { id: 'de', type: 'time', class: 'entrada', step: 900, value: de, onChange: (/** @type {Event} */ ev) => { de = /** @type {HTMLInputElement} */ (ev.target).value; render(); } })),
          h('div', { class: 'campo' }, h('label', { for: 'ate' }, 'Até'),
            h('input', { id: 'ate', type: 'time', class: 'entrada', step: 900, value: ate, onChange: (/** @type {Event} */ ev) => { ate = /** @type {HTMLInputElement} */ (ev.target).value; render(); } })),
        ),
        h('label', { class: 'check card', style: 'flex-direction:row' },
          h('input', { type: 'checkbox', checked: repetir, onChange: (/** @type {Event} */ ev) => { repetir = /** @type {HTMLInputElement} */ (ev.target).checked; render(); } }),
          h('span', { class: 'topo-textos' }, h('strong', null, 'Repetir toda semana'), h('span', { class: 'ajuda' }, `Toda ${semanaLonga(data)}, nesse horário. Bom pro almoço.`)),
        ),
      ),
      modo === 'atraso' && h('section', { class: 'secao' },
        h('h2', { class: 'secao-titulo' }, 'Quanto vai atrasar hoje?'),
        h('div', { class: 'grade g4' }, [15, 30, 45, 60].map((m) =>
          h('button', { type: 'button', class: 'botao-escolha', 'aria-pressed': String(atraso === m), onClick: () => { atraso = m; render(); } }, `${m} min`))),
        h('p', { class: 'ajuda' }, 'Os próximos horários de hoje andam pra frente. Na próxima tela aparece quem avisar.'),
      ),
      modo !== 'atraso' && h('p', { class: 'aviso aviso--alerta' }, 'Quem já estava marcado nesse período tem o horário cancelado. Na próxima tela aparece a lista pra avisar no WhatsApp.'),
    ),
    h('div', { class: 'rodape' },
      h('button', { type: 'button', class: 'btn btn--primario btn--bloco', disabled: enviando, onClick: confirmar }, enviando ? 'Salvando…' : textoBotao)),
  );
}

render();
