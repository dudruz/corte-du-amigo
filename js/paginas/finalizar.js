// @ts-check
import { rpc } from '../supabase.js';
import { exigirEquipe } from '../auth.js';
import { h, montar, carregando, param } from '../ui/dom.js';
import { icone } from '../ui/icones.js';
import { mostrarErro, toast } from '../ui/toast.js';
import { dinheiro, hora, paraCentavos } from '../lib/formatar.js';
import { blocoPix } from '../ui/pix.js';

const app = /** @type {HTMLElement} */ (document.getElementById('app'));
await exigirEquipe();
const id = param('id');
if (!id) {
  location.replace('agenda.html');
  throw new Error('Sem agendamento');
}

/** @type {any} */ let info;
/** @type {Set<string>} */ const extras = new Set();
/** @type {any} */ let forma = null;
let gorjeta = 0;
// Os campos digitados guardam o texto como foi escrito, pra tela poder apontar o erro sem apagar nada.
// Em centavos, NaN quer dizer "digitou algo que não é valor" e nunca vai pro banco.
let descontoTexto = '';
let desconto = 0;
let recebidoTexto = '';
/** @type {number | null} null = ainda não informou */ let recebido = null;
let mostrarExtras = false;
let mostrarDesconto = false;
let enviando = false;

/** Nomes dos serviços (do agendamento e extras) que o plano do cliente não cobre. Plano sem lista cobre tudo. */
function foraDoPlano() {
  const incluidos = info.plano?.servicos_incluidos;
  if (!Array.isArray(incluidos) || incluidos.length === 0) return [];
  return [
    ...info.itens.map((/** @type {any} */ i) => ({ id: i.servico_id, nome: i.nome })),
    ...info.servicos.filter((/** @type {any} */ s) => extras.has(s.id)).map((/** @type {any} */ s) => ({ id: s.id, nome: s.nome })),
  ].filter((i) => !incluidos.includes(i.id)).map((i) => /** @type {string} */ (i.nome));
}

function calcular() {
  const base = info.itens.reduce((/** @type {number} */ t, /** @type {any} */ i) => t + i.preco_centavos, 0);
  const extra = info.servicos.filter((/** @type {any} */ s) => extras.has(s.id)).reduce((/** @type {number} */ t, /** @type {any} */ s) => t + s.preco_centavos, 0);
  const total = base + extra;
  const noPlano = forma?.tipo === 'plano';
  const fora = noPlano ? foraDoPlano() : [];
  // No plano não existe desconto (o campo nem aparece), então o que ficou digitado não conta
  const descontoErro = noPlano ? ''
    : Number.isNaN(desconto) ? 'Desconto inválido. Usa o formato 5,00.'
    : desconto > total ? `O desconto não pode passar do total (${dinheiro(total)}).`
    : '';
  // O plano só zera a conta quando cobre tudo que foi feito
  const cobrar = noPlano ? (fora.length ? total : 0) : total - (descontoErro ? 0 : desconto);
  const devido = cobrar + gorjeta;
  const taxa = Math.round(devido * Number(forma?.taxa_percentual || 0) / 100);
  const troco = forma?.tipo === 'dinheiro' && recebido != null && !Number.isNaN(recebido) ? recebido - devido : null;
  return { total, devido, taxa, troco, fora, descontoErro };
}

async function confirmar() {
  if (!forma || enviando) return;
  const c = calcular();
  if (c.fora.length) return;
  if (c.descontoErro) {
    mostrarErro(new Error(c.descontoErro));
    return;
  }
  if (forma.tipo === 'dinheiro' && Number.isNaN(recebido)) {
    mostrarErro(new Error('Valor recebido inválido. Usa o formato 70,00.'));
    return;
  }
  if (forma.tipo === 'dinheiro' && (recebido == null || recebido < c.devido)) {
    mostrarErro(new Error('Coloca quanto o cliente deu em dinheiro.'));
    return;
  }
  enviando = true; render();
  try {
    const r = await rpc('finalizar_atendimento', {
      p_id: id, p_forma_id: forma.id, p_extras: [...extras],
      p_desconto: forma.tipo === 'plano' ? 0 : desconto, p_gorjeta: gorjeta, p_recebido: forma.tipo === 'dinheiro' ? recebido : null,
    });
    toast(r.troco_centavos ? `Finalizado! Troco: ${dinheiro(r.troco_centavos)}` : 'Atendimento finalizado!', 'ok');
    setTimeout(() => location.replace('agenda.html'), 1400);
  } catch (e) {
    mostrarErro(e); enviando = false; render();
  }
}

function painelForma(/** @type {ReturnType<typeof calcular>} */ c) {
  if (!forma) return h('p', { class: 'ajuda' }, 'Escolha como o cliente pagou.');
  switch (forma.tipo) {
    case 'pix': return c.devido > 0 ? blocoPix(info.pix, c.devido) : h('p', { class: 'aviso' }, 'Nada a cobrar no Pix.');
    case 'dinheiro': {
      const sugestoes = [...new Set([c.devido, Math.ceil(c.devido / 1000) * 1000, Math.ceil(c.devido / 5000) * 5000, 10000])]
        .filter((v) => v >= c.devido).slice(0, 4);
      return h('div', { class: 'card' },
        h('span', { class: 'rotulo' }, 'Quanto o cliente deu?'),
        h('div', { class: 'grade g4' }, sugestoes.map((v) =>
          h('button', { type: 'button', class: 'botao-escolha', 'aria-pressed': String(recebido === v), onClick: () => { recebido = v; recebidoTexto = ''; render(); } },
            v === c.devido ? 'Exato' : dinheiro(v).replace(',00', '')))),
        h('div', { class: 'campo' },
          h('label', { for: 'recebido' }, 'Outro valor'),
          h('input', { id: 'recebido', class: 'entrada entrada--peq', inputmode: 'decimal', placeholder: 'Ex.: 70,00', value: recebidoTexto,
                       onChange: (/** @type {Event} */ ev) => {
                         recebidoTexto = /** @type {HTMLInputElement} */ (ev.target).value;
                         recebido = recebidoTexto.trim() === '' ? null : paraCentavos(recebidoTexto);
                         render();
                       } })),
        Number.isNaN(recebido) && h('p', { class: 'aviso aviso--erro', role: 'alert' }, 'Esse valor não deu pra entender. Usa o formato 70,00.'),
        c.troco != null && h('div', { class: 'secao-cabeca' },
          h('span', null, 'Troco'),
          h('strong', { class: c.troco < 0 ? 'negativo' : '' }, c.troco < 0 ? `Faltam ${dinheiro(-c.troco)}` : dinheiro(c.troco))),
      );
    }
    case 'credito': case 'debito':
      return h('p', { class: 'aviso' }, Number(forma.taxa_percentual) > 0
        ? `Taxa da maquininha: ${String(forma.taxa_percentual).replace('.', ',')}% (${dinheiro(c.taxa)}). Entra ${dinheiro(c.devido - c.taxa)} na conta.`
        : 'Taxa da maquininha ainda não cadastrada. O dono ajusta em Ajustes › Formas de pagamento.');
    case 'plano': {
      const p = info.plano;
      if (c.fora.length) {
        return h('p', { class: 'aviso aviso--alerta', role: 'alert' }, `Tem serviço fora do plano: ${c.fora.join(', ')}. Tira o extra ou cobra tudo em outra forma.`);
      }
      const restam = p?.usos_por_mes == null ? 'ilimitado' : `restam ${Math.max(0, p.usos_por_mes - p.usados - 1)} depois deste`;
      return h('p', { class: 'aviso aviso--info' }, `Desconta 1 uso do ${p?.nome ?? 'plano'} (${restam}). Não entra dinheiro no caixa agora.`);
    }
    case 'fiado':
      return h('p', { class: 'aviso aviso--alerta' }, `${info.cliente.nome} fica devendo ${dinheiro(c.devido)}. Aparece no Caixa até ele acertar.`);
    default: return null;
  }
}

function render() {
  const c = calcular();
  const a = info.agendamento;
  const planoOk = info.plano && info.plano.status === 'ativa' && (info.plano.usos_por_mes == null || info.plano.usados < info.plano.usos_por_mes);
  const formas = info.formas.filter((/** @type {any} */ f) => f.tipo !== 'plano' || planoOk);
  const disponiveis = info.servicos.filter((/** @type {any} */ s) => !info.itens.some((/** @type {any} */ i) => i.servico_id === s.id));
  const semCobertura = c.fora.length > 0;
  const peloPlano = forma?.tipo === 'plano' && !semCobertura;
  const nomeForma = forma ? { pix: 'no Pix', dinheiro: 'em dinheiro', credito: 'no crédito', debito: 'no débito', plano: 'pelo plano', fiado: 'no fiado' }[/** @type {'pix'} */ (forma.tipo)] : '';

  montar(app,
    h('header', { class: 'topo--escuro' },
      h('div', { class: 'topo-linha', style: 'justify-content:flex-start' },
        h('a', { class: 'btn-icone', href: 'agenda.html', 'aria-label': 'Voltar' }, icone('fechar')),
        h('div', { class: 'topo-textos' },
          h('span', { class: 'titulo-m' }, 'Finalizar atendimento'),
          h('span', { class: 'sub' }, `${info.cliente.nome} · ${hora(a.inicio)} · com ${a.barbeiro}`)),
      ),
      planoOk && h('span', { class: 'tag tag--info', style: 'align-self:flex-start' }, `Assinante · ${info.plano.nome}`),
    ),
    h('main', { class: 'conteudo', style: 'gap:18px' },
      h('section', { class: 'secao' },
        h('h2', { class: 'secao-titulo' }, 'O que foi feito'),
        h('div', { class: 'lista' },
          info.itens.map((/** @type {any} */ i) => h('div', { class: 'linha' }, h('span', { class: 'linha-textos linha-titulo' }, i.nome), h('span', { class: 'linha-valor' }, dinheiro(i.preco_centavos)))),
          info.servicos.filter((/** @type {any} */ s) => extras.has(s.id)).map((/** @type {any} */ s) =>
            h('div', { class: 'linha' },
              h('span', { class: 'linha-textos linha-titulo' }, `${s.nome} (adicionado)`),
              h('span', { class: 'linha-valor' }, dinheiro(s.preco_centavos)),
              h('button', { type: 'button', class: 'btn-icone', style: 'width:36px;height:36px;border:none', 'aria-label': `Tirar ${s.nome}`, onClick: () => { extras.delete(s.id); render(); } }, icone('fechar', 16)))),
        ),
        disponiveis.length > 0 && (mostrarExtras
          ? h('div', { class: 'chips' }, disponiveis.filter((/** @type {any} */ s) => !extras.has(s.id)).map((/** @type {any} */ s) =>
              h('button', { type: 'button', class: 'chip', onClick: () => { extras.add(s.id); mostrarExtras = false; render(); } }, `+ ${s.nome}`)))
          : h('button', { type: 'button', class: 'btn btn--texto', style: 'align-self:flex-start', onClick: () => { mostrarExtras = true; render(); } }, '+ Adicionar serviço')),
      ),
      h('section', { class: 'secao' },
        h('h2', { class: 'secao-titulo' }, 'Como pagou?'),
        h('div', { class: 'grade g3' }, formas.map((/** @type {any} */ f) =>
          h('button', { type: 'button', class: 'botao-escolha', 'aria-pressed': String(forma?.id === f.id),
                        onClick: () => { forma = f; recebido = null; recebidoTexto = ''; render(); } }, f.nome))),
        painelForma(c),
      ),
      h('section', { class: 'secao' },
        h('h2', { class: 'secao-titulo' }, 'Gorjeta'),
        h('div', { class: 'grade g4' }, [0, 500, 1000, 2000].map((v) =>
          h('button', { type: 'button', class: 'botao-escolha', 'aria-pressed': String(gorjeta === v), onClick: () => { gorjeta = v; render(); } },
            v === 0 ? 'Sem' : dinheiro(v).replace(',00', '')))),
        forma?.tipo !== 'plano' && (mostrarDesconto
          ? h('div', { class: 'campo' },
              h('label', { for: 'desconto' }, 'Desconto (R$)'),
              h('input', { id: 'desconto', class: 'entrada entrada--peq', inputmode: 'decimal', placeholder: 'Ex.: 5,00', value: descontoTexto,
                           onChange: (/** @type {Event} */ ev) => {
                             descontoTexto = /** @type {HTMLInputElement} */ (ev.target).value;
                             desconto = descontoTexto.trim() === '' ? 0 : paraCentavos(descontoTexto);
                             render();
                           } }))
          : h('button', { type: 'button', class: 'btn btn--texto', style: 'align-self:flex-start', onClick: () => { mostrarDesconto = true; render(); } }, '+ Dar desconto')),
        c.descontoErro && h('p', { class: 'aviso aviso--erro', role: 'alert' }, c.descontoErro),
        forma?.tipo !== 'plano' && !c.descontoErro && desconto > 0 && h('span', { class: 'ajuda' }, `Desconto de ${dinheiro(desconto)} aplicado.`),
      ),
    ),
    h('div', { class: 'rodape' },
      h('div', { class: 'rodape-linha' },
        h('span', { class: 'sub' }, peloPlano ? (gorjeta ? 'Só a gorjeta' : 'Nada a cobrar agora') : 'Total a receber'),
        h('span', { class: 'valor-grande' }, dinheiro(c.devido))),
      h('button', { type: 'button', class: 'btn btn--primario btn--bloco', disabled: !forma || enviando || semCobertura, onClick: confirmar },
        enviando ? 'Salvando…' : semCobertura ? 'Tem serviço fora do plano' : forma ? `Confirmar ${dinheiro(c.devido)} ${nomeForma}` : 'Escolha a forma de pagamento'),
    ),
  );
}

try {
  montar(app, carregando());
  info = await rpc('info_finalizar', { p_id: id });
  // Só horário marcado ou em atendimento tem o que cobrar
  const fechado = {
    finalizado: 'Esse atendimento já foi finalizado.',
    cancelado: 'Esse horário foi cancelado, então não tem o que cobrar.',
    faltou: 'Esse horário ficou como falta, então não tem o que cobrar.',
  }[/** @type {'finalizado'} */ (info.agendamento.status)];
  if (fechado) {
    montar(app, h('div', { class: 'vazio' }, fechado, h('a', { class: 'btn btn--escuro', href: 'agenda.html' }, 'Voltar pra agenda')));
  } else {
    render();
  }
} catch (e) {
  montar(app, h('div', { class: 'vazio' }, 'Não deu pra abrir esse atendimento.', h('a', { class: 'btn btn--escuro', href: 'agenda.html' }, 'Voltar pra agenda')));
  mostrarErro(e);
}
