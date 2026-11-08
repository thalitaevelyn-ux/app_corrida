import { serve } from "@hono/node-server";
import { cert, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";

import { createApp } from "./app.js";
import { AppTokenAuthenticator, type Authenticator, FirebaseAuthenticator } from "./auth.js";
import { Budget } from "./budget.js";
import { FirestoreUsageStore } from "./firestore-store.js";
import { Planner } from "./planner.js";
import { MemoryUsageStore, type UsageStore } from "./usage.js";

const env = process.env;
const port = Number(env.PORT ?? 8080);

if (!env.ANTHROPIC_API_KEY) console.warn("ANTHROPIC_API_KEY não definida: as chamadas à IA vão falhar.");

// Firebase: com a conta de serviço, o servidor valida logins e grava o uso no
// Firestore. Sem ela, roda no modo legado (APP_TOKEN, contadores em memória).
let auth: Authenticator;
let usage: UsageStore;
if (env.FIREBASE_SERVICE_ACCOUNT) {
  const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
  const fb = initializeApp({ credential: cert(sa) });
  const db = getFirestore(fb);
  db.settings({ ignoreUndefinedProperties: true });
  const fbAuth = getAuth(fb);
  auth = new FirebaseAuthenticator(fbAuth, env.ADMIN_EMAILS ?? "");
  usage = new FirestoreUsageStore(db, (uid) => fbAuth.deleteUser(uid));
  console.log(`Firebase ativo (projeto ${sa.project_id}). Admins: ${env.ADMIN_EMAILS || "nenhum"}.`);
} else {
  auth = new AppTokenAuthenticator(env.APP_TOKEN ?? "");
  usage = new MemoryUsageStore();
  console.warn("FIREBASE_SERVICE_ACCOUNT ausente: modo sem contas (APP_TOKEN) e uso só em memória.");
}

const budget = new Budget(usage, {
  monthlyUsd: Number(env.MONTHLY_BUDGET_USD ?? 5),
  maxPerDay: Number(env.MAX_PER_DAY ?? 60),
  maxPerUserDay: Number(env.MAX_PER_USER_DAY ?? 5),
});
console.log(`Teto: US$ ${budget.limits.monthlyUsd}/mês, ${budget.limits.maxPerDay} planos/dia, ${budget.limits.maxPerUserDay} por usuário/dia.`);

let firebaseWebConfig: Record<string, string> | undefined;
try {
  firebaseWebConfig = env.FIREBASE_WEB_CONFIG ? JSON.parse(env.FIREBASE_WEB_CONFIG) : undefined;
} catch {
  console.warn("FIREBASE_WEB_CONFIG não é um JSON válido; /admin fica sem login.");
}

const app = createApp({
  planner: new Planner(undefined, budget, usage),
  auth,
  usage,
  budget,
  maxPerHour: Number(env.MAX_PER_HOUR ?? 20),
  firebaseWebConfig,
});

serve({ fetch: app.fetch, port }, (info) => console.log(`Servidor do plano em http://localhost:${info.port}`));
