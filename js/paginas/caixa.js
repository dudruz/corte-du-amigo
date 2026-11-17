// @ts-check
import { sb, rpc, traduzirErro } from '../supabase.js';
import { exigirEquipe } from '../auth.js';
import { h, montar, carregando, param, telaErro } from '../ui/dom.js';
import { icone } from '../ui/icones.js';
import { mostrarErro, toast } from '../ui/toast.js';
import { tabbar } from '../ui/tabbar.js';
import { dinheiro, hora, hojeISO, somarDias, semanaLonga, diaMes, paraCentavos, diaDoTimestamp } from '../lib/formatar.js';
import { linkWhats, mensagens } from '../lib/mensagens.js';

const app = /** @type {HTMLElement} */ (document.getElementById('app'));
const perfil = await exigirEquipe({ somenteDono: true });
const { data: formas, error: erroFormas } = await sb.from('formas_pagamento').select('id, nome, tipo').eq('ativa', true).order('ordem');
if (erroFormas) {
  const erro = traduzirErro(erroFormas);
  telaErro(app, erro);
  throw erro;
}
const formasDinheiro = (formas ?? []).filter((f) => !['plano', 'fiado'].includes(f.tipo));

let dia = param('dia') || hojeISO();
/** @type {any} */ let r = null;

// Número do último pedido de carga: trocando de dia rápido, a resposta (ou o erro) de um
// pedido mais antigo pode chegar depois e não pode cair em cima do dia que está na tela
let pedido = 0;

async function carregar() {
  const vez = ++pedido;
  r = null; render();
  try {
    const novo = await rpc('caixa_resumo', { p_dia: dia });
    if (vez !== pedido) return;
    r = novo;
    render();
  } catch (e) {
    if (vez === pedido) throw e;
  }
}

// Cada carga troca a tela por "Carregando…", então a falha precisa ocupar a tela com "Tentar de novo"
/** @returns {Promise<void>} */
const atualizar = () => carregar().catch((e) => telaErro(app, e, atualizar));

/** Lê um formulário, chama a ação e recarrega. @param {SubmitEvent} ev @param {(fd: FormData) => Promise<void>} acao */
async function enviar(ev, acao) {
  ev.preventDefault();
  const form = /** @type {HTMLFormElement} */ (ev.target);
  const botao = /** @type {HTMLButtonElement} */ (form.querySelector('button[type=submit]'));
  botao.disabled = true;
  try { await acao(new FormData(form)); }
  catch (e) { mostrarErro(e); botao.disabled = false; return; }
  await atualizar();
}

const valorDe = (/** @type {FormData} */ fd, /** @type {string} */ campo) => {
  const v = paraCentavos(String(fd.get(campo) || ''));
  if (Number.isNaN(v)) throw new Error('Valor inválido. Usa o formato 35,00.');
  return v;
};

const seletorForma = (/** @type {string} */ nome, /** @type {any[]} */ lista, /** @type {string | undefined} */ id = undefined) =>
  h('select', { name: nome, id, class: 'entrada entrada--peq', required: true, 'aria-label': 'Forma de pagamento' }, lista.map((f) => h('option', { value: f.id }, f.nome)));

function render() {
  const hoje = dia === hojeISO();
  const esperado = r ? r.esperado_dinheiro : 0;
  const fechado = r?.fechamento;
  // Movimento lançado depois do fechamento muda o que deveria ter na gaveta
  const desatualizado = fechado?.desatualizado === true;

  montar(app,
    h('div', { class: 'poste', 'aria-hidden': 'true' }),
    h('header', { class: 'topo', style: 'flex-direction:column;align-items:stretch;gap:12px' },
      h('div', { class: 'topo-linha' },
        h('div', { class: 'topo-textos' },
          h('span', { class: 'sub' }, `${hoje ? 'Hoje · ' : ''}${semanaLonga(dia)}, ${diaMes(dia)}`),
          h('span', { class: 'titulo' }, hoje ? 'Caixa de hoje' : 'Caixa do dia')),
        h('span', { class: `tag ${fechado ? (desatualizado ? 'tag--alerta' : '') : 'tag--ok'}` }, fechado ? (desatualizado ? 'Fechar de novo' : 'Fechado') : 'Aberto'),
      ),
      h('div', { class: 'topo-linha' },
        h('button', { type: 'button', class: 'btn-icone', 'aria-label': 'Dia anterior', onClick: () => { dia = somarDias(dia, -1); atualizar(); } }, icone('voltar')),
        !hoje && h('button', { type: 'button', class: 'chip', onClick: () => { dia = hojeISO(); atualizar(); } }, 'Voltar pra hoje'),
        h('button', { type: 'button', class: 'btn-icone', 'aria-label': 'Próximo dia', disabled: hoje, onClick: () => { dia = somarDias(dia, 1); atualizar(); } }, icone('avancar')),
      ),
    ),
    !r ? h('main', { class: 'conteudo' }, carregando()) : h('main', { class: 'conteudo', style: 'gap:14px' },
      h('div', { class: 'metricas' },
        h('div', { class: 'metrica' }, h('span', { class: 'metrica-rotulo' }, 'Entradas'), h('span', { class: 'metrica-valor positivo' }, dinheiro(r.entradas))),
        h('div', { class: 'metrica' }, h('span', { class: 'metrica-rotulo' }, 'Saídas'), h('span', { class: 'metrica-valor negativo' }, dinheiro(r.saidas))),
        h('div', { class: 'metrica metrica--escura' }, h('span', { class: 'metrica-rotulo' }, 'Saldo'), h('span', { class: 'metrica-valor' }, dinheiro(r.entradas - r.saidas))),
      ),
      r.entradas !== r.entradas_liquido && h('p', { class: 'ajuda' }, `Líquido depois das taxas da maquininha: ${dinheiro(r.entradas_liquido - r.saidas)}`),

      h('div', { class: 'card', style: 'gap:8px' },
        h('strong', null, `Deve ter na gaveta: ${dinheiro(esperado)}`),
        h('span', { class: 'ajuda' }, `Troco inicial ${dinheiro(r.troco_inicial)} + ${dinheiro(r.dinheiro_recebido)} recebidos − ${dinheiro(r.dinheiro_saidas)} de saídas, tudo em dinheiro.`),
        fechado && !desatualizado && h('span', { class: `tag ${fechado.diferenca_centavos === 0 ? 'tag--ok' : 'tag--alerta'}`, style: 'align-self:flex-start' },
          fechado.diferenca_centavos === 0 ? 'Fechou certinho'
            : `Contado ${dinheiro(fechado.contado_dinheiro_centavos)} · ${fechado.diferenca_centavos > 0 ? 'sobrou' : 'faltou'} ${dinheiro(Math.abs(fechado.diferenca_centavos))}`),
      ),
      desatualizado && h('p', { class: 'aviso aviso--alerta', role: 'alert' },
        'Entrou movimento depois que esse caixa foi fechado, então a conta do fechamento ficou velha. Conta a gaveta de novo e fecha outra vez ali embaixo, em "Refazer fechamento".'),

      r.fiados.length > 0 && h('section', { class: 'secao' },
        h('h2', { class: 'secao-titulo' }, `Fiado a receber · ${dinheiro(r.fiados.reduce((/** @type {number} */ t, /** @type {any} */ f) => t + f.valor, 0))}`),
        h('div', { class: 'lista' }, r.fiados.map((/** @type {any} */ f) =>
          h('form', { class: 'linha', style: 'flex-wrap:wrap', onSubmit: (/** @type {SubmitEvent} */ ev) => enviar(ev, async (fd) => {
              await rpc('quitar_fiado', { p_pagamento_id: f.pagamento_id, p_forma_id: fd.get('forma') });
              toast(`Fiado de ${f.cliente} acertado.`, 'ok');
            }) },
            h('div', { class: 'linha-textos' },
              h('span', { class: 'linha-titulo' }, `${f.cliente} · ${dinheiro(f.valor)}`),
              h('span', { class: 'ajuda' }, `Desde ${diaMes(diaDoTimestamp(f.data))}`)),
            h('a', { class: 'btn btn--claro btn--peq', href: linkWhats(f.telefone, mensagens.fiado(f.cliente, dinheiro(f.valor))), target: '_blank', rel: 'noopener', 'aria-label': `Cobrar ${f.cliente} no WhatsApp` }, icone('zap', 18)),
            h('div', { style: 'display:flex;gap:8px;width:100%' },
              seletorForma('forma', formasDinheiro),
              h('button', { type: 'submit', class: 'btn btn--escuro btn--peq' }, 'Recebi')),
          ))),
      ),

      h('section', { class: 'secao' },
        h('h2', { class: 'secao-titulo' }, 'Movimentos'),
        r.movimentos.length === 0 ? h('p', { class: 'vazio' }, 'Nenhum movimento nesse dia.')
          : h('div', { class: 'lista' }, r.movimentos.map((/** @type {any} */ m) =>
              h('div', { class: 'linha' },
                h('span', { class: 'ajuda', style: 'width:44px' }, hora(m.hora)),
                h('div', { class: 'linha-textos' },
                  h('span', { class: 'linha-titulo' }, m.descricao),
                  h('span', { class: 'ajuda' }, m.forma ? `${m.forma}${m.bruto !== m.liquido ? ` · líquido ${dinheiro(m.liquido)}` : ''}` : '')),
                h('span', { class: `linha-valor ${m.tipo === 'entrada' ? 'positivo' : 'negativo'}` }, `${m.tipo === 'entrada' ? '+' : '−'} ${dinheiro(m.bruto)}`),
              ))),
      ),

      h('details', { class: 'painel' },
        h('summary', null, 'Lançar despesa'),
        h('form', { class: 'painel-corpo', onSubmit: (/** @type {SubmitEvent} */ ev) => enviar(ev, async (fd) => {
            await rpc('lancar_despesa', { p_descricao: fd.get('descricao'), p_valor: valorDe(fd, 'valor'), p_forma_id: fd.get('forma'), p_dia: dia });
            toast('Despesa lançada.', 'ok');
          }) },
          h('div', { class: 'campo' }, h('label', { for: 'descricao' }, 'Do que foi'), h('input', { id: 'descricao', name: 'descricao', class: 'entrada entrada--peq', required: true, placeholder: 'Ex.: lâminas e talco' })),
          h('div', { class: 'grade g2' },
            h('div', { class: 'campo' }, h('label', { for: 'valor' }, 'Valor (R$)'), h('input', { id: 'valor', name: 'valor', class: 'entrada entrada--peq', inputmode: 'decimal', required: true, placeholder: '40,00' })),
            h('div', { class: 'campo' }, h('label', { for: 'forma-d' }, 'Pago com'), seletorForma('forma', formasDinheiro, 'forma-d'))),
          h('button', { type: 'submit', class: 'btn btn--escuro btn--peq' }, 'Lançar despesa'),
        ),
      ),
      h('details', { class: 'painel' },
        h('summary', null, 'Troco inicial do dia'),
        h('form', { class: 'painel-corpo', onSubmit: (/** @type {SubmitEvent} */ ev) => enviar(ev, async (fd) => {
            await rpc('definir_troco_inicial', { p_dia: dia, p_valor: valorDe(fd, 'troco') });
            toast('Troco inicial salvo.', 'ok');
          }) },
          h('div', { class: 'campo' }, h('label', { for: 'troco' }, 'Quanto tinha na gaveta ao abrir (R$)'), h('input', { id: 'troco', name: 'troco', class: 'entrada entrada--peq', inputmode: 'decimal', required: true, placeholder: '60,00' })),
          h('button', { type: 'submit', class: 'btn btn--escuro btn--peq' }, 'Salvar troco inicial'),
        ),
      ),
      h('details', { class: 'painel', open: desatualizado },
        h('summary', null, fechado ? 'Refazer fechamento' : 'Fechar caixa'),
        h('form', { class: 'painel-corpo', onSubmit: (/** @type {SubmitEvent} */ ev) => enviar(ev, async (fd) => {
            const res = await rpc('fechar_caixa', { p_dia: dia, p_contado: valorDe(fd, 'contado') });
            toast(res.diferenca === 0 ? 'Caixa fechado certinho!' : `Caixa fechado. ${res.diferenca > 0 ? 'Sobrou' : 'Faltou'} ${dinheiro(Math.abs(res.diferenca))}.`, res.diferenca === 0 ? 'ok' : 'neutro');
          }) },
          h('div', { class: 'campo' }, h('label', { for: 'contado' }, 'Quanto você contou em dinheiro na gaveta (R$)'), h('input', { id: 'contado', name: 'contado', class: 'entrada entrada--peq', inputmode: 'decimal', required: true })),
          h('button', { type: 'submit', class: 'btn btn--primario btn--peq' }, 'Fechar caixa'),
        ),
      ),
    ),
    tabbar('caixa', perfil),
  );
}

atualizar();
