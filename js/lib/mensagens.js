// @ts-check
import { NOME_BARBEARIA } from '../config.js';

/** @param {string} telefone @param {string} texto */
export const linkWhats = (telefone, texto) =>
  `https://wa.me/${String(telefone).replace(/\D/g, '')}?text=${encodeURIComponent(texto)}`;

/** URL absoluta de uma página do site, funcionando dentro ou fora de /equipe/. @param {string} arquivo */
export function urlDoSite(arquivo) {
  const raiz = location.pathname.includes('/equipe/') ? new URL('../', location.href) : new URL('./', location.href);
  return new URL(arquivo, raiz).href;
}

export const mensagens = {
  /** @param {string} link */
  minhaArea: (link) => `Meu horário na ${NOME_BARBEARIA}. Por aqui eu vejo, remarco ou cancelo: ${link}`,

  /** @param {string} nome @param {string} quando @param {string} link */
  bloqueio: (nome, quando, link) =>
    `Fala, ${nome}! Aqui é da ${NOME_BARBEARIA}. Vou precisar fechar a agenda ${quando} e seu horário foi cancelado. Desculpa o transtorno! Escolhe outro horário aqui: ${link}`,

  /** @param {string} nome @param {number} minutos @param {string} novaHora @param {string} link */
  atraso: (nome, minutos, novaHora, link) =>
    `Fala, ${nome}! Aqui é da ${NOME_BARBEARIA}. Tô atrasando uns ${minutos} minutos hoje, então seu horário passou pras ${novaHora}. Se não der pra você, marca outro aqui: ${link}`,

  /** @param {string} nome @param {string} horaTexto */
  lembrete: (nome, horaTexto) =>
    `Fala, ${nome}! Passando pra lembrar do seu horário amanhã às ${horaTexto} na ${NOME_BARBEARIA}. Te esperamos!`,

  /** @param {string} nome @param {string} link */
  sumido: (nome, link) =>
    `Fala, ${nome}! Aqui é da ${NOME_BARBEARIA}. Faz tempo que você não aparece por aqui. E aí, bora cortar? Marca seu horário aqui: ${link}`,

  /** @param {string} nome @param {string} valorTexto */
  fiado: (nome, valorTexto) =>
    `Fala, ${nome}! Aqui é da ${NOME_BARBEARIA}. Passando pra lembrar do acerto de ${valorTexto}. Pode ser no Pix!`,

  /**
   * @param {string} nome @param {string} plano @param {string} valorTexto
   * @param {string} vencimento 'venceu em 08/11' ou 'vence em 15/11' @param {string | null} codigoPix
   */
  cobrancaPlano: (nome, plano, valorTexto, vencimento, codigoPix) =>
    `Fala, ${nome}! Aqui é da ${NOME_BARBEARIA}. Seu ${plano} ${vencimento} (${valorTexto}).`
    + (codigoPix
      ? ` Pra renovar, é só pagar com o Pix copia e cola abaixo:\n\n${codigoPix}`
      : ' Pra renovar, pode ser no Pix ou na hora do próximo corte.'),
};
