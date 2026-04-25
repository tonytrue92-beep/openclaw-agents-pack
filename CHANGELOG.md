# Changelog

История изменений в установщике OpenClaw Agents Pack.

Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/).

---

## 2026-04-25 — Wave 8.2 (карты РФ + ref-ссылка на виртуальную карту)

Уточнение к wave 8.1. В первой версии было сказано «РФ-карты могут не
пройти, вот варианты». Это **неточно** — российские карты OpenAI не
принимает 100%. Переписал блок жёстче и добавил конкретный путь решения.

### Changed

- **`docs/openai-key-setup.md`** — раздел «Если карта не проходит (РФ-карты)»:
  - Заголовок: «Карты РФ — что делать (100% не работают напрямую)».
  - Прямой текст: «OpenAI **не принимает** карты выпущенные в России —
    это санкционное ограничение, обходного пути нет».
  - **Вариант 1** — реф-ссылка на бот для выпуска виртуальной зарубежной
    карты (Казахстан/Армения):
    `https://t.me/WhisperSummaryAI_bot?start=ref_1167075209` +
    пошаговая инструкция (открыть → выпустить → пополнить рублями →
    использовать в OpenAI billing).
  - **Вариант 2** — уже есть зарубежная карта (список не-санкционных стран).
  - **Вариант 3** — попросить друга с зарубежной картой.
  - Расчёт реальной стоимости в рублях (~1000-1500₽ первый раз,
    дальше 500-600₽ раз в год-два).
  - Явный «❌ что НЕ работает» список (МИР, криптокарты, российские BIN).
- **`docs/vip-install-guide.md`** — новый FAQ «У меня российская карта —
  что делать?» с краткой версией и ссылкой на бот.
- **`docs/workbook-source.md`** — Модуль 2, шаг 2.3: РФ-карта блок
  переписан на конкретный (открыть бот → выпустить → пополнить).

### Why

Антон в чате сказал: «Карты РФ не работают, это 100%. Нужно дать ссылку
на бот для выпуска виртуальной зарубежной карты». Учёл — гайд теперь
содержит **конкретное действие** вместо обтекаемых «варианты есть».

---

## 2026-04-25 — Wave 8.1 (инструкция «где взять OpenAI-ключ»)

Минорный hotfix для wave 8. В шаге R1.5 теперь есть **прямая ссылка**
на `https://platform.openai.com/api-keys` и краткая инструкция (4 шага),
чтобы клиент не зависал когда установщик попросит ключ.

### Added

- В **R1.5 explain-блок** добавлены 3 строки: ссылка на api-keys,
  краткая инструкция (войти → Create new secret key → скопировать → положить $5).
- В обоих местах ввода ключа (interactive sub-prompt) — короткая подсказка
  «где взять» с тем же URL.
- **`docs/openai-key-setup.md`** — полный пошаговый гайд (~250 строк):
  - Регистрация в OpenAI (или вход через существующий ChatGPT-аккаунт)
  - Создание API-ключа со скриншотами
  - Положить $5 на счёт + расчёт «сколько хватит»
  - Список прокси-сервисов для карт РФ (WireMo / PayPond / GetCard)
  - Проверка ключа через curl
  - Best practices безопасности (не публиковать, лимиты, отдельный ключ под embedding)
  - FAQ (10 вопросов)
- **`docs/vip-install-guide.md`** — новая FAQ-секция «Где взять OpenAI API-ключ для embedding?»
- **`docs/workbook-source.md`** — новый шаг **2.3** в Модуле 2 про получение
  OpenAI-ключа (со скриншотами `[SCREENSHOT: ...]`). Существующий «получить
  VIP-токен» сдвинут в 2.4. Все референсы (типа «из шага 2.3» в 3.2)
  обновлены до 2.4.

### Changed

- INSTALLER_VERSION 2026.04.25 → 2026.04.26.

---

## 2026-04-25 — Wave 8 (embedding-память opt-in + multi-agent в TG-группах)

Две независимо-выкатываемые фичи. Wave 8 не трогает ядро OpenClaw —
только конфигурирует то, что Gateway уже умеет (`memorySearch` и
`channels.telegram.accounts.*.groupPolicy`).

### Added — Feature 1: Opt-in embedding-память

- **Новый шаг R1.5 в установщике** между «выбор модели» и «токены ботов»:
  - Объяснение клиенту зачем нужна embedding-память (3-5 строк):
    без неё MEMORY.md читается целиком при каждом ответе → дороже и
    медленнее с ростом памяти. С ней — семантический поиск, копейки в
    месяц.
  - Меню «1) Включить (рекомендуется) / 2) Без embedding», default 1.
  - Sub-вопрос: использовать тот же OpenAI-ключ что для chat-модели,
    или ввести отдельный «cheap» ключ.
  - Валидация ключа через ping `/v1/embeddings` (5s timeout). На неудаче
    — retry / save-anyway / skip.
- **Новые CLI-флаги:** `--enable-embedding` (non-interactive, берёт ключ
  из `OPENAI_EMBEDDING_API_KEY` или `OPENAI_API_KEY`) и `--no-embedding`
  (пропустить шаг — для CI / скриптов).
- **Новые lib-функции в `scripts/lib/agents.sh`:**
  - `validate_openai_embedding_key(key)` — POST на `/v1/embeddings`.
  - `enable_embedding_for_agent(agent_id)` — пишет per-agent
    `agents.<id>.memorySearch.{enabled,provider,model}`.
  - `write_embedding_env_key(key)` — глобально один раз
    `env.vars.OPENAI_EMBEDDING_API_KEY`.
  - `index_agent_memory(agent_id)` — wrapper над `openclaw memory index`
    с heartbeat + `|| warn`.
  - `embedding_status_for_agent(agent_id)` — для diagnose.
- **Хук в R4** (после `copy_auth_profile_from_main`): если
  `EMBEDDING_ENABLED=true` — записываем env-key (один раз) + включаем
  embedding для агента + запускаем индексацию.
- **`--refresh-templates` НЕ трогает embedding-конфиг** — это
  пользовательская настройка, как MEMORY/USER.

### Added — Feature 2: Multi-agent TG-группы

- **Новый CLI-флаг `--enable-group-mode <chat_id>`** для уже установленных
  агентов:
  - Bypass'ит R0–R5, идёт в dedicated entrypoint.
  - Список агентов через `find_installed_agents()`.
  - Печатает чек-лист «BotFather privacy disable + админы + chat_id».
  - Спрашивает подтверждение.
  - Для каждого агента пишет `groupPolicy=allowlist`,
    `groupAllowFrom += chat_id` (дедуп через JSON-массив),
    `groups.<chat_id>.requireMention=true`.
  - Идемпотентно: повторный запуск с тем же chat_id не создаёт дубли.
- **Новый интерактивный шаг R5b** после установки агентов
  (только если ≥2 агентов установлено и не `--config` режим):
  - «Хочешь чтобы агенты работали как команда в общей TG-группе? [y/N]».
  - Default N (не пугаем).
  - На y → пошаговый чек-лист + ввод chat_id (regex `^-?[0-9]+$`).
  - На пустой ввод — отложено: точная команда для запуска позже.
- **Новая lib-функция `configure_group_membership(agent_id, chat_id)`**.
- **Блок «## Если ты в группе с другими агентами» во все 6 AGENTS.md:**
  правила тегания (только @-mention или reply), делегирования по
  ролям. Координатор получает дополнительную строку «я главный по
  координации».
- **`docs/group-mode.md`** — полный гайд: зачем, как настроить
  (BotFather privacy disable + добавление ботов админами + получение
  chat_id), типичные сценарии (утренний брифинг, запрос на продакшн),
  типичные проблемы, откат.

### Changed

- **`scripts/diagnose-agents.sh`:**
  - Раньше итерировал по жёсткому списку `tech / marketer / producer`.
    Теперь динамически определяет какие установлены через
    `openclaw agents list` (поддерживает 3 / 5 / 6 агентов).
  - Добавлены строки **embedding** и **group-mode** в диагностический
    вывод (зелёный / серый / жёлтый).
- **`templates/<agent>/AGENTS.md`** — добавлен блок про работу в группе
  (все 6 ролей).

### Что нужно от клиента вручную (нельзя автоматизировать)

- **Privacy mode у каждого бота** через `@BotFather` → `/setprivacy` →
  `Disable`. Иначе бот в группе видит только сообщения адресованные ему.
- **Создать TG-группу** и добавить ботов как админов.
- **Узнать chat_id** через `@username_to_id_bot` или из URL супергруппы.

### Что под капотом (для Антона / технаря)

- OpenClaw v2026.4.22+ уже поддерживает `memorySearch` (OpenAI
  text-embedding-3-large + sqlite-vec) и `channels.telegram.accounts.*.
  {groupPolicy,groupAllowFrom,groups,requireMention}`. Wave 8 — это
  тонкая UX-обёртка над тем что уже умеет Gateway.
- Watermark из IDENTITY.md (wave 3) не задействован — embedding и
  group-mode не нуждаются в TG-binding'е VIP-токена.

### Verification

- `bash scripts/smoke-test.sh` — 18/18 pass (13 старых + 5 новых wave-8
  ассертов).
- `bash scripts/security-audit.sh` — 6/6 pass.
- `--refresh-templates` не пишет `memorySearch` (verify через `bash -x`).
- Live-тест embedding: dump в MEMORY.md → переиндексация → запрос с
  перефразированной формулировкой → должна быть сослана на сохранённый
  факт.
- Live-тест group-mode: 2 бота в группе, один тегает другого — оба
  отвечают.

---

## 2026-04-23 — Wave 7 (безопасное обновление шаблонов: `--refresh-templates`)

Для клиентов у которых уже стоят агенты, и которые хотят получить новые
шаблоны (SOUL.md, LEARNING.md, обновлённые skills) **без потери MEMORY.md
и USER.md**. Раньше апдейт требовал полной переустановки с потерей
накопленного контекста — это блокировало обновления у тех кто уже
наработал данные.

### Added

- **Новый флаг `--refresh-templates`** (неинтерактивный):
  ```bash
  bash <(curl -fsSL .../install-agents.sh) --refresh-templates
  ```
  Находит все установленные агенты через `openclaw agents list`, идёт
  по каждому, обновляет шаблоны. Не спрашивает токены / модель /
  каналы. Не нужен VIP-токен.

- **Новый пункт меню в R0 (interactive)**:
  Когда установщик видит что все целевые агенты уже стоят (сценарий
  OVERWRITE), теперь предлагается **3 варианта** вместо 2:
  1. **Обновить шаблоны** (default, безопасно) ← новое
  2. Перезаписать начисто (как раньше, с потерей MEMORY.md)
  3. Ничего не делать

  Старый default «Перезаписать» заменён на «Обновить» — это то что
  в 90% случаев нужно клиенту после выхода новой версии. Кто хочет
  clean reinstall — явно выбирает пункт 2.

- **Бэкапы перед перезаписью**: при любом refresh старые файлы
  сохраняются в `~/.openclaw/workspace-<agent>/.backups/<YYYYMMDD-HHMMSS>/`.
  Если новая версия шаблона что-то сломала — откатиться одной командой:
  ```bash
  cp ~/.openclaw/workspace-designer/.backups/20260423-143022/* \
     ~/.openclaw/workspace-designer/
  ```

### Changed

- **`scripts/lib/agents.sh`** — `prepare_workspace_from_templates()` теперь
  принимает третий аргумент `mode` (`full` | `refresh`):
  - `full` (default, поведение как раньше): качает все 4 md-файла +
    VIP-extras, генерит новый watermark из VIP_TOKEN.
  - `refresh`: качает только **системные** файлы (IDENTITY, AGENTS,
    SOUL, LEARNING, skills) — MEMORY.md и USER.md **не трогает**.
    Сохраняет существующий anti-sharing watermark (из старой IDENTITY.md),
    не перевыпускает — для refresh VIP-токен не нужен.

- **Новая функция `find_installed_agents()`** — итерируется по
  известным ID и возвращает список установленных. Используется
  `--refresh-templates` чтобы не спрашивать клиента.

### Что защищено при refresh

- **MEMORY.md** — контекст накопленных сессий (сработавшие заголовки,
  стоп-слова, история задач) — **не трогается**.
- **USER.md** — ответы клиента на онбординг (ниша, ЦА, тон) —
  **не трогается**.
- **Auth-profile** — `~/.openclaw/agents/<id>/agent/auth-profiles.json` —
  **не трогается**.
- **Telegram channel binding** + `dmPolicy`/`allowFrom` настройки —
  **не трогаются**.
- **Anti-sharing watermark** (wave 3) — переносится из старой
  IDENTITY.md в новую как есть.

### Upgrade scenario

- **Клиенты wave 5 / 6** → запускают тот же `curl | bash`, выбирают
  пункт 1 «Обновить шаблоны» (или сразу `--refresh-templates`) →
  получают новые SOUL/LEARNING/skills при сохранённых MEMORY/USER.
- **Новые клиенты** → всё как раньше, свежая установка через
  wave 6 шаблоны.
- **Standard-клиенты** → тоже получают обновление IDENTITY + AGENTS
  (SOUL/LEARNING/skills у них нет — они только для VIP).

### Verification

- `bash scripts/smoke-test.sh` — добавлен wave-7 тест (проверка что
  refresh mode и `--refresh-templates` на месте).
- `bash -n scripts/install-agents.sh` — OK.
- `--refresh-templates` на свежей машине без агентов → корректно
  выходит без ошибок с подсказкой «сначала обычная установка».

---

## 2026-04-22 — Wave 6 (VIP-агенты становятся умнее: SOUL + LEARNING + skills/)

### Added

Три VIP-агента (Дизайнер, Координатор, Копирайтер) получили **расширенный
набор шаблонов** — теперь это не «роль + правила», а полноценные
AI-сотрудники с явным характером, накопленным опытом и готовыми
инструментами:

- **`SOUL.md`** (по одному на агента) — personality, границы
  компетенции, правила автономии (`plan → approve → execute` для
  опасных операций, `do-it-now` для безопасных), протокол
  взаимодействия с командой, **онбординг-протокол** — 5-6 коротких
  вопросов при первой встрече чтобы заполнить USER.md живыми
  данными вместо плейсхолдеров.

- **`LEARNING.md`** (предзаполненный, по одному на агента) —
  5 правил в формате `[CORRECTION] → [CORRECT] → [RULE]`. Примеры:
  - Дизайнер: «Визуал без брифа = мусор — перед работой сверка с Маркетологом»
  - Координатор: «Не "я сделаю" — "я назначу и проконтролирую"»
  - Копирайтер: «Один сильный вариант > пять средних»

  Плюс раздел «Сюда запиши свои уроки» — клиент может дописывать
  свои корректировки в том же формате.

- **`skills/*/SKILL.md`** (по 2 на агента, 6 всего) — импортированные
  из [awesome-openclaw-skills](https://github.com/VoltAgent/awesome-openclaw-skills)
  под MIT-лицензией «smart wrappers»: краткое описание когда
  применять + attribution + ссылка на оригинал для полной установки:
  - **Дизайнер**: `eachlabs-image-generation` (@eftalyurtseven),
    `color-palette` (@qrost)
  - **Координатор**: `agent-collaboration-network` (@neiljo-gy),
    `close-loop` (@clarezoe)
  - **Копирайтер**: `reef-copywriting` (@staybased) — 6 фреймворков
    (PAS/AIDA/FAB/BAB/4P/Star-Story-Solution), `brand-voice-profile`
    (@dimitripantzos)

- **`templates/LICENSE-skills.md`** — единый attribution-manifest со
  ссылками на авторов всех 6 импортированных скиллов + текст MIT-лицензии.

### Changed

- **`scripts/lib/agents.sh`** — `prepare_workspace_from_templates()`
  теперь скачивает расширенные шаблоны (`SOUL.md`, `LEARNING.md`,
  `skills/*/SKILL.md`) **только** для `designer / coordinator /
  copywriter`. Остальные 3 агента (`tech / marketer / producer`)
  получают базовый набор как раньше. Если VIP-extras не докачались
  — `warn`, но установку не прерываем.

- **`templates/<vip_agent>/IDENTITY.md`** и **`AGENTS.md`** — блок
  **Session Startup** (читать файлы в порядке `IDENTITY → SOUL →
  USER → LEARNING → MEMORY → skills`) и секция **«Первый контакт
  (онбординг)»** со списком вопросов под роль.

- **CI-тесты** (`tests/docker/run-checks.sh`, `scripts/smoke-test.sh`,
  `scripts/security-audit.sh`):
  - Docker smoke принимает template count **37** (wave 6) в дополнение
    к историческим 12/24.
  - smoke-test.sh добавлены 3 новых проверки: SOUL+LEARNING существуют,
    6 SKILL.md на месте, AGENTS.md содержит Session Startup + онбординг.
  - security-audit check #6 расширен новыми паттернами (`serditov`,
    `TRUE AI AGENCY`, `СРАБОТАЛО`, `СВЯЗКИ`, `instapol2136`,
    `ntn_ / cpk_ / pat_FL`-префиксы API-ключей) для защиты от случайной
    утечки личных данных автора при добавлении нового контента.

### Upgrade scenario

- **Новые VIP-клиенты** — получают все расширенные шаблоны автоматически.
- **Уже установленные VIP-клиенты с 5-6 агентами** — R0 при повторном
  запуске увидит что агенты есть, предложит «Перезаписать начисто
  (потеря MEMORY.md)» или «Дополнить недостающих». Для текущих wave-5
  клиентов расширение уже стоящих агентов (добавление SOUL+LEARNING
  без потери MEMORY) требует флага `--refresh-templates` — он придёт
  в wave 7, если будет запрос.
- **Standard-клиенты** (3 агента: tech/marketer/producer) — никаких
  изменений, базовый набор как раньше. Расширения только для VIP.

### Что это даёт клиенту

- **Онбординг при первом контакте**: агент не пишет «обобщённо
  про эксперта», а задаёт короткие вопросы и записывает ответы
  в USER.md. Первая же задача решается с контекстом.
- **Предзаполненный опыт**: LEARNING.md с 5 правилами на роль — агент
  уже «знает» что не делать (типовые грабли копирайтера, дизайнера,
  координатора). Меньше итераций правок.
- **Готовые инструменты**: skills/ дают агенту чёткую инструкцию
  «если задача X — применяй фреймворк Y». Плюс возможность
  апгрейднуть до полной версии через `clawhub install <skill>`.

### MIT-attribution

Все импортированные скиллы — MIT. Оригинальный репозиторий:
[github.com/VoltAgent/awesome-openclaw-skills](https://github.com/VoltAgent/awesome-openclaw-skills)
/ каталог [clawskills.sh](https://clawskills.sh). Список авторов и
оригинальных ссылок — в `templates/LICENSE-skills.md`.

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
