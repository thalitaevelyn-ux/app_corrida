/**
 * Política de privacidade do Fast run, servida em /privacidade.
 * Exigida pela Play Store e pelo Health Connect (tela "por que este app pede acesso").
 *
 * ANTES DE PUBLICAR: troque CONTATO por um e-mail seu de suporte.
 */
export const CONTATO = process.env.PRIVACY_CONTACT_EMAIL ?? "[SEU E-MAIL DE CONTATO]";
const ATUALIZADA = "8 de novembro de 2026";

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

<h2>Dados que você informa</h2>
<p>Objetivo de treino, dias por semana, data da prova, tempo-alvo, idade (para estimar a FC máxima), peso (para estimar calorias) e como você está se sentindo na semana.</p>

<h2>Como os dados são usados</h2>
<ul>
  <li>Para mostrar seus treinos, estatísticas e o progresso no plano.</li>
  <li>Para gerar e ajustar o plano de treino.</li>
</ul>
<p>Os dados do Health Connect são usados <b>somente</b> para essas funções. Não são usados para publicidade, não são vendidos e não são compartilhados com corretores de dados.</p>

<h2>Geração do plano com inteligência artificial</h2>
<p>Quando a geração por IA está ativa, o app envia ao nosso servidor um <b>resumo</b>: seu objetivo, idade, peso, sensação da semana, médias de treino e, para cada treino recente, data, tipo, duração, distância, pace e FC média. O servidor repassa esse resumo à Anthropic (fornecedora do modelo Claude), que gera o plano e o devolve. <b>Localização e rotas nunca saem do aparelho.</b> O servidor não guarda esses dados depois de responder. A Anthropic trata os dados conforme a política de privacidade dela (<a href="https://www.anthropic.com/legal/privacy">anthropic.com/legal/privacy</a>). Sem a IA, o plano é gerado no próprio aparelho, e nada é enviado.</p>

<h2>Armazenamento</h2>
<p>O plano, o objetivo e os detalhes das corridas gravadas (parciais e rota) ficam guardados apenas no seu aparelho. Não há conta de usuário nem banco de dados com seus treinos no servidor.</p>

<h2>Seus controles</h2>
<ul>
  <li>Revogar o acesso a qualquer momento em <b>Configurações → Health Connect → Permissões do app → Fast run</b>.</li>
  <li>Apagar os dados do app em <b>Plano → Sobre e privacidade → Apagar meus dados</b>, ou desinstalando o app.</li>
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
