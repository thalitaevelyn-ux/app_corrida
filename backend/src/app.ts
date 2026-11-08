import { Hono, type Context } from "hono";
import { bodyLimit } from "hono/body-limit";

import { adminSummary } from "./admin.js";
import { adminHtml } from "./admin-page.js";
import type { Authenticator, Caller } from "./auth.js";
import type { Budget } from "./budget.js";
import { Planner, PlannerError } from "./planner.js";
import { deleteAccountHtml, privacyHtml } from "./privacy.js";
import { AjustarRequest, GerarRequest } from "./schema.js";
import type { UsageStore } from "./usage.js";

export interface AppOptions {
  planner: Pick<Planner, "gerar" | "ajustar">;
  auth: Authenticator;
  usage: UsageStore;
  budget: Budget;
  /** Limite de requisições por usuário por hora (proteção contra abuso). */
  maxPerHour?: number;
  /** Config web do Firebase (pública) para o login do /admin. */
  firebaseWebConfig?: Record<string, string>;
}

type Env = { Variables: { caller: Caller } };

export function createApp({ planner, auth, usage, budget, maxPerHour = 20, firebaseWebConfig }: AppOptions) {
  const app = new Hono<Env>();
  const hits = new Map<string, number[]>();

  // ------------------------------------------------------------ públicas
  app.get("/health", (c) => c.json({ ok: true, contas: auth.accounts }));
  app.get("/privacidade", (c) => c.html(privacyHtml()));
  app.get("/excluir-conta", (c) => c.html(deleteAccountHtml()));
  app.get("/admin", (c) => {
    c.header("cache-control", "no-store");
    return c.html(adminHtml(firebaseWebConfig));
  });

  // -------------------------------------------------------- autenticadas
  app.use("/v1/*", bodyLimit({ maxSize: 200 * 1024, onError: (c) => c.json({ erro: "Requisição grande demais." }, 413) }));

  app.use("/v1/*", async (c, next) => {
    const token = (c.req.header("authorization") ?? "").replace(/^Bearer\s+/i, "");
    const caller = await auth.verify(token);
    if (!caller) return c.json({ erro: auth.accounts ? "Entre na sua conta de novo." : "Não autorizado." }, 401);
    // Limite simples por usuário (em memória, por instância).
    const now = Date.now();
    const recent = (hits.get(caller.uid) ?? []).filter((t) => now - t < 3600_000);
    if (recent.length >= maxPerHour && !caller.admin) return c.json({ erro: "Muitas solicitações nesta hora." }, 429);
    recent.push(now);
    hits.set(caller.uid, recent);
    c.set("caller", caller);
    await next();
  });

  const ctx = (c: Context<Env>) => ({ uid: c.get("caller").uid, email: c.get("caller").email });

  app.post("/v1/plano/gerar", async (c) => {
    const body = GerarRequest.safeParse(await c.req.json().catch(() => null));
    if (!body.success) return c.json({ erro: "Dados inválidos.", detalhes: body.error.issues.slice(0, 5) }, 400);
    return handle(() => planner.gerar(body.data, ctx(c)), c);
  });

  app.post("/v1/plano/ajustar", async (c) => {
    const body = AjustarRequest.safeParse(await c.req.json().catch(() => null));
    if (!body.success) return c.json({ erro: "Dados inválidos.", detalhes: body.error.issues.slice(0, 5) }, 400);
    return handle(() => planner.ajustar(body.data, ctx(c)), c);
  });

  /** Exclusão de conta pelo app (exigência da Play Store). */
  app.delete("/v1/conta", async (c) => {
    if (!auth.accounts) return c.json({ erro: "Este servidor não tem contas." }, 400);
    const { uid } = c.get("caller");
    try {
      await usage.deleteUser(uid);
      console.log(`[conta] excluída ${uid.slice(0, 6)}…`);
      return c.json({ ok: true });
    } catch (e) {
      console.error("Falha ao excluir conta:", e);
      return c.json({ erro: "Não foi possível excluir agora. Tente de novo." }, 500);
    }
  });

  // ---------------------------------------------------------------- admin
  app.use("/v1/admin/*", async (c, next) => {
    if (!c.get("caller").admin) return c.json({ erro: "Acesso restrito ao administrador." }, 403);
    await next();
  });
  app.get("/v1/admin/resumo", async (c) => {
    const dias = Math.min(180, Math.max(7, Number(c.req.query("dias") ?? 30) || 30));
    try {
      return c.json(await adminSummary(usage, budget.limits, dias));
    } catch (e) {
      console.error("Falha no resumo:", e);
      return c.json({ erro: "Não foi possível montar o resumo." }, 500);
    }
  });
  app.get("/v1/uso", async (c) => {
    if (!c.get("caller").admin) return c.json({ erro: "Acesso restrito ao administrador." }, 403);
    return c.json(await budget.status());
  });

  return app;
}

async function handle(fn: () => Promise<unknown>, c: Context<Env>) {
  try {
    return c.json(await fn());
  } catch (err) {
    const e = err instanceof PlannerError ? err : new PlannerError("Erro interno.", 500);
    if (!(err instanceof PlannerError)) console.error(err);
    return c.json({ erro: e.message }, e.status as 400);
  }
}
