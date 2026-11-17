// @ts-check
import { rpc } from '../supabase.js';
import { h, montar, poste, carregando, param, telaErro } from '../ui/dom.js';
import { icone } from '../ui/icones.js';
import { hora, dataLonga } from '../lib/formatar.js';
import { linkWhats, mensagens, urlDoSite } from '../lib/mensagens.js';
import { tokenValido } from '../lib/armazenamento.js';
import { NOME_BARBEARIA } from '../config.js';

const app = /** @type {HTMLElement} */ (document.getElementById('app'));
const token = param('t');

/** Gera e baixa um arquivo .ics pra salvar na agenda do celular. @param {any} a @param {string} endereco */
function salvarNaAgenda(a, endereco) {
  const fmt = (/** @type {string} */ iso) => new Date(iso).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
  const ics = [
    'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Corte DU Amigo//PT', 'BEGIN:VEVENT',
    `UID:${a.token}@corteduamigo`, `DTSTAMP:${fmt(new Date().toISOString())}`,
    `DTSTART:${fmt(a.inicio)}`, `DTEND:${fmt(a.fim)}`,
    `SUMMARY:${a.servicos.join(' + ')} · ${NOME_BARBEARIA}`,
    `LOCATION:${String(endereco || '').replace(/[,;]/g, ' ')}`,
    'BEGIN:VALARM', 'TRIGGER:-PT1H', 'ACTION:DISPLAY', 'DESCRIPTION:Horário na barbearia', 'END:VALARM',
    'END:VEVENT', 'END:VCALENDAR',
  ].join('\r\n');
  const url = URL.createObjectURL(new Blob([ics], { type: 'text/calendar' }));
  const link = h('a', { href: url, download: 'horario-corte-du-amigo.ics' });
  document.body.append(link); link.click(); link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
}

function linkInvalido() {
  montar(app, poste(),
    h('main', { class: 'conteudo' },
      h('h1', { class: 'titulo' }, 'Esse link não vale mais'),
      h('div', { class: 'vazio' },
        'O link pode ter vindo incompleto ou esse horário não existe mais. Bora marcar outro?',
        h('a', { class: 'btn btn--primario', href: 'index.html' }, 'Marcar um horário')),
    ));
}

/** Título e explicação pra quando o horário do link não está mais de pé. */
const FORA_DE_PE = /** @type {Record<string, [string, string]>} */ ({
  cancelado: ['Horário cancelado', 'Esse horário foi cancelado. Quando quiser, é só marcar outro.'],
  finalizado: ['Corte feito!', 'Esse horário já foi atendido. Valeu pela visita!'],
  faltou: ['Esse horário passou', 'Não rolou dessa vez. Bora marcar outro?'],
  em_atendimento: ['Tá na sua vez!', 'Esse horário já está em atendimento.'],
});

/** @param {any} info */
function telaForaDePe(info) {
  const a = info.atual;
  const [titulo, texto] = FORA_DE_PE[a.status] || ['Esse horário não vale mais', 'Bora marcar outro?'];
  montar(app,
    poste(),
    h('main', { class: 'conteudo', style: 'padding-top:40px' },
      h('div', { class: 'centro' },
        h('h1', { class: 'titulo-xl', style: 'font-size:44px' }, titulo),
        h('p', { class: 'sub', style: 'font-size:15px' }, texto),
      ),
      h('div', { class: 'card' },
        h('div', { class: 'topo-textos' },
          h('span', { class: 'titulo-m' }, `${dataLonga(a.inicio)} · ${hora(a.inicio)}`),
          h('span', { class: 'sub' }, `${a.servicos.join(' + ')} com ${a.barbeiro}`),
        ),
      ),
    ),
    h('div', { class: 'rodape' },
      h('a', { class: 'btn btn--primario btn--bloco', href: 'index.html' }, 'Marcar outro horário'),
      h('a', { class: 'btn btn--escuro btn--bloco', href: `minha-area.html?t=${token}` }, 'Ver meus horários'),
    ),
  );
}

async function iniciar() {
  if (!token) { location.replace('index.html'); return; }
  if (!tokenValido(token)) { linkInvalido(); return; }
  montar(app, poste(), carregando());
  const [info, dados] = await Promise.all([
    rpc('agendamento_por_token', { p_token: token }),
    rpc('dados_publicos'),
  ]);
  if (!info) { linkInvalido(); return; }
  const a = info.atual;
  if (a.status !== 'marcado') { telaForaDePe(info); return; }
  const linkArea = urlDoSite(`minha-area.html?t=${token}`);
  const mapa = `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(dados.endereco || NOME_BARBEARIA)}`;

  montar(app,
    poste(),
    h('main', { class: 'conteudo', style: 'padding-top:40px' },
      h('div', { class: 'centro' },
        h('span', { class: 'selo-ok' }, icone('check', 36, 2.6)),
        h('h1', { class: 'titulo-xl', style: 'font-size:44px' }, param('remarcado') ? 'Remarcado!' : 'Tá marcado!'),
        h('p', { class: 'sub', style: 'font-size:15px' }, `Te esperamos, ${info.cliente.nome}.`),
      ),
      h('div', { class: 'card' },
        h('div', { class: 'topo-textos' },
          h('span', { class: 'titulo-m' }, `${dataLonga(a.inicio)} · ${hora(a.inicio)}`),
          h('span', { class: 'sub' }, `${a.servicos.join(' + ')} com ${a.barbeiro}`),
        ),
        h('div', { class: 'divisor' }),
        dados.endereco && h('span', null, dados.endereco),
        h('div', { class: 'grade g2' },
          h('button', { type: 'button', class: 'btn btn--claro btn--peq', onClick: () => salvarNaAgenda(a, dados.endereco) }, 'Salvar na agenda'),
          h('a', { class: 'btn btn--claro btn--peq', href: mapa, target: '_blank', rel: 'noopener' }, 'Como chegar'),
        ),
      ),
      h('div', { class: 'card card--azul' },
        h('strong', null, 'Guarda o link do seu horário'),
        h('span', { class: 'sub' }, 'Manda pro seu próprio WhatsApp. Por ele você remarca ou cancela quando quiser.'),
        h('a', { class: 'btn btn--peq', href: linkWhats(info.cliente.telefone, mensagens.minhaArea(linkArea)), target: '_blank', rel: 'noopener', style: 'align-self:flex-start;color:var(--azul)' },
          icone('zap', 18), 'Mandar pro meu WhatsApp'),
      ),
    ),
    h('div', { class: 'rodape' },
      h('a', { class: 'btn btn--escuro btn--bloco', href: `minha-area.html?t=${token}` }, 'Ver meus horários'),
    ),
  );
}

function abrir() {
  iniciar().catch((e) => telaErro(app, e, abrir));
}

abrir();
