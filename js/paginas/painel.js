// @ts-check
import { rpc } from '../supabase.js';
import { exigirEquipe } from '../auth.js';
import { h, montar, carregando, telaErro } from '../ui/dom.js';
import { icone } from '../ui/icones.js';
import { tabbar } from '../ui/tabbar.js';
import { dinheiro, hojeISO, semanaCurta, plural } from '../lib/formatar.js';
import { FUSO } from '../config.js';

const app = /** @type {HTMLElement} */ (document.getElementById('app'));
const perfil = await exigirEquipe({ somenteDono: true });

const fmtMes = new Intl.DateTimeFormat('pt-BR', { month: 'long', year: 'numeric', timeZone: 'UTC' });
const fmtHora = new Intl.DateTimeFormat('pt-BR', { hour: 'numeric', hourCycle: 'h23', timeZone: FUSO });

/** 'AAAA-MM-01' dos últimos 12 meses, do atual pro mais antigo. */
function ultimosMeses() {
  const [ano, mes] = hojeISO().split('-').map(Number);
  return Array.from({ length: 12 }, (_, i) => {
    const d = new Date(Date.UTC(ano, mes - 1 - i, 1));
    return d.toISOString().slice(0, 10);
  });
}
const MESES = ultimosMeses();
const nomeMes = (/** @type {string} */ iso) => {
  const t = fmtMes.format(new Date(`${iso}T12:00:00Z`));
  return t.charAt(0).toUpperCase() + t.slice(1);
};

let mes = MESES[0];
/** @type {any} */ let p = null;
let pedido = 0;

function saudacao() {
  const hora = Number(fmtHora.format(new Date()));
  const primeiro = perfil.nome.split(' ')[0];
  return `${hora < 12 ? 'Bom dia' : hora < 18 ? 'Boa tarde' : 'Boa noite'}, ${primeiro}`;
}

/** Valor curto pro gráfico: 'R$ 310' ou 'R$ 1,2 mil'. @param {number} c */
const curto = (c) => c >= 100000 ? `R$ ${(c / 100000).toFixed(1).replace('.', ',')} mil` : `R$ ${Math.round(c / 100)}`;

function graficoSemana() {
  const max = Math.max(1, ...p.semana.map((/** @type {any} */ d) => d.valor));
  const descricao = p.semana.map((/** @type {any} */ d) => `${semanaCurta(d.dia)} ${d.futuro ? 'ainda não chegou' : dinheiro(d.valor)}`).join(', ');
  return h('section', { class: 'card', style: 'gap:12px' },
    h('div', { class: 'secao-cabeca' }, h('h2', { class: 'secao-titulo' }, 'Esta semana'), h('span', { class: 'ajuda' }, 'faturamento por dia')),
    p.semana.length === 0 ? h('p', { class: 'ajuda' }, 'Sem dias de trabalho cadastrados.')
      : h('div', { class: 'barras', role: 'img', 'aria-label': `Faturamento por dia: ${descricao}` },
          p.semana.map((/** @type {any} */ d) => h('div', { class: `barra-col${d.hoje ? ' barra-col--hoje' : ''}${d.futuro ? ' barra-col--futuro' : ''}` },
            h('span', { class: 'barra-valor' }, d.futuro || !d.valor ? '—' : curto(d.valor)),
            h('i', { style: `height:${Math.max(4, Math.round((d.valor / max) * 90))}px` }),
            h('span', { class: 'barra-dia' }, semanaCurta(d.dia))))),
  );
}

function comoPagaram() {
  const total = p.formas.reduce((/** @type {number} */ t, /** @type {any} */ f) => t + f.bruto, 0);
  return h('section', { class: 'card', style: 'gap:10px' },
    h('h2', { class: 'secao-titulo' }, 'Como pagaram'),
    p.formas.length === 0 ? h('p', { class: 'ajuda' }, 'Nada recebido nesse mês ainda.')
      : p.formas.map((/** @type {any} */ f) => h('div', { class: 'secao', style: 'gap:5px' },
          h('div', { class: 'secao-cabeca' },
            h('span', { class: 'linha-titulo' }, f.nome),
            h('span', { class: 'ajuda' }, f.bruto !== f.liquido ? `${dinheiro(f.bruto)} bruto` : dinheiro(f.bruto))),
          h('div', { class: 'barra' }, h('span', { style: `width:${Math.round((f.bruto / Math.max(total, 1)) * 100)}%` })))),
    p.pelo_plano > 0 && h('p', { class: 'ajuda' }, `${plural(p.pelo_plano, 'atendimento', 'atendimentos')} pelo plano (o dinheiro entrou quando o plano foi pago).`),
  );
}

function comissoes() {
  const lista = p.comissoes.filter((/** @type {any} */ c) => c.atendimentos > 0 || c.tipo);
  if (lista.length === 0) return null;
  return h('section', { class: 'secao' },
    h('h2', { class: 'secao-titulo' }, 'Por barbeiro'),
    h('div', { class: 'lista' }, lista.map((/** @type {any} */ c) => h('div', { class: 'linha' },
      h('div', { class: 'linha-textos' },
        h('span', { class: 'linha-titulo' }, c.barbeiro),
        h('span', { class: 'ajuda' }, `${plural(c.atendimentos, 'atendimento', 'atendimentos')} · ${dinheiro(c.base_centavos)} em serviços`
          + (c.gorjetas_centavos ? ` · ${dinheiro(c.gorjetas_centavos)} de gorjeta` : ''))),
      h('div', { class: 'linha-textos', style: 'flex:0 0 auto;text-align:right' },
        h('span', { class: 'linha-valor' }, c.comissao_centavos == null ? '—' : dinheiro(c.comissao_centavos)),
        h('span', { class: 'ajuda' }, c.tipo === 'percentual' ? `comissão ${c.valor}%` : c.tipo === 'fixo_por_corte' ? `${dinheiro(c.valor)} por corte` : 'sem comissão'))))),
    h('p', { class: 'ajuda' }, 'Comissão sobre o valor dos serviços, com desconto. Gorjeta é do barbeiro e fica à parte. A comissão de cada um se ajusta em Ajustes › Equipe.'),
  );
}

function alertaPlanos() {
  const { vencendo, atrasados } = p.planos;
  if (!vencendo && !atrasados) return null;
  const linhas = [
    vencendo && `${plural(vencendo, 'plano vence', 'planos vencem')} nos próximos 7 dias`,
    atrasados && `${plural(atrasados, 'assinante', 'assinantes')} com pagamento atrasado`,
  ].filter(Boolean);
  return h('a', { class: 'alerta-card', href: 'planos.html' },
    h('span', { class: 'alerta-icone' }, icone('planos')),
    h('span', { class: 'topo-textos', style: 'flex:1' },
      h('strong', null, linhas[0]),
      linhas[1] && h('span', { style: 'font-size:12px' }, linhas[1])),
    icone('avancar', 18));
}

function render() {
  const atual = mes === MESES[0];
  montar(app,
    h('div', { class: 'poste', 'aria-hidden': 'true' }),
    h('header', { class: 'topo', style: 'align-items:flex-end' },
      h('div', { class: 'topo-textos' },
        h('span', { class: 'sub' }, saudacao()),
        h('h1', { class: 'titulo' }, 'Como tá a casa')),
      h('div', { style: 'display:flex;gap:8px;align-items:center' },
        h('label', { class: 'sr-only', for: 'mes' }, 'Mês'),
        h('select', { id: 'mes', class: 'chip', style: 'padding-right:10px', onChange: (/** @type {Event} */ ev) => { mes = /** @type {HTMLSelectElement} */ (ev.target).value; atualizar(); } },
          MESES.map((m, i) => h('option', { value: m, selected: m === mes }, i === 0 ? nomeMes(m).split(' ')[0] : nomeMes(m)))),
        h('a', { class: 'btn-icone', href: 'config.html', 'aria-label': 'Ajustes' }, icone('ajustes'))),
    ),
    !p ? h('main', { class: 'conteudo' }, carregando()) : h('main', { class: 'conteudo', style: 'gap:16px' },
      h('div', { class: 'grade g2', style: 'gap:10px' },
        h('div', { class: 'card card--escuro', style: 'grid-column:span 2;gap:6px' },
          h('span', { class: 'sub' }, `Faturamento ${atual ? 'do mês' : `de ${nomeMes(mes).split(' ')[0].toLowerCase()}`} · líquido`),
          h('span', { class: 'valor-grande', style: 'font-size:36px' }, dinheiro(p.liquido)),
          h('span', { class: 'sub' }, `Bruto ${dinheiro(p.bruto)} · ${dinheiro(p.bruto - p.liquido)} em taxas de maquininha`)),
        h('div', { class: 'metrica' },
          h('span', { class: 'metrica-rotulo' }, 'Hoje'),
          h('span', { class: 'metrica-valor', style: 'font-size:24px' }, dinheiro(p.hoje.entradas)),
          h('span', { class: 'ajuda' }, `${p.hoje.atendidos} de ${p.hoje.marcados} atendidos`)),
        h('div', { class: 'metrica' },
          h('span', { class: 'metrica-rotulo' }, 'Ticket médio'),
          h('span', { class: 'metrica-valor', style: 'font-size:24px' }, p.ticket_medio == null ? '—' : dinheiro(p.ticket_medio)),
          h('span', { class: 'ajuda' }, plural(p.atendimentos, 'atendimento', 'atendimentos'))),
      ),
      h('div', { class: 'lista' },
        h('div', { class: 'linha' }, h('span', { class: 'linha-textos linha-titulo' }, 'Despesas do mês'), h('span', { class: 'linha-valor negativo' }, `− ${dinheiro(p.despesas)}`)),
        h('div', { class: 'linha' }, h('span', { class: 'linha-textos linha-titulo' }, 'Sobra (líquido − despesas)'), h('span', { class: `linha-valor ${p.liquido - p.despesas >= 0 ? 'positivo' : 'negativo'}` }, dinheiro(p.liquido - p.despesas))),
        p.fiado_aberto > 0 && h('a', { class: 'linha', href: 'clientes.html?filtro=fiado', style: 'color:inherit;text-decoration:none' },
          h('span', { class: 'linha-textos linha-titulo' }, 'Fiado pra receber'), h('span', { class: 'linha-valor' }, dinheiro(p.fiado_aberto)), icone('avancar', 16))),
      alertaPlanos(),
      graficoSemana(),
      comoPagaram(),
      comissoes(),
    ),
    tabbar('inicio', perfil),
  );
}

async function carregar() {
  const vez = ++pedido;
  p = null; render();
  try {
    const novo = await rpc('painel_mes', { p_mes: mes });
    if (vez !== pedido) return;
    p = novo;
    render();
  } catch (e) {
    // Resposta de um mês que já foi trocado não derruba a tela do mês atual
    if (vez === pedido) throw e;
  }
}

/** @returns {Promise<void>} */
const atualizar = () => carregar().catch((e) => telaErro(app, e, atualizar));

atualizar();
// Volta pro app depois de um tempo: números novos
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible' && p) atualizar(); });
