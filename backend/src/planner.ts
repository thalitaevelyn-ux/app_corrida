import Anthropic from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";

import { type Budget, BudgetExceeded, costUsd } from "./budget.js";
import { ajustarMessage, gerarMessage, SYSTEM_PROMPT } from "./prompts.js";
import { type AjustarRequest, type GerarRequest, type Plano, PlanoSchema, sanitizePlan } from "./schema.js";
import { eventFrom, type UsageStore } from "./usage.js";

export const MODEL = process.env.CLAUDE_MODEL ?? "claude-opus-5-5";

/** Erro com mensagem que pode ir para o app (sem detalhes internos). */
export class PlannerError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

/** Quem pediu o plano (para limites por usuário e o dashboard). */
export interface PlanContext {
  uid: string;
  email?: string;
}

export class Planner {
  constructor(
    private readonly client: Anthropic = new Anthropic(),
    private readonly budget?: Budget,
    private readonly usage?: UsageStore,
  ) {}

  gerar(req: GerarRequest, ctx: PlanContext = { uid: "local" }): Promise<Plano> {
    return this.run(gerarMessage(req), 1, ctx, "gerar");
  }

  ajustar(req: AjustarRequest, ctx: PlanContext = { uid: "local" }): Promise<Plano> {
    return this.run(ajustarMessage(req), req.semanaAtual, ctx, "ajustar");
  }

  private async run(userText: string, firstWeek: number, ctx: PlanContext, kind: "gerar" | "ajustar"): Promise<Plano> {
    try {
      await this.budget?.check(ctx.uid);
    } catch (err) {
      if (err instanceof BudgetExceeded) throw new PlannerError(`${err.message} O app usa o plano por regras até lá.`, 429);
      throw err;
    }
    const started = Date.now();
    const base = { uid: ctx.uid, email: ctx.email, kind, model: MODEL };
    const log = async (usage: Parameters<typeof costUsd>[1] | undefined, model: string, ok: boolean, error?: string) => {
      if (!this.usage) return;
      const cost = usage ? costUsd(model, usage) : 0;
      try {
        await this.usage.record(eventFrom({ ...base, model }, usage, cost, ok, Date.now() - started, error));
      } catch (e) {
        console.error("Falha ao registrar uso:", e);
      }
      console.log(`[uso] ${kind} ${ok ? "ok" : "erro"} US$ ${cost.toFixed(4)} ${Date.now() - started} ms`);
    };

    let message;
    try {
      // Streaming: planos longos (maratona) podem passar de alguns minutos.
      const stream = this.client.beta.messages.stream({
        model: MODEL,
        max_tokens: 64000,
        // Claude Opus 5.5 usa effort "medium" por padrão; deixamos explícito.
        output_config: { effort: "medium", format: betaZodOutputFormat(PlanoSchema) },
        // Se o modelo recusar por política, a API tenta o modelo recomendado.
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
        system: [{ type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
        messages: [{ role: "user", content: userText }],
      });
      message = await stream.finalMessage();
    } catch (err) {
      const e = toPlannerError(err);
      await log(undefined, MODEL, false, e.message);
      throw e;
    }
    // Contabiliza o custo real, inclusive de respostas recusadas ou truncadas.
    const model = message.model ?? MODEL;

    if (message.stop_reason === "refusal") {
      const msg = "A IA não conseguiu gerar este plano. Tente novamente ou use o plano por regras.";
      await log(message.usage, model, false, "recusa");
      throw new PlannerError(msg, 422);
    }
    if (message.stop_reason === "max_tokens") {
      await log(message.usage, model, false, "resposta truncada");
      throw new PlannerError("O plano ficou longo demais. Tente um prazo menor.", 422);
    }
    const parsed = message.parsed_output;
    if (!parsed) {
      await log(message.usage, model, false, "formato inesperado");
      throw new PlannerError("Resposta da IA em formato inesperado.", 502);
    }
    await log(message.usage, model, true);
    return sanitizePlan(parsed, firstWeek);
  }
}

function toPlannerError(err: unknown): PlannerError {
  if (err instanceof Anthropic.RateLimitError) {
    return new PlannerError("Muitas solicitações agora. Tente de novo em alguns minutos.", 503);
  }
  if (err instanceof Anthropic.AuthenticationError || err instanceof Anthropic.PermissionDeniedError) {
    console.error("Chave da Anthropic inválida ou sem permissão:", err.message);
    return new PlannerError("Servidor do plano mal configurado.", 500);
  }
  if (err instanceof Anthropic.BadRequestError) {
    console.error("Requisição rejeitada pela API:", err.message);
    return new PlannerError("Não foi possível gerar o plano com esses dados.", 400);
  }
  if (err instanceof Anthropic.APIConnectionError) {
    return new PlannerError("Sem conexão com a IA. Tente de novo.", 503);
  }
  if (err instanceof Anthropic.APIError) {
    console.error("Erro da API:", err.status, err.message);
    return new PlannerError("A IA está indisponível no momento.", 503);
  }
  console.error("Erro inesperado:", err);
  return new PlannerError("Erro interno.", 500);
}
