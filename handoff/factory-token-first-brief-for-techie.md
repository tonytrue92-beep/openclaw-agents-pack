# ТЗ: token-first flow в `openclaw-factory/demo-install.sh`

**Дата:** 2026-05-13
**Кому:** технарь Антона (`openclaw-factory`)
**Автор запроса:** Антон Поляков
**Зависимости:** wave 12 (course-token mandatory) + wave 16 (SUB-tier) уже сделаны

## TL;DR

Сейчас в factory **курс-токен запрашивается только при выборе «Реальная установка»** в меню. Антон в чате: «при выборе демо установки тоже не запрашивается токен — это плохо».

Нужно **поднять запрос токена ВЫШЕ меню** — чтобы любой клиент (даже для «Демо» / «Симуляция» / «VPS-гайд») сначала валидировался токеном. Это **гейтит весь продукт** — посторонние не могут просто запустить и посмотреть как устроена установка.

Та же логика что мы сделали в `openclaw-agents-pack` v2026.05.04 (wave 14): «token-first flow».

## Что сейчас (`b491e89868` — последний main)

```
запуск demo-install.sh
  ↓
парсинг флагов
  ↓
early-exit --collect-debug, --diagnose-only        (read-only, токен ок)
  ↓
НАЧАЛЬНОЕ МЕНЮ — 4 варианта:
   1) Демо                  ← токен НЕ запрашивается
   2) Реальная установка    ← токен запрашивается ниже
   3) Симуляция (dry-run)   ← токен НЕ запрашивается
   4) VPS-гайд              ← токен НЕ запрашивается, скрипт показывает текст и exit
  ↓
[если SKIP_DEMO=true (выбрана опция 2 или 3)]
  step_header "R0" "COURSE-TOKEN"           ← запрос токена ЗДЕСЬ
  acquire_course_token_for_install
  ↓
R1 SYSTEM CHECK → R2 INSTALL OPENCLAW → R3 ONBOARDING → ...
```

**Проблема**: опции 1, 3, 4 проходят без токена. Демо реально показывает все шаги установки с командами — фактически даёт инструкцию как поставить вручную **без покупки**.

## Что должно быть (token-first)

```
запуск demo-install.sh
  ↓
парсинг флагов
  ↓
early-exit --collect-debug, --diagnose-only        (как раньше, read-only)
  ↓
*** НОВОЕ: V0 — COURSE-TOKEN — ДО МЕНЮ ***
  step_header "V0" "COURSE-TOKEN"
  acquire_course_token_for_install
  (если токен не валиден → exit 1 с red-блоком)
  ↓
clear + banner OpenClaw
  ↓
НАЧАЛЬНОЕ МЕНЮ — 4 варианта (теперь tier-aware):
   - SUB-tier → автоматически Реальная установка (без меню),
                после установки: «у тебя базовая, доп. агенты на STD/VIP»
   - STD/VIP → меню как сейчас, но опция 4 (VPS-гайд) под VIP/STD/SUB одинаково
  ↓
R1 → R2 → R3 → ...
```

**Логика выхода**: если клиент **отменяет** на V0 (не вводит токен или вводит невалидный) — скрипт завершается без банера/меню. Никаких подсказок «вот так бы выглядела установка». Клиент видит:

```
╔════════════════════════════════════════════════════════════════╗
║   ✗  УСТАНОВКА ОТКЛОНЕНА — курс-токен не валиден              ║
╚════════════════════════════════════════════════════════════════╝

Получи токен в @AITeamVIPBot:
  /start → email/телефон → токен SUB-... / STD-... / VIP-...
```

## Конкретный патч

### Шаг 1. Перенести вызов `acquire_course_token_for_install` ВЫШЕ меню

В текущем коде:
- Объявление функции на строке 426
- Использование где-то после строки 1945 (в блоке `if [[ "$SKIP_DEMO" == true ]]; then ... R0 ... fi`)

**Изменение**:

1. Удалить блок `step_header "R0" "COURSE-TOKEN"` + `acquire_course_token_for_install ...` из текущего места (где он сейчас, после меню)

2. Поднять его **сразу после** early-exit'ов и **ДО** `if [[ "$SKIP_DEMO" != true ]]; then ... МЕНЮ ... fi` (примерно строка ~1865).

Псевдокод:

```bash
# ─── Early exits (как сейчас) ───
if [[ "$COLLECT_DEBUG_ONLY" == true ]]; then ... exit 0; fi
if [[ "$DIAGNOSE_ONLY" == true ]]; then run_diagnostics; exit 0; fi

# ─── НОВОЕ: V0 — COURSE-TOKEN ───
# Любой intent (демо/реал/симуляция/VPS) сначала валидируется.
step_header "V0" "ПРОВЕРКА КУРС-ТОКЕНА"
machine_tg_id=$(...)  # detect

if ! acquire_course_token_for_install "$COURSE_TOKEN_PRESET" "$machine_tg_id"; then
  # Большой red-блок с инструкцией (можно скопировать из
  # openclaw-agents-pack/scripts/install-agents.sh wave 15.1)
  echo "╔══...══╗"
  echo "║  ✗  УСТАНОВКА ОТКЛОНЕНА — курс-токен не валиден  ║"
  # ... подробные инструкции
  exit 1
fi

ok "Курс-токен подтверждён: ${COURSE_TIER}-тариф"

# ─── SUB-tier: auto skip menu (опционально) ───
# Если хочешь — для SUB-tier пропустить меню и сразу к реальной установке,
# потому что SUB = только базовая установка main-агента. Меню «демо/симуляция»
# для SUB не имеет смысла.
if [[ "$COURSE_TIER" == "SUB" ]]; then
  SKIP_DEMO=true
  echo "ℹ️  SUB-тариф (подписка) — перехожу к установке OpenClaw + main-агента."
fi

# ─── МЕНЮ (как сейчас, для STD/VIP) ───
if [[ "$SKIP_DEMO" != true ]]; then
  clear
  # ... banner + меню как сейчас
fi

# ─── R1 → R2 → R3 (как сейчас) ───
```

### Шаг 2. Обновить help

```bash
echo "Options:"
echo "  --install         Skip menu, go to real install"
echo "  --dry-run         Simulate install (nothing changed)"
echo "  --vps             Show VPS deployment guide and exit"
echo "  --course-token T  Course-token from @AITeamVIPBot (SUB/STD/VIP)"
echo "  --collect-debug   Collect debug-bundle (no token required)"
echo "  --diagnose-only   Check installation health (no token required)"
echo "  --help            Show this help"
```

### Шаг 3. INSTALLER_VERSION bump

```
INSTALLER_VERSION="2026.05.13"   # или твоя следующая
```

И запуш с commit-сообщением:

```
Wave 14 equivalent: token-first flow in factory installer

Перенёс course-token check ВЫШЕ меню. Раньше токен запрашивался
только для опции «Реальная установка»; теперь — для любого варианта
(демо/симуляция/VPS-гайд тоже требуют токен).

Аналогично openclaw-agents-pack v2026.05.04 (wave 14).
```

## Что НЕ менять (out of scope)

- **VPS-режим (опция 4)** — оставить как есть в плане «показать инструкцию и exit». Только теперь после валидации токена. Это правильно — клиент должен подтвердить тариф перед получением инструкции «как развернуть на VPS».
- **Демо-режим (опция 1)** — оставить как есть в части «10 шагов с объяснениями, ничего не ставится». Только теперь требует токен.
- **acquire_course_token_for_install функция** — не менять её, только переместить вызов.

## Что добавить в нашем agents-pack (после твоего деплоя)

Когда задеплоишь — наш agents-pack уже **готов**: SUB / STD / VIP-токены распознаются с wave 16. Никаких изменений с моей стороны.

Но я хочу 2 теста после твоего деплоя:

1. **Запустить factory без токена** → ожидаю «УСТАНОВКА ОТКЛОНЕНА» сразу, до меню
2. **Запустить с `--course-token SUB-...`** → ожидаю что меню пропускается, идёт к R1 (если SUB auto-skip menu сделан)

Пришли что задеплоил — прогоню эти 2 теста на своей машине.

## Estimate

- Шаг 1 (перенос блока): **30 минут** (просто sed-like операция)
- Шаг 2 (help): 5 минут
- Шаг 3 (bump + commit + push): 10 минут
- **Итого: ~45 минут работы**

## Reference

Вот как сделано в нашем agents-pack (готовый пример):
- https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/scripts/install-agents.sh
- Поиск: `step_header "V0" "ПРОВЕРКА КУРС-ТОКЕНА"` — это V0 блок
- Поиск: `УСТАНОВКА ОТКЛОНЕНА — курс-токен не валиден` — red-блок отказа

Можешь скопировать red-блок 1-в-1 — он generic, не привязан к agents-pack.
