# 🎓 Шпаргалка куратора — OpenClaw Agents Pack

> Единый документ для куратора курса (AI-агента или живого человека).
> Здесь — всё что нужно знать чтобы быстро ответить клиенту по установке,
> обновлению, типичным проблемам.
>
> 🔗 Прямая ссылка на этот документ:
> [github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/docs/curator-cheatsheet.md](https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/docs/curator-cheatsheet.md)
>
> 📅 Актуально для: **v2026.04.28** (wave 8.4)
> Если клиент на старой версии — `--refresh-templates` обновит без потери MEMORY.

---

## 🎯 Главный принцип

**Не лечи клиента, не разобравшись.** Сначала спроси:
1. Какая ОС? (macOS / Linux / Windows)
2. На какой стадии застрял? (OpenClaw / агенты / отдельный шаг)
3. Что говорит установщик? (точный текст ошибки)

Без этих 3 ответов — **не давай команд**. Это правило #4 из Windows
success kit и оно валидно для всех.

---

## 🗺 Карта документации

| Документ | О чём | Когда давать клиенту |
|---|---|---|
| `README.md` | Общий обзор + флаги | Первое знакомство, «что вообще такое» |
| `docs/vip-install-guide.md` | VIP пошагово (6 агентов) | Клиент купил VIP, ставит впервые |
| `docs/windows-install-guide.md` | Windows-путь + 7 правил | Любой Windows-клиент **обязательно** |
| `docs/openai-key-setup.md` | OpenAI ключ + карты РФ | Шаг embedding, проблема с картой |
| `docs/group-mode.md` | Команда агентов в TG-группе | Клиент хочет «общий чат команды AI» |
| `docs/workbook-source.md` | Source для печатного workbook | Передаётся продюсеру для вёрстки |
| `docs/openclaw-telegram-sales-bot-plan.md` | План sales-бота | Не для клиента, это план Антона |
| `CHANGELOG.md` | История обновлений | Если клиент спрашивает «что нового» |

GitHub-источник: [github.com/tonytrue92-beep/openclaw-agents-pack](https://github.com/tonytrue92-beep/openclaw-agents-pack)

---

## ⚡ Команды-памятка (для копирования)

### Установка с нуля

```bash
# 1. OpenClaw (движок) — Mac/Linux:
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh)

# Windows: скачать .exe с https://openclaw.ai/download/windows
# (см. docs/windows-install-guide.md)

# 2. AI-команда (этот pack):
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh)
```

### Self-contained bundle (если raw.githubusercontent тупит)

Когда клиент жалуется на `exit=28` / curl-timeout / VPN режет
GitHub raw — давай **bundled-версию**. Один файл, никаких nested
curl. Особенно нужно на VPS / корпоративных сетях.

```bash
bash <(curl -fsSL https://github.com/tonytrue92-beep/openclaw-agents-pack/releases/latest/download/install-agents-bundled.sh)
```

Версия совпадает с последним релизным тегом репозитория. SHA256 —
в файле `install-agents-bundled.sh.sha256` рядом с asset'ом.

### Обновление БЕЗ потери MEMORY

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh) --refresh-templates
```

### Диагностика (ничего не меняет)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh) --diagnose-only
```

### Debug-bundle для саппорта

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh) --collect-debug
```

Файл `~/openclaw-agents-pack-debug-*.zip` — все секреты замаскированы.

### Включить TG-группу для уже установленных

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh) --enable-group-mode -100123456789
```

### Включить embedding неинтерактивно (если есть OPENAI_API_KEY в env)

```bash
OPENAI_API_KEY=sk-... bash <(curl -fsSL .../install-agents.sh) --enable-embedding --install
```

### Проверить версию

```bash
bash <(curl -fsSL .../install-agents.sh) --version
# Ожидаем: OpenClaw Agents Pack v2026.04.28 (хэш-dev)
```

---

## 📋 Что в установщике v2026.04.28

### Основное

- **3 Standard агента**: Технарь 🔧, Маркетолог 📈, Продюсер 🎬
- **6 VIP агентов** (+к Standard): Дизайнер 🎨, Координатор 🧭, Копирайтер ✍️
- **VIP-агенты «умнее»** (wave 6): SOUL.md (характер) + LEARNING.md
  (типовые грабли) + skills/ (готовые фреймворки) + онбординг-протокол
  (5-6 вопросов при первой встрече)

### Шаги установщика по порядку

| Шаг | Что делает | Когда нужен |
|---|---|---|
| Меню | Standard или VIP | Свежая установка |
| **R0** | Анализ что уже стоит | Всегда |
| **R1** | Выбор модели AI | Свежая установка |
| **R1.5** | Embedding-память (opt-in) | Свежая установка |
| **R2** | Telegram bot tokens | Свежая установка |
| **R2.5** | Подтверждение TG ID | Свежая установка |
| **R3** | Очистка старых (если перезапись) | OVERWRITE сценарий |
| **R4** | Создание агентов | Свежая установка / upgrade |
| **R5** | Restart gateway | Свежая установка |
| **R5b** | Опционально: общая TG-группа | После R5, если ≥2 агентов |

---

## 🆘 Типичные сценарии клиентов

### СЦЕНАРИЙ 1: «У меня ничего не работает / только купил VIP»

**Действия куратора:**
1. Уточни ОС
2. Macбук/Linux → дай команды установки с нуля (см. выше)
3. Windows → дай ссылку на `docs/windows-install-guide.md` и **попроси
   обязательно прочитать 7 правил вверху** перед началом
4. Сообщи что **сначала ставится OpenClaw**, потом **второй установщик**
   для агентов — это **2 разные команды**

### СЦЕНАРИЙ 2: «Уже стоит, как обновиться?»

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh) --refresh-templates
```

**Что обновится:** характер агентов (IDENTITY, AGENTS, SOUL, LEARNING, skills).
**Что НЕ тронется:** MEMORY (контекст сессий) + USER (ответы онбординга) + Telegram-привязки.

Бэкап старого автоматически в `~/.openclaw/workspace-<agent>/.backups/<timestamp>/`.

### СЦЕНАРИЙ 3: «У меня российская карта, OpenAI её не принимает»

**Это 100%, обхода нет.** Решения:
1. **Виртуальная зарубежная карта** через бот (~10 минут):
   `https://t.me/WantToPayBot?start=w17851188--GUSNM`
2. **Уже есть зарубежная карта** (Казахстан / Армения / Грузия / Турция /
   ОАЭ / EU / US) — используй её
3. **Друг с зарубежной картой** положит $5 на свой OpenAI, выдаст ключ

Полный гайд: `docs/openai-key-setup.md` (раздел «Карты РФ — что делать»).

### СЦЕНАРИЙ 4: «Бот в Telegram молчит после /start»

**НЕ переустанавливай.** По порядку:

```bash
# 1. Проверь что агент есть
openclaw agents list

# 2. Проверь routing
openclaw agents bindings

# 3. Probe канала
openclaw channels status --probe

# 4. Если probe зелёный — смотри логи gateway свежие
openclaw logs --tail 50 --follow
# (Windows: openclaw.cmd logs --tail 50 --follow)

# Параллельно в Telegram пиши боту /start, читай логи.
# Обычно одно из:
# - API-ключ модели исчерпан / неверный
# - Routing rule перепутан (написал боту А, маршрут к Б)
# - DM allowlist блокирует — твой TG ID не в allowFrom
```

См. правило #6 в `docs/windows-install-guide.md`.

### СЦЕНАРИЙ 5: «Установщик ругается на auth-profile»

**Не лечи руками.** Это значит первый установщик не довёл `main` агента
до конца — нет настроенного opencode.ai ключа.

```bash
# Перезапусти первый установщик
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh)

# Доведи до того момента когда main реально создаст профиль
# и заговорит в Telegram.

# Потом запускай второй установщик.
```

См. правило #4 в Windows guide.

### СЦЕНАРИЙ 6: «Скачивание зависает / raw.githubusercontent тупит / exit=28»

Особенно на Windows и VPS. **Не долбим curl-bash по кругу.**

**Сначала — self-contained bundle** (один файл, без nested curl):

```bash
bash <(curl -fsSL https://github.com/tonytrue92-beep/openclaw-agents-pack/releases/latest/download/install-agents-bundled.sh)
```

**Если bundle тоже не качается** — `git clone`:

```bash
git clone https://github.com/tonytrue92-beep/openclaw-agents-pack
cd openclaw-agents-pack
bash scripts/install-agents.sh
```

См. правило #5 в Windows guide и сообщение wave 9 BUG-06 которое
установщик сам печатает при сбое.

### СЦЕНАРИЙ 7: «Хочу чтобы агенты тегали друг друга в общем чате»

Это **group-mode**. Возможно от 2+ агентов. Шаги:

1. У `@BotFather` для **каждого** бота: `/setprivacy → Disable`
2. Создать TG-группу, добавить **всех** ботов как **админов**
3. Узнать chat_id через `@username_to_id_bot`
4. Запустить:
   ```bash
   bash <(curl -fsSL .../install-agents.sh) --enable-group-mode -100123456789
   ```

Полный гайд: `docs/group-mode.md` (с типичными сценариями использования
и проблемами).

### СЦЕНАРИЙ 8: «У меня Windows, что делать?»

**Не PowerShell для bash-скриптов!** Рабочий путь:
1. Установить **Git Bash**: [git-scm.com/download/win](https://git-scm.com/download/win)
2. Установить **OpenClaw нативно**: [openclaw.ai/download/windows](https://openclaw.ai/download/windows)
3. В **PowerShell** настроить main: `openclaw.cmd configure → gateway start → channels status --probe`
4. В **Git Bash** (не PowerShell!) — наш установщик

Полный гайд с 7 правилами: `docs/windows-install-guide.md` —
**обязательно** дать клиенту ссылку перед началом, иначе наступит
на грабли.

### СЦЕНАРИЙ 9: «Embedding-память — что это, нужно ли?»

**Нужно** если клиент будет работать долго (2-3 месяца+).
**Не нужно** если делает разовую задачу или хочет «попробовать».

Объяснение для клиента:
> Без embedding агент при каждом ответе перечитывает свою память
> целиком — через 2-3 месяца это 50+ КБ контекста, бот думает
> по 5-7 секунд и стоит ощутимо дороже.
>
> С embedding ищет в памяти семантически — находит «ты говорил
> про лендинг неделю назад» даже если сейчас спрашиваешь иначе.
>
> Стоимость ≈$0.20/месяц на одного клиента. $5 на OpenAI = 2 года.
>
> Можно включить сейчас или позже — `--enable-embedding` (не теряет
> MEMORY).

### СЦЕНАРИЙ 10: «У меня ноут И VPS, можно ли всё на двух?»

Да. На обоих:
- Один и тот же VIP-токен
- Один и тот же Telegram-аккаунт
- Установщик выполняется отдельно на каждой машине

Каждая инсталляция — независимая со своей MEMORY. Если хочешь чтобы
память была общая — wave 9 фича (пока её нет).

### СЦЕНАРИЙ 11: «Хочу удалить одного агента»

```bash
openclaw agents delete <имя-агента> --yes
openclaw channels remove --channel telegram --account <имя> --yes
rm -rf ~/.openclaw/workspace-<имя>
```

(На Windows: `openclaw.cmd ...`, `Remove-Item -Recurse -Force` для папки.)

### СЦЕНАРИЙ 12: «Поменялся VIP-токен / TG-аккаунт»

Эскалация **на Антона**. Это требует обновления привязки на сервере
`@AITeamVIPBot`.

---

## 🚨 Что **не делать** куратору

- ❌ **Не давай руками править `~/.openclaw/openclaw.json`** — клиент
  ушатает конфиг. Используй только `openclaw config set <key> <value>`.
- ❌ **Не предлагай создавать `auth-profiles.json` руками** — см. правило #4.
- ❌ **Не советуй «снеси всё и поставь заново»** при любой проблеме —
  клиент потеряет MEMORY. Сначала:
  - `--diagnose-only`
  - `--collect-debug` → пришли в саппорт
  - `--refresh-templates` (если речь про устаревшие шаблоны)
- ❌ **Не давай команды для PowerShell клиенту с macOS/Linux** и
  наоборот.
- ❌ **Не делись чужими/общими OpenAI-ключами** в чате клиентов —
  это нарушение TOS OpenAI и риск массового бана.

---

## 🚨 Эскалация на технаря (вне нашей зоны)

Эти классы багов **НЕ** в зоне `openclaw-agents-pack` — это
`openclaw-factory` (первый установщик) или OpenClaw core.
Если клиент жалуется на симптомы из таблицы — отправляй технарю
**сразу**, не пытайся лечить через наш установщик.

| Симптом клиента | Класс бага | Куда эскалировать |
|---|---|---|
| `existing config is missing gateway.mode` | BUG-02 | openclaw-factory / OpenClaw core |
| `gateway closed (1006 abnormal closure)` | BUG-02 | openclaw-factory / OpenClaw core |
| `Cannot find package 'openclaw' ... plugin-runtime-deps` | BUG-02 | openclaw-factory / OpenClaw core |
| `memory-core: Error: Cannot find module 'typebox'` | BUG-02 | openclaw-factory / OpenClaw core |
| `HTTP 401: Invalid API key` (после смены модели) | BUG-04 | OpenClaw core |
| `Model is disabled` / `opencode:default` залипание | BUG-04 | OpenClaw core |
| `Missing API key` после `openclaw configure` | BUG-04 | OpenClaw core |
| `make check` / `bash has no bottle` (старый macOS) | BUG-07 | openclaw-factory bootstrap |
| `EACCES: permission denied` / root-owned `~/.npm` | BUG-07 | openclaw-factory bootstrap |
| Sudo password «не вводится» (новичок на macOS) | BUG-07 | objaснить что в терминале пароль невидимый, не баг |
| Xcode CLT не подхватились после установки | BUG-07 | openclaw-factory bootstrap |

**Полный техотчёт** (для технаря, не для клиента):
`/Users/antonpolakov/openclaw-factory/agents/curator/tmp/openclaw-install-fix-report-2026-04-26.md`

**Когда НЕ эскалировать:** если симптом из BUG-01/03/05/06 (наша
зона — обработано в wave 9 v2026.04.29+). Это:
- Установщик висит в R0 / не находит `bash`/`python3`/`curl`
- `auth-profile` валидация / пустой/битый JSON `main`
- `exit=28` / curl-timeout на raw.githubusercontent
- Бот отвечает в `gateway status running`, но молчит в Telegram
  после R5 self-test

Для них кури сценарии 1-12 выше — там есть готовые ответы.

---

## 🔗 Эскалация (если ничего не помогает)

1. Попроси клиента запустить:
   ```bash
   bash <(curl -fsSL .../install-agents.sh) --collect-debug
   ```
2. Файл `~/openclaw-agents-pack-debug-*.zip` — пусть пришлёт куратору
   или в саппорт-чат
3. Все секреты замаскированы (sk-/токены/Bearer)
4. Если bundle не помогает — **эскалация на Антона** с описанием:
   - Что клиент пытается сделать
   - Какие шаги уже сделаны
   - Точный текст ошибки
   - ОС / версия `--version`

---

## 📅 История версий (последние)

| Версия | Дата | Что нового |
|---|---|---|
| **v2026.04.28** | 2026-04-27 | wave 8.4 — РФ-карта warning + бот-ссылка прямо в R1.5 |
| v2026.04.27 | 2026-04-26 | wave 8.3 — Windows + 7 правил из success kit |
| v2026.04.26 | 2026-04-25 | wave 8.2 — ref-ссылка `@WantToPayBot` |
| v2026.04.26 | 2026-04-25 | wave 8.1 — гайд «где взять OpenAI ключ» |
| v2026.04.25 | 2026-04-25 | wave 8 — embedding + multi-agent group-mode |
| v2026.04.23 | 2026-04-23 | wave 7 — `--refresh-templates` |
| v2026.04.23 | 2026-04-22 | wave 6 — VIP агенты с SOUL/LEARNING/skills |
| v2026.04.19 | 2026-04-22 | wave 5 — добавлен Копирайтер ✍️ |

Полная история: [`CHANGELOG.md`](../CHANGELOG.md).

---

## 🤖 Если ты — AI-куратор-агент

При первом контакте с клиентом:
1. **Спроси ОС** (Mac/Linux/Windows) — без этого нельзя дать команды
2. **Спроси что уже стоит** (`openclaw --version`, есть ли агенты)
3. **Уточни на каком шаге проблема** (не общее «не работает»)

Имей под рукой следующие ссылки чтобы давать клиенту:

```
README:        https://github.com/tonytrue92-beep/openclaw-agents-pack
VIP guide:     https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/docs/vip-install-guide.md
Windows guide: https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/docs/windows-install-guide.md
OpenAI ключ:   https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/docs/openai-key-setup.md
Group-mode:    https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/docs/group-mode.md
Changelog:     https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/CHANGELOG.md
```

**Перед любой выдачей команды** — сверься с этой шпаргалкой. Если
ситуация не описана — эскалируй на Антона.

**После решения** — попроси клиента подтвердить что заработало (например,
бот ответил в Telegram). Без подтверждения — задача не закрыта.

---

🔗 **Шпаргалка обновляется** — всегда смотри последнюю версию по
[прямой ссылке на GitHub](https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/docs/curator-cheatsheet.md).
