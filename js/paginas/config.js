// @ts-check
import { sb, rpc, traduzirErro } from '../supabase.js';
import { exigirEquipe, sair } from '../auth.js';
import { h, montar, carregando, telaErro } from '../ui/dom.js';
import { icone } from '../ui/icones.js';
import { mostrarErro, toast } from '../ui/toast.js';
import { tabbar } from '../ui/tabbar.js';
import { paraCentavos, centavosParaTexto } from '../lib/formatar.js';
import { normalizarChavePix, tipoDaChave } from '../lib/pix.js';
import { FUSO } from '../config.js';

const app = /** @type {HTMLElement} */ (document.getElementById('app'));
const perfil = await exigirEquipe({ somenteDono: true });
const DIAS = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];

/** @type {any} */ let d = null;
/** @type {string | null} */ let barbeiroHorario = perfil.barbeiro_id;
// Pedaços da tela que são trocados sozinhos, sem remontar a página
/** @type {HTMLElement | null} */ let elHorarios = null;
/** @type {HTMLElement | null} */ let elChipsHorarios = null;

/**
 * Executa uma consulta do Supabase, lança o erro em português e devolve os dados.
 * @param {PromiseLike<{ data?: any, error: any }>} q
 */
async function ok(q) {
  const { data, error } = await q;
  if (error) throw String(error.message || '').includes('row-level') ? new Error('Sem permissão para alterar isso.') : traduzirErro(error);
  return data;
}

async function carregar() {
  const [serv, barb, hor, formas, cfg, logins, msgs] = await Promise.all([
    sb.from('servicos').select('*').order('ordem'),
    sb.from('barbeiros').select('*').order('nome'),
    sb.from('horarios_trabalho').select('*'),
    sb.from('formas_pagamento').select('*').order('ordem'),
    sb.from('configuracoes').select('*'),
    rpc('equipe_logins'),
    rpc('mensagens_painel'),
  ]);
  const erro = [serv, barb, hor, formas, cfg].find((r) => r.error);
  if (erro) throw traduzirErro(erro.error);
  d = {
    servicos: serv.data, barbeiros: barb.data, horarios: hor.data, formas: formas.data, logins, msgs,
    cfg: Object.fromEntries((cfg.data ?? []).map((c) => [c.chave, c.valor])),
  };
  barbeiroHorario = barbeiroHorario || d.barbeiros[0]?.id || null;
  render();
}

/**
 * Salva um formulário sem remontar a página: os outros formulários podem ter coisa digitada
 * e ainda não salva. A ação atualiza o estado em memória e, se precisar mexer na tela
 * (item novo na lista), devolve uma função que faz só esse ajuste.
 * @param {SubmitEvent} ev @param {(fd: FormData) => Promise<void | (() => void)>} acao @param {string} msg
 */
async function salvar(ev, acao, msg) {
  ev.preventDefault();
  const form = /** @type {HTMLFormElement} */ (ev.target);
  const botao = /** @type {HTMLButtonElement} */ (form.querySelector('button[type=submit]'));
  botao.disabled = true;
  try {
    const ajustarTela = await acao(new FormData(form));
    toast(msg, 'ok');
    if (ajustarTela) ajustarTela();
  } catch (e) { mostrarErro(e); }
  botao.disabled = false;
}

const centavos = (/** @type {FormData} */ fd, /** @type {string} */ c, oQue = 'Preço') => {
  const v = paraCentavos(String(fd.get(c) || ''));
  if (Number.isNaN(v)) throw new Error(`${oQue} inválido. Usa o formato 35,00.`);
  return v;
};

/**
 * Mesma regra do banco (normalizar_telefone): só dígitos, sem zero na frente, DDD + número,
 * e o 55 entra sozinho. Número incompleto não é gravado, porque os links de WhatsApp
 * do site inteiro dependem dele.
 * @param {string} texto
 */
function normalizarZap(texto) {
  let digitos = texto.replace(/\D/g, '').replace(/^0+/, '');
  if (!digitos) throw new Error('Coloca o WhatsApp da barbearia, com DDD.');
  if (digitos.length === 10 || digitos.length === 11) digitos = `55${digitos}`;
  if (!/^55\d{10,11}$/.test(digitos)) throw new Error('WhatsApp inválido. Coloca DDD + número.');
  return digitos;
}
const inteiro = (/** @type {FormData} */ fd, /** @type {string} */ c, /** @type {number} */ min) => {
  const v = Number(fd.get(c));
  if (!Number.isInteger(v) || v < min) throw new Error('Número inválido.');
  return v;
};
const campo = (/** @type {string} */ rotulo, /** @type {HTMLElement} */ entrada) => h('label', { class: 'campo' }, h('span', { class: 'rotulo' }, rotulo), entrada);
const entrada = (/** @type {Record<string, any>} */ a) => h('input', { class: 'entrada entrada--peq', ...a });

function secaoServicos() {
  const tituloNovo = h('strong', { style: 'margin-top:6px' }, 'Novo serviço');
  /** @type {(s: any) => HTMLElement} */
  const form = (s) => h('form', { class: 'card', style: 'gap:10px', onSubmit: (/** @type {SubmitEvent} */ ev) => salvar(ev, async (fd) => {
      const dados = { nome: String(fd.get('nome')).trim(), preco_centavos: centavos(fd, 'preco'), duracao_min: inteiro(fd, 'duracao', 5), ativo: fd.get('ativo') === 'on' };
      if (s) {
        await ok(sb.from('servicos').update(dados).eq('id', s.id));
        Object.assign(s, dados);
        return;
      }
      const criado = await ok(sb.from('servicos').insert({ ...dados, ordem: d.servicos.length + 1 }).select().single());
      d.servicos.push(criado);
      const formNovo = /** @type {HTMLElement} */ (ev.target);
      return () => { tituloNovo.before(form(criado)); formNovo.replaceWith(form(null)); };
    }, s ? 'Serviço salvo.' : 'Serviço criado.') },
    campo('Nome', entrada({ name: 'nome', required: true, value: s?.nome ?? '', placeholder: 'Ex.: Pigmentação' })),
    h('div', { class: 'grade g2' },
      campo('Preço (R$)', entrada({ name: 'preco', inputmode: 'decimal', required: true, value: s ? centavosParaTexto(s.preco_centavos) : '' })),
      campo('Duração (min)', entrada({ name: 'duracao', type: 'number', min: 5, step: 5, required: true, value: s?.duracao_min ?? 30 }))),
    h('div', { class: 'secao-cabeca' },
      h('label', { class: 'check' }, h('input', { type: 'checkbox', name: 'ativo', checked: s ? s.ativo : true }), h('span', null, 'Aparece pro cliente')),
      h('button', { type: 'submit', class: 'btn btn--escuro btn--peq' }, s ? 'Salvar' : 'Criar serviço')),
  );
  return h('details', { class: 'painel', open: true },
    h('summary', null, 'Serviços e preços'),
    h('div', { class: 'painel-corpo' }, d.servicos.map(form), tituloNovo, form(null)));
}

/** Escolha de qual barbeiro tem os horários na tela. Com um barbeiro só, não aparece. */
function chipsHorarios() {
  if (d.barbeiros.length <= 1) return h('span', { hidden: true });
  return h('div', { class: 'chips' }, d.barbeiros.map((/** @type {any} */ b) =>
    h('button', { type: 'button', class: 'chip', 'aria-pressed': String(b.id === barbeiroHorario),
                  onClick: () => { barbeiroHorario = b.id; elHorarios?.replaceWith(secaoHorarios(true)); } }, b.apelido || b.nome)));
}

/** Refaz só os chips (barbeiro novo ou renomeado), sem tocar no formulário de horários. */
function atualizarChipsHorarios() {
  const novo = chipsHorarios();
  elChipsHorarios?.replaceWith(novo);
  elChipsHorarios = novo;
}

function secaoHorarios(aberto = false) {
  const doBarbeiro = d.horarios.filter((/** @type {any} */ x) => x.barbeiro_id === barbeiroHorario);
  elChipsHorarios = chipsHorarios();
  elHorarios = h('details', { class: 'painel', open: aberto },
    h('summary', null, 'Dias e horário de trabalho'),
    h('div', { class: 'painel-corpo' },
      elChipsHorarios,
      h('p', { class: 'ajuda' }, 'Pausa de almoço e folgas: use "Fechar agenda" na Agenda, com "Repetir toda semana".'),
      h('form', { class: 'secao', onSubmit: (/** @type {SubmitEvent} */ ev) => salvar(ev, async (fd) => {
          const linhas = DIAS.map((_, i) => ({ dia_semana: i, abre: fd.get(`abre${i}`) === 'on', inicio: String(fd.get(`ini${i}`)), fim: String(fd.get(`fim${i}`)) }))
            .filter((l) => l.abre);
          if (linhas.some((l) => !l.inicio || !l.fim || l.fim <= l.inicio)) throw new Error('Confere os horários: o fim precisa ser depois do início.');
          const novas = linhas.map((l) => ({ barbeiro_id: barbeiroHorario, dia_semana: l.dia_semana, inicio: l.inicio, fim: l.fim }));
          // Uma chamada só: ou grava todos os dias, ou não mexe em nada
          await rpc('salvar_horarios', { p_barbeiro: barbeiroHorario, p_horarios: novas.map((n) => ({ dia_semana: n.dia_semana, inicio: n.inicio, fim: n.fim })) });
          d.horarios = [...d.horarios.filter((/** @type {any} */ x) => x.barbeiro_id !== barbeiroHorario), ...novas];
        }, 'Horários salvos.') },
        DIAS.map((nome, i) => {
          const atual = doBarbeiro.find((/** @type {any} */ x) => x.dia_semana === i);
          return h('div', { style: 'display:grid;grid-template-columns:1.2fr 1fr 1fr;gap:8px;align-items:center' },
            h('label', { class: 'check' }, h('input', { type: 'checkbox', name: `abre${i}`, checked: !!atual }), h('span', null, nome)),
            entrada({ type: 'time', name: `ini${i}`, value: atual?.inicio?.slice(0, 5) ?? '09:00', 'aria-label': `${nome}, abre às` }),
            entrada({ type: 'time', name: `fim${i}`, value: atual?.fim?.slice(0, 5) ?? '19:30', 'aria-label': `${nome}, fecha às` }));
        }),
        h('button', { type: 'submit', class: 'btn btn--escuro btn--peq' }, 'Salvar horários'),
      ),
    ),
  );
  return elHorarios;
}

function secaoFormas() {
  return h('details', { class: 'painel' },
    h('summary', null, 'Formas de pagamento e taxas'),
    h('div', { class: 'painel-corpo' },
      h('p', { class: 'ajuda' }, 'Coloque a taxa da maquininha (InfinitePay) no crédito e no débito. O caixa mostra bruto e líquido.'),
      d.formas.map((/** @type {any} */ f) => h('form', { class: 'linha', style: 'padding:6px 0;gap:8px', onSubmit: (/** @type {SubmitEvent} */ ev) => salvar(ev, async (fd) => {
          const taxa = Number(String(fd.get('taxa') || '0').replace(',', '.'));
          if (!Number.isFinite(taxa) || taxa < 0 || taxa > 30) throw new Error('Taxa inválida.');
          const dados = { taxa_percentual: taxa, ativa: fd.get('ativa') === 'on' };
          await ok(sb.from('formas_pagamento').update(dados).eq('id', f.id));
          Object.assign(f, dados);
        }, `${f.nome} salvo.`) },
        h('label', { class: 'check', style: 'flex:1' }, h('input', { type: 'checkbox', name: 'ativa', checked: f.ativa }), h('span', null, f.nome)),
        ['credito', 'debito'].includes(f.tipo)
          ? entrada({ name: 'taxa', inputmode: 'decimal', value: String(f.taxa_percentual).replace('.', ','), style: 'width:80px', 'aria-label': `Taxa ${f.nome} em %` })
          : h('input', { type: 'hidden', name: 'taxa', value: '0' }),
        ['credito', 'debito'].includes(f.tipo) && h('span', { class: 'ajuda' }, '%'),
        h('button', { type: 'submit', class: 'btn btn--claro btn--peq' }, 'Salvar'),
      )),
    ),
  );
}

function secaoRegras() {
  const c = d.cfg;
  return h('details', { class: 'painel' },
    h('summary', null, 'Dados da barbearia e regras'),
    h('form', { class: 'painel-corpo', onSubmit: (/** @type {SubmitEvent} */ ev) => salvar(ev, async (fd) => {
        const troco = String(fd.get('troco') || '').trim();
        const linhas = [
          ['whatsapp_barbearia', normalizarZap(String(fd.get('zap') || ''))],
          ['endereco', String(fd.get('endereco') || '').trim()],
          ['horario_texto', String(fd.get('horario_texto') || '').trim()],
          ['cancelamento_antecedencia_horas', inteiro(fd, 'cancelamento', 0)],
          ['intervalo_slots_min', inteiro(fd, 'intervalo', 5)],
          ['troco_inicial_padrao_centavos', troco === '' ? 0 : centavos(fd, 'troco', 'Troco')],
        ].map(([chave, valor]) => ({ chave, valor }));
        await ok(sb.from('configuracoes').upsert(linhas));
        for (const l of linhas) d.cfg[/** @type {string} */ (l.chave)] = l.valor;
      }, 'Dados salvos.') },
      campo('WhatsApp da barbearia', entrada({ name: 'zap', type: 'tel', value: String(c.whatsapp_barbearia ?? '').replace(/^55/, ''), placeholder: '31 90000-0000' })),
      campo('Endereço', entrada({ name: 'endereco', value: c.endereco ?? '' })),
      campo('Horário (texto que o cliente vê)', entrada({ name: 'horario_texto', value: c.horario_texto ?? '' })),
      h('div', { class: 'grade g2' },
        campo('Cancelar até (horas antes)', entrada({ name: 'cancelamento', type: 'number', min: 0, value: c.cancelamento_antecedencia_horas ?? 2 })),
        campo('Horários de quanto em quanto', h('select', { name: 'intervalo', class: 'entrada entrada--peq' },
          [15, 20, 30, 40, 60].map((m) => h('option', { value: m, selected: Number(c.intervalo_slots_min ?? 30) === m }, `${m} min`))))),
      campo('Troco inicial padrão (R$)', entrada({ name: 'troco', inputmode: 'decimal', value: centavosParaTexto(Number(c.troco_inicial_padrao_centavos ?? 0)) })),
      h('button', { type: 'submit', class: 'btn btn--escuro btn--peq' }, 'Salvar dados'),
    ),
  );
}

function secaoEquipe() {
  const linha = (/** @type {any} */ b) =>
    h('form', { class: 'linha', style: 'flex-wrap:wrap', onSubmit: (/** @type {SubmitEvent} */ ev) => salvar(ev, async (fd) => {
        const tipo = String(fd.get('comissao_tipo') || '');
        const valorTexto = String(fd.get('comissao_valor') || '').trim();
        /** @type {number | null} */ let valor = null;
        if (tipo === 'percentual') {
          valor = Number(valorTexto.replace(',', '.'));
          if (!valorTexto || !Number.isInteger(valor) || valor < 0 || valor > 100) throw new Error('Comissão em %: um número inteiro de 0 a 100.');
        } else if (tipo === 'fixo_por_corte') {
          valor = paraCentavos(valorTexto);
          if (Number.isNaN(valor)) throw new Error('Comissão por atendimento inválida. Usa o formato 15,00.');
        }
        const dados = { apelido: String(fd.get('apelido') || '').trim() || null, ativo: fd.get('ativo') === 'on',
                        comissao_tipo: tipo || null, comissao_valor: valor };
        await ok(sb.from('barbeiros').update(dados).eq('id', b.id));
        Object.assign(b, dados);
        return atualizarChipsHorarios;
      }, 'Barbeiro salvo.') },
      entrada({ name: 'apelido', value: b.apelido ?? b.nome, 'aria-label': 'Nome que o cliente vê', style: 'flex:1' }),
      h('label', { class: 'check' }, h('input', { type: 'checkbox', name: 'ativo', checked: b.ativo }), h('span', null, 'Ativo')),
      h('div', { class: 'grade g2', style: 'width:100%' },
        h('select', { name: 'comissao_tipo', class: 'entrada entrada--peq', 'aria-label': `Comissão de ${b.apelido || b.nome}` },
          h('option', { value: '', selected: !b.comissao_tipo }, 'Sem comissão'),
          h('option', { value: 'percentual', selected: b.comissao_tipo === 'percentual' }, '% do serviço'),
          h('option', { value: 'fixo_por_corte', selected: b.comissao_tipo === 'fixo_por_corte' }, 'R$ por atendimento')),
        entrada({ name: 'comissao_valor', inputmode: 'decimal', 'aria-label': `Valor da comissão de ${b.apelido || b.nome}`, placeholder: '40 ou 15,00',
                  value: b.comissao_tipo === 'percentual' ? String(b.comissao_valor ?? '') : b.comissao_tipo === 'fixo_por_corte' ? centavosParaTexto(b.comissao_valor ?? 0) : '' })),
      h('button', { type: 'submit', class: 'btn btn--claro btn--peq' }, 'Salvar'));
  const lista = h('div', { class: 'lista' }, d.barbeiros.map(linha));
  return h('details', { class: 'painel' },
    h('summary', null, 'Equipe'),
    h('div', { class: 'painel-corpo' },
      lista,
      h('form', { class: 'secao', onSubmit: (/** @type {SubmitEvent} */ ev) => salvar(ev, async (fd) => {
          const nome = String(fd.get('novo') || '').trim();
          if (nome.length < 2) throw new Error('Coloca o nome do barbeiro.');
          const criado = await ok(sb.from('barbeiros').insert({ nome, apelido: nome }).select().single());
          d.barbeiros.push(criado);
          barbeiroHorario = barbeiroHorario || criado.id;
          const campoNovo = /** @type {HTMLInputElement} */ (/** @type {HTMLFormElement} */ (ev.target).elements.namedItem('novo'));
          return () => { lista.append(linha(criado)); campoNovo.value = ''; atualizarChipsHorarios(); };
        }, 'Barbeiro adicionado. Agora configure os dias e horários dele.') },
        campo('Novo barbeiro', entrada({ name: 'novo', placeholder: 'Nome' })),
        h('button', { type: 'submit', class: 'btn btn--escuro btn--peq' }, 'Adicionar barbeiro')),
      h('p', { class: 'ajuda' }, 'Comissão: "% do serviço" é a porcentagem sobre o valor dos serviços (com desconto); "R$ por atendimento" é um valor fixo por cliente atendido. O resultado do mês aparece no Início. Login próprio do barbeiro: em "Logins da equipe".'),
    ),
  );
}

function secaoLogins() {
  const nomeBarbeiro = (/** @type {string | null} */ id) => {
    const b = d.barbeiros.find((/** @type {any} */ x) => x.id === id);
    return b ? (b.apelido || b.nome) : '—';
  };
  const lista = h('div', { class: 'lista' });
  const desenhar = () => montar(lista, d.logins.map((/** @type {any} */ l) => h('div', { class: 'linha', style: 'flex-wrap:wrap' },
    h('div', { class: 'linha-textos' },
      h('span', { class: 'linha-titulo' }, l.email ?? l.nome),
      h('span', { class: 'ajuda' }, `${l.papel === 'dono' ? 'Dono' : `Barbeiro · ${nomeBarbeiro(l.barbeiro_id)}`}${l.ativo ? '' : ' · acesso desligado'}${l.eu ? ' · você' : ''}`)),
    !l.eu && h('button', { type: 'button', class: 'btn btn--claro btn--peq', onClick: async (/** @type {Event} */ ev) => {
        const botao = /** @type {HTMLButtonElement} */ (ev.currentTarget);
        botao.disabled = true;
        try {
          await rpc('mudar_login_ativo', { p_perfil: l.id, p_ativo: !l.ativo });
          l.ativo = !l.ativo;
          toast(l.ativo ? 'Acesso religado.' : 'Acesso desligado.', 'ok');
          desenhar();
        } catch (e) { mostrarErro(e); botao.disabled = false; }
      } }, l.ativo ? 'Desligar acesso' : 'Religar acesso'))));
  desenhar();
  return h('details', { class: 'painel' },
    h('summary', null, 'Logins da equipe'),
    h('div', { class: 'painel-corpo' },
      lista,
      h('form', { class: 'secao', onSubmit: (/** @type {SubmitEvent} */ ev) => salvar(ev, async (fd) => {
          await rpc('vincular_login', { p_email: String(fd.get('email') || ''), p_barbeiro_id: fd.get('barbeiro') });
          d.logins = await rpc('equipe_logins');
          const form = /** @type {HTMLFormElement} */ (ev.target);
          return () => { desenhar(); form.reset(); };
        }, 'Login ligado. Ele já pode entrar com o e-mail e a senha dele.') },
        h('strong', null, 'Ligar login a um barbeiro'),
        h('p', { class: 'ajuda' }, '1. No Supabase, em Authentication › Users › Add user, crie o login com e-mail e senha (marque Auto Confirm User). 2. Aqui, coloque o mesmo e-mail e escolha o barbeiro.'),
        campo('E-mail do login', entrada({ name: 'email', type: 'email', required: true, autocomplete: 'off' })),
        campo('Barbeiro', h('select', { name: 'barbeiro', class: 'entrada entrada--peq', required: true },
          d.barbeiros.map((/** @type {any} */ b) => h('option', { value: b.id }, b.apelido || b.nome)))),
        h('button', { type: 'submit', class: 'btn btn--escuro btn--peq' }, 'Ligar login')),
    ),
  );
}

const TIPOS_MENSAGEM = /** @type {const} */ ([
  ['confirmacao', 'Confirmação', 'assim que o cliente marca'],
  ['lembrete', 'Lembrete', 'antes do horário, pra quem aceitou'],
  ['horario_mudou', 'Horário mudou', 'atraso ou remarcação'],
  ['cancelado', 'Horário cancelado', 'agenda fechada ou cancelado pela barbearia'],
  ['cobranca_plano', 'Cobrança de plano', '1 dia depois de vencer'],
  ['sumido', 'Chamar sumido', '30+ dias sem vir · mensagem de marketing, a mais cara'],
]);
const NOME_TIPO = Object.fromEntries(TIPOS_MENSAGEM.map(([id, nome]) => [id, nome]));
const STATUS_MENSAGEM = { pendente: 'Na fila', enviando: 'Enviando', enviada: 'Enviada', erro: 'Erro', cancelada: 'Cancelada' };
const fmtQuando = new Intl.DateTimeFormat('pt-BR', { timeZone: FUSO, day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });

/** Situação da ligação com a Meta, pelo último contato da função de envio. @param {any} s */
function situacaoWhatsapp(s) {
  if (!s?.ultimo_contato) return { classe: 'tag', texto: 'Aguardando ativação' };
  if (s.conectado) return { classe: 'tag tag--ok', texto: 'Conectado' };
  if (/Aguardando a chave/i.test(s.erro ?? '')) return { classe: 'tag', texto: 'Aguardando a chave da API' };
  return { classe: 'tag tag--erro', texto: 'Erro de conexão' };
}

function secaoMensagens() {
  const m = d.msgs;
  const c = m.config ?? {};
  const sit = situacaoWhatsapp(m.status);
  return h('details', { class: 'painel' },
    h('summary', null, 'Mensagens automáticas'),
    h('form', { class: 'painel-corpo', onSubmit: (/** @type {SubmitEvent} */ ev) => salvar(ev, async (fd) => {
        const config = { ativo: fd.get('ativo') === 'on', ...Object.fromEntries(TIPOS_MENSAGEM.map(([id]) => [id, fd.get(id) === 'on'])) };
        const site = String(fd.get('site') || '').trim();
        const horas = inteiro(fd, 'horas', 1);
        await rpc('salvar_mensagens_automaticas', { p_config: config, p_site_url: site, p_lembrete_horas: horas });
        d.msgs = await rpc('mensagens_painel');
      }, 'Mensagens automáticas salvas.') },
      h('div', { class: 'secao-cabeca', style: 'align-items:center' },
        h('span', { class: 'rotulo' }, 'WhatsApp oficial'),
        h('span', { class: sit.classe }, sit.texto)),
      m.status?.erro && m.status?.ultimo_contato && !m.status?.conectado && !/Aguardando a chave/i.test(m.status.erro)
        && h('p', { class: 'aviso aviso--erro' }, `Último erro da Meta: ${m.status.erro}`),
      h('p', { class: 'ajuda' }, 'As mensagens saem sozinhas pela API oficial do WhatsApp, com custo por mensagem cobrado pela Meta. Enquanto a API não for ativada (LEIA-ME, passo 8), nada é enviado e os botões de "Avisar" e "Lembrar" continuam funcionando como sempre.'),
      h('label', { class: 'check' }, h('input', { type: 'checkbox', name: 'ativo', checked: !!c.ativo }), h('strong', null, 'Ligar mensagens automáticas')),
      h('fieldset', { class: 'secao', style: 'border:none;padding:0;margin:0;gap:8px' },
        h('legend', { class: 'rotulo', style: 'margin-bottom:8px' }, 'Quais mensagens'),
        TIPOS_MENSAGEM.map(([id, nome, quando]) => h('label', { class: 'check' },
          h('input', { type: 'checkbox', name: id, checked: !!c[id] }),
          h('span', null, h('span', null, nome), h('span', { class: 'ajuda', style: 'display:block' }, quando))))),
      h('div', { class: 'grade g2' },
        campo('Lembrete quantas horas antes', entrada({ name: 'horas', type: 'number', min: 1, max: 48, value: m.lembrete_horas ?? 1 })),
        campo('Endereço do site', entrada({ name: 'site', type: 'url', value: m.site_url ?? '', placeholder: 'https://…' }))),
      h('p', { class: 'ajuda' }, 'O endereço do site entra nos links das mensagens (Minha área e marcar de novo).'),
      h('button', { type: 'submit', class: 'btn btn--escuro btn--peq' }, 'Salvar mensagens'),
      h('div', { class: 'metricas' },
        h('div', { class: 'metrica' }, h('span', { class: 'metrica-rotulo' }, 'Enviadas (7 dias)'), h('span', { class: 'metrica-valor' }, String(m.semana?.enviadas ?? 0))),
        h('div', { class: 'metrica' }, h('span', { class: 'metrica-rotulo' }, 'Na fila'), h('span', { class: 'metrica-valor' }, String(m.semana?.na_fila ?? 0))),
        h('div', { class: 'metrica' }, h('span', { class: 'metrica-rotulo' }, 'Com erro'), h('span', { class: `metrica-valor${m.semana?.erros ? ' negativo' : ''}` }, String(m.semana?.erros ?? 0)))),
      (m.ultimas ?? []).length > 0 && h('div', { class: 'lista' }, m.ultimas.slice(0, 10).map((/** @type {any} */ x) => h('div', { class: 'linha' },
        h('div', { class: 'linha-textos' },
          h('span', { class: 'linha-titulo' }, `${NOME_TIPO[x.tipo] ?? x.tipo} · ${x.cliente ?? '—'}`),
          h('span', { class: 'ajuda' }, `${fmtQuando.format(new Date(x.quando))}${x.erro && x.status !== 'enviada' ? ` · ${x.erro}` : ''}`)),
        h('span', { class: `tag ${x.status === 'enviada' ? 'tag--ok' : x.status === 'erro' ? 'tag--erro' : x.status === 'cancelada' ? '' : 'tag--info'}` },
          STATUS_MENSAGEM[/** @type {'pendente'} */ (x.status)] ?? x.status)))),
    ),
  );
}

function secaoPix() {
  const c = d.cfg;
  const chave = String(c.pix_chave ?? '');
  const tipo = chave ? tipoDaChave(chave) : 'celular';
  const mostrar = chave.startsWith('+55') ? chave.slice(3) : chave;
  return h('details', { class: 'painel', open: !chave },
    h('summary', null, chave ? 'Recebimento por Pix' : 'Recebimento por Pix · Definir'),
    h('form', { class: 'painel-corpo', onSubmit: (/** @type {SubmitEvent} */ ev) => salvar(ev, async (fd) => {
        const chaveNova = normalizarChavePix(/** @type {any} */ (String(fd.get('tipo'))), String(fd.get('chave') || ''));
        const nome = String(fd.get('nome') || '').trim();
        const cidade = String(fd.get('cidade') || '').trim();
        if (nome.length < 2) throw new Error('Coloca o nome de quem recebe.');
        if (cidade.length < 2) throw new Error('Coloca a cidade.');
        const linhas = [['pix_chave', chaveNova], ['pix_nome', nome], ['pix_cidade', cidade]].map(([k, valor]) => ({ chave: k, valor }));
        await ok(sb.from('configuracoes').upsert(linhas));
        for (const l of linhas) d.cfg[l.chave] = l.valor;
      }, 'Pix salvo. O copia e cola já aparece no finalizar e nos planos.') },
      h('p', { class: 'ajuda' }, 'Com a chave cadastrada, o finalizar e a cobrança de plano mostram o Pix copia e cola com o valor certo. O dinheiro cai direto na conta da chave.'),
      campo('Tipo da chave', h('select', { name: 'tipo', class: 'entrada entrada--peq' },
        [['celular', 'Celular'], ['cpf_cnpj', 'CPF ou CNPJ'], ['email', 'E-mail'], ['aleatoria', 'Chave aleatória']].map(([v, r]) =>
          h('option', { value: v, selected: v === tipo }, r)))),
      campo('Chave Pix', entrada({ name: 'chave', value: mostrar, placeholder: 'Ex.: 31 99999-8888', autocomplete: 'off' })),
      h('div', { class: 'grade g2' },
        campo('Nome de quem recebe', entrada({ name: 'nome', value: c.pix_nome ?? '', maxlength: 25 })),
        campo('Cidade', entrada({ name: 'cidade', value: c.pix_cidade ?? '', maxlength: 15 }))),
      h('p', { class: 'ajuda' }, 'Nome e cidade aparecem no app do banco de quem paga (sem acento, até 25 e 15 letras).'),
      h('button', { type: 'submit', class: 'btn btn--escuro btn--peq' }, 'Salvar Pix'),
    ),
  );
}

function render() {
  montar(app,
    h('div', { class: 'poste', 'aria-hidden': 'true' }),
    h('header', { class: 'topo', style: 'justify-content:flex-start' }, perfil.papel === 'dono' && h('a', { class: 'btn-icone', href: 'index.html', 'aria-label': 'Voltar pro início' }, icone('voltar')), h('div', { class: 'topo-textos' }, h('span', { class: 'sub' }, `Olá, ${perfil.nome}`), h('span', { class: 'titulo' }, 'Ajustes'))),
    !d ? h('main', { class: 'conteudo' }, carregando())
      : h('main', { class: 'conteudo', style: 'gap:12px' }, secaoServicos(), secaoHorarios(), secaoFormas(), secaoPix(), secaoRegras(), secaoMensagens(), secaoEquipe(), secaoLogins(),
          h('button', { type: 'button', class: 'btn btn--claro', style: 'margin-top:12px', onClick: sair }, 'Sair da conta')),
    tabbar('config', perfil),
  );
}

function iniciar() {
  render();
  carregar().catch((e) => telaErro(app, e, iniciar));
}

iniciar();
