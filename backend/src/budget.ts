/**
 * Teto de gastos com a Claude API.
 *
 * Antes de cada chamada confere o gasto do mês e os limites do dia; depois,
 * registra o custo real (tokens × preço). Com Firestore os contadores
 * persistem (sobrevivem ao Render reiniciar). O limite de gastos no Console da
 * Anthropic continua sendo a garantia final: configure os dois.
 */
import type { UsageStore } from "./usage.js";

/** Preço em US$ por milhão de tokens. */
interface Price {
  input: number;
  output: number;
  cacheRead: number;
}

const PRICES: Record<string, Price> = {
  "claude-opus-5-5": { input: 4, output: 20, cacheRead: 0.2 },
  "claude-opus-5": { input: 5, output: 25, cacheRead: 0.5 },
  "claude-opus-4-8": { input: 5, output: 25, cacheRead: 0.5 },
  "claude-sonnet-5-5": { input: 2, output: 10, cacheRead: 0.2 },
  "claude-sonnet-5": { input: 2, output: 10, cacheRead: 0.2 },
  "claude-haiku-5-5": { input: 0.1, output: 0.5, cacheRead: 0.01 },
};
// Modelo desconhecido: assume o preço mais alto da tabela, para errar a favor de gastar menos.
const FALLBACK_PRICE: Price = { input: 10, output: 50, cacheRead: 1 };

export interface Usage {
  input_tokens: number;
  output_tokens: number;
  cache_read_input_tokens?: number | null;
  cache_creation_input_tokens?: number | null;
}

export function costUsd(model: string, u: Usage): number {
  const p = PRICES[model] ?? FALLBACK_PRICE;
  const write = u.cache_creation_input_tokens ?? 0;
  const read = u.cache_read_input_tokens ?? 0;
  return (u.input_tokens * p.input + write * p.input * 1.25 + read * p.cacheRead + u.output_tokens * p.output) / 1_000_000;
}

export class BudgetExceeded extends Error {}

export interface BudgetLimits {
  /** US$ por mês (0 = sem teto, não recomendado). */
  monthlyUsd: number;
  /** Chamadas por dia, somando todos os usuários. */
  maxPerDay: number;
  /** Chamadas por dia de cada usuário. */
  maxPerUserDay: number;
}

export class Budget {
  constructor(
    private readonly store: UsageStore,
    readonly limits: BudgetLimits,
    private readonly now: () => Date = () => new Date(),
  ) {}

  /** Lança BudgetExceeded se a chamada não puder acontecer. */
  async check(uid: string) {
    const iso = this.now().toISOString();
    const { monthlyUsd, maxPerDay, maxPerUserDay } = this.limits;
    if (monthlyUsd > 0 && (await this.store.monthSpend(iso.slice(0, 7))) >= monthlyUsd) {
      throw new BudgetExceeded(`Limite de US$ ${monthlyUsd} do mês atingido.`);
    }
    const day = await this.store.dayCalls(iso.slice(0, 10), uid);
    if (maxPerDay > 0 && day.total >= maxPerDay) throw new BudgetExceeded(`Limite de ${maxPerDay} planos por dia atingido.`);
    if (maxPerUserDay > 0 && day.user >= maxPerUserDay) {
      throw new BudgetExceeded(`Você atingiu o limite de ${maxPerUserDay} planos hoje.`);
    }
  }

  async status() {
    const iso = this.now().toISOString();
    const spent = await this.store.monthSpend(iso.slice(0, 7));
    const day = await this.store.dayCalls(iso.slice(0, 10), "");
    return {
      mes: iso.slice(0, 7),
      gastoUsd: Number(spent.toFixed(4)),
      tetoUsd: this.limits.monthlyUsd,
      planosHoje: day.total,
      maxPorDia: this.limits.maxPerDay,
      maxPorUsuarioDia: this.limits.maxPerUserDay,
    };
  }
}
