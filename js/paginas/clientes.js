// @ts-check
import { rpc } from '../supabase.js';
import { exigirEquipe } from '../auth.js';
import { h, montar, carregando, param, telaErro } from '../ui/dom.js';
import { icone } from '../ui/icones.js';
import { mostrarErro, toast } from '../ui/toast.js';
import { tabbar } from '../ui/tabbar.js';
import { dinheiro, dataLonga, hora, plural, telefoneBonito, diaMes, diaDoTimestamp } from '../lib/formatar.js';
import { linkWhats, mensagens, urlDoSite } from '../lib/mensagens.js';

const app = /** @type {HTMLElement} */ (document.getElementById('app'));
const perfil = await exigirEquipe({ somenteDono: true });

const FILTROS = /** @type {const} */ ([
  ['todos', 'Todos'], ['sumidos', 'Sumidos 30+ dias'], ['assinantes', 'Assinantes'], ['fiado', 'Fiado'],
]);

/** "Há 6 dias · Corte + Barba", "Hoje · Corte", "Ainda não veio" @param {any} c */
function ultimaVisita(c) {
  if (c.dias_sem_vir == null) return c.tem_horario ? 'Ainda não veio · tem horário marcado' : 'Ainda não veio';
  const quando = c.dias_sem_vir === 0 ? 'Hoje' : c.dias_sem_vir === 1 ? 'Ontem' : `Há ${c.dias_sem_vir} dias`;
  return c.ultimo_servico ? `${quando} · ${c.ultimo_servico}` : quando;
}

const inicial = (/** @type {string} */ nome) => (nome.trim().charAt(0) || '?').toUpperCase();

// ───────────────────────── lista ─────────────────────────

function telaLista() {
  let filtro = /** @type {string} */ (FILTROS.some(([f]) => f === param('filtro')) ? param('filtro') : 'todos');
  let busca = '';
  /** @type {any} */ let dados = null;
  let pedido = 0;
  /** @type {ReturnType<typeof setTimeout> | undefined} */ let espera;

  const campoBusca = /** @type {HTMLInputElement} */ (h('input', {
    id: 'busca', type: 'search', class: 'entrada', placeholder: 'Buscar por nome ou WhatsApp', autocomplete: 'off',
    onInput: () => { clearTimeout(espera); espera = setTimeout(() => { busca = campoBusca.value; atualizar(); }, 300); },
  }));
  // Pedaços trocados sozinhos: o campo de busca não pode ser recriado enquanto a pessoa digita
  const elContagem = h('span', { class: 'sub' }, '');
  const elFiltros = h('div', { class: 'chips chips--rolar', role: 'group', 'aria-label': 'Filtros' });
  const elLista = h('div', { class: 'secao' }, carregando());

  function desenharFiltros() {
    const n = dados?.contagens ?? {};
    montar(elFiltros, FILTROS.map(([id, rotulo]) =>
      h('button', { type: 'button', class: 'chip', 'aria-pressed': String(filtro === id),
                    onClick: () => { filtro = id; desenharFiltros(); atualizar(); } },
        n[id] == null ? rotulo : `${rotulo} · ${n[id]}`)));
  }

  /** @param {any} c @param {number} i */
  function linha(c, i) {
    const tag = c.fiado_centavos > 0 ? h('span', { class: 'tag tag--alerta' }, `Deve ${dinheiro(c.fiado_centavos)}`)
      : c.assinante ? h('span', { class: 'tag tag--info' }, 'Assinante') : null;
    return h('div', { class: 'cliente' },
      h('a', { class: 'cliente-link', href: `clientes.html?id=${encodeURIComponent(c.id)}` },
        h('span', { class: `avatar avatar--${i % 4}`, 'aria-hidden': 'true' }, inicial(c.nome)),
        h('span', { class: 'topo-textos', style: 'flex:1' },
          h('span', { class: 'cliente-nome' }, c.nome),
          h('span', { class: 'ajuda' }, ultimaVisita(c)))),
      tag,
      c.sumido && h('a', { class: 'btn btn--zap btn--peq', target: '_blank', rel: 'noopener',
                           href: linkWhats(c.telefone, mensagens.sumido(c.nome.split(' ')[0], urlDoSite('index.html'))),
                           'aria-label': `Chamar ${c.nome} no WhatsApp` }, 'Chamar'),
    );
  }

  function desenharLista() {
    elContagem.textContent = dados ? plural(dados.contagens.todos, 'cliente', 'clientes') : '';
    if (!dados) { montar(elLista, carregando()); return; }
    const lista = dados.clientes;
    montar(elLista,
      filtro === 'sumidos' && h('p', { class: 'aviso' }, 'Cliente que não volta há mais de 30 dias. Um "e aí, bora cortar?" no Zap costuma trazer de volta.'),
      lista.length === 0
        ? h('p', { class: 'vazio' }, busca ? 'Ninguém com esse nome ou número.' : filtro === 'todos' ? 'Ainda não tem cliente. Eles aparecem aqui quando marcam horário.' : 'Ninguém nesse filtro.')
        : lista.map(linha),
      lista.length >= 300 && h('p', { class: 'ajuda' }, 'Mostrando os 300 primeiros. Usa a busca pra achar os outros.'),
    );
  }

  async function carregar() {
    const vez = ++pedido;
    try {
      const novo = await rpc('clientes_lista', { p_busca: busca || null, p_filtro: filtro });
      if (vez !== pedido) return;
      dados = novo;
      desenharFiltros();
      desenharLista();
    } catch (e) {
      if (vez === pedido) throw e;
    }
  }
  const atualizar = () => carregar().catch((e) => {
    // Busca e filtro já na tela: o erro aparece na lista, sem perder o que foi digitado
    montar(elLista, h('div', { class: 'vazio', role: 'alert' },
      h('p', null, e instanceof Error ? e.message : 'Não deu pra carregar.'),
      h('button', { type: 'button', class: 'btn btn--contorno btn--peq', onClick: atualizar }, 'Tentar de novo')));
  });

  montar(app,
    h('div', { class: 'poste', 'aria-hidden': 'true' }),
    h('header', { class: 'topo', style: 'flex-direction:column;align-items:stretch;gap:14px' },
      h('div', { class: 'topo-textos' }, elContagem, h('h1', { class: 'titulo' }, 'Clientes')),
      h('div', { class: 'busca' },
        h('label', { class: 'sr-only', for: 'busca' }, 'Buscar cliente'),
        campoBusca,
        h('span', { class: 'busca-icone' }, icone('busca', 18))),
      elFiltros),
    h('main', { class: 'conteudo', style: 'gap:10px;padding-top:14px' }, elLista),
    tabbar('clientes', perfil),
  );
  desenharFiltros();
  atualizar();
}

// ───────────────────────── ficha ─────────────────────────

/** @param {string} id */
async function telaFicha(id) {
  montar(app, carregando());
  /** @type {any} */ let f;
  try {
    f = await rpc('ficha_cliente', { p_id: id });
  } catch (e) {
    telaErro(app, e, () => telaFicha(id));
    return;
  }
  const c = f.cliente;
  const primeiro = c.nome.split(' ')[0];
  const plano = f.plano;
  const totalFiado = f.fiados.reduce((/** @type {number} */ t, /** @type {any} */ x) => t + x.valor, 0);

  /** @param {SubmitEvent} ev @param {(fd: FormData) => Promise<void>} acao @param {string} msg */
  async function enviar(ev, acao, msg) {
    ev.preventDefault();
    const form = /** @type {HTMLFormElement} */ (ev.target);
    const botao = /** @type {HTMLButtonElement} */ (form.querySelector('button[type=submit]'));
    botao.disabled = true;
    try { await acao(new FormData(form)); toast(msg, 'ok'); }
    catch (e) { mostrarErro(e); botao.disabled = false; return; }
    telaFicha(id);
  }

  montar(app,
    h('div', { class: 'poste', 'aria-hidden': 'true' }),
    h('header', { class: 'topo', style: 'justify-content:flex-start' },
      h('a', { class: 'btn-icone', href: 'clientes.html', 'aria-label': 'Voltar pra lista' }, icone('voltar')),
      h('div', { class: 'topo-textos' },
        h('span', { class: 'sub' }, telefoneBonito(c.telefone)),
        h('h1', { class: 'titulo-m' }, c.nome))),
    h('main', { class: 'conteudo', style: 'gap:16px' },
      h('div', { class: 'chips' },
        plano && h('span', { class: `tag ${plano.status === 'ativa' ? 'tag--info' : 'tag--erro'}` }, `${plano.nome}${plano.status === 'ativa' ? '' : ' · atrasado'}`),
        totalFiado > 0 && h('span', { class: 'tag tag--alerta' }, `Deve ${dinheiro(totalFiado)}`),
        c.faltas > 0 && h('span', { class: 'tag tag--erro' }, plural(c.faltas, 'falta', 'faltas')),
        !c.aceita_lembrete && h('span', { class: 'tag' }, 'Não quer lembrete')),
      h('div', { class: 'metricas' },
        h('div', { class: 'metrica' }, h('span', { class: 'metrica-rotulo' }, 'Visitas'), h('span', { class: 'metrica-valor' }, String(f.resumo.visitas))),
        h('div', { class: 'metrica' }, h('span', { class: 'metrica-rotulo' }, 'Já gastou'), h('span', { class: 'metrica-valor' }, dinheiro(f.resumo.gasto_centavos))),
        h('div', { class: 'metrica' }, h('span', { class: 'metrica-rotulo' }, 'Cliente desde'), h('span', { class: 'metrica-valor' }, diaMes(diaDoTimestamp(c.criado_em))))),
      h('a', { class: 'btn btn--zap btn--bloco', href: linkWhats(c.telefone, `Fala, ${primeiro}!`), target: '_blank', rel: 'noopener' }, icone('zap', 18), 'Mandar mensagem'),

      plano && h('a', { class: 'card card--azul', href: 'planos.html', style: 'text-decoration:none;gap:8px' },
        h('div', { class: 'secao-cabeca' }, h('strong', null, plano.nome), h('span', { class: 'sub' }, `vence ${diaMes(plano.vence_em)}`)),
        h('span', { class: 'sub' }, plano.usos_por_mes == null ? `${plano.usados} cortes no mês · ilimitado` : `${plano.usados} de ${plano.usos_por_mes} cortes usados no mês`)),

      f.fiados.length > 0 && h('section', { class: 'secao' },
        h('div', { class: 'secao-cabeca' },
          h('h2', { class: 'secao-titulo' }, `Fiado · ${dinheiro(totalFiado)}`),
          h('a', { class: 'btn btn--claro btn--peq', target: '_blank', rel: 'noopener', href: linkWhats(c.telefone, mensagens.fiado(primeiro, dinheiro(totalFiado))) }, icone('zap', 16), 'Cobrar')),
        h('div', { class: 'lista' }, f.fiados.map((/** @type {any} */ x) =>
          h('form', { class: 'linha', style: 'flex-wrap:wrap', onSubmit: (/** @type {SubmitEvent} */ ev) => enviar(ev,
              (fd) => rpc('quitar_fiado', { p_pagamento_id: x.pagamento_id, p_forma_id: fd.get('forma') }), 'Fiado acertado.') },
            h('div', { class: 'linha-textos' },
              h('span', { class: 'linha-titulo' }, dinheiro(x.valor)),
              h('span', { class: 'ajuda' }, `Desde ${dataLonga(x.data)}`)),
            h('div', { style: 'display:flex;gap:8px;width:100%' },
              h('select', { name: 'forma', class: 'entrada entrada--peq', required: true, 'aria-label': 'Como pagou' },
                f.formas.map((/** @type {any} */ fp) => h('option', { value: fp.id }, fp.nome))),
              h('button', { type: 'submit', class: 'btn btn--escuro btn--peq' }, 'Recebi'))))),
      ),

      f.proximos.length > 0 && h('section', { class: 'secao' },
        h('h2', { class: 'secao-titulo' }, 'Horários marcados'),
        h('div', { class: 'lista' }, f.proximos.map((/** @type {any} */ x) => h('div', { class: 'linha' },
          h('div', { class: 'linha-textos' },
            h('span', { class: 'linha-titulo' }, `${dataLonga(x.inicio)} às ${hora(x.inicio)}`),
            h('span', { class: 'ajuda' }, `${x.servicos ?? ''} · com ${x.barbeiro}`)))))),

      h('section', { class: 'secao' },
        h('h2', { class: 'secao-titulo' }, 'Histórico'),
        f.historico.length === 0 ? h('p', { class: 'vazio' }, 'Ainda não tem atendimento finalizado.')
          : h('div', { class: 'lista' }, f.historico.map((/** @type {any} */ x) => h('div', { class: 'linha' },
              h('div', { class: 'linha-textos' },
                h('span', { class: 'linha-titulo' }, x.servicos || 'Atendimento'),
                h('span', { class: 'ajuda' }, `${dataLonga(x.data)} · com ${x.barbeiro}${x.forma ? ` · ${x.forma}` : ''}${x.gorjeta_centavos ? ` · gorjeta ${dinheiro(x.gorjeta_centavos)}` : ''}`)),
              h('span', { class: `linha-valor${x.pendente ? ' negativo' : ''}` }, x.pendente ? `${dinheiro(x.total_centavos)} (fiado)` : dinheiro(x.total_centavos)))))),

      h('details', { class: 'painel' },
        h('summary', null, 'Editar dados'),
        h('form', { class: 'painel-corpo', onSubmit: (/** @type {SubmitEvent} */ ev) => enviar(ev,
            (fd) => rpc('salvar_cliente', { p_id: c.id, p_nome: String(fd.get('nome') || ''), p_observacoes: String(fd.get('obs') || ''), p_aceita_lembrete: fd.get('lembrete') === 'on' }),
            'Dados salvos.') },
          h('label', { class: 'campo' }, h('span', { class: 'rotulo' }, 'Nome'), h('input', { name: 'nome', class: 'entrada entrada--peq', required: true, value: c.nome, maxlength: 80 })),
          h('label', { class: 'campo' }, h('span', { class: 'rotulo' }, 'Observações (só a equipe vê)'),
            h('textarea', { name: 'obs', class: 'entrada', rows: 3, maxlength: 500, style: 'padding-top:12px;min-height:88px', value: c.observacoes ?? '', placeholder: 'Ex.: gosta de máquina 2 dos lados' })),
          h('label', { class: 'check' }, h('input', { type: 'checkbox', name: 'lembrete', checked: c.aceita_lembrete }), h('span', null, 'Aceita lembrete no WhatsApp')),
          h('button', { type: 'submit', class: 'btn btn--escuro btn--peq' }, 'Salvar'))),
    ),
    tabbar('clientes', perfil),
  );
}

const id = param('id');
if (id) telaFicha(id);
else telaLista();
