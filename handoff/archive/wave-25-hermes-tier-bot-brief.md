# ТЗ: HRM-tier (Hermes) в `@AITeamVIPBot`

**Дата:** 2026-05-25
**Кому:** технарь Антона (`@AITeamVIPBot`)
**Автор запроса:** Антон Поляков
**Приоритет:** средний (после wave 20 rebrand + SUB-tier)
**Estimate:** 3-4 часа

## TL;DR

В нашем `agents-pack` v2026.05.25.3 (wave 25) появилась **новая
опция** «Hermes — супер-агент» в главном меню установщика. Она
требует **отдельный платный токен** `HRM-...`.

На стороне бота нужно: **новая таблица покупателей Hermes** + **выдача
HRM-токенов**. Запуск самого Hermes происходит на стороне установщика
— тебе не надо лезть в Hermes-инфраструктуру, только генерация токенов.

## Что уже сделано в agents-pack (для контекста)

- Опция «4) Hermes» в главном меню (показывается только если
  OpenClaw обнаружен на машине клиента)
- Распознавание формата `HRM-...` в `scripts/lib/vip.sh` (новый
  tier `v3-hrm`)
- Валидация через тот же Ed25519-ключ что для VIP/STD/SUB —
  payload `HRM|<hash>|<tg>`
- Установка Hermes — наша часть установщика, тебе не надо

Сейчас клиенты могут попытаться ввести HRM-токен — но пока бот не
научится их выдавать, валидация будет проваливаться. Это OK как
промежуточное состояние.

## Что нужно на стороне бота

### 1. Новая таблица `hermes_buyers`

По аналогии с `subscribers` из wave 16:

```sql
CREATE TABLE hermes_buyers (
  id            SERIAL PRIMARY KEY,
  email         VARCHAR(255) NOT NULL UNIQUE,
  phone         VARCHAR(20),
  purchased_at  TIMESTAMP NOT NULL DEFAULT NOW(),
  -- Hermes — это покупка, не подписка (без expiry).
  -- Если позже захотите подписочную модель — добавите expires_at NULL.
  tg_id         BIGINT,
  notes         TEXT
);

CREATE INDEX idx_hermes_buyers_email ON hermes_buyers (email);
CREATE INDEX idx_hermes_buyers_tg_id ON hermes_buyers (tg_id) WHERE tg_id IS NOT NULL;
```

### 2. Команда `/admin_upload_hermes_buyers`

По аналогии с `/admin_upload_subscribers` из wave 16:

```
/admin_upload_hermes_buyers
<reply на CSV-файл>
```

CSV-формат:
```csv
email,phone,purchased_at,notes
buyer1@example.com,+79991234567,2026-05-20,early adopter
buyer2@example.com,,2026-05-22,
```

Upsert по `email` (если уже есть — обновить `purchased_at` и `notes`).

### 3. Логика поиска при `/start`

Сейчас (после wave 16) поиск идёт в порядке: **VIP → STD → SUB**.

После wave 25 нужно **4-level**:

```python
def find_tier(email: str, phone: str | None) -> tuple[str, dict] | None:
    """Возвращает (tier, row) или None если ничего не найдено."""
    # Hermes — отдельный SKU. Может быть куплен дополнительно к Pro/Base/SUB.
    if row := query_hermes_buyers(email=email, phone=phone):
        return ('HRM', row)
    if row := query_vip_buyers(email=email, phone=phone):
        return ('VIP', row)
    if row := query_std_buyers(email=email, phone=phone):
        return ('STD', row)
    if row := query_subscribers(email=email, phone=phone):
        return ('SUB', row)
    return None
```

**ВАЖНО**: Hermes можно купить **дополнительно** к Pro/Base/SUB.
Если клиент есть **и** в `vip_buyers` **и** в `hermes_buyers` —
выдаём **два токена** (один VIP, один HRM), они для **разных** опций
установщика.

### 4. Генерация HRM-токенов

Тот же приватный Ed25519-ключ что для VIP/STD/SUB. Payload:

```
"HRM|<email_hash16>|<tg_user_id>"
```

Формат токена:
```
HRM-<email_hash16>-<tg_user_id>-<base64url_signature>
```

Где:
- `<email_hash16>` — первые 16 hex-символов SHA256 от email (как раньше)
- `<tg_user_id>` — числовой ID Telegram-пользователя
- `<base64url_signature>` — Ed25519 без padding, 80-100 символов

Пример (псевдо):
```
HRM-A1B2C3D4E5F60718-123456789-N-Th2FIT...AhpaloRrihjJ2xnxDw
```

Длина 80-100 символов signature — тот же диапазон что в существующих
v3-VIP/STD/SUB.

### 5. Сообщение клиенту при выдаче HRM-токена

Шаблон (адаптируй под стиль бота):

```
🤖 Hermes — твой super-agent

Твой HRM-токен (отдельный от Pro/Base/OpenClaw):

HRM-A1B2C3D4E5F60718-123456789-N-Th2FIT...

Что это даёт:
  • Super-agent над всей твоей AI-командой
  • Оркестрация: одно сообщение — Hermes сам разруливает кому делать
  • Контекст всех агентов в одной голове

Как поставить:
  1. На машине где стоит OpenClaw — запусти установщик AI-команды
     (которым ставил Pro/Base агентов)
  2. В главном меню выбери «4) Hermes»
  3. Вставь этот HRM-токен

Опция 4 появляется в меню автоматически — установщик сам определит
что у тебя OpenClaw стоит.
```

### 6. Опционально — pricing flow

Если Hermes продаётся как **upgrade** к существующему тарифу:

- В `/me` или `/status` показать: «У тебя Pro. Хочешь Hermes (+$X)?»
- Кнопка «Купить Hermes» → лендинг или платёжная ссылка
- После оплаты → автоматически добавить в `hermes_buyers`

Это **не блокирует** wave 25 — можно делать после базовой реализации.

## Тестовые HRM-токены

После реализации **пришли 2 тестовых токена** Антону:
1. HRM-токен для **существующего** TG-аккаунта (для positive-теста)
2. HRM-токен для **другого** TG-аккаунта (для anti-share теста)

Антон добавит их в smoke-test runtime-проверки (как для STD/VIP в
wave 12.1).

## Estimate

- **БД schema + миграция**: 30 минут
- **`/admin_upload_hermes_buyers`**: 1 час (copy-paste из wave 16)
- **4-level поиск при `/start`**: 30 минут
- **Генерация HRM-токенов**: 1 час
- **Сообщение клиенту + тесты**: 30 минут
- **Итого**: 3-4 часа

## Когда задеплоишь

Пиши Антону одной строкой:
```
Wave 25 HRM-tier готов в @AITeamVIPBot. Тестовые токены: HRM-... / HRM-...
```

После этого Антон может купить Hermes сам себе и проверить полный
flow от `/start` в боте до выбора опции 4 в установщике.

## Reference

- Wave 25 в agents-pack: `v2026.05.25.3`
- CHANGELOG (wave 25 раздел):
  https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/CHANGELOG.md
- HRM-tier распознавание в коде: `scripts/lib/vip.sh` (функции
  `vip_token_version`, `verify_vip_token`, `course_token_get_tier`)
