import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { Budget, BudgetExceeded, costUsd } from "../src/budget.js";
import { MemoryUsageStore, eventFrom } from "../src/usage.js";

describe("custo", () => {
  it("calcula pelo preço do Opus 5.5 (US$ 4 entrada / US$ 20 saída por milhão)", () => {
    assert.equal(costUsd("claude-opus-5-5", { input_tokens: 1_000_000, output_tokens: 0 }), 4);
    assert.equal(costUsd("claude-opus-5-5", { input_tokens: 0, output_tokens: 1_000_000 }), 20);
    assert.equal(costUsd("claude-opus-5-5", { input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 1_000_000 }), 0.2);
  });
  it("modelo desconhecido usa o preço mais alto (erra para gastar menos)", () => {
    assert.ok(costUsd("modelo-x", { input_tokens: 1_000_000, output_tokens: 0 }) >= 10);
  });
});

describe("Budget", () => {
  const ev = (uid: string, cost: number, at: Date) => ({ ...eventFrom({ uid, kind: "gerar", model: "m" }, undefined, cost, true, 1), at });

  it("bloqueia no teto do mês e libera no mês seguinte", async () => {
    const store = new MemoryUsageStore();
    let now = new Date("2026-11-20T10:00:00Z");
    const b = new Budget(store, { monthlyUsd: 1, maxPerDay: 0, maxPerUserDay: 0 }, () => now);
    await store.record(ev("a", 1, now));
    await assert.rejects(b.check("a"), BudgetExceeded);
    now = new Date("2026-12-01T00:00:01Z");
    await b.check("a");
  });

  it("limita planos por dia no total e por usuário", async () => {
    const store = new MemoryUsageStore();
    const now = new Date("2026-11-20T10:00:00Z");
    const b = new Budget(store, { monthlyUsd: 100, maxPerDay: 3, maxPerUserDay: 2 }, () => now);
    await store.record(ev("a", 0, now));
    await store.record(ev("a", 0, now));
    await assert.rejects(b.check("a"), /limite de 2 planos hoje/);
    await b.check("b");
    await store.record(ev("b", 0, now));
    await assert.rejects(b.check("c"), /3 planos por dia/);
  });
});
