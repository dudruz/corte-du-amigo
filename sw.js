// Service worker da área da equipe: guarda a "casca" do app (HTML, CSS, JS e o supabase-js
// do CDN) pra abrir rápido e, sem internet, mostrar a tela de erro em vez de travar.
// Dados do Supabase NUNCA são guardados: sempre vêm da internet.
const VERSAO = 'corte-v2';
const CDN = 'https://cdn.jsdelivr.net/';

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    // A versão antiga se registrava na raiz e controlava também as páginas do cliente.
    // Esse registro antigo se desfaz; o novo vale só pra /equipe/.
    if (!new URL(self.registration.scope).pathname.endsWith('/equipe/')) {
      await self.registration.unregister();
      return;
    }
    const nomes = await caches.keys();
    await Promise.all(nomes.filter((n) => n !== VERSAO).map((n) => caches.delete(n)));
    await self.clients.claim();
  })());
});

/** A mesma página com ?id=... diferente é o mesmo arquivo: guarda uma cópia só. */
const chave = (url) => {
  const u = new URL(url);
  u.search = '';
  u.hash = '';
  return u.href;
};

self.addEventListener('fetch', (e) => {
  const req = e.request;
  const url = new URL(req.url);
  const doSite = url.origin === location.origin;
  if (req.method !== 'GET' || (!doSite && !req.url.startsWith(CDN))) return;

  // Rede primeiro; só resposta boa vai pro cache (página de erro não substitui a versão boa).
  // Sem internet, usa a última versão boa.
  e.respondWith((async () => {
    try {
      const resposta = await fetch(req);
      if (resposta.ok) {
        const copia = resposta.clone();
        caches.open(VERSAO).then((c) => c.put(doSite ? chave(req.url) : req.url, copia));
      }
      return resposta;
    } catch (erro) {
      const guardada = await caches.match(doSite ? chave(req.url) : req.url);
      if (guardada) return guardada;
      if (req.mode === 'navigate') {
        return new Response(
          '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">'
          + '<title>Sem internet</title><body style="font-family:system-ui,sans-serif;padding:40px 20px;text-align:center">'
          + '<p>Sem internet e essa tela ainda não foi aberta neste aparelho.</p><p>Confere a conexão e tenta de novo.</p></body>',
          { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
      }
      throw erro;
    }
  })());
});
