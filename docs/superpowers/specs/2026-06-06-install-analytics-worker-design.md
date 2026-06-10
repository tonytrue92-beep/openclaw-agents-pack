# Дизайн: аналитика установок (кто/сколько/email) через Cloudflare Worker

> ⚠️ **Пересмотр 2026-06-10 (решение Антона):** Cloudflare НЕ используем
> (авторизация через VPN не взлетела + лишняя инфраструктура). Контракт
> эндпоинтов/хэш/схема из этой спеки остаются в силе, но хостит их **технарь**
> на своём сервере (рядом с Prodamus-webhook). Референс-код:
> `handoff/analytics-endpoint-reference/`. Актуальное ТЗ:
> `handoff/install-analytics-bot-brief.md`.

**Дата:** 2026-06-06
**Статус:** дизайн согласован Антоном (что собираем, куда, хэш), ожидает вычитки → план уже рядом

---

## 1. Цель

Видеть, **кто и сколько раз ставил** наши установщики, и **связать установку
с email** (привязан к токену при оплате). Сейчас централизованно не собирается
ничего: factory пишет телеметрию только локально (POST закомментирован),
agents-pack шлёт активационный пинг на **неразвёрнутый** `aiteam-vip.openclaw.ai`,
trial не шлёт ничего.

**Решения (подтверждены Антоном):**
- Собирать: **кто (tg_id) + сколько (счётчик/факт) + email + тариф + версия + ОС + когда**.
- Куда: **Cloudflare Worker** (на ресурсах Антона), хранилище **D1**.
- Токен — **хэшем** (SHA-256), не сырым (токен = фактический ключ установки).

---

## 2. Критичный момент: откуда берётся email

**Установщик email НЕ видит** — он знает только токен, tg_id, версию, ОС.
Email привязан к токену **на стороне бота/Prodamus** (при оплате). Поэтому
данные собираются из **двух источников** и склеиваются по **хэшу токена**:

```
  БОТ @AITeamVIPBot ── POST /issue ──→┐ {token_hash, tg_id, email, tier}
  (при выдаче токена)                 │
                                      ├─ D1: ключ token_hash
  УСТАНОВЩИК ──────── POST /activation┘ {token_hash, tg_id, version, os, track}
  (при установке)
                                      ↓
  АНТОН ──────────── GET /stats ──────→ email + tg_id + tier + version + os + когда + счётчик
```

Без шага бота (`/issue`) email в отчёте не будет — это **задача технарю** (см. бриф).

---

## 3. Канонический хэш токена

Один алгоритм у всех сторон, иначе склейка не сойдётся:

`token_hash = SHA-256(полный_токен)` в hex (64 символа).

- bash (установщики): `printf '%s' "$TOKEN" | shasum -a 256 | awk '{print $1}'`
- бот (Python): `hashlib.sha256(token.encode()).hexdigest()`

> При реализации сверить с существующим `agents-pack/scripts/lib/vip.sh:vip_token_get_hash()`:
> если он уже считает `sha256(token)` hex — переиспользуем; иначе приводим все
> стороны к канону выше.

---

## 4. Архитектура Worker

Переписываем существующий `openclaw-factory/cloudflare/worker.js` (он уже задуман
«трекать активацию», но на KV + под генерируемые `OC-`токены). Меняем модель на
**D1 + token_hash**. `wrangler.toml` — D1-биндинг вместо KV.

### 4.1. Хранилище — D1 (таблица `installs`)
```sql
CREATE TABLE IF NOT EXISTS installs (
  token_hash        TEXT PRIMARY KEY,
  tg_id             TEXT,
  email             TEXT,
  tier              TEXT,          -- VIP / STD / SUB / TRY
  track             TEXT,          -- paid / trial
  issued_at         TEXT,
  activated_at      TEXT,          -- первая активация
  last_activated_at TEXT,
  activation_count  INTEGER DEFAULT 0,
  installer_version TEXT,
  client_os         TEXT
);
```

### 4.2. Эндпоинты
| Метод/путь | Кто | Тело | Что делает |
|---|---|---|---|
| `POST /issue` | **бот** (заголовок `X-Admin-Key: ADMIN_SECRET`) | `{token_hash, tg_id, email, tier}` | UPSERT строки: `issued_at=now`, заполнить email/tier/tg_id |
| `POST /activation` | **установщик** (без ключа — бежит у клиента) | `{token_hash, tg_id, installer_version, client_os, track}` | **UPDATE только существующей** строки: `activated_at` (если пусто), `last_activated_at=now`, `activation_count+1`, version/os/track/tg_id |
| `GET /stats` | **Антон** (`X-Admin-Key`) | — | сводка: всего выдано, всего активировано, по тарифам, воронка + список; `?format=csv` |
| `GET /health` | — | — | `{ok:true}` |

### 4.3. Защита / приватность
- `/issue` и `/stats` — под `ADMIN_SECRET` (через `wrangler secret put`, не в файле).
- `/activation` — без ключа (иначе клиент не сможет звать), но **обновляет только
  строки, которые уже `/issue`-нуты** ботом. Неизвестный `token_hash` → молча
  игнор (не создаём левые строки) → мусором не засорить.
- Храним **хэш**, не сырой токен. Email/tg — это собственные клиенты Антона,
  на его Cloudflare, минимум полей. Установщик email не трогает.
- Активационный пинг — **fire-and-forget** (3 c таймаут, ошибки молча глотаются):
  сбой сбора НИКОГДА не ломает установку. Это «license-activation»-запись, не
  завязана на opt-in пошаговую телеметрию (та остаётся как есть, локальной).

---

## 5. Изменения в установщиках (источник `/activation`)

| Репо | Что |
|---|---|
| `agents-pack/scripts/lib/vip.sh` | `VIP_ACTIVATION_ENDPOINT` → новый Worker URL; в payload добавить `tier`, `track:"paid"`. Хэш уже шлётся. |
| `factory/scripts/demo-install.sh` | добавить fire-and-forget пинг `/activation` после валидации токена (есть `COURSE_TOKEN`/`COURSE_TIER`); хэш-хелпер; `track:"paid"`. |
| `test-drive/scripts/install-trial.sh` | добавить такой же пинг; `tier:"TRY"`, `track:"trial"`. |

URL Worker (после деплоя) кладём в переменную с дефолтом, переопределяемую env
(как сейчас `VIP_ACTIVATION_ENDPOINT`).

---

## 6. Деплой (нужен Cloudflare-аккаунт Антона)
Код пишем мы; запускает деплой Антон (или даёт доступ):
```
wrangler login
wrangler d1 create aiteam-installs           # → id в wrangler.toml
wrangler d1 execute aiteam-installs --file=schema.sql
wrangler secret put ADMIN_SECRET             # длинная случайная строка
wrangler deploy
```
URL получится `https://<name>.<acc>.workers.dev` (или свой домен на `tonytrue.pro`).
Этот URL подставляем в установщики и отдаём технарю для бота.

---

## 7. Передать технарю (бот → `/issue`)
При выдаче токена (после оплаты Prodamus) бот:
1. Считает `token_hash = sha256(token)` hex.
2. Шлёт `POST <worker>/issue` с `X-Admin-Key: <ADMIN_SECRET>` и телом
   `{token_hash, tg_id, email, tier}` (email — из платежа Prodamus).
Это единственный источник email. Бриф: `handoff/install-analytics-bot-brief.md`.

---

## 8. Что Антон получит
`GET /stats` (или `?format=csv`): таблица **email · tg_id · тариф · трек ·
версия · ОС · когда поставил · сколько активаций** + счётчики и воронка
«выдано токенов → реально установили».

---

## 9. Out of scope
- Серверная блокировка/гейтинг по токену (`/verify` со счётчиком активаций) —
  отдельная возможная волна; сейчас токен проверяется локально (Ed25519).
- Дослать на сервер подробные пошаговые логи с ошибками — отдельно (это §«богато»
  из обсуждения); сейчас — только факт активации.
- Дашборд-UI; пока `/stats` JSON/CSV.

## 10. Риски
- **Рассинхрон хэша** бот vs установщик → склейка не сойдётся. Митигирование: §3
  канон + сверка `vip_token_get_hash`.
- **Старые токены** (выданы до бота-`/issue`): их активации придут на
  несуществующую строку → игнор. Норма (видим только новые) — либо разово
  загрузить историю через `/issue` из БД бота.
- **Деплой завязан на Cloudflare-аккаунт Антона** — без него Worker не поднять.
