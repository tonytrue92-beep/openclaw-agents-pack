# Changelog

История изменений в установщике OpenClaw Agents Pack.

Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/).

---

## 2026-04-22 — Wave 5 (шестой VIP-агент: Копирайтер ✍️)

### Added

- **Шестой VIP-агент: ✍️ Копирайтер.** Пишет продающие тексты, заголовки,
  посты, сценарии Reels, лид-магниты. Работает в паре с Маркетологом
  (смыслы) и Дизайнером (визуал). Шаблоны в `templates/copywriter/`:
  - `IDENTITY.md` — роль, границы (что делает, что отправляет коллегам)
  - `AGENTS.md` — workspace rules + список форматов которые знает
    (TG-пост, Reels, лендинг, рассылка, welcome-цепочка, заголовок, lead magnet)
  - `MEMORY.md` — рабочая память: твой голос, стоп-слова, сработавшие
    заголовки, словарь клиента
  - `USER.md` — пустой шаблон «заполни сам»: ниша, ЦА, тон, запреты

- VIP-набор теперь **6 агентов** (было 5): Технарь + Маркетолог +
  Продюсер + Дизайнер + Координатор + Копирайтер.
- В `install-agents.sh`: emoji+label для copywriter, добавлен в
  `--only` список, в `AGENTS_TO_INSTALL` для VIP-режима, в текстах
  меню. При выборе `--only copywriter` автоматически включается
  VIP_MODE (как с designer/coordinator).

### Changed

- Docker smoke ожидает **12** (Standard) или **24** (VIP) md-файлов
  в templates/ вместо 12/20.
- Гайд `docs/vip-install-guide.md` обновлён: «5 агентов» → «6», в
  таблице добавлена строка с Копирайтером, пересчитана длительность
  установки (+1 бот = +1 минута).

### Upgrade scenario (важно)

Клиенты, у которых уже стоят 5 VIP-агентов, при повторном запуске
установщика увидят **R0 = UPGRADE** (благодаря коммиту `045fd7d`):

```
🔼 Обнаружен апгрейд:
Уже установлены (будут сохранены):
   ✓ tech, marketer, producer, designer, coordinator
Не хватает (будут добавлены):
   + copywriter

Выбор [1/2/3, Enter = 1]:   ← default «Дополнить»
```

Нажатие Enter → ставится только copywriter, существующие пятеро не
трогаются (их MEMORY.md, подключённые Telegram-боты, personalized
настройки сохраняются). В R2 запрашивается один токен — для бота
Копирайтера, а не все 6.

Для новых VIP-клиентов (свежая установка) — сразу все 6, как раньше
было 5.

---

## 2026-04-21 — Wave 4 (smart upgrade Standard → VIP)

### Changed — R3 перенесён в R0, default теперь зависит от сценария

Раньше при повторном запуске (клиент уже ставил 3, теперь апгрейдится до
VIP) установщик по умолчанию **сносил всех и ставил заново**. Это теряло
накопленную MEMORY.md трёх исходных агентов, заставляло клиента заново
подключать ботов.

Новая логика в R0 (переименован из R3, перенесён ДО R2 чтобы не спрашивать
лишние токены):

- **FRESH** (никого нет) → ставим всех из `AGENTS_TO_INSTALL` без вопросов.
- **UPGRADE** (часть стоит, часть не хватает — типично Standard → VIP):
  default = «Дополнить недостающих, существующих не трогать». Альтернатива
  «Перезаписать всех» осталась как опция 2. `AGENTS_TO_INSTALL` сразу
  фильтруется до missing, и в R2 клиент вводит только 2 новых токена
  (designer + coordinator), а не все 5.
- **OVERWRITE** (все агенты из списка уже стоят — клиент чинит/обновляет):
  default = «Перезаписать начисто».

R3 теперь — просто cleanup-блок, выполняется только если в R0 выбран
overwrite.

### UX-эффект

Клиент, апгрейдящийся Standard → VIP, увидит:

```
━━━ STEP R0: АНАЛИЗ ТЕКУЩЕГО СОСТОЯНИЯ ━━━

🔼 Обнаружен апгрейд (не полная, но частичная установка):

Уже установлены (будут сохранены):
   ✓ tech
   ✓ marketer
   ✓ producer

Не хватает (будут добавлены):
   + designer
   + coordinator

Что делать?
1) Дополнить (поставить только недостающих, существующих не трогать)  ← рекомендуется
2) Перезаписать всех (снести 3 и поставить 5, теряете MEMORY.md)
3) Прервать

Выбор [1/2/3, Enter = 1]: _
```

Enter → автоматически доустановка без потери существующих данных.

---

## 2026-04-21 — Wave 3 (VIP v2: TG-binding, anti-sharing)

### Security — VIP-токен привязывается к Telegram user_id

Раньше токен был детерминирован от email — любой с этим токеном мог
поставить 5 агентов. Если VIP-клиент пересылает токен другу — друг
бесплатно получает VIP. Классическая проблема инфопродуктов.

Фикс: новый формат токена `VIP-<email_hash16>-<tg_user_id>-<signature>`,
где `tg_user_id` зашит в payload и подписан Ed25519 приватным ключом
бота. Установщик:

- Автоматически читает TG ID клиента из `~/.openclaw/openclaw.json`
  (первый установщик уже записал туда `OWNER_TG_ID` для allowlist)
- Сравнивает с tg_user_id внутри токена
- При несовпадении — отказ с объяснением «этот токен выдан для другого TG»
- Retry через `continue` (по правилу #20 в handoff первого установщика)

Подмена чужого TG id невозможна — это аккаунт Telegram. Шаринг
становится бесполезным.

### Added

- **`scripts/lib/vip.sh`** обновлён под v2 формат токена:
  - `verify_vip_token <token> <machine_tg_id>` — раздельные exit codes
    (2=формат, 3=tg-mismatch, 4=base64, 5=bad signature) для точных
    сообщений пользователю
  - `vip_token_get_expected_tg <token>` — извлечь ожидаемый TG ID
    (для show'а пользователю «токен выдан для TG X»)
  - `vip_token_get_hash <token>` — извлечь email_hash16 для fire-and-
    forget логирования
  - `vip_detect_owner_tg_id` — автодетект TG ID из `~/.openclaw/openclaw.json`
    через чтение `channels.telegram.allowFrom` / `allowlistAllowFrom`
  - `vip_log_activation <token_hash> <tg_id>` — fire-and-forget POST
    на `/log/activation` endpoint бота. Таймаут 3 сек, в фоне, при
    недоступности молча пропускаем. Бот ведёт журнал уникальных IP
    по каждому токену и шлёт Антону алерт при ≥3 IP за 7 дней.

- **V1 (`install-agents.sh`)** переписан:
  - Автоматическое чтение TG ID из настроек первого установщика
  - Цикл `while true` с `continue` для retry (правило #20)
  - Точные сообщения под каждый exit code валидации
  - При `--config` режиме — fail-fast, без retry

- **Watermark в IDENTITY.md для VIP-установок**
  (`scripts/lib/agents.sh:prepare_workspace_from_templates`):
  `<!-- issued-to: <hash> | tg:<tg_id> | <agent_id> | YYYY-MM-DD -->`
  Markdown-комментарий не рендерится, агенты его не видят, но если
  VIP-клиент кому-то пришлёт свои файлы — ясно чей это инстанс.
  Психологический сдерживающий слой.

### Breaking

v1-токены (формат `VIP-<hash>-<signature>` без tg_user_id) больше не
валидируются. Все клиенты должны получить свежие токены у
`@AITeamVIPBot`. Для смягчения — см. инструкцию в handoff.

---

## 2026-04-19 — Wave 2 (post-first-client fixes + video demo)

### Added
- **`scripts/demo-simulate.sh`** — автономная симуляция всего флоу установки
  для видеоуроков. Не требует OpenClaw, реальных токенов, API-ключей или
  интернета — просто визуально проигрывает R0-R5 со всеми экранами, цветами
  и таймерами. Три режима:
  - без флагов — интерактивная, Enter между блоками (для подробного объяснения)
  - `--auto` — без пауз, автоматический прогон ~2 мин (для записи видео)
  - `--fast` — ускоренные таймеры ~30 сек (для превью/GIF)
- **Решение #1 в `handoff/01-decisions-log.md`**: повторный запуск =
  clean-reinstall по умолчанию (одно меню + `cleanup_agent_completely()`).
- **Решение #2 там же**: duplicate-bot detection на этапе R2.

### Fixed (по боевому тестированию с первым клиентом)
- **R2 retry через `continue`, не `exit`** — клиент нажимал Y на «попробовать
  ещё» и получал выход в терминал. Переписали цикл сбора токенов на единый
  `while true` со всеми проверками внутри. Зафиксировано правилом #20 в
  handoff первого установщика.
- **bash 3.2 compat** — `declare -A` падал на /bin/bash (macOS по дефолту
  bash 3.2, Apple не обновляет из-за GPLv3). Переделали на динамически-
  именованные переменные + version-gate с auto-brew-install в начале.
  Зафиксировано правилом #19 в handoff первого установщика.
- **R3 clean-reinstall** — повторный запуск больше не показывает три меню
  подряд; одно меню в начале с default'ом «перезаписать начисто» и
  идемпотентной cleanup-функцией.

---

## 2026-04-19 — Initial release (wave 1)

### Added
- `scripts/install-agents.sh` — основной установщик, 13 фаз (R1-R13):
  preflight (OpenClaw должен быть установлен, gateway жив, auth-profile на месте),
  главное меню (4 пункта), сбор трёх Telegram tokens с валидацией через
  `api.telegram.org/bot<t>/getMe`, выбор модели (рекомендация `openai-codex/gpt-5.4`),
  скачивание шаблонов с commit-pin, создание трёх workspace-папок, `channels add`
  × 3 с accountId-разделением, `agents add --bind telegram:<acc>` × 3, копирование
  auth-profile из main в каждого нового агента, финальный тест.
- Флаги: `--install`, `--vps` / `--headless`, `--only <agent>`, `--suffix`,
  `--config <file>`, `--diagnose-only`, `--collect-debug`, `--version`, `--help`.
- `scripts/diagnose-agents.sh` — live-проверка всех трёх агентов без изменений:
  существование workspace-папок, `openclaw agents list` содержит id,
  `auth-profiles.json` на месте + `chmod 600`, gateway running, Telegram getMe ok.
- `templates/{tech,marketer,producer}/{IDENTITY,AGENTS,MEMORY,USER}.md` — контент
  агентов в «средней сокращённой» версии. **Без персональных данных автора курса.**
- `scripts/lib/` — вендорные helpers из `openclaw-installer` (ui, preflight,
  telemetry, debug-bundle, agents). Выбрали вендор, не `curl | source`, чтобы
  избежать рантайм-зависимости от сети и drift между репами.
- `docs/telegram-setup.md` — как создать три бота через @BotFather (пошагово).
- `docs/architecture.md` — один бот = один агент, routing через accountId.
- `docs/vps-install.md` — отсылка к первому + тонкости для agent-pack'а.
- `docs/troubleshooting.md` — типовые проблемы (бот молчит, не тот агент отвечает,
  и т.п.).
- `SHA256SUMS` + `scripts/update-checksums.sh` для проверки целостности.
- CI на GitHub Actions: shellcheck + bash -n + smoke-тесты helper-функций +
  security-audit (в том числе проверка что в `templates/**/*.md` нет личных
  данных автора) + SHA256SUMS freshness + Docker smoke (debian + alpine).

### Security
- В `templates/**/*.md` зашит контракт «нет персональных данных автора»:
  security-audit отклоняет коммит, если находит паттерны `sk-`, `[0-9]{8,}:AA`,
  `antonpolakov|tonytrue|@tonytruee|vip-factory|openclaw-factory`.
- `unset BOT_TOKEN_*` сразу после `openclaw channels add`.
- Вывод всех `openclaw channels add` проходит через inline-`sed`-маску
  (защита от случайной утечки токена в stdout CLI).
- `trap ERR` → `collect_debug_bundle` с `redact_secrets` как в первом установщике.

### Команда для клиентов
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh)
```

---

## Roadmap

- Обновление шаблонов агентов по обратной связи куратора курса.
- Опционально: helper `openclaw-agents-reset <agent>` для быстрого сноса/перестановки одного из трёх.
- Опционально: автообновление шаблонов (`--update-templates`) без пересоздания агента.
- Docker integration-тест с моком Telegram API (`mock-telegram-api.py`).
