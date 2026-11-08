# Backend do plano (Claude API)

Servidor pequeno que recebe do app o objetivo e o resumo dos treinos, chama a Claude API e devolve o plano em JSON
validado. Ele existe para a chave da API **não** ficar dentro do app.

- `POST /v1/plano/gerar`: gera o plano completo
- `POST /v1/plano/ajustar`: ajusta as semanas restantes com base na semana que terminou
- `GET /health`: verificação de vida
- `GET /privacidade`: política de privacidade (pública, exigida pela Play Store e pelo Health Connect)
- `GET /v1/uso`: gasto estimado do mês e planos de hoje (exige o token)

Detalhes:

- **Modelo:** `claude-opus-5-5`, com effort `medium`, que custa menos e é suficiente para montar planos. Troque com
  `CLAUDE_MODEL`, por exemplo `claude-sonnet-5-5`, para cortar o custo pela metade.
- **Saída estruturada:** o schema Zod em `src/schema.ts` vira JSON Schema, e a resposta já chega validada. Depois,
  `sanitizePlan` corrige dia da semana, duplicados e o km total.
- **Fallback de recusa:** `fallbacks: "default"`. Se o modelo recusar por política, a API tenta outro modelo
  automaticamente.
- **Cache de prompt:** o prompt de sistema é fixo e marcado para cache.
- **Proteção:** token compartilhado (`APP_TOKEN`), limite de 200 KB por requisição e limite de planos por hora
  (`MAX_PER_HOUR`) e por dia (`MAX_PER_DAY`).
- **Teto de gastos:** `MONTHLY_BUDGET_USD` (padrão US$ 5). O servidor soma o custo real de cada resposta e para de
  chamar a IA ao atingir o teto; o app passa a usar o plano por regras. O contador fica em memória e zera quando o
  serviço reinicia, então configure também o limite de gastos no Console da Anthropic, que é o limite rígido.

## Rodar localmente

```bash
npm install
```

```bash
cp .env.example .env
```

Preencha `ANTHROPIC_API_KEY` e `APP_TOKEN` no `.env` e rode:

```bash
node --env-file=.env --import tsx src/server.ts
```

No emulador Android, o app acessa o seu computador em `http://10.0.2.2:8080`:

```bash
flutter run --dart-define=PLAN_API_URL=http://10.0.2.2:8080 --dart-define=PLAN_API_TOKEN=SEU_APP_TOKEN
```

## Testes

Os testes usam um cliente falso e não gastam chamadas da API:

```bash
npm test
```

## Publicar

Use o Render, no plano free, com o `render.yaml` da raiz do repositório. O passo a passo está em
[../docs/PUBLICAR.md](../docs/PUBLICAR.md). O `Dockerfile` também roda em outros serviços de contêiner.

## Custo e segurança

- Gerar um plano tem um custo pequeno por chamada, e o ajuste semanal custa menos. Acompanhe o consumo no
  Console da Anthropic e defina um limite de gastos lá.
- O `APP_TOKEN` fica dentro do APK, então ele só barra uso casual. Para abrir o app ao público, troque por login de
  usuário (Firebase Auth, por exemplo) ou pelo Play Integrity, e aplique o limite por usuário.
- O app manda só resumos (data, tipo, duração, distância, pace, FC média). Nenhuma localização sai do celular.
