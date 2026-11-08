import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type Anthropic from "@anthropic-ai/sdk";

import { createApp } from "../src/app.js";
import { AppTokenAuthenticator, FirebaseAuthenticator, type IdTokenVerifier } from "../src/auth.js";
import { Budget } from "../src/budget.js";
import { Planner, PlannerError } from "../src/planner.js";
import { type Plano, sanitizePlan } from "../src/schema.js";
import { MemoryUsageStore } from "../src/usage.js";

const plano: Plano = {
  resumo: "Plano de teste.",
  nivelEstimado: "Iniciante",
  paces: { leve: "6:40–7:00 /km", limiar: "5:50 /km", intervalo: "5:20 /km", longao: "7:00 /km" },
  semanas: [
    {
      numero: 99,
      foco: "Base",
      kmTotal: 0,
      treinos: [
        { diaSemana: 2, tipo: "leve", titulo: "Leve 5 km", descricao: "Z2", distanciaKm: 5, duracaoMin: null, paceAlvo: "6:50 /km" },
        { diaSemana: 2, tipo: "leve", titulo: "Duplicado", descricao: "", distanciaKm: 5, duracaoMin: null, paceAlvo: null },
        { diaSemana: 9, tipo: "longao", titulo: "Longão", descricao: "", distanciaKm: 500, duracaoMin: 60, paceAlvo: null },
      ],
    },
  ],
  explicacaoAjuste: null,
};

export const gerarBody = {
  objetivo: { tipo: "distancia", distanciaKm: 10, diasPorSemana: 3 },
  perfil: { kmSemanaMedia: 8, corridasPorSemana: 2, tempo5kEstimadoSeg: 1900, maiorCorridaKm: 6, corridas90d: 10 },
  treinosRecentes: [{ data: "2026-11-01T07:00:00", tipo: "corrida", duracaoMin: 35, distanciaKm: 5.1 }],
  inicio: "2026-11-09",
};

const USAGE = { input_tokens: 2000, output_tokens: 5000, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 };

export function fakeClient(result: Partial<{ stop_reason: string; parsed_output: Plano | null }> = {}, seen: unknown[] = []) {
  return {
    beta: {
      messages: {
        stream(params: unknown) {
          seen.push(params);
          return {
            finalMessage: async () => ({ stop_reason: "end_turn", parsed_output: plano, model: "claude-opus-5-5", usage: USAGE, ...result }),
          };
        },
      },
    },
  } as unknown as Anthropic;
}

/** Tokens de teste: "tok-<uid>[-admin]". */
const verifier: IdTokenVerifier = {
  async verifyIdToken(token) {
    const m = /^tok-(\w+?)(-admin)?$/.exec(token);
    if (!m) throw new Error("inválido");
    return { uid: m[1], email: m[2] ? "dona@fastrun.app" : `${m[1]}@x.com`, email_verified: true };
  },
};

function setup(opts: { perUser?: number; monthly?: number; client?: Anthropic } = {}) {
  const usage = new MemoryUsageStore();
  const budget = new Budget(usage, { monthlyUsd: opts.monthly ?? 5, maxPerDay: 100, maxPerUserDay: opts.perUser ?? 5 });
  const planner = new Planner(opts.client ?? fakeClient(), budget, usage);
  const auth = new FirebaseAuthenticator(verifier, "Dona@FastRun.app");
  return { usage, budget, app: createApp({ planner, auth, usage, budget }) };
}

const req = (app: ReturnType<typeof createApp>, method: string, path: string, token?: string, body?: unknown) =>
  app.request(path, {
    method,
    headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

describe("sanitizePlan", () => {
  it("normaliza dias, remove duplicados, renumera e recalcula km", () => {
    const s = sanitizePlan(plano, 3).semanas[0];
    assert.equal(s.numero, 3);
    assert.deepEqual(
      s.treinos.map((t) => t.diaSemana),
      [2, 7],
    );
    assert.equal(s.treinos[1].distanciaKm, null);
    assert.equal(s.kmTotal, 5);
  });
});

describe("Planner", () => {
  it("chama a API com modelo, effort, fallback e prompt em cache", async () => {
    const seen: any[] = [];
    await new Planner(fakeClient({}, seen)).gerar(gerarBody as any);
    const p = seen[0];
    assert.equal(p.model, "claude-opus-5-5");
    assert.equal(p.output_config.effort, "medium");
    assert.ok(p.output_config.format);
    assert.deepEqual(p.betas, ["server-side-fallback-2026-07-01"]);
    assert.equal(p.fallbacks, "default");
    assert.equal(p.system[0].cache_control.type, "ephemeral");
    assert.equal(p.thinking, undefined);
  });

  it("transforma recusa e truncamento em erro amigável e registra o custo mesmo assim", async () => {
    const usage = new MemoryUsageStore();
    const b = new Budget(usage, { monthlyUsd: 5, maxPerDay: 0, maxPerUserDay: 0 });
    const run = (r: object) => new Planner(fakeClient(r), b, usage).gerar(gerarBody as any, { uid: "u1" });
    await assert.rejects(run({ stop_reason: "refusal" }), (e: PlannerError) => e.status === 422);
    await assert.rejects(run({ stop_reason: "max_tokens" }), (e: PlannerError) => e.status === 422);
    await assert.rejects(run({ parsed_output: null }), (e: PlannerError) => e.status === 502);
    assert.equal(usage.events.length, 3);
    assert.ok(usage.events.every((e) => !e.ok && e.costUsd > 0));
  });
});

describe("HTTP com contas (Firebase)", () => {
  it("exige login e registra o uso no nome do usuário", async () => {
    const { app, usage } = setup();
    assert.equal((await req(app, "POST", "/v1/plano/gerar", undefined, gerarBody)).status, 401);
    assert.equal((await req(app, "POST", "/v1/plano/gerar", "lixo", gerarBody)).status, 401);
    const ok = await req(app, "POST", "/v1/plano/gerar", "tok-ana", gerarBody);
    assert.equal(ok.status, 200);
    assert.equal(usage.events[0].uid, "ana");
    assert.equal(usage.events[0].email, "ana@x.com");
    // 2000 × US$4/M + 5000 × US$20/M = US$ 0,108
    assert.ok(Math.abs(usage.events[0].costUsd - 0.108) < 1e-9);
  });

  it("limita planos por usuário por dia, sem afetar os outros", async () => {
    const { app } = setup({ perUser: 2 });
    for (let i = 0; i < 2; i++) assert.equal((await req(app, "POST", "/v1/plano/gerar", "tok-ana", gerarBody)).status, 200);
    const blocked = await req(app, "POST", "/v1/plano/gerar", "tok-ana", gerarBody);
    assert.equal(blocked.status, 429);
    assert.match(((await blocked.json()) as any).erro, /limite de 2 planos hoje/);
    assert.equal((await req(app, "POST", "/v1/plano/gerar", "tok-bia", gerarBody)).status, 200);
  });

  it("para de chamar a IA quando o teto do mês é atingido (contador persistente)", async () => {
    let calls = 0;
    const client = fakeClient();
    const counting = { beta: { messages: { stream: (p: unknown) => (calls++, client.beta.messages.stream(p as any)) } } } as unknown as Anthropic;
    const { app } = setup({ monthly: 0.2, client: counting });
    assert.equal((await req(app, "POST", "/v1/plano/gerar", "tok-ana", gerarBody)).status, 200); // US$ 0,108
    assert.equal((await req(app, "POST", "/v1/plano/gerar", "tok-bia", gerarBody)).status, 200); // US$ 0,216
    assert.equal((await req(app, "POST", "/v1/plano/gerar", "tok-caio", gerarBody)).status, 429);
    assert.equal(calls, 2);
  });

  it("dashboard só para o administrador (e-mail verificado em ADMIN_EMAILS)", async () => {
    const { app } = setup();
    await req(app, "POST", "/v1/plano/gerar", "tok-ana", gerarBody);
    assert.equal((await req(app, "GET", "/v1/admin/resumo", "tok-ana")).status, 403);
    assert.equal((await req(app, "GET", "/v1/uso", "tok-ana")).status, 403);
    const r = await req(app, "GET", "/v1/admin/resumo?dias=7", "tok-dona-admin");
    assert.equal(r.status, 200);
    const d: any = await r.json();
    assert.equal(d.chamadas.total, 1);
    assert.equal(d.porDia.length, 7);
    assert.equal(d.recentes[0].email, "ana@x.com");
    assert.equal(d.custo.tetoMensalUsd, 5);
  });

  it("exclui a conta e os registros de uso do usuário", async () => {
    const { app, usage } = setup();
    await req(app, "POST", "/v1/plano/gerar", "tok-ana", gerarBody);
    await req(app, "POST", "/v1/plano/gerar", "tok-bia", gerarBody);
    assert.equal((await req(app, "DELETE", "/v1/conta", "tok-ana")).status, 200);
    assert.deepEqual(
      usage.events.map((e) => e.uid),
      ["bia"],
    );
  });

  it("rejeita dados inválidos", async () => {
    const { app } = setup();
    assert.equal((await req(app, "POST", "/v1/plano/gerar", "tok-ana", { objetivo: { tipo: "voar" } })).status, 400);
  });
});

describe("modo legado (sem Firebase)", () => {
  it("aceita o APP_TOKEN do APK antigo e não tem contas", async () => {
    const usage = new MemoryUsageStore();
    const budget = new Budget(usage, { monthlyUsd: 5, maxPerDay: 60, maxPerUserDay: 0 });
    const app = createApp({ planner: new Planner(fakeClient(), budget, usage), auth: new AppTokenAuthenticator("segredo"), usage, budget });
    assert.equal((await req(app, "POST", "/v1/plano/gerar", "errado", gerarBody)).status, 401);
    assert.equal((await req(app, "POST", "/v1/plano/gerar", "segredo", gerarBody)).status, 200);
    assert.equal((await req(app, "DELETE", "/v1/conta", "segredo")).status, 400);
  });
});

describe("páginas públicas", () => {
  it("serve privacidade, exclusão de conta e o painel sem exigir token", async () => {
    const { app } = setup();
    const priv = await (await app.request("/privacidade")).text();
    assert.match(priv, /Política de privacidade do Fast run/);
    assert.match(priv, /Na sua conta/);
    assert.match(await (await app.request("/excluir-conta")).text(), /Excluir sua conta do Fast run/);
    const admin = await app.request("/admin");
    assert.equal(admin.status, 200);
    assert.match(await admin.text(), /Login do painel não configurado|FIREBASE_WEB_CONFIG/);
  });

  it("o painel não deixa o config quebrar o HTML", async () => {
    const usage = new MemoryUsageStore();
    const budget = new Budget(usage, { monthlyUsd: 5, maxPerDay: 1, maxPerUserDay: 1 });
    const app = createApp({
      planner: new Planner(fakeClient(), budget, usage),
      auth: new AppTokenAuthenticator(""),
      usage,
      budget,
      firebaseWebConfig: { apiKey: "</script><script>alert(1)</script>" },
    });
    const html = await (await app.request("/admin")).text();
    assert.ok(!html.includes("</script><script>alert(1)"));
  });
});

describe("painel /admin", () => {
  it("o JavaScript gerado é válido (pega aspas quebradas na template string)", async () => {
    const { adminHtml } = await import("../src/admin-page.js");
    const html = adminHtml({ apiKey: "x", projectId: "p", appId: "a", authDomain: "d" });
    const js = /<script type="module">([\s\S]*)<\/script>/.exec(html)?.[1] ?? "";
    assert.ok(js.length > 1000);
    // Compila sem executar (await de nível superior exige função async).
    assert.doesNotThrow(() => new Function("return (async () => {" + js.replace(/^\s*import .*$/gm, "") + "})"));
  });
});
