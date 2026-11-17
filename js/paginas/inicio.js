// @ts-check
import { rpc } from '../supabase.js';
import { h, montar, poste, carregando, telaErro } from '../ui/dom.js';
import { icone } from '../ui/icones.js';
import { dinheiro, plural } from '../lib/formatar.js';
import { rascunho, ultimoToken } from '../lib/armazenamento.js';

const app = /** @type {HTMLElement} */ (document.getElementById('app'));
const anterior = rascunho.ler();
const selecionados = new Set(anterior && !anterior.remarcar ? anterior.servicos : []);
/** @type {any} */ let dados;

function render() {
  const token = ultimoToken();
  const n = selecionados.size;

  montar(app,
    poste(),
    h('header', { class: 'topo' },
      h('div', { class: 'topo-textos' },
        h('span', { class: 'marca' }, 'CORTE DÚ AMIGO'),
        h('span', { class: 'sub' }, dados.horario_texto || ''),
      ),
      token && h('a', { class: 'btn-icone', href: `minha-area.html?t=${token}`, 'aria-label': 'Meus horários' }, icone('usuario')),
    ),
    h('main', { class: 'conteudo' },
      h('h1', { class: 'titulo-xl' }, 'Bora marcar', h('br'), 'seu corte?'),
      token && h('a', { class: 'card card--azul', href: `minha-area.html?t=${token}`, style: 'text-decoration:none;flex-direction:row;align-items:center' },
        h('div', { class: 'topo-textos', style: 'flex:1' },
          h('strong', null, 'Já tem horário marcado?'),
          h('span', { class: 'sub' }, 'Veja, remarque ou cancele por aqui.'),
        ),
        icone('avancar'),
      ),
      h('section', { class: 'secao' },
        h('div', { class: 'secao-cabeca' },
          h('h2', { class: 'secao-titulo' }, 'Escolha o serviço'),
          h('span', { class: 'ajuda' }, 'pode marcar mais de um'),
        ),
        dados.servicos.length === 0
          ? h('p', { class: 'vazio' }, 'Nenhum serviço disponível no momento.')
          : dados.servicos.map((/** @type {any} */ s) => {
              const ativo = selecionados.has(s.id);
              return h('button', {
                type: 'button', class: 'opcao', 'aria-pressed': String(ativo),
                onClick: () => { ativo ? selecionados.delete(s.id) : selecionados.add(s.id); render(); },
              },
                h('span', { class: 'opcao-icone' }, icone('tesoura')),
                h('span', { class: 'opcao-textos' },
                  h('span', { class: 'opcao-nome' }, s.nome),
                  h('span', { class: 'sub' }, `${dinheiro(s.preco_centavos)} · ${s.duracao_min} min`),
                ),
                h('span', { class: 'marcador' }, ativo && icone('check', 16, 3)),
              );
            }),
      ),
    ),
    h('div', { class: 'rodape' },
      h('button', {
        type: 'button', class: 'btn btn--primario btn--bloco', disabled: n === 0,
        onClick: () => { rascunho.gravar({ servicos: [...selecionados] }); location.href = 'horario.html'; },
      }, n === 0 ? 'Escolha um serviço' : `Escolher horário · ${plural(n, 'serviço', 'serviços')}`),
    ),
  );
}

async function iniciar() {
  try {
    montar(app, poste(), carregando());
    dados = await rpc('dados_publicos');
    render();
  } catch (e) {
    telaErro(app, e, iniciar);
  }
}

iniciar();
