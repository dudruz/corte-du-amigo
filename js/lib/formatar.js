// @ts-check
import { FUSO } from '../config.js';

const moeda = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });
const fmtHora = new Intl.DateTimeFormat('pt-BR', { timeZone: FUSO, hour: '2-digit', minute: '2-digit' });
const fmtDiaISO = new Intl.DateTimeFormat('en-CA', { timeZone: FUSO, year: 'numeric', month: '2-digit', day: '2-digit' });
const fmtSemanaLonga = new Intl.DateTimeFormat('pt-BR', { timeZone: FUSO, weekday: 'long' });
const SEMANA_CURTA = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
const SEMANA_LONGA = ['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'];

/** @param {number | null | undefined} centavos */
export const dinheiro = (centavos) => moeda.format((centavos || 0) / 100);

/** @param {string | Date} iso */
export const hora = (iso) => fmtHora.format(new Date(iso));

/** Data de hoje no fuso da barbearia, 'AAAA-MM-DD'. */
export const hojeISO = () => fmtDiaISO.format(new Date());

/** @param {string | Date} iso timestamp → 'AAAA-MM-DD' no fuso da barbearia */
export const diaDoTimestamp = (iso) => fmtDiaISO.format(new Date(iso));

/** @param {string} diaISO 'AAAA-MM-DD' (meio-dia UTC evita virar o dia) */
const comoData = (diaISO) => new Date(diaISO + 'T12:00:00Z');

/** @param {string} diaISO @param {number} n */
export const somarDias = (diaISO, n) => {
  const d = comoData(diaISO);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
};

/** @param {string} diaISO */
export const semanaCurta = (diaISO) => SEMANA_CURTA[comoData(diaISO).getUTCDay()];
/** @param {string} diaISO */
export const semanaLonga = (diaISO) => SEMANA_LONGA[comoData(diaISO).getUTCDay()];
/** @param {string} diaISO */
export const diaDoMes = (diaISO) => diaISO.slice(8, 10);
/** @param {string} diaISO → '14/11' */
export const diaMes = (diaISO) => `${diaISO.slice(8, 10)}/${diaISO.slice(5, 7)}`;

/** @param {string} iso timestamp → 'sábado, 14/11' */
export const dataLonga = (iso) => {
  const dia = diaDoTimestamp(iso);
  return `${fmtSemanaLonga.format(new Date(iso)).replace('-feira', '')}, ${diaMes(dia)}`;
};

/**
 * Monta um timestamp no horário de Brasília. O Brasil não tem horário de verão desde 2019,
 * então o deslocamento é fixo em -03:00.
 * @param {string} diaISO @param {string} hhmm
 */
export const noFuso = (diaISO, hhmm) => `${diaISO}T${hhmm}:00-03:00`;

/**
 * Texto digitado → centavos. Aceita vírgula ou ponto como decimal, porque muito teclado
 * de celular só tem ponto: '35,50' | '35.50' | '35' | 'R$ 1.234,56' | '1.234'.
 * Com vírgula, os pontos são milhar. Sem vírgula, um único ponto seguido de 1 ou 2
 * dígitos é decimal ('40.00' = R$ 40,00); seguido de 3 dígitos é milhar ('1.234').
 * Devolve NaN para vazio, texto sem número, negativo ou mais de 2 casas decimais.
 * @param {string} texto
 */
export function paraCentavos(texto) {
  const s = String(texto ?? '').replace(/[R$\s]/g, '');
  if (!/^\d[\d.,]*$/.test(s)) return NaN;
  let inteiro = s;
  let decimal = '';
  const virgula = s.lastIndexOf(',');
  if (virgula >= 0) {
    if (s.indexOf(',') !== virgula) return NaN;
    inteiro = s.slice(0, virgula);
    decimal = s.slice(virgula + 1);
  } else {
    const comPonto = s.match(/^(\d+)\.(\d{1,2})$/);
    if (comPonto) { inteiro = comPonto[1]; decimal = comPonto[2]; }
  }
  if (decimal.includes('.') || decimal.length > 2) return NaN;
  inteiro = inteiro.replace(/\./g, '');
  if (inteiro === '') return NaN;
  const centavos = Number(inteiro) * 100 + Number(decimal.padEnd(2, '0') || '0');
  return Number.isSafeInteger(centavos) ? centavos : NaN;
}

/** centavos → '35,50' para preencher inputs @param {number} c */
export const centavosParaTexto = (c) => (c / 100).toFixed(2).replace('.', ',');

/** '5531999998888' → '(31) 99999-8888' @param {string} tel */
export function telefoneBonito(tel) {
  const d = String(tel || '').replace(/\D/g, '').replace(/^55/, '');
  if (d.length === 11) return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`;
  if (d.length === 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`;
  return tel;
}

/** @param {number} n @param {string} um @param {string} varios */
export const plural = (n, um, varios) => `${n} ${n === 1 ? um : varios}`;
