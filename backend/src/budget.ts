/**
 * Teto de gastos com a Claude API.
 *
 * Soma o custo de cada resposta (tokens × preço do modelo) e recusa novas
 * chamadas quando o mês atinge MONTHLY_BUDGET_USD. Também limita o total de
 * planos por dia (MAX_PER_DAY).
 *
 * IMPORTANTE: os contadores ficam em memória. No plano free do Render o serviço
 * reinicia quando "dorme", e o contador volta a zero. Por isso este teto é uma
 * proteção extra; o limite que realmente garante que você não gasta mais é o
 * limite de gastos configurado no Console da Anthropic (veja docs/PUBLICAR.md).
 */

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

export class Budget {
  private month = "";
  private spent = 0;
  private day = "";
  private callsToday = 0;

  constructor(
    readonly monthlyUsd: number,
    readonly maxPerDay: number,
    private readonly now: () => Date = () => new Date(),
  ) {}

  private roll() {
    const d = this.now().toISOString();
    if (d.slice(0, 7) !== this.month) {
      this.month = d.slice(0, 7);
      this.spent = 0;
    }
    if (d.slice(0, 10) !== this.day) {
      this.day = d.slice(0, 10);
      this.callsToday = 0;
    }
  }

  /** Chame antes de cada requisição à API. Lança BudgetExceeded se não puder. */
  reserve() {
    this.roll();
    if (this.monthlyUsd > 0 && this.spent >= this.monthlyUsd) {
      throw new BudgetExceeded(`Limite de US$ ${this.monthlyUsd} do mês atingido.`);
    }
    if (this.maxPerDay > 0 && this.callsToday >= this.maxPerDay) {
      throw new BudgetExceeded(`Limite de ${this.maxPerDay} planos por dia atingido.`);
    }
    this.callsToday++;
  }

  /** Chame depois de cada resposta, com o uso informado pela API. */
  record(model: string, usage: Usage) {
    this.roll();
    const c = costUsd(model, usage);
    this.spent += c;
    console.log(`Custo da chamada: US$ ${c.toFixed(4)} · mês: US$ ${this.spent.toFixed(2)} de ${this.monthlyUsd}`);
    if (this.monthlyUsd > 0 && this.spent >= this.monthlyUsd * 0.8) {
      console.warn(`ATENÇÃO: 80% do teto mensal usado (US$ ${this.spent.toFixed(2)}).`);
    }
  }

  status() {
    this.roll();
    return { mes: this.month, gastoUsd: Number(this.spent.toFixed(4)), tetoUsd: this.monthlyUsd, planosHoje: this.callsToday, maxPorDia: this.maxPerDay };
  }
}
