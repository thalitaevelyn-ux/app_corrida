import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type Anthropic from "@anthropic-ai/sdk";

import { createApp } from "../src/app.js";
import { Planner, PlannerError } from "../src/planner.js";
import { type Plano, sanitizePlan } from "../src/schema.js";

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
        // Dia repetido: deve ser descartado.
        { diaSemana: 2, tipo: "leve", titulo: "Duplicado", descricao: "", distanciaKm: 5, duracaoMin: null, paceAlvo: null },
        // Dia fora do intervalo vira domingo; distância absurda vira null.
        { diaSemana: 9, tipo: "longao", titulo: "Longão", descricao: "", distanciaKm: 500, duracaoMin: 60, paceAlvo: null },
      ],
    },
  ],
  explicacaoAjuste: null,
};

const gerarBody = {
  objetivo: { tipo: "distancia", distanciaKm: 10, diasPorSemana: 3 },
  perfil: { kmSemanaMedia: 8, corridasPorSemana: 2, tempo5kEstimadoSeg: 1900, maiorCorridaKm: 6, corridas90d: 10 },
  treinosRecentes: [{ data: "2026-11-01T07:00:00", tipo: "corrida", duracaoMin: 35, distanciaKm: 5.1 }],
  inicio: "2026-11-09",
};

function fakeClient(result: Partial<{ stop_reason: string; parsed_output: Plano | null }>, seen: unknown[] = []) {
  return {
    beta: {
      messages: {
        stream(params: unknown) {
          seen.push(params);
          return { finalMessage: async () => ({ stop_reason: "end_turn", parsed_output: plano, ...result }) };
        },
      },
    },
  } as unknown as Anthropic;
}

describe("sanitizePlan", () => {
  it("normaliza dias, remove duplicados, renumera e recalcula km", () => {
    const p = sanitizePlan(plano, 3);
    const s = p.semanas[0];
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
    const out = await new Planner(fakeClient({}, seen)).gerar(gerarBody as any);
    assert.equal(out.semanas[0].numero, 1);
    const p = seen[0];
    assert.equal(p.model, "claude-opus-5-5");
    assert.equal(p.output_config.effort, "medium");
    assert.ok(p.output_config.format, "structured output configurado");
    assert.deepEqual(p.betas, ["server-side-fallback-2026-07-01"]);
    assert.equal(p.fallbacks, "default");
    assert.equal(p.system[0].cache_control.type, "ephemeral");
    assert.equal(p.thinking, undefined, "Opus 5.5 usa thinking adaptativo por padrão");
    assert.match(p.messages[0].content, /"distanciaKm": 10/);
  });

  it("transforma recusa e truncamento em erro amigável", async () => {
    await assert.rejects(new Planner(fakeClient({ stop_reason: "refusal" })).gerar(gerarBody as any), (e: PlannerError) => e.status === 422);
    await assert.rejects(new Planner(fakeClient({ stop_reason: "max_tokens" })).gerar(gerarBody as any), (e: PlannerError) => e.status === 422);
    await assert.rejects(new Planner(fakeClient({ parsed_output: null })).gerar(gerarBody as any), (e: PlannerError) => e.status === 502);
  });
});

describe("HTTP", () => {
  const planner = new Planner(fakeClient({}));
  const post = (app: ReturnType<typeof createApp>, path: string, body: unknown, token?: string) =>
    app.request(path, {
      method: "POST",
      headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: JSON.stringify(body),
    });

  it("exige o token do app", async () => {
    const app = createApp({ planner, appToken: "segredo" });
    assert.equal((await post(app, "/v1/plano/gerar", gerarBody)).status, 401);
    assert.equal((await post(app, "/v1/plano/gerar", gerarBody, "errado")).status, 401);
    const ok = await post(app, "/v1/plano/gerar", gerarBody, "segredo");
    assert.equal(ok.status, 200);
    const json: any = await ok.json();
    assert.equal(json.semanas.length, 1);
  });

  it("rejeita dados inválidos", async () => {
    const app = createApp({ planner, appToken: "" });
    const res = await post(app, "/v1/plano/gerar", { objetivo: { tipo: "voar" } });
    assert.equal(res.status, 400);
  });

  it("limita planos por hora", async () => {
    const app = createApp({ planner, appToken: "", maxPerHour: 2 });
    assert.equal((await post(app, "/v1/plano/gerar", gerarBody)).status, 200);
    assert.equal((await post(app, "/v1/plano/gerar", gerarBody)).status, 200);
    assert.equal((await post(app, "/v1/plano/gerar", gerarBody)).status, 429);
  });

  it("aceita o pedido de ajuste do app", async () => {
    const app = createApp({ planner, appToken: "" });
    const res = await post(app, "/v1/plano/ajustar", {
      objetivo: gerarBody.objetivo,
      paces: plano.paces,
      semanaAtual: 5,
      semanasRestantes: [{ numero: 5 }],
      relatorioSemanaAnterior: { semana: 4 },
      sensacao: "cansado",
    });
    assert.equal(res.status, 200);
    const json: any = await res.json();
    assert.equal(json.semanas[0].numero, 5);
  });
});
