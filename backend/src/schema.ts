import { z } from "zod";

/**
 * Formato do plano devolvido ao app. É o mesmo usado pelo app Flutter
 * (lib/models/plan.dart), com chaves em português.
 *
 * Structured outputs exigem todos os campos presentes: campos opcionais são
 * `nullable`. Limites (dia 1–7, km razoáveis) são conferidos depois, em
 * `sanitizePlan`, porque nem toda restrição de JSON Schema é suportada.
 */
export const TIPOS_TREINO = [
  "leve",
  "regenerativo",
  "longao",
  "tempo",
  "intervalado",
  "fartlek",
  "caminhadaCorrida",
  "forca",
  "descanso",
] as const;

export const TreinoSchema = z.object({
  diaSemana: z.number().int().describe("1 = segunda ... 7 = domingo"),
  tipo: z.enum(TIPOS_TREINO),
  titulo: z.string().describe("Curto, ex.: 'Leve 6 km', 'Intervalado 6 × 400 m'"),
  descricao: z.string().describe("Como executar: aquecimento, blocos, recuperação, desaquecimento"),
  distanciaKm: z.number().nullable(),
  duracaoMin: z.number().int().nullable(),
  paceAlvo: z.string().nullable().describe("Ex.: '6:20–6:40 /km' ou '4:55 /km'"),
});

export const SemanaSchema = z.object({
  numero: z.number().int(),
  foco: z.string(),
  kmTotal: z.number(),
  treinos: z.array(TreinoSchema),
});

export const PlanoSchema = z.object({
  resumo: z.string().describe("2–4 frases explicando a estratégia do plano"),
  nivelEstimado: z.string(),
  paces: z.object({
    leve: z.string(),
    limiar: z.string(),
    intervalo: z.string(),
    longao: z.string(),
  }),
  semanas: z.array(SemanaSchema),
  explicacaoAjuste: z
    .string()
    .nullable()
    .describe("No ajuste semanal: o que mudou e por quê, falando com o corredor. Na geração: null."),
});

export type Plano = z.infer<typeof PlanoSchema>;

// ---------------------------------------------------------------- entrada

const Objetivo = z.object({
  tipo: z.enum(["distancia", "tempo", "base", "sofa5k"]),
  distanciaKm: z.number().positive().max(100),
  diasPorSemana: z.number().int().min(2).max(7),
  tempoAlvoSeg: z.number().int().positive().optional(),
  dataProva: z.string().optional(),
  idade: z.number().int().min(10).max(100).optional(),
  pesoKg: z.number().positive().max(300).optional(),
});

const TreinoResumo = z.object({
  data: z.string(),
  tipo: z.string(),
  duracaoMin: z.number(),
  distanciaKm: z.number().optional(),
  paceSegKm: z.number().optional(),
  fcMedia: z.number().optional(),
});

export const GerarRequest = z.object({
  objetivo: Objetivo,
  perfil: z.object({
    kmSemanaMedia: z.number(),
    corridasPorSemana: z.number(),
    tempo5kEstimadoSeg: z.number(),
    maiorCorridaKm: z.number(),
    corridas90d: z.number().int(),
  }),
  treinosRecentes: z.array(TreinoResumo).max(60),
  inicio: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
});

export const AjustarRequest = z.object({
  objetivo: Objetivo,
  paces: z.record(z.string(), z.string()),
  semanaAtual: z.number().int().min(1),
  semanasRestantes: z.array(z.unknown()).min(1).max(30),
  relatorioSemanaAnterior: z.unknown(),
  sensacao: z.enum(["cansado", "normal", "otimo"]).optional(),
});

export type GerarRequest = z.infer<typeof GerarRequest>;
export type AjustarRequest = z.infer<typeof AjustarRequest>;

/**
 * Normaliza o plano do modelo: dia da semana válido, um treino por dia,
 * semanas numeradas em ordem e km total coerente com os treinos.
 */
export function sanitizePlan(p: Plano, firstWeek = 1): Plano {
  const semanas = p.semanas.map((s, i) => {
    const porDia = new Map<number, Plano["semanas"][number]["treinos"][number]>();
    for (const t of s.treinos) {
      const dia = Math.min(7, Math.max(1, Math.round(t.diaSemana)));
      if (!porDia.has(dia)) {
        porDia.set(dia, {
          ...t,
          diaSemana: dia,
          distanciaKm: t.distanciaKm != null && t.distanciaKm > 0 && t.distanciaKm <= 60 ? t.distanciaKm : null,
          duracaoMin: t.duracaoMin != null && t.duracaoMin > 0 && t.duracaoMin <= 400 ? t.duracaoMin : null,
        });
      }
    }
    const treinos = [...porDia.values()].sort((a, b) => a.diaSemana - b.diaSemana);
    const km = treinos.reduce((acc, t) => acc + (t.distanciaKm ?? 0), 0);
    return { ...s, numero: firstWeek + i, kmTotal: Math.round(km * 10) / 10, treinos };
  });
  return { ...p, semanas };
}
