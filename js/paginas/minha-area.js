// @ts-check
import { rpc } from '../supabase.js';
import { h, montar, poste, carregando, param, telaErro } from '../ui/dom.js';
import { mostrarErro, toast } from '../ui/toast.js';
import { hora, dataLonga, diaDoTimestamp, diaMes } from '../lib/formatar.js';
import { rascunho, ultimoToken, guardarToken, meusTokens, tokenValido } from '../lib/armazenamento.js';

const app = /** @type {HTMLElement} */ (document.getElementById('app'));
const token = param('t') || ultimoToken();

function semHorario() {
  montar(app, poste(),
    h('main', { class: 'conteudo' },
      h('h1', { class: 'titulo' }, 'Meus horários'),
      h('div', { class: 'vazio' },
        'Não encontramos horário marcado neste aparelho. Se você marcou em outro, abre o link que mandou pro seu WhatsApp.',
        h('a', { class: 'btn btn--primario', href: 'index.html' }, 'Marcar um horário')),
    ));
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

let cancelando = false;

async function cancelar(/** @type {any} */ a) {
  if (cancelando) return;
  if (!confirm(`Cancelar o horário de ${dataLonga(a.inicio)} às ${hora(a.inicio)}?`)) return;
  cancelando = true;
  try {
    await rpc('cancelar_por_token', { p_token: a.token });
  } catch (e) { mostrarErro(e); return; } finally { cancelando = false; }
  toast('Horário cancelado.', 'ok');
  abrir();
}

function remarcar(/** @type {any} */ a) {
  rascunho.gravar({ servicos: a.servico_ids, barbeiro_id: a.barbeiro_id, remarcar: a.token });
  location.href = 'horario.html';
}

async function iniciar() {
  if (!token) { semHorario(); return; }
  if (!tokenValido(token)) { linkInvalido(); return; }
  montar(app, poste(), carregando());

  // O banco só devolve agendamento de quem tem o token (telefone não prova identidade),
  // então a lista sai dos tokens guardados neste aparelho. O token aberto entra na mão
  // porque em aba anônima o aparelho não guarda nada.
  const tokens = [token, ...meusTokens().filter((t) => t !== token)];
  const [info, lista] = await Promise.all([
    rpc('agendamento_por_token', { p_token: token }),
    rpc('agendamentos_por_tokens', { p_tokens: tokens }),
  ]);
  if (!info) { linkInvalido(); return; }
  guardarToken(token);

  const horas = info.cancelamento_horas;
  const agora = Date.now();
  const limite = agora + horas * 3600_000;
  const quando = (/** @type {any} */ a) => new Date(a.inicio).getTime();
  /** @type {any[]} */
  const todos = lista || [];
  const proximos = todos.filter((a) => a.status === 'marcado' && quando(a) > agora);
  const historico = todos.filter((a) => a.status === 'finalizado').sort((a, b) => quando(b) - quando(a)).slice(0, 5);

  montar(app,
    poste(),
    h('header', { class: 'topo' },
      h('div', { class: 'topo-textos' },
        h('span', { class: 'sub' }, 'Corte DÚ Amigo'),
        h('span', { class: 'titulo' }, `Fala, ${String(info.cliente.nome || '').split(' ')[0]}!`),
      ),
    ),
    h('main', { class: 'conteudo' },
      h('section', { class: 'secao' },
        h('h2', { class: 'secao-titulo' }, proximos.length > 1 ? 'Próximos horários' : 'Próximo horário'),
        proximos.length === 0
          ? h('p', { class: 'aviso' }, 'Nenhum horário marcado.')
          : proximos.map((a) => {
              const podeMexer = quando(a) > limite;
              return h('div', { class: 'card card--destaque' },
                h('div', { class: 'topo-textos' },
                  h('span', { class: 'titulo-m' }, `${dataLonga(a.inicio)} · ${hora(a.inicio)}`),
                  h('span', { class: 'sub' }, `${a.servicos.join(' + ')} com ${a.barbeiro}`),
                ),
                podeMexer
                  ? h('div', { class: 'grade g2' },
                      h('button', { type: 'button', class: 'btn btn--escuro btn--peq', onClick: () => remarcar(a) }, 'Remarcar'),
                      h('button', { type: 'button', class: 'btn btn--claro btn--peq', style: 'color:var(--erro);font-weight:700', onClick: () => cancelar(a) }, 'Cancelar'))
                  : h('p', { class: 'ajuda' }, `Faltam menos de ${horas} horas. Pra mudar, chama a barbearia no WhatsApp.`),
              );
            }),
      ),
      historico.length > 0 && h('section', { class: 'secao' },
        h('h2', { class: 'secao-titulo' }, 'Últimas visitas'),
        h('div', { class: 'lista' }, historico.map((a) =>
          h('div', { class: 'linha' },
            h('div', { class: 'linha-textos' },
              h('span', { class: 'linha-titulo' }, a.servicos.join(' + ')),
              h('span', { class: 'ajuda' }, `${diaMes(diaDoTimestamp(a.inicio))} · com ${a.barbeiro}`)),
          ))),
      ),
    ),
    h('div', { class: 'rodape' },
      h('a', { class: 'btn btn--primario btn--bloco', href: 'index.html' }, 'Marcar outro horário'),
    ),
  );
}

function abrir() {
  iniciar().catch((e) => telaErro(app, e, abrir));
}

abrir();
