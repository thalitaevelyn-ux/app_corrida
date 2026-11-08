/**
 * Dashboard gerencial em /admin. Login com Google (Firebase Auth, SDK web);
 * os dados vêm de /v1/admin/resumo, que só responde para e-mails em ADMIN_EMAILS.
 * Gráficos em SVG puro (sem bibliotecas), tema claro/escuro.
 *
 * Observação: o JavaScript abaixo evita `${...}` porque está dentro de uma
 * template string do TypeScript.
 */
const FIREBASE_SDK = "https://www.gstatic.com/firebasejs/13.0.0";

export function adminHtml(webConfig?: Record<string, string>): string {
  const cfg = JSON.stringify(webConfig ?? null).replace(/</g, "\\u003c");
  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Fast run · Painel</title>
<style>
:root {
  color-scheme: light;
  --page: #f9f9f7; --surface: #fcfcfb; --ink: #0b0b0b; --ink-2: #52514e; --muted: #6f6e69;
  --grid: #e1e0d9; --axis: #c3c2b7; --border: rgba(11,11,11,0.10);
  --s1: #2a78d6; --crit: #d03b3b; --good: #006300; --accent: #b33f0b;
}
@media (prefers-color-scheme: dark) {
  :root:where(:not([data-theme="light"])) {
    color-scheme: dark;
    --page: #0d0d0d; --surface: #1a1a19; --ink: #f0efec; --ink-2: #c3c2b7; --muted: #a3a29b;
    --grid: #2c2c2a; --axis: #383835; --border: rgba(255,255,255,0.10);
    --s1: #3987e5; --crit: #d03b3b; --good: #0ca30c; --accent: #ffb599;
  }
}
:root[data-theme="dark"] {
  color-scheme: dark;
  --page: #0d0d0d; --surface: #1a1a19; --ink: #f0efec; --ink-2: #c3c2b7; --muted: #a3a29b;
  --grid: #2c2c2a; --axis: #383835; --border: rgba(255,255,255,0.10);
  --s1: #3987e5; --crit: #d03b3b; --good: #0ca30c; --accent: #ffb599;
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--page); color: var(--ink); font: 14px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif; }
header { display: flex; flex-wrap: wrap; gap: 12px; align-items: center; justify-content: space-between; padding: 16px; max-width: 1200px; margin: 0 auto; }
h1 { font-size: 20px; margin: 0; } h1 span { color: var(--accent); }
h2 { font-size: 15px; margin: 0 0 4px; }
main { max-width: 1200px; margin: 0 auto; padding: 0 16px 48px; display: grid; gap: 16px; }
.row { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
button { font: inherit; border: 1px solid var(--border); background: var(--surface); color: var(--ink); border-radius: 999px; padding: 8px 14px; min-height: 40px; cursor: pointer; }
button[aria-pressed="true"] { background: var(--ink); color: var(--surface); }
button.primary { background: var(--accent); color: #fff; border: 0; }
.card { background: var(--surface); border: 1px solid var(--border); border-radius: 16px; padding: 16px; min-width: 0; }
.kpis { display: grid; gap: 12px; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); }
.kpi .label { color: var(--ink-2); font-size: 13px; }
.kpi .value { font-size: 28px; font-weight: 700; margin-top: 2px; }
.kpi .note { color: var(--muted); font-size: 12px; margin-top: 2px; }
.meter { height: 8px; border-radius: 4px; background: var(--grid); margin-top: 8px; overflow: hidden; }
.meter > div { height: 100%; border-radius: 4px; background: var(--s1); }
.meter.over > div { background: var(--crit); }
.grid2 { display: grid; gap: 16px; grid-template-columns: repeat(auto-fit, minmax(340px, 1fr)); }
.grid3 { display: grid; gap: 16px; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); }
.sub { color: var(--ink-2); font-size: 12px; margin: 0 0 8px; }
svg text { fill: var(--muted); font-size: 11px; font-variant-numeric: tabular-nums; }
.legend { display: flex; gap: 14px; font-size: 12px; color: var(--ink-2); margin: 4px 0 6px; }
.legend i { display: inline-block; width: 10px; height: 10px; border-radius: 2px; margin-right: 5px; vertical-align: -1px; }
.bar { fill: var(--s1); } .bar.err { fill: var(--crit); }
.hit { fill: transparent; cursor: default; outline: none; }
.hit:focus-visible { stroke: var(--ink); stroke-width: 1.5; }
.tip { position: fixed; pointer-events: none; background: var(--ink); color: var(--surface); padding: 6px 9px; border-radius: 8px; font-size: 12px; white-space: pre; z-index: 10; display: none; }
.hbar { display: grid; grid-template-columns: minmax(80px, 34%) 1fr 44px; gap: 8px; align-items: center; margin: 6px 0; font-size: 13px; }
.hbar .track { height: 10px; background: var(--grid); border-radius: 0 4px 4px 0; overflow: hidden; }
.hbar .fill { height: 100%; background: var(--s1); border-radius: 0 4px 4px 0; }
.hbar .n { text-align: right; font-variant-numeric: tabular-nums; color: var(--ink-2); }
.table-wrap { overflow-x: auto; }
table { width: 100%; border-collapse: collapse; font-size: 13px; }
th, td { text-align: left; padding: 7px 8px; border-bottom: 1px solid var(--grid); white-space: nowrap; }
th { color: var(--ink-2); font-weight: 600; }
td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; }
.status { display: inline-flex; gap: 4px; align-items: center; font-weight: 600; }
.status.ok { color: var(--good); } .status.err { color: var(--crit); }
details { margin-top: 8px; } summary { cursor: pointer; color: var(--ink-2); font-size: 12px; }
.center { text-align: center; padding: 64px 16px; }
.muted { color: var(--muted); }
.error { color: var(--crit); }
</style>
</head>
<body>
<header>
  <h1><span>Fast run</span> · Painel</h1>
  <div class="row" id="controls" hidden>
    <div class="row" role="group" aria-label="Período">
      <button data-days="7" aria-pressed="false">7 dias</button>
      <button data-days="30" aria-pressed="true">30 dias</button>
      <button data-days="90" aria-pressed="false">90 dias</button>
    </div>
    <button id="refresh" aria-label="Atualizar dados">Atualizar</button>
    <button id="theme" aria-label="Alternar tema claro/escuro">Tema</button>
    <button id="logout">Sair</button>
  </div>
</header>
<main id="app"><div class="card center muted">Carregando…</div></main>
<div class="tip" id="tip" role="status" aria-live="polite"></div>

<script type="module">
const CONFIG = ${cfg};
const app = document.getElementById("app");
const tip = document.getElementById("tip");
let days = 30, auth, user;

function esc(v) { return String(v == null ? "" : v).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]); }
const usd = (v, d) => "US$ " + Number(v || 0).toLocaleString("pt-BR", { minimumFractionDigits: d == null ? 2 : d, maximumFractionDigits: d == null ? 2 : d });
const int = (v) => Number(v || 0).toLocaleString("pt-BR");
const pct = (v) => (Number(v || 0) * 100).toLocaleString("pt-BR", { maximumFractionDigits: 1 }) + "%";
const dm = (s) => s.slice(8, 10) + "/" + s.slice(5, 7);
const when = (s) => s ? new Date(s).toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }) : "—";
const LABELS = { distancia: "Completar distância", tempo: "Melhorar tempo", base: "Construir base", sofa5k: "Sofá aos 5 km", ia: "IA", local: "Regras (sem IA)", gpx: "GPX", tcx: "TCX", fit: "FIT", gerar: "Gerar plano", ajustar: "Ajuste semanal" };
const lab = (k) => LABELS[k] || k;

function message(html) { app.innerHTML = '<div class="card center">' + html + "</div>"; }

// ------------------------------------------------------------- login
if (!CONFIG) {
  message('<h2>Login do painel não configurado</h2><p class="muted">Defina FIREBASE_WEB_CONFIG no Render (veja docs/PUBLICAR.md).</p>');
} else {
  const { initializeApp } = await import("${FIREBASE_SDK}/firebase-app.js");
  const fa = await import("${FIREBASE_SDK}/firebase-auth.js");
  auth = fa.getAuth(initializeApp(CONFIG));
  fa.onAuthStateChanged(auth, (u) => {
    user = u;
    document.getElementById("controls").hidden = !u;
    if (!u) {
      message('<h2>Painel do administrador</h2><p class="muted">Entre com a conta Google cadastrada como administradora.</p><button class="primary" id="login">Entrar com Google</button>');
      document.getElementById("login").onclick = () => fa.signInWithPopup(auth, new fa.GoogleAuthProvider()).catch((e) => message('<p class="error">' + esc(e.message) + "</p>"));
    } else load();
  });
  document.getElementById("logout").onclick = () => fa.signOut(auth);
}

document.querySelectorAll("[data-days]").forEach((b) => b.onclick = () => {
  days = Number(b.dataset.days);
  document.querySelectorAll("[data-days]").forEach((x) => x.setAttribute("aria-pressed", String(x === b)));
  load();
});
document.getElementById("refresh").onclick = () => load();
document.getElementById("theme").onclick = () => {
  const r = document.documentElement;
  const dark = r.dataset.theme ? r.dataset.theme === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
  r.dataset.theme = dark ? "light" : "dark";
};

async function load() {
  if (!user) return;
  try {
    const token = await user.getIdToken();
    const res = await fetch("/v1/admin/resumo?dias=" + days, { headers: { authorization: "Bearer " + token } });
    const body = await res.json();
    if (!res.ok) return message('<h2>Sem acesso</h2><p class="error">' + esc(body.erro || res.status) + '</p><p class="muted">Conta: ' + esc(user.email) + "</p>");
    render(body);
  } catch (e) {
    message('<p class="error">Não foi possível carregar: ' + esc(e.message) + "</p>");
  }
}

// ------------------------------------------------------------- gráficos
function bars(data, opts) {
  // data: [{ label, parts: [{ v, cls, name }] }]  — barras (empilhadas) com baseline em zero.
  const W = Math.max(260, Math.round(opts.width || 600)), H = 200, L = 40, R = 8, T = 10, B = 24;
  const max = Math.max(opts.integer ? 1 : 1e-9, ...data.map((d) => d.parts.reduce((a, p) => a + p.v, 0)));
  const step = niceStep(max, opts.integer), ticks = Math.max(1, Math.ceil(max / step - 1e-9));
  const nice = step * ticks, iw = W - L - R, ih = H - T - B;
  const bw = iw / data.length, gap = Math.min(4, bw * 0.25);
  let s = '<svg viewBox="0 0 ' + W + " " + H + '" width="100%" role="img" aria-label="' + esc(opts.title) + '">';
  for (let i = 0; i <= ticks; i++) {
    const y = T + ih - (ih * i) / ticks, v = step * i;
    s += '<line x1="' + L + '" x2="' + (W - R) + '" y1="' + y + '" y2="' + y + '" stroke="var(--' + (i ? "grid" : "axis") + ')" stroke-width="1"/>';
    s += '<text x="' + (L - 6) + '" y="' + (y + 4) + '" text-anchor="end">' + esc(opts.tick(v)) + "</text>";
  }
  const every = Math.max(1, Math.ceil(data.length / Math.max(2, Math.floor(iw / 56))));
  const lastLabeled = Math.floor((data.length - 1) / every) * every;
  data.forEach((d, i) => {
    const x = L + i * bw + gap / 2, w = Math.max(1, bw - gap);
    let y0 = T + ih;
    d.parts.forEach((p, j) => {
      const h = (p.v / nice) * ih;
      if (h <= 0) return;
      const top = j === d.parts.length - 1 || d.parts.slice(j + 1).every((q) => q.v === 0);
      const r = top ? Math.min(4, w / 2, h) : 0;
      // segmento com cantos de cima arredondados só no topo; 2px de espaço entre segmentos
      const yy = y0 - h, hh = j > 0 ? Math.max(0, h - 2) : h;
      s += '<path class="bar ' + (p.cls || "") + '" d="' + roundTop(x, yy, w, hh, r) + '"/>';
      y0 -= h;
    });
    if (i % every === 0 || (i === data.length - 1 && (i - lastLabeled) * bw >= 44)) {
      const cx = x + w / 2, edge = cx + 18 > W ? ["end", W - 1] : cx - 18 < 0 ? ["start", 1] : ["middle", cx];
      s += '<text x="' + edge[1] + '" y="' + (H - 6) + '" text-anchor="' + edge[0] + '">' + esc(d.label) + "</text>";
    }
    s += '<rect class="hit" tabindex="0" x="' + (L + i * bw) + '" y="' + T + '" width="' + bw + '" height="' + ih + '" data-tip="' + esc(opts.tip(d)) + '"/>';
  });
  return s + "</svg>";
}
function roundTop(x, y, w, h, r) {
  return "M" + x + "," + (y + h) + "V" + (y + r) + "Q" + x + "," + y + " " + (x + r) + "," + y + "H" + (x + w - r) + "Q" + (x + w) + "," + y + " " + (x + w) + "," + (y + r) + "V" + (y + h) + "Z";
}
// Passo "redondo" (1, 2 ou 5 × 10^n) com no máximo 5 divisões.
function niceStep(max, integer) {
  let p = Math.pow(10, Math.floor(Math.log10(max / 5)));
  for (;;) {
    for (const m of [1, 2, 5]) {
      const st = m * p;
      if ((!integer || st >= 1) && max / st <= 5) return integer ? Math.max(1, Math.round(st)) : st;
    }
    p *= 10;
  }
}
function table(head, rows, numCols) {
  const n = new Set(numCols || []);
  return '<div class="table-wrap"><table><thead><tr>' + head.map((h, i) => '<th class="' + (n.has(i) ? "num" : "") + '">' + esc(h) + "</th>").join("") + "</tr></thead><tbody>" +
    (rows.length ? rows.map((r) => "<tr>" + r.map((c, i) => '<td class="' + (n.has(i) ? "num" : "") + '">' + c + "</td>").join("") + "</tr>").join("") : '<tr><td colspan="' + head.length + '" class="muted">Sem dados no período.</td></tr>') +
    "</tbody></table></div>";
}
function hbars(obj) {
  const e = Object.entries(obj || {});
  if (!e.length) return '<p class="muted">Sem dados ainda.</p>';
  const max = Math.max(...e.map((x) => x[1]));
  return e.map(([k, v]) => '<div class="hbar"><span>' + esc(lab(k)) + '</span><div class="track"><div class="fill" style="width:' + ((v / max) * 100).toFixed(1) + '%"></div></div><span class="n">' + int(v) + "</span></div>").join("");
}
function kpi(label, value, note, meter) {
  let m = "";
  if (meter) m = '<div class="meter' + (meter >= 1 ? " over" : "") + '" role="img" aria-label="' + pct(meter) + ' do teto"><div style="width:' + Math.min(100, meter * 100).toFixed(1) + '%"></div></div>';
  return '<div class="card kpi"><div class="label">' + esc(label) + '</div><div class="value">' + value + '</div>' + m + (note ? '<div class="note">' + note + "</div>" : "") + "</div>";
}

// Largura útil de um gráfico numa grade de N colunas (cartão: 16px de padding + borda).
function colW(n) {
  const w = app.clientWidth, cols = w >= n * 340 + (n - 1) * 16 ? n : 1;
  return (w - (cols - 1) * 16) / cols - 34;
}
let last = null, resizeTimer;
addEventListener("resize", () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(() => last && render(last), 150); });

// ------------------------------------------------------------- tela
function render(d) {
  last = d;
  const c = d.custo, u = d.usuarios, ch = d.chamadas;
  const dias = d.porDia;
  const used = c.tetoMensalUsd > 0 ? c.mesUsd / c.tetoMensalUsd : 0;
  let h = '<section class="kpis" aria-label="Indicadores">';
  h += kpi("Usuários", int(u.total), "+" + int(u.novosNoPeriodo) + " no período");
  h += kpi("Ativos (7 dias)", int(u.ativos7d), int(u.ativos1d) + " hoje · " + int(u.ativos30d) + " em 30 dias");
  h += kpi("Gasto no mês", usd(c.mesUsd), "de " + usd(c.tetoMensalUsd, 0) + " de teto · projeção " + usd(c.projecaoMesUsd), c.tetoMensalUsd > 0 ? Math.max(used, 0.001) : 0);
  h += kpi("Planos no período", int(ch.total), int(ch.total - ch.erros) + " com sucesso");
  h += kpi("Taxa de erro", pct(ch.taxaErro), int(ch.erros) + (ch.erros === 1 ? " falha · " : " falhas · ") + int(ch.duracaoMediaSeg) + " s em média");
  h += kpi("Custo médio por plano", usd(c.mediaPorPlanoUsd, 3), "tokens: " + int(d.tokens.entrada) + " entrada · " + int(d.tokens.saida) + " saída");
  h += "</section>";

  h += '<section class="grid2">';
  h += '<div class="card"><h2>Gasto com a IA por dia</h2><p class="sub">US$ · ' + esc(d.periodo.de.split("-").reverse().join("/")) + " a " + esc(d.periodo.ate.split("-").reverse().join("/")) + "</p>";
  h += bars(dias.map((x) => ({ label: dm(x.dia), parts: [{ v: x.custoUsd }], x })), {
    width: colW(2), title: "Gasto por dia em dólares", tick: (v) => "$" + (v < 1 ? v.toFixed(2) : v.toFixed(v % 1 ? 1 : 0)),
    tip: (b) => dm(b.x.dia) + "\\n" + usd(b.x.custoUsd, 4) + "\\n" + int(b.x.tokensEntrada + b.x.tokensSaida) + " tokens",
  });
  h += "<details><summary>Ver tabela</summary>" + table(["Dia", "Gasto", "Tokens entrada", "Tokens saída"], dias.map((x) => [esc(dm(x.dia)), usd(x.custoUsd, 4), int(x.tokensEntrada), int(x.tokensSaida)]), [1, 2, 3]) + "</details></div>";

  h += '<div class="card"><h2>Planos gerados por dia</h2><p class="sub">Chamadas à IA, com sucesso e com erro</p>';
  h += '<div class="legend"><span><i style="background:var(--s1)"></i>Sucesso</span><span><i style="background:var(--crit)"></i>Erro</span></div>';
  h += bars(dias.map((x) => ({ label: dm(x.dia), parts: [{ v: x.chamadas - x.erros }, { v: x.erros, cls: "err" }], x })), {
    width: colW(2), integer: true, title: "Planos por dia", tick: (v) => String(v),
    tip: (b) => dm(b.x.dia) + "\\n" + int(b.x.chamadas) + " planos\\n" + int(b.x.erros) + " com erro\\n" + int(b.x.usuariosIa) + " usuários",
  });
  h += "<details><summary>Ver tabela</summary>" + table(["Dia", "Planos", "Erros", "Usuários"], dias.map((x) => [esc(dm(x.dia)), int(x.chamadas), int(x.erros), int(x.usuariosIa)]), [1, 2, 3]) + "</details></div>";
  h += "</section>";

  h += '<section class="grid2">';
  h += '<div class="card"><h2>Novos usuários por dia</h2><p class="sub">Cadastros</p>' + bars(dias.map((x) => ({ label: dm(x.dia), parts: [{ v: x.novosUsuarios }], x })), {
    width: colW(2), integer: true, title: "Novos usuários por dia", tick: (v) => String(v),
    tip: (b) => dm(b.x.dia) + "\\n" + int(b.x.novosUsuarios) + " novos",
  }) + "</div>";
  h += '<div class="card"><h2>Objetivos</h2><p class="sub">Usuários por objetivo escolhido</p>' + hbars(d.objetivos) + "</div>";
  h += '</section><section class="grid2">';
  h += '<div class="card"><h2>Origem do plano</h2><p class="sub">Plano atual de cada usuário</p>' + hbars(d.origemPlano) + "</div>";
  h += '<div class="card"><h2>Importação de arquivos</h2><p class="sub">' + int(d.treinosImportados) + " treinos importados · " + int(u.comImportacao) + " usuários · último formato</p>" + hbars(d.formatosImportados) + "</div>";
  h += "</section>";

  h += '<section class="card"><h2>Usuários que mais geram custo</h2><p class="sub">Acumulado desde o cadastro</p>' + table(
    ["Usuário", "Objetivo", "Planos", "Gasto", "Cadastro", "Último acesso"],
    (d.topUsuarios || []).map((x) => [esc(x.nome ? x.nome + " · " + x.email : x.email), esc(lab(x.objetivo || "—")), int(x.planos), usd(x.custoUsd, 3), when(x.criadoEm), when(x.ultimoAcesso)]),
    [2, 3]) + "</section>";

  h += '<section class="card"><h2>Chamadas recentes</h2><p class="sub">Últimas 25 gerações e ajustes de plano</p>' + table(
    ["Quando", "Usuário", "Tipo", "Resultado", "Tokens", "Gasto", "Duração"],
    (d.recentes || []).map((x) => [when(x.em), esc(x.email), esc(lab(x.tipo)),
      x.ok ? '<span class="status ok">✓ OK</span>' : '<span class="status err">✕ ' + esc(x.erro || "erro") + "</span>",
      int(x.tokens), usd(x.custoUsd, 4), int(x.duracaoSeg) + " s"]),
    [4, 5, 6]) + "</section>";

  h += '<p class="muted">Atualizado em ' + when(d.geradoEm) + " · Versões do app: " + esc(Object.entries(d.versoesApp || {}).map((e) => e[0] + " (" + e[1] + ")").join(", ") || "—") + "</p>";
  app.innerHTML = h;
  bindTips();
}

function bindTips() {
  const show = (el, x, y) => { tip.textContent = el.dataset.tip; tip.style.display = "block"; place(x, y); };
  const place = (x, y) => {
    const r = tip.getBoundingClientRect();
    tip.style.left = Math.min(innerWidth - r.width - 8, Math.max(8, x + 12)) + "px";
    tip.style.top = Math.max(8, y - r.height - 12) + "px";
  };
  document.querySelectorAll(".hit").forEach((el) => {
    el.addEventListener("pointermove", (e) => show(el, e.clientX, e.clientY));
    el.addEventListener("pointerleave", () => tip.style.display = "none");
    el.addEventListener("focus", () => { const b = el.getBoundingClientRect(); show(el, b.left + b.width / 2, b.top + 20); });
    el.addEventListener("blur", () => tip.style.display = "none");
  });
}
</script>
</body>
</html>`;
}
