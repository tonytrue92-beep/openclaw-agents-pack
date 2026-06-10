// ═══════════════════════════════════════════════════════════════
//  OpenClaw — Install analytics Worker (D1)
//
//  Назначение: видеть КТО и СКОЛЬКО ставил + email + тариф + версия + ОС.
//  Склейка по sha256(токена): бот шлёт /issue (с email), установщик /activation.
//
//  Эндпоинты:
//    POST /issue       — бот (X-Admin-Key): {token_hash, tg_id, email, tier}
//    POST /activation  — установщик (без ключа): {token_hash, tg_id, installer_version, client_os, track}
//    GET  /stats       — Антон (X-Admin-Key): сводка (?format=csv)
//    GET  /health      — проверка
//
//  Деплой: см. cloudflare/README.md
// ═══════════════════════════════════════════════════════════════
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const cors = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, X-Admin-Key",
    };
    if (request.method === "OPTIONS") return new Response(null, { headers: cors });

    if (url.pathname === "/health") {
      return json({ ok: true, service: "aiteam-installs" }, 200, cors);
    }

    // ── /issue — бот регистрирует токен с email (admin) ──
    if (url.pathname === "/issue" && request.method === "POST") {
      if (request.headers.get("X-Admin-Key") !== env.ADMIN_SECRET) {
        return json({ ok: false, error: "forbidden" }, 403, cors);
      }
      const b = await request.json().catch(() => ({}));
      const th = (b.token_hash || "").trim();
      if (!th) return json({ ok: false, error: "no_token_hash" }, 400, cors);
      const now = new Date().toISOString();
      // R2-аудит: без tier track = null (COALESCE сохранит прежний) —
      // иначе /issue без tier молча перетирал trial→paid.
      const track = b.tier ? (b.tier === "TRY" ? "trial" : "paid") : null;
      // ON CONFLICT: last-write-wins для tg_id/email/tier/track (повторный /issue =
      // коррекция данных), issued_at сохраняем первый.
      await env.DB.prepare(
        `INSERT INTO installs (token_hash, tg_id, email, tier, track, issued_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)
         ON CONFLICT(token_hash) DO UPDATE SET
           tg_id=COALESCE(excluded.tg_id, installs.tg_id),
           email=COALESCE(excluded.email, installs.email),
           tier=COALESCE(excluded.tier, installs.tier),
           track=COALESCE(excluded.track, installs.track),
           issued_at=COALESCE(installs.issued_at, excluded.issued_at)`
      ).bind(th, b.tg_id || null, b.email || null, b.tier || null, track, now).run();
      return json({ ok: true }, 200, cors);
    }

    // ── /activation — установщик отмечает активацию (без ключа) ──
    //    Обновляем ТОЛЬКО уже issue-нутую строку → мусор/неизвестные хэши игнор.
    if (url.pathname === "/activation" && request.method === "POST") {
      const b = await request.json().catch(() => ({}));
      const th = (b.token_hash || "").trim();
      if (!th) return json({ ok: false, error: "no_token_hash" }, 400, cors);
      const now = new Date().toISOString();
      await env.DB.prepare(
        `UPDATE installs SET
           activated_at = COALESCE(activated_at, ?2),
           last_activated_at = ?2,
           activation_count = activation_count + 1,
           installer_version = ?3,
           client_os = ?4,
           track = COALESCE(?5, track),
           tg_id = COALESCE(tg_id, ?6),
           tier = COALESCE(tier, ?7)
         WHERE token_hash = ?1`
      ).bind(th, now, b.installer_version || null, b.client_os || null, b.track || null, b.tg_id || null, b.tier || null).run();
      return json({ ok: true }, 200, cors); // fire-and-forget: всегда ok
    }

    // ── /stats — сводка (admin) ──
    if (url.pathname === "/stats" && request.method === "GET") {
      if (request.headers.get("X-Admin-Key") !== env.ADMIN_SECRET) {
        return json({ ok: false, error: "forbidden" }, 403, cors);
      }
      const rows = (await env.DB.prepare(
        `SELECT token_hash, tg_id, email, tier, track, issued_at, activated_at,
                last_activated_at, activation_count, installer_version, client_os
         FROM installs ORDER BY COALESCE(activated_at, issued_at) DESC`
      ).all()).results || [];
      const issued = rows.length;
      const activated = rows.filter(r => r.activated_at).length;
      const byTier = {};
      for (const r of rows) {
        const t = r.tier || "?";
        byTier[t] = byTier[t] || { issued: 0, activated: 0 };
        byTier[t].issued++;
        if (r.activated_at) byTier[t].activated++;
      }
      if (url.searchParams.get("format") === "csv") {
        const head = "email,tg_id,tier,track,issued_at,activated_at,activation_count,installer_version,client_os";
        const lines = rows.map(r => [
          r.email, r.tg_id, r.tier, r.track, r.issued_at, r.activated_at,
          r.activation_count, r.installer_version, r.client_os,
        ].map(v => {
          let s = (v ?? "").toString();
          if (/^[=+\-@\t\r]/.test(s)) s = "'" + s; // анти CSV-formula-injection
          return `"${s.replace(/"/g, '""')}"`;
        }).join(","));
        return new Response([head, ...lines].join("\n"), {
          status: 200,
          headers: { "Content-Type": "text/csv; charset=utf-8", ...cors },
        });
      }
      return json({
        ok: true,
        issued,
        activated,
        funnel: { issued, activated, rate: issued ? +(activated / issued).toFixed(3) : 0 },
        byTier,
        rows,
      }, 200, cors);
    }

    return json({ ok: false, error: "not_found" }, 404, cors);
  },
};

function json(data, status, headers = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...headers },
  });
}
