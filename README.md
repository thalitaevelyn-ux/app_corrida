# Fast run

App Android em Flutter para corredores, de iniciantes a quem quer melhorar o tempo. Ele lê seus treinos do
**Health Connect**, monta um **plano personalizado** para o seu objetivo, ajusta o plano **toda semana** conforme
o que você fez e grava corridas com **GPS**, salvando no Health Connect.

## O que tem

| Tela | O que faz |
|---|---|
| Objetivo | Completar distância (5/10/21/42 km), melhorar tempo, construir base ou "do sofá aos 5 km"; dias por semana, data da prova, idade e peso |
| Início | Progresso do objetivo, semana em dias (feito / perdido / hoje), próximo treino, nota do ajuste semanal, últimos treinos |
| Treinos | Lista do Health Connect (180 dias) com filtro por tipo: corrida, caminhada, bike, academia |
| Detalhe | Distância, duração, pace/velocidade, FC média e máxima, calorias, passos, zonas de FC, parciais e rota (corridas gravadas no app), comparação com o treino planejado |
| Estatísticas | Semanas ou meses: km, treinos, pace médio, tempo ativo, gráfico de volume, divisão por tipo, recordes |
| Plano | Semanas do plano, ritmos de treino, status de cada sessão, "como está se sentindo", gerar de novo |
| Entrar | Login com Google ou e-mail e senha (Firebase), aceite da política, excluir conta |
| Adicionar treino | Importar GPX/TCX/FIT (ou "Compartilhar → Fast run" de outro app), guia para conectar Zepp/Garmin/Strava ao Health Connect, ou gravar com GPS |
| Gravar | GPS em serviço de primeiro plano (funciona com a tela apagada), pace atual e médio, parciais por km, pausa; salva corrida e rota no Health Connect |
| Painel `/admin` | Para a administradora: usuários, ativos, planos gerados, gasto de tokens por dia e por usuário, erros, fontes de dados |

## Como o plano é gerado

- **Com IA** (quando o backend está configurado): o app manda ao `backend/` o objetivo, um resumo do seu nível e os
  últimos treinos (sem localização). O backend chama a Claude API e devolve o plano em JSON validado. No início de
  cada semana, o app envia o relatório da semana anterior (planejado × realizado + sensação) e a IA ajusta as
  semanas seguintes.
- **Sem IA** (padrão do build, ou se o servidor falhar): o app usa regras de treino locais (`lib/services/local_planner.dart`):
  progressão de até ~10% por semana, recuperação a cada 4 semanas, polimento antes da prova e ritmos derivados do
  seu 5 km estimado. O ajuste semanal reduz o volume quando a semana foi fraca ou você está cansado.

A chave da Claude API **nunca** vai no app: qualquer pessoa conseguiria extraí-la do APK. Ela fica só no servidor.

## Rodar o app

Pré-requisitos: Flutter stable, Android SDK 36, um celular Android 9+ (ou emulador com Google Play) com Health Connect.

```bash
flutter pub get
```

```bash
flutter run
```

Com login, nuvem e IA (valores em `config/app.json`; veja [docs/FIREBASE.md](docs/FIREBASE.md)):

```bash
flutter run --dart-define-from-file=config/app.json
```

No primeiro uso, toque em **Conectar** para liberar o Health Connect. O app pede leitura de treinos e FC, escrita de
treinos e rotas e acesso ao histórico (mais de 30 dias), usado para estimar seu nível.

Testes da lógica (plano, aderência, ajuste, GPS, estatísticas):

```bash
flutter test
```

## Rodar o backend

Veja [backend/README.md](backend/README.md). Deploy no Render (plano free) pelo `render.yaml`: passo a passo em [docs/PUBLICAR.md](docs/PUBLICAR.md).

## Estrutura

```
lib/
  models/      workout, goal, plan (JSON igual ao do backend)
  services/    auth_service + firestore_repo (contas e nuvem), importers (GPX/TCX/FIT),
               health_service (Health Connect), run_recorder (GPS), fitness (nível),
               local_planner (plano por regras), plan_progress (aderência + ajuste),
               plan_api (backend de IA), stats, storage_service
  state/       app_state (ChangeNotifier com Provider)
  screens/     onboarding, home, workouts, workout_detail, stats, plan, record, shell
backend/       servidor TypeScript (Hono + SDK da Anthropic)
```

## Limitações conhecidas

- Rotas de outros apps (Strava, Garmin) só aparecem se você liberar "Rotas de exercício → Sempre permitir" no
  Health Connect. Parciais por km só existem nas corridas gravadas por este app.
- A rota é desenhada sem mapa de fundo (evita depender de chave de API de mapas).
- Pacote: `com.thalitaevelyn.fast_run`. Para publicar (Render, chave da API, assinatura, Play Store), siga
  [docs/PUBLICAR.md](docs/PUBLICAR.md): os passos que custam dinheiro estão marcados.
