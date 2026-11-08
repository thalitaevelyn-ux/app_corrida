import type { Usage } from "./budget.js";

/** Uma chamada à IA, registrada para o teto de gastos e o dashboard. */
export interface UsageEvent {
  uid: string;
  email?: string;
  kind: "gerar" | "ajustar";
  ok: boolean;
  /** Erro amigável quando ok = false (sem dados do usuário). */
  error?: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  costUsd: number;
  durationMs: number;
  at: Date;
}

export interface DayStats {
  day: string;
  calls: number;
  errors: number;
  costUsd: number;
  inputTokens: number;
  outputTokens: number;
  users: number;
}

export interface UserRow {
  uid: string;
  email?: string;
  name?: string;
  createdAt?: Date;
  lastSeenAt?: Date;
  goalType?: string;
  planSource?: string;
  importedCount?: number;
  lastImportFormat?: string;
  appVersion?: string;
  calls: number;
  costUsd: number;
}

/** Armazenamento de uso. Firestore em produção; memória nos testes e no modo legado. */
export interface UsageStore {
  /** Gasto do mês "AAAA-MM" em US$. */
  monthSpend(month: string): Promise<number>;
  /** Chamadas do dia "AAAA-MM-DD": total e do usuário. */
  dayCalls(day: string, uid: string): Promise<{ total: number; user: number }>;
  record(e: UsageEvent): Promise<void>;
  days(from: string, to: string): Promise<DayStats[]>;
  users(limit: number): Promise<UserRow[]>;
  recent(limit: number): Promise<UsageEvent[]>;
  /** Exclui tudo que liga o usuário aos dados (eventos, perfil, treinos). */
  deleteUser(uid: string): Promise<void>;
}

export function eventFrom(
  base: Pick<UsageEvent, "uid" | "email" | "kind" | "model">,
  usage: Usage | undefined,
  costUsd: number,
  ok: boolean,
  durationMs: number,
  error?: string,
): UsageEvent {
  return {
    ...base,
    ok,
    error,
    inputTokens: usage?.input_tokens ?? 0,
    outputTokens: usage?.output_tokens ?? 0,
    cacheReadTokens: usage?.cache_read_input_tokens ?? 0,
    cacheWriteTokens: usage?.cache_creation_input_tokens ?? 0,
    costUsd,
    durationMs,
    at: new Date(),
  };
}

const dayOf = (d: Date) => d.toISOString().slice(0, 10);

export class MemoryUsageStore implements UsageStore {
  events: UsageEvent[] = [];
  profiles = new Map<string, Omit<UserRow, "calls" | "costUsd">>();

  async monthSpend(month: string) {
    return this.events.filter((e) => e.at.toISOString().startsWith(month)).reduce((s, e) => s + e.costUsd, 0);
  }

  async dayCalls(day: string, uid: string) {
    const today = this.events.filter((e) => dayOf(e.at) === day);
    return { total: today.length, user: today.filter((e) => e.uid === uid).length };
  }

  async record(e: UsageEvent) {
    this.events.push(e);
  }

  async days(from: string, to: string): Promise<DayStats[]> {
    const map = new Map<string, DayStats & { uids: Set<string> }>();
    for (const e of this.events) {
      const d = dayOf(e.at);
      if (d < from || d > to) continue;
      const s = map.get(d) ?? { day: d, calls: 0, errors: 0, costUsd: 0, inputTokens: 0, outputTokens: 0, users: 0, uids: new Set() };
      s.calls++;
      if (!e.ok) s.errors++;
      s.costUsd += e.costUsd;
      s.inputTokens += e.inputTokens;
      s.outputTokens += e.outputTokens;
      s.uids.add(e.uid);
      s.users = s.uids.size;
      map.set(d, s);
    }
    return [...map.values()].map(({ uids: _u, ...rest }) => rest).sort((a, b) => a.day.localeCompare(b.day));
  }

  async users(limit: number): Promise<UserRow[]> {
    const ids = new Set([...this.profiles.keys(), ...this.events.map((e) => e.uid)]);
    return [...ids].slice(0, limit).map((uid) => {
      const mine = this.events.filter((e) => e.uid === uid);
      return { uid, ...this.profiles.get(uid), calls: mine.length, costUsd: mine.reduce((s, e) => s + e.costUsd, 0) };
    });
  }

  async recent(limit: number) {
    return [...this.events].sort((a, b) => b.at.getTime() - a.at.getTime()).slice(0, limit);
  }

  async deleteUser(uid: string) {
    this.events = this.events.filter((e) => e.uid !== uid);
    this.profiles.delete(uid);
  }
}
