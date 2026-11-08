import type { BudgetLimits } from "./budget.js";
import type { UsageStore } from "./usage.js";

const DAY = 86_400_000;
const iso = (d: Date) => d.toISOString().slice(0, 10);

function count<T>(items: T[], key: (t: T) => string | undefined) {
  const m: Record<string, number> = {};
  for (const i of items) {
    const k = key(i) ?? "não informado";
    m[k] = (m[k] ?? 0) + 1;
  }
  return Object.fromEntries(Object.entries(m).sort((a, b) => b[1] - a[1]));
}

/** Resumo para o dashboard gerencial (/admin). */
export async function adminSummary(store: UsageStore, limits: BudgetLimits, days = 30, now = new Date()) {
  const from = new Date(now.getTime() - (days - 1) * DAY);
  const [daily, users, recent, monthSpend] = await Promise.all([
    store.days(iso(from), iso(now)),
    store.users(5000),
    store.recent(200),
    store.monthSpend(iso(now).slice(0, 7)),
  ]);

  // Série diária completa (dias sem uso aparecem com zero).
  const byDay = new Map(daily.map((d) => [d.day, d]));
  const newByDay = count(
    users.filter((u) => u.createdAt && u.createdAt >= from),
    (u) => iso(u.createdAt!),
  );
  const porDia = [];
  for (let t = from.getTime(); t <= now.getTime() + 1; t += DAY) {
    const d = iso(new Date(t));
    const s = byDay.get(d);
    porDia.push({
      dia: d,
      chamadas: s?.calls ?? 0,
      erros: s?.errors ?? 0,
      custoUsd: Number((s?.costUsd ?? 0).toFixed(4)),
      tokensEntrada: s?.inputTokens ?? 0,
      tokensSaida: s?.outputTokens ?? 0,
      usuariosIa: s?.users ?? 0,
      novosUsuarios: newByDay[d] ?? 0,
    });
  }

  const calls = daily.reduce((a, d) => a + d.calls, 0);
  const errors = daily.reduce((a, d) => a + d.errors, 0);
  const periodCost = daily.reduce((a, d) => a + d.costUsd, 0);
  const okCalls = calls - errors;
  const active = (ms: number) => users.filter((u) => u.lastSeenAt && now.getTime() - u.lastSeenAt.getTime() <= ms).length;
  const dayOfMonth = now.getUTCDate();
  const daysInMonth = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 0)).getUTCDate();
  const okRecent = recent.filter((e) => e.ok);

  return {
    geradoEm: now.toISOString(),
    periodo: { de: iso(from), ate: iso(now), dias: days },
    custo: {
      mesUsd: Number(monthSpend.toFixed(4)),
      tetoMensalUsd: limits.monthlyUsd,
      projecaoMesUsd: Number(((monthSpend / dayOfMonth) * daysInMonth).toFixed(2)),
      periodoUsd: Number(periodCost.toFixed(4)),
      mediaPorPlanoUsd: okCalls > 0 ? Number((periodCost / okCalls).toFixed(4)) : 0,
    },
    chamadas: {
      total: calls,
      erros: errors,
      taxaErro: calls > 0 ? Number((errors / calls).toFixed(3)) : 0,
      duracaoMediaSeg: okRecent.length ? Math.round(okRecent.reduce((a, e) => a + e.durationMs, 0) / okRecent.length / 1000) : 0,
      porTipo: count(recent, (e) => e.kind),
    },
    tokens: {
      entrada: daily.reduce((a, d) => a + d.inputTokens, 0),
      saida: daily.reduce((a, d) => a + d.outputTokens, 0),
    },
    usuarios: {
      total: users.length,
      novosNoPeriodo: users.filter((u) => u.createdAt && u.createdAt >= from).length,
      ativos1d: active(DAY),
      ativos7d: active(7 * DAY),
      ativos30d: active(30 * DAY),
      comPlanoIa: users.filter((u) => u.planSource === "ia").length,
      comImportacao: users.filter((u) => (u.importedCount ?? 0) > 0).length,
    },
    objetivos: count(users, (u) => u.goalType),
    origemPlano: count(users, (u) => u.planSource),
    formatosImportados: count(
      users.filter((u) => u.lastImportFormat),
      (u) => u.lastImportFormat,
    ),
    treinosImportados: users.reduce((a, u) => a + (u.importedCount ?? 0), 0),
    versoesApp: count(users, (u) => u.appVersion),
    porDia,
    topUsuarios: [...users]
      .sort((a, b) => b.costUsd - a.costUsd)
      .slice(0, 15)
      .map((u) => ({
        email: u.email ?? u.uid.slice(0, 8),
        nome: u.name,
        planos: u.calls,
        custoUsd: Number(u.costUsd.toFixed(4)),
        criadoEm: u.createdAt?.toISOString(),
        ultimoAcesso: u.lastSeenAt?.toISOString(),
        objetivo: u.goalType,
      })),
    recentes: recent.slice(0, 25).map((e) => ({
      em: e.at.toISOString(),
      email: e.email ?? e.uid.slice(0, 8),
      tipo: e.kind,
      ok: e.ok,
      erro: e.error,
      custoUsd: Number(e.costUsd.toFixed(4)),
      tokens: e.inputTokens + e.outputTokens,
      duracaoSeg: Math.round(e.durationMs / 1000),
    })),
  };
}
