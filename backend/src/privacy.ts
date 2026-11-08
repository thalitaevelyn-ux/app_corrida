/**
 * Política de privacidade do Fast run, servida em /privacidade.
 * Exigida pela Play Store e pelo Health Connect (tela "por que este app pede acesso").
 *
 * ANTES DE PUBLICAR: troque CONTATO por um e-mail seu de suporte.
 */
export const CONTATO = process.env.PRIVACY_CONTACT_EMAIL ?? "[SEU E-MAIL DE CONTATO]";
const ATUALIZADA = "8 de novembro de 2026 (contas e importação de arquivos)";

export function privacyHtml(): string {
  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Fast run · Política de privacidade</title>
<style>
  body { font-family: system-ui, sans-serif; max-width: 720px; margin: 0 auto; padding: 24px 16px 48px; line-height: 1.55; color: #201A17; background: #FFF8F5; }
  h1 { font-size: 28px; } h2 { font-size: 19px; margin-top: 28px; }
  li { margin: 4px 0; } small { color: #5C5450; }
  @media (prefers-color-scheme: dark) { body { color: #EDE0DA; background: #1A1110; } small { color: #C9B9AF; } a { color: #FFB599; } }
</style>
</head>
<body>
<h1>Política de privacidade do Fast run</h1>
<p><small>Última atualização: ${ATUALIZADA}</small></p>

<p>O Fast run ajuda você a treinar corrida: lê seus treinos do Health Connect, monta um plano de treino e grava corridas com GPS. Esta página explica quais dados o app usa, para quê e o que você pode fazer com eles.</p>

<h2>Dados que o app lê do Health Connect</h2>
<ul>
  <li><b>Sessões de exercício</b> (tipo, início, fim, distância, calorias e passos) dos últimos 180 dias, inclusive as registradas por outros apps e relógios.</li>
  <li><b>Frequência cardíaca</b> durante os treinos, para mostrar zonas de FC.</li>
  <li><b>Rotas de exercício</b>, quando você permitir, para desenhar o percurso.</li>
  <li><b>Histórico com mais de 30 dias</b>, só para estimar seu nível inicial.</li>
</ul>

<h2>Dados que o app grava no Health Connect</h2>
<p>As corridas que você grava no Fast run (início, fim, distância, calorias estimadas e rota GPS) são salvas no Health Connect, para que outros apps que você autorizar possam vê-las.</p>

<h2>Arquivos de treino que você importa</h2>
<p>Quando você importa um arquivo GPX, TCX ou FIT (por exemplo, exportado do Zepp, Garmin ou Strava), o app lê data, tipo, duração, distância, calorias, frequência cardíaca, parciais e a rota contida no arquivo.</p>

<h2>Dados que você informa</h2>
<p>Nome e e-mail da conta, objetivo de treino, dias por semana, data da prova, tempo-alvo, idade (para estimar a FC máxima), peso (para estimar calorias) e como você está se sentindo na semana.</p>

<h2>Conta</h2>
<p>O login é feito pelo Firebase Authentication (Google), com sua conta Google ou com e-mail e senha. Não temos acesso à sua senha.</p>

<h2>Como os dados são usados</h2>
<ul>
  <li>Para mostrar seus treinos, estatísticas e o progresso no plano.</li>
  <li>Para gerar e ajustar o plano de treino.</li>
</ul>
<p>Os dados do Health Connect são usados <b>somente</b> para essas funções. Não são usados para publicidade, não são vendidos e não são compartilhados com corretores de dados.</p>

<h2>Geração do plano com inteligência artificial</h2>
<p>Quando a geração por IA está ativa, o app envia ao nosso servidor um <b>resumo</b>: seu objetivo, idade, peso, sensação da semana, médias de treino e, para cada treino recente, data, tipo, duração, distância, pace e FC média. O servidor repassa esse resumo à Anthropic (fornecedora do modelo Claude), que gera o plano e o devolve. <b>Localização e rotas nunca saem do aparelho.</b> O servidor não guarda esse resumo depois de responder (guarda só o registro de uso descrito abaixo). A Anthropic trata os dados conforme a política de privacidade dela (<a href="https://www.anthropic.com/legal/privacy">anthropic.com/legal/privacy</a>). Sem a IA, o plano é gerado no próprio aparelho, e nada é enviado.</p>

<h2>Armazenamento</h2>
<ul>
  <li><b>Na sua conta</b> (Google Firebase/Firestore): perfil, objetivo, plano e os treinos que você importou de arquivo (incluindo a rota desses arquivos), para você não perder nada ao trocar de celular. Só você tem acesso a esses dados pelo app.</li>
  <li><b>Só no aparelho</b>: os treinos lidos do Health Connect e as corridas gravadas pelo GPS do app (o resumo vai para o Health Connect).</li>
  <li><b>Registros de uso</b>: para controlar custos, registramos cada geração de plano (data, quantidade de tokens, custo e se deu certo), ligada à sua conta. Usamos isso para limites de uso e estatísticas do serviço.</li>
</ul>

<h2>Seus controles</h2>
<ul>
  <li>Revogar o acesso a qualquer momento em <b>Configurações → Health Connect → Permissões do app → Fast run</b>.</li>
  <li>Excluir a conta e todos os dados (no aparelho e na nuvem) em <b>Plano → Sobre e privacidade → Excluir conta</b>, ou pedir pela página <a href="/excluir-conta">excluir conta</a>.</li>
  <li>Corridas já gravadas no Health Connect podem ser apagadas pelo próprio Health Connect.</li>
</ul>

<h2>Segurança</h2>
<p>A comunicação com o servidor usa HTTPS. A chave de acesso à IA fica só no servidor, nunca no aplicativo.</p>

<h2>Saúde</h2>
<p>O Fast run não é um dispositivo médico e não substitui orientação profissional. Consulte um médico antes de começar um programa de exercícios, principalmente se tiver alguma condição de saúde.</p>

<h2>Contato</h2>
<p>Dúvidas ou pedidos sobre seus dados: <a href="mailto:${CONTATO}">${CONTATO}</a>.</p>
</body>
</html>`;
}


export function deleteAccountHtml(): string {
  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Fast run · Excluir conta</title>
<style>
  body { font-family: system-ui, sans-serif; max-width: 720px; margin: 0 auto; padding: 24px 16px 48px; line-height: 1.55; color: #201A17; background: #FFF8F5; }
  h1 { font-size: 28px; } li { margin: 6px 0; }
  @media (prefers-color-scheme: dark) { body { color: #EDE0DA; background: #1A1110; } a { color: #FFB599; } }
</style>
</head>
<body>
<h1>Excluir sua conta do Fast run</h1>
<p>Você pode excluir sua conta e todos os dados ligados a ela de duas formas:</p>
<ol>
  <li><b>Pelo app:</b> abra o Fast run → aba <b>Plano</b> → <b>Sobre e privacidade</b> → <b>Excluir conta</b>. A exclusão é imediata.</li>
  <li><b>Por e-mail</b> (se não tiver mais o app): escreva para <a href="mailto:${CONTATO}?subject=Excluir%20conta%20Fast%20run">${CONTATO}</a> com o assunto "Excluir conta", a partir do e-mail cadastrado. Respondemos e excluímos em até 15 dias.</li>
</ol>
<h2>O que é excluído</h2>
<ul>
  <li>Sua conta de login, perfil, objetivo e plano de treino.</li>
  <li>Os treinos importados de arquivo (incluindo rotas).</li>
  <li>Os registros de uso ligados à sua conta.</li>
</ul>
<h2>O que não é excluído</h2>
<ul>
  <li>Totais diários e mensais do serviço, sem nenhum dado que identifique você.</li>
  <li>Treinos que estão no Health Connect do seu celular: eles pertencem ao Health Connect e podem ser apagados por lá.</li>
</ul>
<p><a href="/privacidade">Política de privacidade</a></p>
</body>
</html>`;
}
