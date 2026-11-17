// @ts-check
import { rpc } from '../supabase.js';
import { exigirEquipe } from '../auth.js';
import { h, montar, carregando, telaErro } from '../ui/dom.js';
import { mostrarErro, toast } from '../ui/toast.js';
import { tabbar } from '../ui/tabbar.js';
import { blocoPix, codigoDoValor } from '../ui/pix.js';
import { dinheiro, diaMes, plural, paraCentavos, centavosParaTexto } from '../lib/formatar.js';
import { linkWhats, mensagens } from '../lib/mensagens.js';

const app = /** @type {HTMLElement} */ (document.getElementById('app'));
const perfil = await exigirEquipe({ somenteDono: true });

/** @type {any} */ let d = null;
let filtro = 'todos';
/** @type {string | null} id do plano aberto no editor, 'novo' ou null */ let editando = null;
/** @type {string | null} assinatura com o formulário de pagamento aberto */ let pagando = null;

// Pedaços trocados sozinhos, pra não apagar o que está digitado nos outros formulários
const elEditor = h('div', { class: 'secao' });
const elLista = h('div', { class: 'secao' });

/** Mostra o erro e devolve o botão, ou recarrega a tela depois de dar certo. @param {HTMLButtonElement} botao @param {() => Promise<void>} acao @param {string} msg */
async function executar(botao, acao, msg) {
  botao.disabled = true;
  try { await acao(); if (msg) toast(msg, 'ok'); }
  catch (e) { mostrarErro(e); botao.disabled = false; return; }
  await atualizar();
}

const seletorFormas = (/** @type {Record<string, any>} */ attrs) =>
  h('select', { class: 'entrada entrada--peq', required: true, ...attrs }, d.formas.map((/** @type {any} */ f) => h('option', { value: f.id }, f.nome)));
const formaPorId = (/** @type {string} */ id) => d.formas.find((/** @type {any} */ f) => f.id === id);
const usoTexto = (/** @type {any} */ p) => p.usos_por_mes == null ? 'Ilimitado' : `${p.usos_por_mes} ${p.usos_por_mes === 1 ? 'corte' : 'cortes'}/mês`;

// ───────────────────────── planos ─────────────────────────

function editor() {
  if (!editando) { montar(elEditor); return; }
  const p = editando === 'novo' ? null : d.planos.find((/** @type {any} */ x) => x.id === editando);
  const incluidos = new Set(p?.servicos_incluidos ?? []);
  montar(elEditor, h('form', { class: 'card', onSubmit: async (/** @type {SubmitEvent} */ ev) => {
      ev.preventDefault();
      const fd = new FormData(/** @type {HTMLFormElement} */ (ev.target));
      const preco = paraCentavos(String(fd.get('preco') || ''));
      const usosTexto = String(fd.get('usos') || '').trim();
      const usos = usosTexto === '' ? null : Number(usosTexto);
      const botao = /** @type {HTMLButtonElement} */ (/** @type {HTMLFormElement} */ (ev.target).querySelector('button[type=submit]'));
      if (Number.isNaN(preco)) { mostrarErro(new Error('Preço inválido. Usa o formato 120,00.')); return; }
      if (usos != null && !Number.isInteger(usos)) { mostrarErro(new Error('Cortes por mês precisa ser um número inteiro.')); return; }
      await executar(botao, async () => {
        await rpc('salvar_plano', {
          p_id: p?.id ?? null, p_nome: String(fd.get('nome') || ''), p_descricao: String(fd.get('descricao') || ''),
          p_preco: preco, p_usos: usos, p_servicos: fd.getAll('servicos').map(String), p_ativo: fd.get('ativo') === 'on',
        });
        editando = null;
      }, p ? 'Plano salvo.' : 'Plano criado.');
    } },
    h('div', { class: 'secao-cabeca' },
      h('strong', null, p ? `Editar ${p.nome}` : 'Novo plano'),
      h('button', { type: 'button', class: 'btn btn--texto', onClick: () => { editando = null; editor(); } }, 'Fechar')),
    h('label', { class: 'campo' }, h('span', { class: 'rotulo' }, 'Nome'),
      h('input', { name: 'nome', class: 'entrada entrada--peq', required: true, maxlength: 60, value: p?.nome ?? '', placeholder: 'Ex.: Plano Corte' })),
    h('label', { class: 'campo' }, h('span', { class: 'rotulo' }, 'Descrição (opcional)'),
      h('input', { name: 'descricao', class: 'entrada entrada--peq', value: p?.descricao ?? '', placeholder: 'Ex.: 4 cortes por mês' })),
    h('div', { class: 'grade g2' },
      h('label', { class: 'campo' }, h('span', { class: 'rotulo' }, 'Preço por mês (R$)'),
        h('input', { name: 'preco', class: 'entrada entrada--peq', inputmode: 'decimal', required: true, value: p ? centavosParaTexto(p.preco_centavos) : '' })),
      h('label', { class: 'campo' }, h('span', { class: 'rotulo' }, 'Cortes por mês'),
        h('input', { name: 'usos', class: 'entrada entrada--peq', type: 'number', min: 1, max: 31, value: p?.usos_por_mes ?? '', placeholder: 'em branco = ilimitado' }))),
    h('fieldset', { class: 'secao', style: 'border:none;padding:0;margin:0;gap:8px' },
      h('legend', { class: 'rotulo', style: 'margin-bottom:8px' }, 'Serviços que o plano cobre'),
      d.servicos.map((/** @type {any} */ s) => h('label', { class: 'check' },
        h('input', { type: 'checkbox', name: 'servicos', value: s.id, checked: incluidos.has(s.id) }), h('span', null, s.nome))),
      h('p', { class: 'ajuda' }, 'Nenhum marcado = cobre qualquer serviço. Serviço fora do plano é cobrado à parte no finalizar.')),
    h('label', { class: 'check' }, h('input', { type: 'checkbox', name: 'ativo', checked: p ? p.ativo : true }), h('span', null, 'Plano à venda')),
    h('button', { type: 'submit', class: 'btn btn--escuro btn--peq' }, p ? 'Salvar plano' : 'Criar plano'),
  ));
  elEditor.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

function cardsPlanos() {
  if (d.planos.length === 0) {
    return h('div', { class: 'aviso aviso--info' }, 'Nenhum plano ainda. Cria o primeiro no "+ Novo plano": quem assina paga por mês e usa os cortes sem pagar na hora.');
  }
  return h('div', { class: 'planos-cards' }, d.planos.map((/** @type {any} */ p) =>
    h('button', { type: 'button', class: `plano-card${p.ativo ? '' : ' plano-card--inativo'}`, 'aria-label': `Editar ${p.nome}`,
                  onClick: () => { editando = p.id; editor(); } },
      h('span', { class: 'sub' }, p.ativo ? p.nome : `${p.nome} · fora de venda`),
      h('span', { class: 'titulo-m' }, usoTexto(p)),
      h('span', { class: 'sub' }, `${dinheiro(p.preco_centavos)} · ${plural(p.assinantes, 'assinante', 'assinantes')}`))));
}

// ───────────────────────── assinar ─────────────────────────

function formAssinar() {
  const ativos = d.planos.filter((/** @type {any} */ p) => p.ativo);
  if (ativos.length === 0) return null;
  const elPix = h('div');
  const selPlano = /** @type {HTMLSelectElement} */ (h('select', { name: 'plano', id: 'plano', class: 'entrada entrada--peq', required: true, onChange: () => mostrarPix() },
    ativos.map((/** @type {any} */ p) => h('option', { value: p.id }, `${p.nome} · ${dinheiro(p.preco_centavos)}`))));
  const selForma = /** @type {HTMLSelectElement} */ (seletorFormas({ name: 'forma', id: 'forma-assinar', onChange: () => mostrarPix() }));
  const botao = /** @type {HTMLButtonElement} */ (h('button', { type: 'submit', class: 'btn btn--primario btn--peq' }, ''));
  function mostrarPix() {
    const plano = ativos.find((/** @type {any} */ p) => p.id === selPlano.value);
    botao.textContent = `Assinar e receber ${dinheiro(plano?.preco_centavos ?? 0)}`;
    montar(elPix, formaPorId(selForma.value)?.tipo === 'pix' && plano ? blocoPix(d.pix, plano.preco_centavos) : null);
  }
  const form = h('form', { class: 'painel-corpo', onSubmit: async (/** @type {SubmitEvent} */ ev) => {
      ev.preventDefault();
      const fd = new FormData(/** @type {HTMLFormElement} */ (ev.target));
      await executar(botao, () => rpc('assinar_plano', {
        p_plano_id: fd.get('plano'), p_forma_id: fd.get('forma'), p_cliente_id: null,
        p_nome: String(fd.get('nome') || ''), p_telefone: String(fd.get('telefone') || ''),
      }), 'Plano assinado e primeiro mês no caixa.');
    } },
    h('div', { class: 'campo' }, h('label', { for: 'plano' }, 'Plano'), selPlano),
    h('div', { class: 'grade g2' },
      h('label', { class: 'campo' }, h('span', { class: 'rotulo' }, 'Nome do cliente'), h('input', { name: 'nome', class: 'entrada entrada--peq', required: true, maxlength: 80, autocomplete: 'off' })),
      h('label', { class: 'campo' }, h('span', { class: 'rotulo' }, 'WhatsApp'), h('input', { name: 'telefone', class: 'entrada entrada--peq', type: 'tel', required: true, placeholder: '31 99999-8888', autocomplete: 'off' }))),
    h('p', { class: 'ajuda' }, 'Se o WhatsApp já é de um cliente, o plano entra no cadastro dele.'),
    h('div', { class: 'campo' }, h('label', { for: 'forma-assinar' }, 'Pagou o primeiro mês com'), selForma),
    elPix,
    botao,
  );
  mostrarPix();
  return h('details', { class: 'painel' }, h('summary', null, 'Assinar plano pra um cliente'), form);
}

// ───────────────────────── assinantes ─────────────────────────

/** @param {any} a */
function etiqueta(a) {
  if (a.situacao === 'atrasada') return h('span', { class: 'tag tag--erro' }, 'Atrasado');
  if (a.situacao === 'vencendo') return h('span', { class: 'tag tag--alerta' }, a.dias === 0 ? 'Vence hoje' : `Vence em ${plural(a.dias, 'dia', 'dias')}`);
  return h('span', { class: 'tag tag--ok' }, 'Em dia');
}

/** @param {any} a */
function formPagamento(a) {
  const elPix = h('div');
  const sel = /** @type {HTMLSelectElement} */ (seletorFormas({ name: 'forma', 'aria-label': 'Como pagou', onChange: () => mostrarPix() }));
  const mostrarPix = () => montar(elPix, formaPorId(sel.value)?.tipo === 'pix' ? blocoPix(d.pix, a.preco_centavos) : null);
  const botao = /** @type {HTMLButtonElement} */ (h('button', { type: 'submit', class: 'btn btn--primario btn--peq' }, `Recebi ${dinheiro(a.preco_centavos)}`));
  const form = h('form', { class: 'secao', onSubmit: async (/** @type {SubmitEvent} */ ev) => {
      ev.preventDefault();
      await executar(botao, async () => {
        const vence = await rpc('registrar_pagamento_plano', { p_assinatura_id: a.id, p_forma_id: sel.value });
        pagando = null;
        toast(`Pagamento no caixa. Plano renovado até ${diaMes(vence)}.`, 'ok');
      }, '');
    } },
    h('div', { style: 'display:flex;gap:8px' }, sel,
      h('button', { type: 'button', class: 'btn btn--claro btn--peq', onClick: () => { pagando = null; lista(); } }, 'Voltar')),
    elPix, botao);
  mostrarPix();
  return form;
}

/** @param {any} a */
function cardAssinante(a) {
  const pct = a.usos_por_mes ? Math.min(100, Math.round((a.usados / a.usos_por_mes) * 100)) : 0;
  const vencimento = a.dias < 0 ? `venceu em ${diaMes(a.vence_em)}` : `vence em ${diaMes(a.vence_em)}`;
  const cobranca = mensagens.cobrancaPlano(a.cliente.split(' ')[0], a.plano, dinheiro(a.preco_centavos), vencimento, codigoDoValor(d.pix, a.preco_centavos));
  return h('div', { class: 'card', style: 'gap:10px' },
    h('div', { class: 'secao-cabeca', style: 'align-items:center' },
      h('a', { class: 'topo-textos', href: `clientes.html?id=${encodeURIComponent(a.cliente_id)}`, style: 'color:inherit;text-decoration:none' },
        h('strong', null, a.cliente),
        h('span', { class: 'ajuda' }, a.plano)),
      etiqueta(a)),
    h('div', { class: 'secao', style: 'gap:5px' },
      h('div', { class: 'secao-cabeca' },
        h('span', { class: 'ajuda' }, a.usos_por_mes == null ? `${plural(a.usados, 'corte', 'cortes')} no mês · ilimitado` : `${a.usados} de ${a.usos_por_mes} cortes usados`),
        h('span', { class: 'ajuda' }, vencimento)),
      a.usos_por_mes != null && h('div', { class: 'barra' }, h('span', { style: `width:${pct}%` }))),
    pagando === a.id ? formPagamento(a)
      : h('div', { style: 'display:flex;gap:8px;flex-wrap:wrap' },
          h('button', { type: 'button', class: `btn ${a.situacao === 'em_dia' ? 'btn--claro' : 'btn--primario'} btn--peq`, style: 'flex:1',
                        onClick: () => { pagando = a.id; lista(); } }, 'Registrar pagamento'),
          a.situacao !== 'em_dia' && h('a', { class: 'btn btn--claro btn--peq', href: linkWhats(a.telefone, cobranca), target: '_blank', rel: 'noopener' }, 'Cobrar no Zap')),
    h('button', { type: 'button', class: 'btn btn--texto', style: 'align-self:flex-start', onClick: async (/** @type {Event} */ ev) => {
        if (!confirm(`Cancelar o ${a.plano} de ${a.cliente}? Ele deixa de usar os cortes do plano.`)) return;
        await executar(/** @type {HTMLButtonElement} */ (ev.currentTarget), () => rpc('cancelar_assinatura', { p_assinatura_id: a.id }), 'Plano cancelado.');
      } }, 'Cancelar plano'),
  );
}

function lista() {
  const todas = d.assinaturas;
  const n = { todos: todas.length, vencendo: todas.filter((/** @type {any} */ a) => a.situacao === 'vencendo').length, atrasada: todas.filter((/** @type {any} */ a) => a.situacao === 'atrasada').length };
  const visiveis = filtro === 'todos' ? todas : todas.filter((/** @type {any} */ a) => a.situacao === filtro);
  montar(elLista,
    h('div', { class: 'secao-cabeca' }, h('h2', { class: 'secao-titulo' }, 'Assinantes')),
    h('div', { class: 'chips', role: 'group', 'aria-label': 'Filtros' },
      [['todos', 'Todos'], ['vencendo', 'Vencendo'], ['atrasada', 'Atrasados']].map(([id, rotulo]) =>
        h('button', { type: 'button', class: 'chip', 'aria-pressed': String(filtro === id), onClick: () => { filtro = id; lista(); } },
          `${rotulo} · ${n[/** @type {'todos'} */ (id)]}`))),
    visiveis.length === 0
      ? h('p', { class: 'vazio' }, todas.length === 0 ? 'Ninguém assinou ainda.' : 'Ninguém nesse filtro.')
      : visiveis.map(cardAssinante),
  );
}

// ───────────────────────── tela ─────────────────────────

function render() {
  const ativos = d ? d.assinaturas.length : 0;
  montar(app,
    h('div', { class: 'poste', 'aria-hidden': 'true' }),
    h('header', { class: 'topo', style: 'align-items:flex-end' },
      h('div', { class: 'topo-textos' },
        h('span', { class: 'sub' }, d ? plural(ativos, 'assinante ativo', 'assinantes ativos') : ''),
        h('h1', { class: 'titulo' }, 'Planos mensais')),
      d && h('button', { type: 'button', class: 'btn btn--escuro btn--peq', onClick: () => { editando = 'novo'; editor(); } }, '+ Novo plano')),
    !d ? h('main', { class: 'conteudo' }, carregando()) : h('main', { class: 'conteudo', style: 'gap:16px' },
      !d.pix.chave && h('p', { class: 'aviso aviso--alerta' }, 'Cadastre a chave Pix em Ajustes › Recebimento por Pix pra cobrança já ir com o Pix copia e cola.'),
      cardsPlanos(),
      elEditor,
      formAssinar(),
      elLista,
    ),
    tabbar('planos', perfil),
  );
  if (d) { editor(); lista(); }
}

async function carregar() {
  d = await rpc('planos_painel');
  render();
}
/** @returns {Promise<void>} */
const atualizar = () => carregar().catch((e) => telaErro(app, e, () => { d = null; render(); atualizar(); }));

render();
atualizar();
