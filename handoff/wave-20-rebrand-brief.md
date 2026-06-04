# ТЗ: Wave 20 rebrand — публичные тарифы Base/Pro/OpenClaw

**Дата:** 2026-05-24
**Кому:** технарь Антона (`openclaw-factory` + `@AITeamVIPBot`)
**Автор запроса:** Антон Поляков
**Приоритет:** средний (не блокирует продакшен — старые названия
ещё понятны клиентам)
**Estimate:** 30 минут factory + 1-2 часа бот

## TL;DR

Антон зафиксировал **публичный нейминг** продуктовой линейки.
В `openclaw-agents-pack` v2026.05.24 (wave 20) уже сделано —
нужно применить такое же переименование в **factory** (UI-тексты)
и **@AITeamVIPBot** (сообщения клиентам).

## Финальная линейка тарифов

| Внутри (token-payload) | Публично | Что включает |
|---|---|---|
| `SUB` (subscription, ежемесячная) | **OpenClaw** | Только движок + main-агент |
| `STD` (Standard, разовая) | **Base** | + 3 агента (Технарь, Маркетолог, Продюсер) |
| `VIP` (разовая) | **Pro** | + 8 агентов (всё + Дизайнер, Координатор, Копирайтер) |

**ВАЖНО**: внутренний `tier` в payload-формате токена **не меняется**.
Backwards-compat 100%. Старые токены продолжают работать. Меняется
**только** что клиент **видит на экране**.

## Reference — что уже сделано в agents-pack

Commit: https://github.com/tonytrue92-beep/openclaw-agents-pack/commit/v2026.05.24
CHANGELOG: https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/CHANGELOG.md#2026-05-24--wave-20

Конкретные правки можно посмотреть в diff'е PR #30:
https://github.com/tonytrue92-beep/openclaw-agents-pack/pull/30/files

---

## ЧАСТЬ 1 — Factory `demo-install.sh`

### Шаг 1.1. Найти упоминания тарифов в UI-выводе

```bash
grep -nE 'Standard|VIP|подписка|Subscription' scripts/demo-install.sh
```

Игнорировать: технические термины (`COURSE_TIER`, `_verify_v3`,
комментарии в коде), payload-формат `VIP-...`, `STD-...`, `SUB-...`
(это в токенах, не меняем).

### Шаг 1.2. Заменить в `echo` / `explain` / `printf` блоках

| Старое | Новое |
|---|---|
| `Standard` (в выводе клиенту) | `Base` |
| `Standard-набор` / `Standard-тариф` | `Base-набор` / `Base-тариф` |
| `VIP` (в выводе клиенту) | `Pro` |
| `VIP-набор` / `VIP-тариф` | `Pro-набор` / `Pro-тариф` |
| `Subscription` / `SUB-тариф (подписка)` | `Тариф OpenClaw (подписка)` |

### Шаг 1.3. Что **НЕ менять**

- ❌ Внутренние переменные: `COURSE_TIER`, `VIP_MODE`, `STD_MODE`,
  `SUB_MODE` — оставляем как есть
- ❌ Имя бота: `@AITeamVIPBot` — это бренд, не меняем
- ❌ Параметры функций: `verify_vip_token`, `_verify_v3_vip` — это
  внутренняя API
- ❌ Префиксы токенов в комментариях кода (например, в формате
  `SUB-XXXXXX-<TG>-<sign>` — это технический формат)
- ❌ Сам формат токена (Ed25519, payload)

### Шаг 1.4. Bump INSTALLER_VERSION

Например, `2026.05.24` → `2026.05.25` (или твоя следующая дата).

### Шаг 1.5. Commit + PR

Suggested commit message:
```
Wave 20: публичные тарифы Base/Pro в demo-install.sh

  • Standard → Base (в UI-выводе)
  • VIP → Pro (в UI-выводе)
  • SUB-тариф (подписка) → Тариф OpenClaw (подписка)

Внутренние COURSE_TIER (STD/VIP/SUB) и token-payload не меняются —
backwards-compat 100%. Старые токены работают.

Аналогично openclaw-agents-pack v2026.05.24 (wave 20).
```

---

## ЧАСТЬ 2 — @AITeamVIPBot (сообщения клиентам)

### Где менять

Бот выдаёт несколько типов сообщений где упоминаются тарифы:

1. **При выдаче токена** (`/start` → email/phone → токен)
2. **При проверке статуса** (`/status`, `/me` или подобное)
3. **При истёкшей подписке** (SUB-tier)
4. **При апгрейде** (если есть `/upgrade`)
5. **В саппорт-сообщениях** / описании тарифов
6. **В справке** (`/help`)

### Шаг 2.1. Сообщения при выдаче токена

| Сценарий | Старое сообщение (примерно) | Новое сообщение |
|---|---|---|
| Найден VIP | «Привет! Твой VIP-токен:» | «Привет! Твой **Pro**-токен:» |
| Найден STD | «Твой Standard-токен:» | «Твой **Base**-токен:» |
| Найден SUB | «Твой Subscription-токен:» | «Твой **OpenClaw** (подписка)-токен:» |
| Не найден | «Не нашёл оплаты по этому email» | (не меняется) |

### Шаг 2.2. Сообщения об истёкшей подписке (SUB)

```
СТАРОЕ:
  ❌ Твоя SUB-подписка истекла 14 мая 2026.
     Продли в @AITeamSupport чтобы получить новый токен.

НОВОЕ:
  ❌ Твоя OpenClaw-подписка истекла 14 мая 2026.
     Продли в @AITeamSupport чтобы получить новый токен.
```

### Шаг 2.3. Описание тарифов в `/help` или `/start`

```
СТАРОЕ:
  Тарифы:
    • Subscription — базовая установка
    • Standard — + 3 агента
    • VIP — + 8 агентов

НОВОЕ:
  Тарифы:
    • OpenClaw — базовая установка (движок + main-агент)
    • Base — + 3 агента (Технарь, Маркетолог, Продюсер)
    • Pro — + 8 агентов (всё + Дизайнер, Координатор, Копирайтер)
```

### Шаг 2.4. Внутренние названия — НЕ менять

```python
# Эти строки в коде бота не трогать:
TIER_SUB = "SUB"          # ← остаётся в БД и payload
TIER_STD = "STD"          # ← остаётся
TIER_VIP = "VIP"          # ← остаётся

# Меняется только то что бот ПОКАЗЫВАЕТ:
TIER_PUBLIC_NAMES = {
    "SUB": "OpenClaw",
    "STD": "Base",
    "VIP": "Pro",
}
```

То есть: **внутри** бота tier остаётся `SUB`/`STD`/`VIP`, а **наружу**
бот подменяет на `OpenClaw`/`Base`/`Pro`.

Это **самый аккуратный** способ rebrand'а — нулевой риск сломать БД
и совместимость со старыми токенами.

### Шаг 2.5. CSV-импорт (из wave 16 subscription brief)

Если в CSV-импорте подписчиков есть колонка `tier` — она может
содержать `SUB` / `Standard` / `VIP` (или `Base` / `Pro` — на усмотрение
автора CSV). Бот должен **принимать оба варианта** на импорте:

```python
TIER_ALIASES = {
    # старые имена
    "SUB": "SUB", "Subscription": "SUB", "subscription": "SUB",
    "STD": "STD", "Standard": "STD", "standard": "STD",
    "VIP": "VIP", "vip": "VIP",
    # новые публичные имена
    "OpenClaw": "SUB", "openclaw": "SUB",
    "Base": "STD", "base": "STD",
    "Pro": "STD" if False else "VIP", "pro": "VIP",
}
```

Это страховка от случайной путаницы при ручном импорте.

---

## Тестирование

### Factory

```bash
# 1. Запустить с тестовым токеном и проверить что меню / выводы
# показывают Base / Pro / OpenClaw, а НЕ Standard / VIP / SUB.
bash scripts/demo-install.sh --install --course-token TEST-TOKEN

# 2. Help содержит новые названия (если упоминаются):
bash scripts/demo-install.sh --help | grep -iE 'Base|Pro|OpenClaw'

# 3. bash -n + smoke-test + security audit — всё зелёное.
```

### Бот

```bash
# 1. Поднять локально / dev
# 2. Команда /start как VIP-клиент → токен с сообщением «Pro-токен»
# 3. Команда /start как STD-клиент → токен с сообщением «Base-токен»
# 4. Команда /start как SUB-клиент → токен с сообщением «OpenClaw-токен»
# 5. /help → новые названия тарифов
# 6. Тест с истёкшей подпиской → «OpenClaw-подписка истекла»
```

---

## Что после деплоя

Пиши Антону одной строкой:
```
Wave 20 rebrand:
  • factory готов, версия 2026.MM.DD
  • @AITeamVIPBot обновлён (deploy на проде)
```

Антон может запустить **полный flow** установки и убедиться что
**всё** что видит клиент — Base / Pro / OpenClaw (нигде не торчит
старое название). Если что-то осталось — отдельный hotfix.

---

## Estimate

- **Factory** (Часть 1): **30 минут** (5 grep + 5 edit + commit)
- **@AITeamVIPBot** (Часть 2): **1-2 часа** (зависит от количества
  мест где упоминаются тарифы в боте)
- **Итого**: **1.5-2.5 часа**

## Reference

- agents-pack wave 20 PR (готовый паттерн):
  https://github.com/tonytrue92-beep/openclaw-agents-pack/pull/30/files
- agents-pack v2026.05.24 (готовый код):
  https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/v2026.05.24/scripts/install-agents.sh
- CHANGELOG wave 20:
  https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/CHANGELOG.md#2026-05-24--wave-20

Поиск в файле: `wave 20` — это все изменения.
