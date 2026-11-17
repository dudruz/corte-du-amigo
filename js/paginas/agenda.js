// @ts-check
import { sb, rpc, traduzirErro } from '../supabase.js';
import { exigirEquipe } from '../auth.js';
import { h, montar, carregando, param, telaErro } from '../ui/dom.js';
import { icone } from '../ui/icones.js';
import { mostrarErro, toast } from '../ui/toast.js';
import { tabbar } from '../ui/tabbar.js';
import { hora, hojeISO, somarDias, semanaLonga, diaMes, telefoneBonito } from '../lib/formatar.js';
import { linkWhats, mensagens } from '../lib/mensagens.js';

const app = /** @type {HTMLElement} */ (document.getElementById('app'));
const perfil = await exigirEquipe();
const ehDono = perfil.papel === 'dono';

const { data: barbeiros, error: erroBarbeiros } = await sb.from('barbeiros').select('id, nome, apelido').eq('ativo', true).order('nome');
if (erroBarbeiros) {
  const erro = traduzirErro(erroBarbeiros);
  telaErro(app, erro);
  throw erro;
}
/** @type {string} */
let barbeiro = param('barbeiro') || perfil.barbeiro_id || barbeiros?.[0]?.id || '';
let dia = param('dia') || hojeISO();
/** @type {any} */ let agenda = null;
/** @type {any[]} */ let amanha = [];
// Número do último pedido de carga: resposta de pedido mais antigo é descartada
let pedido = 0;
// Último "hoje" que a tela viu, pra perceber a virada do dia com o app aberto
let hojeVisto = hojeISO();

const nomeBarbeiro = () => {
  const b = barbeiros?.find((x) => x.id === barbeiro);
  return b ? (b.apelido || b.nome) : '';
};

async function carregar() {
  const vez = ++pedido;
  // Quem deixou a agenda aberta em "hoje" de um dia pro outro continua vendo hoje
  const hoje = hojeISO();
  if (hoje !== hojeVisto) {
    if (dia === hojeVisto) dia = hoje;
    hojeVisto = hoje;
  }
  if (!barbeiro) { agenda = { itens: [], bloqueios: [] }; amanha = []; render(); return; }
  const doBarbeiro = barbeiro;
  const doDia = dia;
  try {
    const nova = await rpc('agenda_do_dia', { p_barbeiro: doBarbeiro, p_dia: doDia });
    const lembretes = doDia === hoje
      ? (await rpc('agenda_do_dia', { p_barbeiro: doBarbeiro, p_dia: somarDias(doDia, 1) })).itens
          .filter((/** @type {any} */ a) => a.status === 'marcado' && a.aceita_lembrete)
      : [];
    // Trocando de dia ou barbeiro rápido, a resposta antiga pode chegar depois da nova
    if (vez !== pedido) return;
    agenda = nova;
    amanha = lembretes;
    render();
  } catch (e) {
    if (vez === pedido) throw e;
  }
}

/** Sem nada na tela ainda, o erro ocupa a tela com "Tentar de novo"; com a agenda aberta, vira só um aviso. @param {unknown} e */
function aoFalhar(e) {
  if (agenda === null) telaErro(app, e, () => { render(); atualizar(); });
  else mostrarErro(e);
}

const atualizar = () => carregar().catch(aoFalhar);

async function mudar(/** @type {any} */ a, /** @type {string} */ status, /** @type {string} */ pergunta) {
  if (pergunta && !confirm(pergunta)) return;
  try { await rpc('mudar_status', { p_id: a.id, p_status: status }); await carregar(); }
  catch (e) { mostrarErro(e); }
}

async function removerBloqueio(/** @type {any} */ b) {
  if (!confirm('Liberar esse horário de novo pra agendamento?')) return;
  try { await rpc('remover_bloqueio', { p_id: b.id }); toast('Horário liberado.', 'ok'); await carregar(); }
  catch (e) { mostrarErro(e); }
}

function itemAgendamento(/** @type {any} */ a) {
  const agora = a.status === 'em_atendimento';
  const feito = a.status === 'finalizado' || a.status === 'faltou';
  const tag = {
    marcado: ['Marcado', ''], em_atendimento: ['Agora', 'tag--agora'],
    finalizado: ['Finalizado', 'tag--ok'], faltou: ['Faltou', 'tag--erro'],
  }[/** @type {'marcado'} */ (a.status)] ?? [a.status, ''];

  return h('div', { class: 'hora-item' },
    h('span', { class: 'hora-rotulo', style: agora ? 'color:var(--vermelho)' : '' }, hora(a.inicio)),
    h('div', { class: `agend ${agora ? 'agend--agora' : ''} ${feito ? 'agend--feito' : ''}` },
      h('div', { class: 'agend-cabeca' },
        h('strong', null, a.cliente),
        h('span', { class: `tag ${tag[1]}` }, tag[0]),
      ),
      h('span', { class: 'sub' }, `${a.servicos.join(' + ')} · até ${hora(a.fim)}`),
      a.faltas > 0 && a.status === 'marcado' && h('span', { class: 'ajuda', style: 'color:var(--alerta)' }, `Já faltou ${a.faltas}x`),
      agora && h('a', { class: 'btn btn--primario btn--peq', href: `finalizar.html?id=${a.id}` }, 'Finalizar e receber'),
      a.status === 'marcado' && h('div', { class: 'agend-acoes' },
        h('button', { type: 'button', class: 'btn btn--escuro btn--peq', onClick: () => mudar(a, 'em_atendimento', '') }, 'Começar'),
        h('a', { class: 'btn btn--claro btn--peq', href: `finalizar.html?id=${a.id}` }, 'Finalizar'),
        h('a', { class: 'btn btn--claro btn--peq', href: linkWhats(a.telefone, `Fala, ${a.cliente}! `), target: '_blank', rel: 'noopener', 'aria-label': `WhatsApp de ${a.cliente}` }, icone('zap', 18)),
        h('button', { type: 'button', class: 'btn btn--texto', onClick: () => mudar(a, 'faltou', `Marcar que ${a.cliente} faltou?`) }, 'Faltou'),
        h('button', { type: 'button', class: 'btn btn--texto', style: 'color:var(--muted)', onClick: () => mudar(a, 'cancelado', `Cancelar o horário de ${a.cliente}?`) }, 'Cancelar'),
      ),
    ),
  );
}

function itemBloqueio(/** @type {any} */ b) {
  const texto = `${b.barbearia ? 'Barbearia fechada' : 'Bloqueado'}${b.motivo ? ` · ${b.motivo}` : ''} · até ${hora(b.fim)}${b.recorrente ? ' (toda semana)' : ''}`;
  return h('div', { class: 'hora-item' },
    h('span', { class: 'hora-rotulo', style: 'color:var(--muted)' }, hora(b.inicio)),
    h('div', { class: 'bloqueio-item' },
      icone('cadeado', 16), h('span', { style: 'flex:1' }, texto),
      h('button', { type: 'button', class: 'btn-icone', style: 'background:transparent;border:none', 'aria-label': 'Liberar horário', onClick: () => removerBloqueio(b) }, icone('fechar', 18)),
    ),
  );
}

function render() {
  const hoje = dia === hojeISO();
  const itens = agenda?.itens ?? [];
  const linhas = [
    ...itens.map((/** @type {any} */ a) => ({ t: a.inicio, el: () => itemAgendamento(a) })),
    ...(agenda?.bloqueios ?? []).map((/** @type {any} */ b) => ({ t: b.inicio, el: () => itemBloqueio(b) })),
  ].sort((x, y) => new Date(x.t).getTime() - new Date(y.t).getTime());
  const conta = (/** @type {string} */ s) => itens.filter((/** @type {any} */ a) => a.status === s).length;

  montar(app,
    h('header', { class: 'topo--escuro' },
      h('div', { class: 'topo-linha' },
        h('div', { class: 'topo-textos' },
          h('span', { class: 'sub' }, `${hoje ? 'Hoje · ' : ''}${semanaLonga(dia)}, ${diaMes(dia)}`),
          h('span', { class: 'titulo' }, `Agenda${nomeBarbeiro() ? ` do ${nomeBarbeiro()}` : ''}`),
        ),
        h('div', { style: 'display:flex;gap:8px' },
          h('a', { class: 'btn-icone', href: `bloquear.html?barbeiro=${barbeiro}`, 'aria-label': 'Fechar agenda' }, icone('cadeado')),
          h('a', { class: 'btn-icone btn-icone--vermelho', href: '../index.html', 'aria-label': 'Novo agendamento' }, icone('mais', 22, 2.4)),
        ),
      ),
      h('div', { class: 'topo-linha' },
        h('button', { type: 'button', class: 'btn-icone', 'aria-label': 'Dia anterior', onClick: () => { dia = somarDias(dia, -1); atualizar(); } }, icone('voltar')),
        !hoje && h('button', { type: 'button', class: 'chip', onClick: () => { dia = hojeISO(); atualizar(); } }, 'Voltar pra hoje'),
        h('button', { type: 'button', class: 'btn-icone', 'aria-label': 'Próximo dia', onClick: () => { dia = somarDias(dia, 1); atualizar(); } }, icone('avancar')),
      ),
      ehDono && (barbeiros?.length ?? 0) > 1 && h('div', { class: 'chips' }, barbeiros?.map((b) =>
        h('button', { type: 'button', class: 'chip', 'aria-pressed': String(b.id === barbeiro),
                      onClick: () => { barbeiro = b.id; atualizar(); } }, b.apelido || b.nome))),
      h('div', { class: 'metricas' },
        h('div', { class: 'metrica metrica--escura' }, h('span', { class: 'metrica-valor' }, String(conta('marcado') + conta('em_atendimento'))), h('span', { class: 'metrica-rotulo' }, 'pra atender')),
        h('div', { class: 'metrica metrica--escura' }, h('span', { class: 'metrica-valor' }, String(conta('finalizado'))), h('span', { class: 'metrica-rotulo' }, 'finalizados')),
        h('div', { class: 'metrica metrica--escura' }, h('span', { class: 'metrica-valor' }, String(conta('faltou'))), h('span', { class: 'metrica-rotulo' }, 'faltas')),
      ),
    ),
    h('main', { class: 'conteudo', style: 'gap:16px' },
      agenda === null ? carregando()
        : linhas.length === 0 ? h('div', { class: 'vazio' }, 'Nenhum horário marcado nesse dia.')
        : h('div', { class: 'timeline' }, linhas.map((l) => l.el())),
      amanha.length > 0 && h('section', { class: 'secao' },
        h('h2', { class: 'secao-titulo' }, 'Lembretes de amanhã'),
        h('div', { class: 'lista' }, amanha.map((a) =>
          h('div', { class: 'linha' },
            h('div', { class: 'linha-textos' },
              h('span', { class: 'linha-titulo' }, `${hora(a.inicio)} · ${a.cliente}`),
              h('span', { class: 'ajuda' }, telefoneBonito(a.telefone))),
            h('a', { class: 'btn btn--zap btn--peq', href: linkWhats(a.telefone, mensagens.lembrete(a.cliente, hora(a.inicio))), target: '_blank', rel: 'noopener',
                     onClick: (/** @type {Event} */ ev) => { /** @type {HTMLElement} */ (ev.currentTarget).textContent = 'Enviado'; } }, 'Lembrar'),
          ))),
      ),
    ),
    tabbar('agenda', perfil),
  );
}

render();
await atualizar();

// Atualiza sozinho quando um cliente marca, cancela ou remarca
let espera = 0;
const recarregar = () => { clearTimeout(espera); espera = setTimeout(atualizar, 400); };
sb.channel('agenda')
  .on('postgres_changes', { event: '*', schema: 'public', table: 'agendamentos' }, recarregar)
  .on('postgres_changes', { event: '*', schema: 'public', table: 'bloqueios' }, recarregar)
  // O Realtime não reenvia o que aconteceu enquanto a conexão esteve caída
  .subscribe((status) => { if (status === 'SUBSCRIBED') recarregar(); });

// Celular bloqueado ou app em segundo plano param de receber eventos: ao voltar, busca tudo de novo
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') recarregar(); });
window.addEventListener('online', recarregar);
window.addEventListener('pageshow', (ev) => { if (ev.persisted) recarregar(); });
