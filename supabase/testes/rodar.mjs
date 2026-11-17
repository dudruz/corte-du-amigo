// @ts-check
// Corte DÚ Amigo · roda as migrations e os testes do banco num Postgres embutido (PGlite).
//
// COMO RODAR
// O PGlite fica FORA do repositório (o projeto não tem dependências). Uma vez só,
// numa pasta qualquer fora do projeto:
//
//   mkdir ../pgteste && cd ../pgteste
//   npm init -y
//   npm install @electric-sql/pglite
//
// Depois, sempre de dentro dessa pasta (é nela que o Node acha o PGlite):
//
//   node /caminho/do/projeto/supabase/testes/rodar.mjs
//   node /caminho/do/projeto/supabase/testes/rodar.mjs 30      (só os arquivos com "30" no nome)
//
// O QUE ELE FAZ
// 1. Cria um banco vazio na memória e roda 00_ambiente.sql (o que o Supabase já entrega).
// 2. Aplica as migrations na ordem. A 005 fica de fora porque precisa do pg_cron.
// 3. Roda 01_apoio.sql (logins de teste e funções de ajuda).
// 4. Roda os outros .sql desta pasta. Cada bloco que começa com "-- TESTE: nome" é um teste:
//    roda numa transação desfeita no fim, então um teste não suja o outro.
//    Teste passa quando não dá erro. "-- PULAR: motivo" logo abaixo do nome pula o teste.
// Sai com código 1 se algum teste falhar.

import { readFileSync, readdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const MIGRATIONS = join(AQUI, '..', 'migrations');
const PULAR_MIGRATIONS = [/^005_/];
const EXTENSOES = ['btree_gist', 'pgcrypto'];

/** Importa um módulo instalado na pasta de onde o comando foi chamado. */
async function importarDaqui(/** @type {string} */ nome) {
  const exigir = createRequire(pathToFileURL(join(process.cwd(), 'x.js')));
  const mod = await import(pathToFileURL(exigir.resolve(nome)).href);
  return mod.default && !mod.PGlite && typeof mod.default === 'object' ? { ...mod.default, ...mod } : mod;
}

/** @returns {Promise<{ db: any, faltando: string[] }>} */
async function abrirBanco() {
  let PGlite;
  try {
    ({ PGlite } = await importarDaqui('@electric-sql/pglite'));
  } catch {
    console.error('Não achei o @electric-sql/pglite nesta pasta. Veja "COMO RODAR" no topo de rodar.mjs.');
    process.exit(2);
  }
  /** @type {Record<string, any>} */
  const extensions = {};
  const faltando = [];
  for (const nome of EXTENSOES) {
    try {
      extensions[nome] = (await importarDaqui(`@electric-sql/pglite/contrib/${nome}`))[nome];
      if (!extensions[nome]) throw new Error('sem export');
    } catch {
      delete extensions[nome];
      faltando.push(nome);
    }
  }
  return { db: new PGlite({ extensions }), faltando };
}

/** Tira o "create extension" das extensões que o PGlite não tem (gen_random_uuid já é nativo). */
function semExtensoesFaltando(/** @type {string} */ sql, /** @type {string[]} */ faltando) {
  return sql
    .split('\n')
    .filter((linha) => !faltando.some((e) => new RegExp(`^\\s*create\\s+extension\\b.*\\b${e}\\b`, 'i').test(linha)))
    .join('\n');
}

/**
 * Quebra um arquivo em testes.
 * @returns {{ nome: string, pular: string | null, sql: string }[]}
 */
function separarTestes(/** @type {string} */ texto) {
  const testes = [];
  let atual = null;
  for (const linha of texto.split(/\r?\n/)) {
    const nome = linha.match(/^-- TESTE:\s*(.+)$/);
    if (nome) {
      atual = { nome: nome[1].trim(), pular: /** @type {string | null} */ (null), linhas: /** @type {string[]} */ ([]) };
      testes.push(atual);
      continue;
    }
    if (!atual) continue;
    const pular = linha.match(/^-- PULAR:\s*(.+)$/);
    if (pular) atual.pular = pular[1].trim();
    else atual.linhas.push(linha);
  }
  return testes.map((t) => ({ nome: t.nome, pular: t.pular, sql: t.linhas.join('\n') }));
}

const filtro = process.argv[2] ?? '';
const { db, faltando } = await abrirBanco();

/** Roda um arquivo inteiro; se der erro, para tudo (sem preparo não há o que testar). */
async function aplicar(/** @type {string} */ caminho, /** @type {string} */ rotulo) {
  try {
    await db.exec(semExtensoesFaltando(readFileSync(caminho, 'utf8'), faltando));
    console.log(`  ok  ${rotulo}`);
  } catch (e) {
    console.error(`ERRO ao aplicar ${rotulo}: ${/** @type {Error} */ (e).message}`);
    process.exit(2);
  }
}

console.log('Preparando o banco');
if (faltando.length) console.log(`  (PGlite sem: ${faltando.join(', ')}; "create extension" dessas é ignorado)`);
await aplicar(join(AQUI, '00_ambiente.sql'), 'testes/00_ambiente.sql');
for (const arq of readdirSync(MIGRATIONS).filter((a) => a.endsWith('.sql')).sort()) {
  if (PULAR_MIGRATIONS.some((r) => r.test(arq))) {
    console.log(`  --  migrations/${arq} (pulada: precisa do pg_cron)`);
    continue;
  }
  await aplicar(join(MIGRATIONS, arq), `migrations/${arq}`);
}
await aplicar(join(AQUI, '01_apoio.sql'), 'testes/01_apoio.sql');

let passou = 0;
let falhou = 0;
let pulado = 0;
const arquivos = readdirSync(AQUI)
  .filter((a) => /^\d\d_.*\.sql$/.test(a) && !/^0[01]_/.test(a) && a.includes(filtro))
  .sort();

for (const arq of arquivos) {
  console.log(`\n${arq}`);
  for (const t of separarTestes(readFileSync(join(AQUI, arq), 'utf8'))) {
    if (t.pular) {
      pulado++;
      console.log(`  PULADO  ${t.nome} (${t.pular})`);
      continue;
    }
    await db.exec('begin');
    try {
      await db.exec(t.sql);
      passou++;
      console.log(`  passou  ${t.nome}`);
    } catch (e) {
      falhou++;
      console.log(`  FALHOU  ${t.nome}\n          ${/** @type {Error} */ (e).message}`);
    } finally {
      // Desfaz tudo, inclusive o papel e o login que o teste tenha deixado ligados.
      await db.exec('rollback');
      await db.exec("reset role; select set_config('request.jwt.claim.sub', '', false)");
    }
  }
}

console.log(`\nResultado: ${passou} passaram, ${falhou} falharam, ${pulado} pulados.`);
await db.close();
process.exit(falhou ? 1 : 0);
