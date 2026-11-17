// @ts-check
import { rpc } from '../supabase.js';
import { h, montar, poste, carregando, telaErro } from '../ui/dom.js';
import { icone } from '../ui/icones.js';
import { mostrarErro } from '../ui/toast.js';
import { hora, dataLonga, semanaCurta, diaDoMes } from '../lib/formatar.js';
import { rascunho } from '../lib/armazenamento.js';

const app = /** @type {HTMLElement} */ (document.getElementById('app'));
const r = rascunho.ler();

const remarcando = !!r?.remarcar;
/** @type {any} */ let dados;
/** @type {string | null} */ let barbeiro = r?.barbeiro_id ?? null;
/** Barbeiro dos dias e horários que estão na tela. @type {string | null} */ let barbeiroNaTela = barbeiro;
/** @type {{dia: string, livre: boolean}[]} */ let dias = [];
/** @type {string | null} */ let diaSel = null;
/** @type {{inicio: string, barbeiro_id: string}[] | null} */ let slots = null;
/** @type {{inicio: string, barbeiro_id: string} | null} */ let slotSel = null;
/** @type {unknown} */ let erroSlots = null;
let enviando = false;
// Cada busca de dias ou horários ganha um número. Quem troca de dia ou barbeiro rápido
// dispara várias, e a resposta só vale se ainda for a da última escolha.
let pedido = 0;

async function carregarDias() {
  const meu = ++pedido;
  let resposta;
  try {
    resposta = await rpc('dias_disponiveis', { p_servico_ids: r?.servicos, p_barbeiro_id: barbeiro, p_qtd: 14 });
  } catch (e) {
    if (meu !== pedido) return;
    throw e;
  }
  if (meu !== pedido) return;
  dias = resposta;
  barbeiroNaTela = barbeiro;
  diaSel = dias.find((d) => d.livre)?.dia ?? null;
  await carregarSlots();
}

async function carregarSlots() {
  const meu = ++pedido;
  slots = null; slotSel = null; erroSlots = null; render();
  try {
    const resposta = diaSel ? await rpc('horarios_livres', { p_servico_ids: r?.servicos, p_barbeiro_id: barbeiro, p_dia: diaSel }) : [];
    if (meu !== pedido) return;
    slots = resposta;
  } catch (e) {
    if (meu !== pedido) return;
    slots = []; erroSlots = e;
  }
  render();
}

const nomeBarbeiro = (/** @type {string | null} */ id) => dados.barbeiros.find((/** @type {any} */ b) => b.id === id)?.nome ?? '';

async function continuar() {
  if (!slotSel || enviando) return;
  if (remarcando) {
    enviando = true; render();
    try {
      const token = await rpc('remarcar_por_token', { p_token: r?.remarcar, p_novo_inicio: slotSel.inicio });
      rascunho.limpar();
      location.href = `agendado.html?t=${token}&remarcado=1`;
    } catch (e) {
      mostrarErro(e); enviando = false; await carregarSlots();
    }
    return;
  }
  rascunho.gravar({ ...r, servicos: r?.servicos ?? [], barbeiro_id: slotSel.barbeiro_id, inicio: slotSel.inicio });
  location.href = 'dados.html';
}

function render() {
  const varios = dados.barbeiros.length > 1;
  montar(app,
    poste(),
    h('header', { class: 'topo', style: 'justify-content:flex-start' },
      h('a', { class: 'btn-icone', href: remarcando ? `minha-area.html?t=${r?.remarcar}` : 'index.html', 'aria-label': 'Voltar' }, icone('voltar')),
      h('div', { class: 'topo-textos' },
        h('span', { class: 'sub' }, remarcando ? 'Remarcar horário' : 'Passo 2 de 3'),
        h('strong', null, varios && !remarcando ? 'Barbeiro e horário' : 'Escolha o horário'),
      ),
    ),
    h('main', { class: 'conteudo' },
      varios && !remarcando && h('section', { class: 'secao' },
        h('h2', { class: 'secao-titulo' }, 'Com quem?'),
        h('div', { class: 'chips' },
          [{ id: null, nome: 'Tanto faz' }, ...dados.barbeiros].map((b) =>
            h('button', {
              type: 'button', class: 'chip', 'aria-pressed': String(barbeiro === b.id),
              onClick: async () => {
                // Se a busca falha, os dias e horários na tela ainda são do barbeiro anterior.
                barbeiro = b.id;
                await carregarDias().catch((e) => { barbeiro = barbeiroNaTela; render(); mostrarErro(e); });
              },
            }, b.nome)),
        ),
      ),
      h('section', { class: 'secao' },
        h('h2', { class: 'secao-titulo' }, 'Que dia?'),
        dias.length === 0
          ? h('p', { class: 'aviso' }, 'Sem dias de atendimento nas próximas duas semanas.')
          : h('div', { class: 'dias' }, dias.map((d) =>
              h('button', {
                type: 'button', class: 'dia', disabled: !d.livre, 'aria-pressed': String(d.dia === diaSel),
                'aria-label': `${semanaCurta(d.dia)} ${diaDoMes(d.dia)}${d.livre ? '' : ', sem horário'}`,
                onClick: async () => { diaSel = d.dia; await carregarSlots().catch(mostrarErro); },
              }, h('span', { class: 'dia-sem' }, semanaCurta(d.dia)), h('span', { class: 'dia-num' }, diaDoMes(d.dia))))),
        h('span', { class: 'ajuda' }, 'Dia riscado: sem horário livre ou barbearia fechada.'),
      ),
      h('section', { class: 'secao' },
        h('h2', { class: 'secao-titulo' }, 'Horários livres'),
        slots === null ? carregando('Buscando horários…')
          : erroSlots ? h('div', { class: 'aviso' },
              h('p', null, erroSlots instanceof Error && erroSlots.message ? erroSlots.message : 'Não deu pra buscar os horários.'),
              h('button', { type: 'button', class: 'btn btn--contorno btn--peq', onClick: carregarSlots }, 'Tentar de novo'))
          : slots.length === 0 ? h('p', { class: 'aviso' }, 'Nenhum horário livre nesse dia. Tenta outro dia.')
          : h('div', { class: 'grade g4' }, slots.map((s) =>
              h('button', {
                type: 'button', class: 'slot', 'aria-pressed': String(slotSel?.inicio === s.inicio),
                onClick: () => { slotSel = s; render(); },
              }, hora(s.inicio)))),
      ),
    ),
    h('div', { class: 'rodape', style: 'flex-direction:row;align-items:center' },
      h('div', { class: 'topo-textos', style: 'flex:1' },
        h('span', { class: 'sub' }, slotSel ? `Com ${nomeBarbeiro(slotSel.barbeiro_id)}` : 'Escolha um horário'),
        h('strong', null, slotSel ? `${dataLonga(slotSel.inicio)} às ${hora(slotSel.inicio)}` : '—'),
      ),
      h('button', { type: 'button', class: 'btn btn--primario', disabled: !slotSel || enviando, onClick: continuar },
        remarcando ? (enviando ? 'Salvando…' : 'Remarcar') : 'Continuar'),
    ),
  );
}

async function iniciar() {
  if (!r || !r.servicos?.length) { location.replace('index.html'); return; }
  try {
    montar(app, poste(), carregando());
    dados = await rpc('dados_publicos');
    if (!barbeiro && dados.barbeiros.length === 1) barbeiro = dados.barbeiros[0].id;
    await carregarDias();
  } catch (e) {
    telaErro(app, e, iniciar);
  }
}

iniciar();
