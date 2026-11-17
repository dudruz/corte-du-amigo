// @ts-check
// Script comum (não é módulo) de propósito: módulos não rodam quando o HTML é aberto
// com dois cliques (file://), e este aviso precisa aparecer justamente nesse caso.
(function () {
  if (location.protocol !== 'file:') return;
  var app = document.getElementById('app');
  if (!app) return;

  var caixa = document.createElement('div');
  caixa.className = 'vazio';
  caixa.setAttribute('role', 'alert');

  var titulo = document.createElement('strong');
  titulo.textContent = 'Abra pelo servidor local, não pelo arquivo';

  var texto = document.createElement('p');
  texto.textContent = 'Com dois cliques no arquivo, o navegador bloqueia os scripts e a página não carrega. '
    + 'Na pasta do projeto, rode o comando abaixo e abra http://localhost:8000';

  var comando = document.createElement('code');
  comando.textContent = 'python -m http.server 8000';

  caixa.append(titulo, texto, comando);
  app.replaceChildren(caixa);
})();
