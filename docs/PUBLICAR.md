# Como colocar o Fast run no ar

Os passos que podem gerar cobrança estão marcados com **[CUSTO]**. Nenhum deles acontece sozinho: todos dependem de
você confirmar no site do serviço. Se algum passo pedir cartão ou pagamento sem estar marcado aqui, pare e pergunte
antes de continuar.

| Etapa | Custo |
|---|---|
| 1. Chave da Claude API | **[CUSTO]** por uso. Você define o limite máximo antes de colocar crédito. |
| 2. Backend no Render | Grátis (plano free fixo no `render.yaml`) |
| 3. Build do app | Grátis |
| 4. Chave de assinatura | Grátis |
| 5. Play Store | **[CUSTO]** taxa única de cadastro de desenvolvedor no Google Play |

---

## 1. Chave da Claude API **[CUSTO por uso]**

1. Crie uma conta em https://console.anthropic.com.
2. **Antes de colocar crédito**, procure a área de **limites de gastos** nas configurações da organização (*Limits*) e defina um **limite de gastos mensal** baixo, por exemplo
   US$ 5. É o limite que a Anthropic aplica de verdade: passou dele, as chamadas são recusadas e nada mais é cobrado.
3. Em **Billing**, decida se e quanto crédito colocar. Esta é a decisão de cobrança: sem crédito, a IA não funciona
   e o app continua usando o plano por regras.
4. Em **API Keys**, crie uma chave chamada `fast-run-render`. Copie e guarde num lugar seguro: ela aparece uma vez só.
   Não cole a chave em chat, e-mail ou no código.

**Quanto custa, mais ou menos:** cada plano novo usa poucos milhares de tokens de entrada e alguns milhares de
saída, o que dá centavos de dólar no `claude-opus-5-5`. O ajuste semanal custa menos. O custo exato de cada chamada
aparece no log do Render (`Custo da chamada: US$ ...`).

**Proteções no backend** (configuradas no `render.yaml`):

- `MONTHLY_BUDGET_USD=5`: o servidor para de chamar a IA ao atingir US$ 5 no mês.
- `MAX_PER_DAY=60` e `MAX_PER_HOUR=20`: limite de planos por dia e por hora.

O contador do servidor zera quando o Render reinicia o serviço, o que acontece no plano free. Por isso, a garantia
real é o limite do passo 2, no Console da Anthropic. Configure os dois.

---

## 2. Backend no Render (grátis)

1. Crie uma conta em https://render.com (pode entrar com o GitHub).
2. Clique em **New → Blueprint** e escolha o repositório `thalitaevelyn-ux/app_corrida`. O Render lê o `render.yaml`
   e mostra o serviço `fast-run-plano` no plano **Free**.
   - Confira se aparece **Free** antes de confirmar. Se aparecer outro plano, preço ou pedido de cartão, pare aqui.
3. Preencha as variáveis que o Render pedir:
   - `ANTHROPIC_API_KEY`: a chave do passo 1.
   - `PRIVACY_CONTACT_EMAIL`: o e-mail que vai aparecer na política de privacidade.
   - O `APP_TOKEN` é gerado automaticamente.
4. Clique em **Apply**. O primeiro deploy leva alguns minutos.
5. Abra o serviço e copie a URL (algo como `https://fast-run-plano.onrender.com`). Em **Environment**, copie o valor
   de `APP_TOKEN`.
6. Teste no navegador:
   - `https://SUA-URL/health` deve mostrar `{"ok":true}`.
   - `https://SUA-URL/privacidade` deve mostrar a política de privacidade.

**Como é o plano free:** o serviço "dorme" depois de uns 15 minutos sem uso, e a primeira chamada depois disso leva
cerca de 1 minuto para acordar. O app espera até 4 minutos, então funciona, só fica mais lento na primeira vez.

**Se a URL não for `fast-run-plano.onrender.com`** (o nome pode estar ocupado), troque-a em dois lugares:

- `android/app/src/main/res/values/strings.xml` (`privacy_policy_url`)
- no build do app, com `--dart-define=PRIVACY_URL=...` (passo 3)

---

## 3. Build do app

Para testar no celular com a IA ligada:

```bash
flutter run --dart-define=PLAN_API_URL=https://SUA-URL --dart-define=PLAN_API_TOKEN=SEU_APP_TOKEN
```

O build para a Play Store usa os mesmos parâmetros e exige o passo 4 antes:

```bash
flutter build appbundle --release --dart-define=PLAN_API_URL=https://SUA-URL --dart-define=PLAN_API_TOKEN=SEU_APP_TOKEN
```

O arquivo gerado fica em `build/app/outputs/bundle/release/app-release.aab`.

---

## 4. Chave de assinatura (grátis, uma vez só)

A Play Store exige que o app seja assinado com uma chave sua. **Se perder essa chave, você não consegue mais
atualizar o app** (a Google até ajuda a trocar, mas dá trabalho). Faça backup em dois lugares seguros.

No seu PC, fora da pasta do projeto (o `keytool` vem com o Android Studio):

```bash
keytool -genkey -v -keystore fast-run-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Depois, copie `android/key.properties.example` para `android/key.properties` e preencha o caminho do `.jks` e as
senhas. Esse arquivo e o `.jks` já estão no `.gitignore`: **nunca** os envie ao GitHub.

---

## 5. Play Store **[CUSTO: taxa única]**

1. Crie a conta de desenvolvedor em https://play.google.com/console. A Google cobra uma **taxa única de cadastro**
   (o valor aparece na tela antes do pagamento). Pagar ou não é decisão sua; sem isso, dá para usar o app instalando
   o APK direto no celular.
2. Crie o app **Fast run**, com pacote `com.thalitaevelyn.fast_run`, que é permanente.
3. **Política de privacidade:** use `https://SUA-URL/privacidade`.
4. **Declaração de permissões de saúde (Health Connect):** o Play Console pede o motivo de cada permissão:

   | Permissão | Motivo |
   |---|---|
   | Ler exercício | Mostrar o histórico de treinos, calcular estatísticas e personalizar o plano de corrida |
   | Gravar exercício | Salvar as corridas gravadas com GPS no app |
   | Ler/gravar rota de exercício | Desenhar o percurso e salvar a rota das corridas gravadas |
   | Ler frequência cardíaca | Mostrar zonas de FC e verificar se os treinos estão na intensidade certa |
   | Ler/gravar distância e calorias | Métricas das sessões de exercício |
   | Ler passos | Mostrar passos das sessões de caminhada e corrida |
   | Ler histórico | Estimar o nível inicial com treinos de mais de 30 dias |

5. **Segurança dos dados**, para preencher o formulário:
   - Coleta: dados de saúde e condicionamento (exercício, frequência cardíaca), informações pessoais (idade, peso).
   - Compartilhamento: um resumo dos treinos é enviado para processamento pela IA (Anthropic), só para gerar o plano.
     Localização **não** é enviada.
   - Criptografia em trânsito: sim (HTTPS).
   - O usuário pode pedir a exclusão: sim (no app, em "Apagar meus dados", ou desinstalando).
   - Não usado para publicidade, não vendido.
6. **Teste antes da produção:** contas pessoais novas precisam rodar um teste fechado, com um número mínimo de
   testadores por um período, antes de liberar a produção. O Play Console mostra os números atuais.
7. Envie o `app-release.aab` do passo 3 na faixa de teste.

---

## Checklist antes de publicar

- [ ] Limite de gastos definido no Console da Anthropic
- [ ] Render mostrando o plano **Free**
- [ ] `/privacidade` abrindo, com o seu e-mail de contato
- [ ] `strings.xml` com a URL certa da política
- [ ] Chave de assinatura criada, com backup
- [ ] App testado num celular real: permissões do Health Connect, leitura de treinos, gravação de uma corrida curta
