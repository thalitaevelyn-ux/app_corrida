import { FieldValue, type Firestore, Timestamp } from "firebase-admin/firestore";

import type { DayStats, UsageEvent, UsageStore, UserRow } from "./usage.js";

const dayOf = (d: Date) => d.toISOString().slice(0, 10);
const toDate = (v: unknown) => (v instanceof Timestamp ? v.toDate() : undefined);

/**
 * Uso no Firestore (só o servidor lê e escreve; ver firestore.rules):
 *   usage_events/{id}       uma chamada à IA
 *   usage_daily/{AAAA-MM-DD} totais do dia + chamadas por usuário
 *   usage_monthly/{AAAA-MM}  gasto do mês (base do teto)
 *   users/{uid}.usage        chamadas e gasto acumulados do usuário
 * Perfis (users/{uid}) são escritos pelo app.
 */
export class FirestoreUsageStore implements UsageStore {
  constructor(
    private readonly db: Firestore,
    private readonly deleteAuthUser: (uid: string) => Promise<void>,
  ) {}

  async monthSpend(month: string) {
    const d = await this.db.collection("usage_monthly").doc(month).get();
    return (d.get("costUsd") as number | undefined) ?? 0;
  }

  async dayCalls(day: string, uid: string) {
    const d = await this.db.collection("usage_daily").doc(day).get();
    const per = (d.get("perUser") as Record<string, number> | undefined) ?? {};
    return { total: (d.get("calls") as number | undefined) ?? 0, user: per[uid] ?? 0 };
  }

  async record(e: UsageEvent) {
    const day = dayOf(e.at),
      month = day.slice(0, 7);
    const inc = FieldValue.increment;
    const batch = this.db.batch();
    batch.set(this.db.collection("usage_events").doc(), {
      ...Object.fromEntries(Object.entries(e).filter(([, v]) => v !== undefined)),
      at: Timestamp.fromDate(e.at),
    });
    batch.set(
      this.db.collection("usage_daily").doc(day),
      {
        calls: inc(1),
        errors: inc(e.ok ? 0 : 1),
        costUsd: inc(e.costUsd),
        inputTokens: inc(e.inputTokens),
        outputTokens: inc(e.outputTokens),
        uids: FieldValue.arrayUnion(e.uid),
        perUser: { [e.uid]: inc(1) },
      },
      { merge: true },
    );
    batch.set(this.db.collection("usage_monthly").doc(month), { costUsd: inc(e.costUsd), calls: inc(1) }, { merge: true });
    if (e.uid !== "app-token" && e.uid !== "local") {
      batch.set(
        this.db.collection("users").doc(e.uid),
        { usage: { calls: inc(1), costUsd: inc(e.costUsd), lastPlanAt: Timestamp.fromDate(e.at) } },
        { merge: true },
      );
    }
    await batch.commit();
  }

  async days(from: string, to: string): Promise<DayStats[]> {
    const snap = await this.db.collection("usage_daily").where("__name__", ">=", from).where("__name__", "<=", to).get();
    return snap.docs.map((d) => ({
      day: d.id,
      calls: d.get("calls") ?? 0,
      errors: d.get("errors") ?? 0,
      costUsd: d.get("costUsd") ?? 0,
      inputTokens: d.get("inputTokens") ?? 0,
      outputTokens: d.get("outputTokens") ?? 0,
      users: ((d.get("uids") as string[] | undefined) ?? []).length,
    }));
  }

  async users(limit: number): Promise<UserRow[]> {
    const snap = await this.db
      .collection("users")
      .select("email", "name", "createdAt", "lastSeenAt", "goalType", "planSource", "importedCount", "lastImportFormat", "appVersion", "usage")
      .limit(limit)
      .get();
    return snap.docs.map((d) => {
      const u = (d.get("usage") as { calls?: number; costUsd?: number } | undefined) ?? {};
      return {
        uid: d.id,
        email: d.get("email"),
        name: d.get("name"),
        createdAt: toDate(d.get("createdAt")),
        lastSeenAt: toDate(d.get("lastSeenAt")),
        goalType: d.get("goalType") ?? undefined,
        planSource: d.get("planSource") ?? undefined,
        importedCount: d.get("importedCount") ?? undefined,
        lastImportFormat: d.get("lastImportFormat") ?? undefined,
        appVersion: d.get("appVersion") ?? undefined,
        calls: u.calls ?? 0,
        costUsd: u.costUsd ?? 0,
      };
    });
  }

  async recent(limit: number): Promise<UsageEvent[]> {
    const snap = await this.db.collection("usage_events").orderBy("at", "desc").limit(limit).get();
    return snap.docs.map((d) => ({ ...(d.data() as UsageEvent), at: toDate(d.get("at")) ?? new Date(0) }));
  }

  async deleteUser(uid: string) {
    const user = this.db.collection("users").doc(uid);
    await this.db.recursiveDelete(user); // perfil + treinos importados
    // Eventos de uso ligados ao usuário. Os totais diários/mensais não têm dados
    // pessoais e ficam (são a base do teto de gastos).
    for (;;) {
      const s = await this.db.collection("usage_events").where("uid", "==", uid).limit(400).get();
      if (s.empty) break;
      const b = this.db.batch();
      s.docs.forEach((d) => b.delete(d.ref));
      await b.commit();
    }
    const days = await this.db.collection("usage_daily").where("uids", "array-contains", uid).get();
    for (const d of days.docs) {
      await d.ref.update({ uids: FieldValue.arrayRemove(uid), [`perUser.${uid}`]: FieldValue.delete() });
    }
    await this.deleteAuthUser(uid);
  }
}
