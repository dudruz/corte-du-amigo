// @ts-check
// Pix "copia e cola" (BR Code estático, padrão do Banco Central), feito à mão, sem biblioteca.
// O cliente cola o código no app do banco e o valor já vem preenchido.

/** @typedef {'cpf_cnpj' | 'celular' | 'email' | 'aleatoria'} TipoChave */

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** CRC16-CCITT (polinômio 0x1021, início 0xFFFF), exigido no fim do código. @param {string} texto */
export function crc16(texto) {
  let crc = 0xffff;
  for (let i = 0; i < texto.length; i++) {
    crc ^= texto.charCodeAt(i) << 8;
    for (let b = 0; b < 8; b++) {
      crc = crc & 0x8000 ? (crc << 1) ^ 0x1021 : crc << 1;
      crc &= 0xffff;
    }
  }
  return crc.toString(16).toUpperCase().padStart(4, '0');
}

/** Campo do código: id + tamanho com 2 dígitos + valor. @param {string} id @param {string} valor */
const campo = (id, valor) => `${id}${String(valor.length).padStart(2, '0')}${valor}`;

/**
 * Nome e cidade entram sem acento e em maiúsculas: alguns bancos recusam o código com acento.
 * @param {string} texto @param {number} max
 */
function limpar(texto, max) {
  return String(texto || '')
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toUpperCase().replace(/[^A-Z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim()
    .slice(0, max);
}

/**
 * Monta o código Pix copia e cola.
 * @param {{ chave: string, nome: string, cidade: string, valorCentavos?: number | null }} dados
 * @returns {string}
 */
export function codigoPix({ chave, nome, cidade, valorCentavos = null }) {
  const conta = campo('26', campo('00', 'br.gov.bcb.pix') + campo('01', chave));
  let corpo = campo('00', '01') + conta + campo('52', '0000') + campo('53', '986');
  if (valorCentavos != null && valorCentavos > 0) corpo += campo('54', (valorCentavos / 100).toFixed(2));
  corpo += campo('58', 'BR') + campo('59', limpar(nome, 25) || 'RECEBEDOR') + campo('60', limpar(cidade, 15) || 'BRASIL');
  corpo += campo('62', campo('05', '***'));
  corpo += '6304';
  return corpo + crc16(corpo);
}

/**
 * Deixa a chave no formato que o Pix exige. Celular vira +55DDDNUMERO; CPF e CNPJ, só dígitos.
 * Lança erro com mensagem pra tela quando a chave não fecha com o tipo.
 * @param {TipoChave} tipo @param {string} texto
 */
export function normalizarChavePix(tipo, texto) {
  const t = String(texto || '').trim();
  if (!t) throw new Error('Coloca a chave Pix.');
  const digitos = t.replace(/\D/g, '');
  switch (tipo) {
    case 'cpf_cnpj':
      if (digitos.length !== 11 && digitos.length !== 14) throw new Error('CPF tem 11 números e CNPJ tem 14.');
      return digitos;
    case 'celular': {
      let d = digitos.replace(/^0+/, '');
      if (d.length === 10 || d.length === 11) d = `55${d}`;
      if (!/^55\d{10,11}$/.test(d)) throw new Error('Celular inválido. Coloca DDD + número.');
      return `+${d}`;
    }
    case 'email':
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(t) || t.length > 77) throw new Error('E-mail inválido.');
      return t.toLowerCase();
    case 'aleatoria':
      if (!UUID.test(t)) throw new Error('Chave aleatória inválida. Copia ela inteira do app do banco.');
      return t.toLowerCase();
    default:
      throw new Error('Escolhe o tipo da chave.');
  }
}

/** Descobre o tipo de uma chave já salva, pra tela de Ajustes. @param {string} chave @returns {TipoChave} */
export function tipoDaChave(chave) {
  if (chave.startsWith('+')) return 'celular';
  if (chave.includes('@')) return 'email';
  if (UUID.test(chave)) return 'aleatoria';
  return 'cpf_cnpj';
}
