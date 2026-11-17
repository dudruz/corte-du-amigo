// @ts-check
import { sb, traduzirErro } from './supabase.js';
import { telaErro } from './ui/dom.js';

/**
 * @typedef {{ id: string, nome: string, papel: 'dono' | 'barbeiro', barbeiro_id: string | null }} Perfil
 */

/**
 * Mostra o erro na tela, com "Tentar de novo", e interrompe a página.
 * @param {unknown} erro
 * @returns {never}
 */
function pararComErro(erro) {
  const app = document.getElementById('app');
  if (app) telaErro(app, erro);
  throw erro;
}

/**
 * Protege as páginas da equipe. Sem login vai pro login; barbeiro em página de dono vai pra agenda.
 * Falha de internet ou do banco não desloga ninguém: a sessão continua valendo e a pessoa só
 * precisa tentar de novo. Quem sai é só quem não tem perfil ou foi desativado.
 * @param {{ somenteDono?: boolean }} [opcoes]
 * @returns {Promise<Perfil>}
 */
export async function exigirEquipe({ somenteDono = false } = {}) {
  let sessao;
  try {
    sessao = await sb.auth.getSession();
  } catch (e) {
    return pararComErro(traduzirErro(/** @type {any} */ (e)));
  }
  const session = sessao.data.session;
  if (!session) {
    // Sem internet a renovação da sessão falha, mas o login guardado no aparelho continua lá
    if (sessao.error && traduzirErro(sessao.error).rede) pararComErro(traduzirErro(sessao.error));
    location.replace('login.html');
    throw new Error('Sem sessão');
  }
  let resposta;
  try {
    resposta = await sb
      .from('perfis')
      .select('id, nome, papel, barbeiro_id, ativo')
      .eq('id', session.user.id)
      .maybeSingle();
  } catch (e) {
    return pararComErro(traduzirErro(/** @type {any} */ (e)));
  }
  if (resposta.error) pararComErro(traduzirErro(resposta.error));
  const perfil = resposta.data;
  if (!perfil || !perfil.ativo) {
    // scope 'local' apaga a sessão do aparelho sem depender do servidor. Se a sessão ficasse,
    // o login mandaria de volta pra agenda e a agenda de volta pro login, sem parar.
    await sb.auth.signOut({ scope: 'local' }).catch(() => {});
    location.replace('login.html?erro=perfil');
    throw new Error('Sem perfil');
  }
  if (somenteDono && perfil.papel !== 'dono') {
    location.replace('agenda.html');
    throw new Error('Só dono');
  }
  return /** @type {Perfil} */ (perfil);
}

export async function sair() {
  await sb.auth.signOut();
  location.replace('login.html');
}
