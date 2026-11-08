import { timingSafeEqual } from "node:crypto";

import { Hono } from "hono";
import { bodyLimit } from "hono/body-limit";

import { Planner, PlannerError } from "./planner.js";
import { AjustarRequest, GerarRequest } from "./schema.js";

export interface AppOptions {
  planner: Pick<Planner, "gerar" | "ajustar">;
  /** Token compartilhado com o app (APP_TOKEN). Vazio = sem autenticação (só para dev local). */
  appToken: string;
  /** Limite de planos por token/IP por hora, para conter custo. */
  maxPerHour?: number;
}

export function createApp({ planner, appToken, maxPerHour = 20 }: AppOptions) {
  const app = new Hono();
  const hits = new Map<string, number[]>();

  app.get("/health", (c) => c.json({ ok: true }));

  app.use("/v1/*", bodyLimit({ maxSize: 200 * 1024, onError: (c) => c.json({ erro: "Requisição grande demais." }, 413) }));

  app.use("/v1/*", async (c, next) => {
    if (appToken) {
      const got = (c.req.header("authorization") ?? "").replace(/^Bearer\s+/i, "");
      const a = Buffer.from(got),
        b = Buffer.from(appToken);
      if (a.length !== b.length || !timingSafeEqual(a, b)) return c.json({ erro: "Não autorizado." }, 401);
    }
    // Limite simples em memória (suficiente para uma instância).
    const key = c.req.header("x-forwarded-for")?.split(",")[0]?.trim() ?? "local";
    const now = Date.now();
    const recent = (hits.get(key) ?? []).filter((t) => now - t < 3600_000);
    if (recent.length >= maxPerHour) return c.json({ erro: "Limite de planos por hora atingido." }, 429);
    recent.push(now);
    hits.set(key, recent);
    await next();
  });

  app.post("/v1/plano/gerar", async (c) => {
    const body = GerarRequest.safeParse(await c.req.json().catch(() => null));
    if (!body.success) return c.json({ erro: "Dados inválidos.", detalhes: body.error.issues.slice(0, 5) }, 400);
    return handle(() => planner.gerar(body.data), c);
  });

  app.post("/v1/plano/ajustar", async (c) => {
    const body = AjustarRequest.safeParse(await c.req.json().catch(() => null));
    if (!body.success) return c.json({ erro: "Dados inválidos.", detalhes: body.error.issues.slice(0, 5) }, 400);
    return handle(() => planner.ajustar(body.data), c);
  });

  return app;
}

async function handle(fn: () => Promise<unknown>, c: { json: (b: unknown, s?: number) => Response }) {
  try {
    return c.json(await fn());
  } catch (err) {
    const e = err instanceof PlannerError ? err : new PlannerError("Erro interno.", 500);
    // Status como número literal aceito pelo Hono.
    return c.json({ erro: e.message }, e.status as 400);
  }
}
