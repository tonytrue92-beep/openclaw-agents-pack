# Install Analytics Worker — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development или superpowers:executing-plans. Для кода Worker полезны скиллы `cloudflare:workers-best-practices` и `cloudflare:wrangler`. Steps — чекбоксы `- [ ]`.

**Goal:** Видеть кто/сколько/email установок — Cloudflare Worker (D1) принимает `/issue` от бота (с email) и `/activation` от установщиков, склеивает по хэшу токена; `/stats` отдаёт сводку.

**Architecture:** переписываем существующий `openclaw-factory/cloudflare/worker.js` с KV на **D1**; 3 эндпоинта; установщики шлют fire-and-forget `/activation` по `sha256(token)`; бот шлёт `/issue` с email (бриф технарю).

**Tech Stack:** Cloudflare Workers + D1 (SQLite); wrangler; bash-пинги (shasum/sha256sum); GitHub Actions CI установщиков.

**Спека:** `docs/superpowers/specs/2026-06-06-install-analytics-worker-design.md`

> Канонический хэш у всех сторон: `SHA-256(полный_токен)` hex.

---

## Task 1: Worker — D1-схема + переписать worker.js + wrangler.toml

**Files:**
- Create: `openclaw-factory/cloudflare/schema.sql`
- Modify: `openclaw-factory/cloudflare/worker.js` (полная замена)
- Modify: `openclaw-factory/cloudflare/wrangler.toml` (KV → D1)

- [ ] **Step 1: schema.sql**

Создай `openclaw-factory/cloudflare/schema.sql`:

```sql
CREATE TABLE IF NOT EXISTS installs (
  token_hash        TEXT PRIMARY KEY,
  tg_id             TEXT,
  email             TEXT,
  tier              TEXT,   -- VIP / STD / SUB / TRY
  track             TEXT,   -- paid / trial
  issued_at         TEXT,
  activated_at      TEXT,
  last_activated_at TEXT,
  activation_count  INTEGER DEFAULT 0,
  installer_version TEXT,
  client_os         TEXT
);
```

- [ ] **Step 2: переписать worker.js**

Замени содержимое `openclaw-factory/cloudflare/worker.js` на:

```js
// ═══════════════════════════════════════════════════════════════
//  OpenClaw — Install analytics Worker (D1)
//  /issue (бот, admin) · /activation (установщик) · /stats (admin) · /health
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

    if (url.pathname === "/health") return json({ ok: true, service: "aiteam-installs" }, 200, cors);

    // ── /issue — бот регистрирует токен с email (admin) ──
    if (url.pathname === "/issue" && request.method === "POST") {
      if (request.headers.get("X-Admin-Key") !== env.ADMIN_SECRET)
        return json({ ok: false, error: "forbidden" }, 403, cors);
      const b = await request.json().catch(() => ({}));
      const th = (b.token_hash || "").trim();
      if (!th) return json({ ok: false, error: "no_token_hash" }, 400, cors);
      const now = new Date().toISOString();
      await env.DB.prepare(
        `INSERT INTO installs (token_hash, tg_id, email, tier, issued_at)
         VALUES (?1, ?2, ?3, ?4, ?5)
         ON CONFLICT(token_hash) DO UPDATE SET
           tg_id=COALESCE(excluded.tg_id, installs.tg_id),
           email=COALESCE(excluded.email, installs.email),
           tier=COALESCE(excluded.tier, installs.tier),
           issued_at=COALESCE(installs.issued_at, excluded.issued_at)`
      ).bind(th, b.tg_id || null, b.email || null, b.tier || null, now).run();
      return json({ ok: true }, 200, cors);
    }

    // ── /activation — установщик отмечает активацию (без ключа) ──
    if (url.pathname === "/activation" && request.method === "POST") {
      const b = await request.json().catch(() => ({}));
      const th = (b.token_hash || "").trim();
      if (!th) return json({ ok: false, error: "no_token_hash" }, 400, cors);
      const now = new Date().toISOString();
      // обновляем ТОЛЬКО существующую (issue-нутую) строку — мусор игнорируем
      await env.DB.prepare(
        `UPDATE installs SET
           activated_at = COALESCE(activated_at, ?2),
           last_activated_at = ?2,
           activation_count = activation_count + 1,
           installer_version = ?3,
           client_os = ?4,
           track = COALESCE(?5, track),
           tg_id = COALESCE(tg_id, ?6)
         WHERE token_hash = ?1`
      ).bind(th, now, b.installer_version || null, b.client_os || null, b.track || null, b.tg_id || null).run();
      return json({ ok: true }, 200, cors); // fire-and-forget: всегда ok
    }

    // ── /stats — сводка (admin) ──
    if (url.pathname === "/stats" && request.method === "GET") {
      if (request.headers.get("X-Admin-Key") !== env.ADMIN_SECRET)
        return json({ ok: false, error: "forbidden" }, 403, cors);
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
        byTier[t].issued++; if (r.activated_at) byTier[t].activated++;
      }
      if (url.searchParams.get("format") === "csv") {
        const head = "email,tg_id,tier,track,issued_at,activated_at,activation_count,installer_version,client_os";
        const lines = rows.map(r => [r.email, r.tg_id, r.tier, r.track, r.issued_at, r.activated_at, r.activation_count, r.installer_version, r.client_os]
          .map(v => `"${(v ?? "").toString().replace(/"/g, '""')}"`).join(","));
        return new Response([head, ...lines].join("\n"), { status: 200, headers: { "Content-Type": "text/csv", ...cors } });
      }
      return json({ ok: true, issued, activated, funnel: { issued, activated, rate: issued ? +(activated / issued).toFixed(3) : 0 }, byTier, rows }, 200, cors);
    }

    return json({ ok: false, error: "not_found" }, 404, cors);
  },
};
function json(d, s, h = {}) {
  return new Response(JSON.stringify(d), { status: s, headers: { "Content-Type": "application/json", ...h } });
}
```

- [ ] **Step 3: wrangler.toml на D1**

Замени `openclaw-factory/cloudflare/wrangler.toml` на:

```toml
name = "aiteam-installs"
main = "worker.js"
compatibility_date = "2026-01-01"
workers_dev = true

# свой домен (опц.):
# routes = [{ pattern = "installs.tonytrue.pro/*", zone_name = "tonytrue.pro" }]

[[d1_databases]]
binding = "DB"
database_name = "aiteam-installs"
database_id = "<вставить-после: wrangler d1 create aiteam-installs>"

# ADMIN_SECRET — через `wrangler secret put ADMIN_SECRET` (не в файле)
```

- [ ] **Step 4: Локальный тест (wrangler dev + curl)**

Run (в `openclaw-factory/cloudflare/`):
```bash
cd ~/git/openclaw-factory/cloudflare
npm i -g wrangler 2>/dev/null || true
wrangler d1 execute aiteam-installs --local --file=schema.sql
wrangler dev --local --persist &   # поднимет http://127.0.0.1:8787
sleep 3
# нет ADMIN_SECRET локально? задай через .dev.vars: echo 'ADMIN_SECRET=testkey' > .dev.vars  и перезапусти dev
curl -s localhost:8787/health
curl -s -X POST localhost:8787/issue -H 'X-Admin-Key: testkey' -H 'Content-Type: application/json' \
  -d '{"token_hash":"abc123","tg_id":"555","email":"a@b.com","tier":"VIP"}'
curl -s -X POST localhost:8787/activation -H 'Content-Type: application/json' \
  -d '{"token_hash":"abc123","tg_id":"555","installer_version":"2026.06.06","client_os":"darwin-arm64","track":"paid"}'
curl -s localhost:8787/stats -H 'X-Admin-Key: testkey'
```
Expected: `/health` ok; `/issue` ok; `/activation` ok; `/stats` показывает 1 issued, 1 activated, email `a@b.com`, activation_count 1.
Затем останови dev: `kill %1`.

- [ ] **Step 5: Commit (в factory)**

```bash
cd ~/git/openclaw-factory
git checkout -b install-analytics
git add cloudflare/worker.js cloudflare/wrangler.toml cloudflare/schema.sql
git commit -m "cloudflare: install-analytics Worker (D1, /issue /activation /stats)"
```

---

## Task 2: Деплой Worker (Cloudflare-аккаунт Антона)

> Эти шаги запускает Антон (нужен его Cloudflare). Мы подготовили всё для copy-paste.

- [ ] **Step 1: D1 + secret + deploy**

```bash
cd ~/git/openclaw-factory/cloudflare
wrangler login
wrangler d1 create aiteam-installs        # → скопировать database_id в wrangler.toml
wrangler d1 execute aiteam-installs --remote --file=schema.sql
wrangler secret put ADMIN_SECRET          # ввести длинную случайную строку, СОХРАНИТЬ её
wrangler deploy
```
Expected: получен URL `https://aiteam-installs.<acc>.workers.dev`

- [ ] **Step 2: Проверка прод-эндпоинта**

```bash
W=https://aiteam-installs.<acc>.workers.dev
curl -s $W/health
curl -s $W/stats -H "X-Admin-Key: <ADMIN_SECRET>"
```
Expected: health ok; stats ok (0 issued при пустой базе)

- [ ] **Step 3: Зафиксировать database_id в wrangler.toml + commit**

```bash
cd ~/git/openclaw-factory
git add cloudflare/wrangler.toml
git commit -m "cloudflare: database_id для aiteam-installs"
```

> **Зафиксируй URL Worker** — он нужен в Task 3 (установщики) и Task 4 (бот).

---

## Task 3: Установщики шлют `/activation`

**Files:**
- Modify: `openclaw-agents-pack/scripts/lib/vip.sh` (эндпоинт + tier/track)
- Modify: `openclaw-factory/scripts/demo-install.sh` (хэш-хелпер + пинг)
- Modify: `openclaw-test-drive/scripts/install-trial.sh` (пинг)
- Modify: smoke-тесты трёх репо; CHANGELOG; SHA256SUMS

- [ ] **Step 1: Сверить канонический хэш (agents-pack)**

Прочти `openclaw-agents-pack/scripts/lib/vip.sh` функцию `vip_token_get_hash()` (~стр.87).
Если она = `sha256(token)` hex — оставляем. Если другое — приводим к канону
`printf '%s' "$T" | shasum -a 256 | awk '{print $1}'` (с fallback на `sha256sum`).
Бот (Task 4) ОБЯЗАН считать тот же хэш.

- [ ] **Step 2: agents-pack — endpoint + tier/track (smoke сначала)**

В `openclaw-agents-pack/scripts/smoke-test.sh` добавь:
```bash
grep -q 'aiteam-installs.*workers.dev\|/activation' scripts/lib/vip.sh \
  || { echo "FAIL: vip.sh не указывает на новый /activation"; exit 1; }
grep -q '"track"' scripts/lib/vip.sh || { echo "FAIL: нет track в payload"; exit 1; }
echo "OK: agents-pack activation payload обновлён"
```
Run: `cd ~/git/openclaw-agents-pack && bash scripts/smoke-test.sh` → FAIL.

В `vip.sh`: строку `VIP_ACTIVATION_ENDPOINT="${VIP_ACTIVATION_ENDPOINT:-https://aiteam-vip.openclaw.ai/log/activation}"`
замени на (подставь реальный URL из Task 2):
```bash
VIP_ACTIVATION_ENDPOINT="${VIP_ACTIVATION_ENDPOINT:-https://aiteam-installs.<acc>.workers.dev/activation}"
```
В теле `vip_log_activation` добавь в JSON `tier` и `track`:
```bash
      -d "{\"token_hash\":\"${token_hash}\",\"tg_id\":${tg_id:-0},\"installer_version\":\"${INSTALLER_VERSION:-unknown}\",\"client_os\":\"${os_info}\",\"tier\":\"${COURSE_TIER:-}\",\"track\":\"paid\"}" \
```
Run smoke → PASS. `bash -n scripts/install-agents.sh`.

- [ ] **Step 3: factory — хэш-хелпер + пинг (smoke сначала)**

В `openclaw-factory/scripts/smoke-test.sh` добавь:
```bash
grep -q '/activation' scripts/demo-install.sh || { echo "FAIL: factory не шлёт /activation"; exit 1; }
grep -q '_oc_token_hash' scripts/demo-install.sh || { echo "FAIL: нет хэш-хелпера"; exit 1; }
echo "OK: factory activation ping на месте"
```
Run → FAIL.

В `demo-install.sh` рядом с другими helper-функциями (после блока цветов/функций, до фаз) добавь:
```bash
ACTIVATION_ENDPOINT="${ACTIVATION_ENDPOINT:-https://aiteam-installs.<acc>.workers.dev/activation}"
_oc_token_hash() {
  if command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 256 | awk '{print $1}';
  elif command -v sha256sum >/dev/null 2>&1; then printf '%s' "$1" | sha256sum | awk '{print $1}'; fi
}
_oc_log_activation() {  # fire-and-forget, не валит установку
  local token="$1" tier="$2" track="$3" th os
  th=$(_oc_token_hash "$token"); [[ -z "$th" ]] && return 0
  os=$(uname -sm 2>/dev/null | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
  ( curl -fsSL --max-time 3 -X POST "$ACTIVATION_ENDPOINT" -H 'Content-Type: application/json' \
      -d "{\"token_hash\":\"${th}\",\"tg_id\":\"${OWNER_TG_ID:-}\",\"installer_version\":\"${INSTALLER_VERSION:-unknown}\",\"client_os\":\"${os}\",\"tier\":\"${tier}\",\"track\":\"${track}\"}" \
      >/dev/null 2>&1 ) &
}
```
Вызов добавь в реальной установке ПОСЛЕ валидации токена (там, где известны
`COURSE_TOKEN`/`COURSE_TIER`, до/после R6 — но только при `DRY_RUN != true`):
```bash
[[ "${DRY_RUN:-false}" != true && -n "${COURSE_TOKEN:-}" ]] && _oc_log_activation "$COURSE_TOKEN" "${COURSE_TIER:-}" "paid"
```
Run smoke → PASS. `bash -n scripts/demo-install.sh`.

- [ ] **Step 4: trial — пинг (smoke сначала)**

В `openclaw-test-drive/scripts/smoke-test.sh`:
```bash
grep -q '/activation' scripts/install-trial.sh || { echo "FAIL: trial не шлёт /activation"; exit 1; }
echo "OK: trial activation ping на месте"
```
Run → FAIL.

В `install-trial.sh` добавь такой же `_oc_token_hash` + `ACTIVATION_ENDPOINT` +
fire-and-forget пинг после успешной проверки TRY-токена:
```bash
ACTIVATION_ENDPOINT="${ACTIVATION_ENDPOINT:-https://aiteam-installs.<acc>.workers.dev/activation}"
_oc_token_hash() {
  if command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 256 | awk '{print $1}';
  elif command -v sha256sum >/dev/null 2>&1; then printf '%s' "$1" | sha256sum | awk '{print $1}'; fi
}
# после валидации TRY-токена ($TRIAL_TOKEN или как называется переменная):
_th=$(_oc_token_hash "${TRIAL_TOKEN:-}")
[[ -n "$_th" ]] && ( curl -fsSL --max-time 3 -X POST "$ACTIVATION_ENDPOINT" -H 'Content-Type: application/json' \
  -d "{\"token_hash\":\"${_th}\",\"tg_id\":\"${TG_ID:-}\",\"installer_version\":\"${TRIAL_VERSION:-unknown}\",\"client_os\":\"$(uname -sm | tr ' ' '-' | tr '[:upper:]' '[:lower:]')\",\"tier\":\"TRY\",\"track\":\"trial\"}" \
  >/dev/null 2>&1 ) &
unset _th
```
> Имя переменной токена в trial сверь по факту (`grep -n 'token' scripts/install-trial.sh`).
Run smoke → PASS. `bash -n scripts/install-trial.sh`.

- [ ] **Step 5: По каждому репо — bump версии + CHANGELOG + shellcheck + checksums**

Версии всех трёх → `2026.06.06` (если ещё не подняты в другом плане; иначе суффикс `.1`).
CHANGELOG-запись: «activation-пинг в Worker аналитики (token_hash/tg/tier/os, fire-and-forget)».
Для каждого репо:
```bash
shellcheck -S warning -e SC1090,SC1091,SC2155,SC2086,SC2034 scripts/*.sh scripts/lib/*.sh 2>/dev/null
bash scripts/update-checksums.sh
```
agents-pack дополнительно: `bash scripts/build-bundle.sh && bash -n dist/install-agents-bundled.sh`.

- [ ] **Step 6: PR по каждому репо**

factory (ветка `install-analytics` уже есть):
```bash
cd ~/git/openclaw-factory && git add -A
git commit -m "factory: activation-пинг в Worker аналитики + bump"
git push -u origin install-analytics
gh pr create --title "factory: activation analytics ping" --body "Спека 2026-06-06 install-analytics. 🤖 Generated with [Claude Code](https://claude.com/claude-code)"
gh pr checks install-analytics --watch && gh pr merge --merge --delete-branch && git checkout main && git pull --ff-only
```
Аналогично agents-pack и trial (ветки `install-analytics`). agents-pack — после merge **тег** `v2026.06.06` (bundled пересоберётся).

---

## Task 4: Бриф технарю (бот → /issue с email)

**Files:** Create `openclaw-agents-pack/handoff/install-analytics-bot-brief.md`; Modify `handoff/STATUS-FOR-TECHIE.md`

- [ ] **Step 1: Создай бриф**

`openclaw-agents-pack/handoff/install-analytics-bot-brief.md`:
```markdown
# Бриф боту @AITeamVIPBot — регистрация токена в аналитике (/issue)

## Зачем
Чтобы в отчёте по установкам был **email** (он есть только у бота — из Prodamus).

## Что сделать
При выдаче токена (после успешной оплаты) бот шлёт POST на Worker аналитики:

POST <WORKER_URL>/issue
Headers: X-Admin-Key: <ADMIN_SECRET>   (тот, что задан `wrangler secret put`)
Body (JSON): {"token_hash":"<sha256(token) hex>","tg_id":"<tg_id>","email":"<email_из_Prodamus>","tier":"VIP|STD|SUB|TRY"}

## Хэш — строго так (иначе склейка не сойдётся)
token_hash = hashlib.sha256(token.encode()).hexdigest()   # 64 hex-символа
(полный токен целиком, как выдан клиенту).

## Детали
- WORKER_URL и ADMIN_SECRET даст Антон после деплоя Worker.
- Fire-and-forget: если /issue не ответил — не блокируй выдачу токена, залогируй.
- (Опц., разово) проставить email старым токенам: пройтись по БД выданных
  токенов и для каждого вызвать /issue — тогда и старые установки получат email.
```

- [ ] **Step 2: Обнови STATUS-FOR-TECHIE.md** — добавь пункт «Аналитика установок: бот → /issue» со ссылкой на бриф.

- [ ] **Step 3: Commit + push**

```bash
cd ~/git/openclaw-agents-pack
git add handoff/install-analytics-bot-brief.md handoff/STATUS-FOR-TECHIE.md
git commit -m "handoff: бриф боту — /issue с email для аналитики установок"
git push origin HEAD
```

---

## Task 5: Сквозная проверка + приватность

- [ ] **Step 1: End-to-end на проде**

```bash
W=https://aiteam-installs.<acc>.workers.dev
# имитируем бота:
curl -s -X POST $W/issue -H "X-Admin-Key: <ADMIN_SECRET>" -H 'Content-Type: application/json' \
  -d '{"token_hash":"e2e-test","tg_id":"1","email":"test@x.com","tier":"VIP"}'
# имитируем установщик:
curl -s -X POST $W/activation -H 'Content-Type: application/json' \
  -d '{"token_hash":"e2e-test","tg_id":"1","installer_version":"2026.06.06","client_os":"darwin-arm64","track":"paid"}'
curl -s "$W/stats?format=csv" -H "X-Admin-Key: <ADMIN_SECRET>"
```
Expected: в CSV строка с `test@x.com,1,VIP,paid,...,1`. Удалить тест-строку при желании.

- [ ] **Step 2: Проверка «мусор игнорируется»**

```bash
curl -s -X POST $W/activation -H 'Content-Type: application/json' \
  -d '{"token_hash":"never-issued","track":"paid"}'
curl -s $W/stats -H "X-Admin-Key: <ADMIN_SECRET>" | grep -c never-issued
```
Expected: `0` — строка не создалась (обновляем только issue-нутые).

- [ ] **Step 3: Приватность-чек**
  - [ ] В базе только хэш токена (не сырой).
  - [ ] `/issue` и `/stats` под ADMIN_SECRET; `/activation` ничего не создаёт для неизвестных хэшей.
  - [ ] Установщик НЕ шлёт секретов/ключей (только hash/tg/version/os/tier/track).
  - [ ] security-audit установщиков зелёный (`bash scripts/security-audit.sh` где есть).

---

## Self-Review (выполнено)
- **Покрытие спеки:** Worker+D1 (§4) → Task 1-2; пинги установщиков (§5) → Task 3;
  бот/email (§7) → Task 4; что получит Антон (§8) + приватность (§4.3) → Task 5.
- **Плейсхолдеры:** `<acc>`, `<ADMIN_SECRET>`, `<WORKER_URL>`, `database_id` — реальные
  значения подставляются после деплоя (Task 2); это не код-заглушки.
- **Консистентность:** хэш = `sha256(token)` hex у всех (bash shasum/sha256sum, бот
  hashlib); биндинг D1 `DB`; поля таблицы совпадают в worker.js и schema.sql.
- **Зависимости порядка:** Task 2 (URL+secret) до Task 3/4 (подстановка URL); agents-pack
  тег после merge.
```
