# Configurar o Firebase (contas, nuvem e painel)

Tudo aqui usa o plano gratuito **Spark**, que **não pede cartão**. Se em algum momento o Firebase pedir para trocar
para o plano **Blaze** (pago) ou cadastrar cartão, pare e me avise: o Fast run não precisa de nada pago do Firebase.

Tempo: uns 20 minutos.

## 1. Criar o projeto

1. Acesse https://console.firebase.google.com e clique em **Criar projeto**.
2. Nome: `fast-run`. Pode desativar o Google Analytics, que não usamos.

## 2. Login (Authentication)

1. Menu **Build → Authentication → Começar**.
2. Em **Método de login**, ative:
   - **E-mail/senha**
   - **Google** (escolha o seu e-mail como "e-mail de suporte")
3. Abra o provedor **Google** de novo e, em **Configuração do SDK da Web**, copie o **ID do cliente da Web**
   (termina em `.apps.googleusercontent.com`).
4. Em **Configurações → Domínios autorizados**, clique em **Adicionar domínio** e coloque `fast-run-plano.onrender.com`.
   Isso libera o login do painel `/admin`.

## 3. Banco de dados (Firestore)

1. Menu **Build → Firestore Database → Criar banco de dados**.
2. Local: **southamerica-east1 (São Paulo)**. Modo: **produção**.
3. Na aba **Regras**, apague o conteúdo, cole o arquivo [`firestore.rules`](../firestore.rules) deste repositório e
   clique em **Publicar**.

## 4. App Android

1. Em **Configurações do projeto (engrenagem) → Geral → Seus apps**, clique no ícone do Android.
2. Nome do pacote: `com.thalitaevelyn.fast_run`
3. Em **Certificado de assinatura SHA-1**, cole a chave de teste:
   `FA:52:10:B8:72:DB:D6:D4:25:E5:AB:FD:E4:D7:51:37:D0:8A:0C:53`
4. Registre o app. O `google-services.json` não é necessário (pode pular o download).
5. Ainda em **Seus apps → Android**, clique em **Adicionar impressão digital** e cole também o SHA-256:
   `1D:7A:27:81:68:A3:FF:E3:2F:44:A1:66:FD:48:40:DF:FB:29:4A:1F:D1:41:D3:F3:EB:9F:2A:50:8A:9B:3B:13`

Quando criar a chave de publicação da Play Store (docs/PUBLICAR.md, passo 4), cadastre também os SHA-1 e SHA-256
dela aqui. Depois de publicar, cadastre ainda os da **chave de assinatura do app** que o Play Console mostra em
**Integridade do app**.

## 5. App Web (para o painel /admin)

1. Em **Seus apps**, clique no ícone **Web** (`</>`), dê o nome `painel` e registre. Não precisa de Hosting.
2. Copie o objeto `firebaseConfig` que aparece (apiKey, authDomain, projectId, appId...).

## 6. O que me mandar (nada disto é segredo)

Pode colar no chat:

- O `firebaseConfig` do passo 5.
- O **ID do cliente da Web** do passo 2.3.
- O **App ID do Android** (Configurações do projeto → Seus apps → Android → "ID do app", começa com `1:` e tem
  `:android:`).

Com isso eu preencho o `config/app.json` e gero o APK com login.

## 7. Chave do servidor: vai direto no Render, nunca no chat

1. **Configurações do projeto → Contas de serviço → Gerar nova chave privada**. Isso baixa um arquivo `.json`.
   **É uma senha de administrador do seu Firebase:** não mande por chat, e-mail ou GitHub.
2. No painel do Render, abra o serviço `fast-run-plano` → **Environment** e adicione:
   - `FIREBASE_SERVICE_ACCOUNT`: abra o `.json` num editor de texto, copie **todo** o conteúdo e cole como valor.
   - `FIREBASE_WEB_CONFIG`: o `firebaseConfig` do passo 5 **em formato JSON**, com aspas nas chaves, por exemplo:
     `{"apiKey":"...","authDomain":"fast-run.firebaseapp.com","projectId":"fast-run","appId":"1:...:web:..."}`
   - `ADMIN_EMAILS`: o seu e-mail Google (o que vai entrar no painel).
3. Salve. O Render reinicia o serviço sozinho.
4. Depois disso, apague o `.json` baixado do seu computador (ou guarde num gerenciador de senhas).

Para conferir: `https://fast-run-plano.onrender.com/health` deve mostrar `"contas":true`, e
`https://fast-run-plano.onrender.com/admin` deve abrir o login do painel.

> **Atenção:** quando `FIREBASE_SERVICE_ACCOUNT` estiver configurada, o servidor passa a exigir login. O APK antigo
> (1.0.0, sem login) deixa de gerar planos com IA e cai no plano por regras. Use o APK novo.
