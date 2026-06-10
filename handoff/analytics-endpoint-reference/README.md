# Референс эндпоинта аналитики установок (для технаря)

Антон решил **не разворачивать Cloudflare** — эндпоинты аналитики хостишь
**ты, на своём сервере** (логично рядом с Prodamus-webhook). Что собирать и
зачем — в брифе `../install-analytics-bot-brief.md`. Здесь — готовая логика.

## Файлы
- **`reference-worker.js`** — полная рабочая реализация трёх эндпоинтов
  (писалась под Cloudflare Worker + D1/SQLite, но логика переносится 1-в-1
  на Express/FastAPI/что угодно: это обычный HTTP + 3 SQL-запроса).
- **`schema.sql`** — схема таблицы `installs` (SQLite-диалект; для Postgres
  поменяй TEXT/INTEGER по вкусу).

## Контракт (повтори его, чем бы ни хостил)
| Метод/путь | Кто зовёт | Auth | Тело |
|---|---|---|---|
| `POST /issue` | бот (при выдаче токена) | `X-Admin-Key: <секрет>` | `{token_hash, tg_id, email, tier}` |
| `POST /activation` | установщик клиента | без ключа | `{token_hash, tg_id, installer_version, client_os, tier, track}` |
| `GET /stats` | Антон | `X-Admin-Key` | — (`?format=csv`) |

Ключевые правила (в reference-worker.js всё это уже есть):
- `token_hash` = **sha256(полного токена) hex** — канон, тот же в установщиках.
- `/activation` обновляет **только** уже `/issue`-нутые строки (мусор — игнор).
- `/issue` идемпотентен (UPSERT, last-write-wins; `issued_at` сохраняем первый).
- CSV-вывод экранирует formula-injection (`= + - @` → префикс `'`).

## Когда поднимешь
Пришли Антону **URL** (`https://…/activation`) — он подставит его в установщики
(переменная `VIP_ACTIVATION_ENDPOINT`, сейчас пустая = пинг выключен) и
перевыпустит bundled. `X-Admin-Key`-секрет сгенерируй сам и держи у себя +
отдай Антону для `/stats`.
