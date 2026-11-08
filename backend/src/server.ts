import { serve } from "@hono/node-server";

import { createApp } from "./app.js";
import { Budget } from "./budget.js";
import { Planner } from "./planner.js";

const port = Number(process.env.PORT ?? 8080);
const appToken = process.env.APP_TOKEN ?? "";

if (!process.env.ANTHROPIC_API_KEY) {
  console.warn("ANTHROPIC_API_KEY não definida: as chamadas à IA vão falhar.");
}
if (!appToken) {
  console.warn("APP_TOKEN vazio: qualquer um pode chamar este servidor. Defina APP_TOKEN em produção.");
}

// Teto de gastos com a Claude API. 0 desliga (não recomendado).
const budget = new Budget(Number(process.env.MONTHLY_BUDGET_USD ?? 5), Number(process.env.MAX_PER_DAY ?? 60));
console.log(`Teto de gastos: US$ ${budget.monthlyUsd}/mês, ${budget.maxPerDay} planos/dia.`);

const app = createApp({
  planner: new Planner(undefined, budget),
  appToken,
  maxPerHour: Number(process.env.MAX_PER_HOUR ?? 20),
  budget,
});

serve({ fetch: app.fetch, port }, (info) => console.log(`Servidor do plano em http://localhost:${info.port}`));
