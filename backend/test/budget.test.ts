import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type Anthropic from "@anthropic-ai/sdk";

import { Budget, BudgetExceeded, costUsd } from "../src/budget.js";
import { Planner, PlannerError } from "../src/planner.js";

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
  it("bloqueia quando o teto do mês é atingido e libera no mês seguinte", () => {
    let now = new Date("2026-11-20T10:00:00Z");
    const b = new Budget(1, 0, () => now);
    b.reserve();
    b.record("claude-opus-5-5", { input_tokens: 0, output_tokens: 50_000 }); // US$ 1,00
    assert.throws(() => b.reserve(), BudgetExceeded);
    now = new Date("2026-12-01T00:00:01Z");
    assert.doesNotThrow(() => b.reserve());
  });

  it("limita planos por dia", () => {
    const b = new Budget(100, 2, () => new Date("2026-11-20T10:00:00Z"));
    b.reserve();
    b.reserve();
    assert.throws(() => b.reserve(), /por dia/);
  });

  it("o Planner não chama a API quando o teto estourou", async () => {
    let calls = 0;
    const client = {
      beta: { messages: { stream() { calls++; throw new Error("não deveria chamar"); } } },
    } as unknown as Anthropic;
    const b = new Budget(1, 0);
    b.record("claude-opus-5-5", { input_tokens: 0, output_tokens: 60_000 });
    await assert.rejects(new Planner(client, b).gerar({} as any), (e: PlannerError) => e.status === 429);
    assert.equal(calls, 0);
  });
});
