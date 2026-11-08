import Anthropic from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";

import { ajustarMessage, gerarMessage, SYSTEM_PROMPT } from "./prompts.js";
import { type AjustarRequest, type GerarRequest, type Plano, PlanoSchema, sanitizePlan } from "./schema.js";

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

export class Planner {
  constructor(private readonly client: Anthropic = new Anthropic()) {}

  gerar(req: GerarRequest): Promise<Plano> {
    return this.run(gerarMessage(req), 1);
  }

  async ajustar(req: AjustarRequest): Promise<Plano> {
    return this.run(ajustarMessage(req), req.semanaAtual);
  }

  private async run(userText: string, firstWeek: number): Promise<Plano> {
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
      throw toPlannerError(err);
    }

    if (message.stop_reason === "refusal") {
      throw new PlannerError("A IA não conseguiu gerar este plano. Tente novamente ou use o plano por regras.", 422);
    }
    if (message.stop_reason === "max_tokens") {
      throw new PlannerError("O plano ficou longo demais. Tente um prazo menor.", 422);
    }
    const parsed = message.parsed_output;
    if (!parsed) throw new PlannerError("Resposta da IA em formato inesperado.", 502);
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
