# Бриф боту @AITeamVIPBot — регистрация токена в аналитике установок (/issue)

## Зачем
Мы поднимаем аналитику установок (Cloudflare Worker): видеть **кто и сколько
ставил + email + тариф + версия + ОС**. Установщик email **не видит** — он есть
только у бота (из оплаты Prodamus). Поэтому бот при выдаче токена должен
зарегистрировать его в Worker — это **единственный источник email** в отчёте.

## Что сделать
При успешной выдаче токена (после оплаты) бот шлёт один POST:

```
POST <WORKER_URL>/issue
Headers:
  X-Admin-Key: <ADMIN_SECRET>
  Content-Type: application/json
Body:
  {
    "token_hash": "<sha256(token) hex>",
    "tg_id": "<tg_id_клиента>",
    "email": "<email_из_Prodamus>",
    "tier": "VIP"        // или STD / SUB / TRY — по выданному токену
  }
```

`<WORKER_URL>` и `<ADMIN_SECRET>` даст **Антон** после деплоя Worker
(например `https://aiteam-installs.<acc>.workers.dev`).

## Хэш токена — строго так (иначе склейка с установкой не сойдётся)
```python
import hashlib
token_hash = hashlib.sha256(token.encode()).hexdigest()   # 64 hex-символа
```
Хэшируется **полный токен целиком**, как он выдан клиенту
(`VIP-<hash16>-<tg_id>-<sig>` и т.п.). Тот же алгоритм используют установщики —
не меняй регистр/обрезку, иначе строки не сойдутся.

## Важные детали
- **Fire-and-forget:** если `/issue` не ответил — НЕ блокируй выдачу токена,
  просто залогируй ошибку и продолжай. Аналитика вторична по отношению к продаже.
- **Идемпотентно:** повторный `/issue` с тем же `token_hash` не плодит дубли
  (Worker делает UPSERT) — можно слать спокойно.
- **Не слать сырой токен** — только хэш (так решили: токен = фактический ключ
  установки, в базе храним хэш).
- **TRY-токены тоже регистрируй** (`tier:"TRY"`) — тогда увидим воронку и по
  тест-драйву.

## (Опционально, разово) проставить email старым токенам
Чтобы и ранее выданные токены попали в отчёт с email — пройтись по БД выданных
токенов и для каждого вызвать `/issue` (тот же payload). После этого их
будущие/прошлые активации склеятся по `token_hash`.

## Как проверить, что работает
После внедрения выдай себе тестовый токен → попроси Антона глянуть:
```
curl -s "<WORKER_URL>/stats" -H "X-Admin-Key: <ADMIN_SECRET>"
```
Должна появиться строка с твоим email/tg_id/tier (issued), а после установки —
заполнятся `activated_at`, `installer_version`, `client_os`.

## Контекст
- Спека: `docs/superpowers/specs/2026-06-06-install-analytics-worker-design.md`
- План (наша часть — Worker + пинги установщиков): `docs/superpowers/plans/2026-06-06-install-analytics-worker.md`
- Worker-код: `openclaw-factory/cloudflare/` (worker.js / schema.sql / wrangler.toml)
