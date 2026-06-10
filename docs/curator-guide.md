# 🎓 Мастер-инструкция нейрокуратора — установка OpenClaw (AI TEAM)

> **Это единый, самодостаточный контекст для куратора** (AI-агента на базе
> OpenClaw или живого человека), который ведёт клиентов через установку.
> Здесь всё: какие у нас продукты, какие команды давать, что входит,
> какие модели, и — главное — **все известные ошибки и готовые фиксы**.
>
> 📅 **Актуально на 2026-06-10.** Текущие версии установщиков:
> - Платный движок (`openclaw-factory`): **v2026.06.10**
> - Платные агенты (`openclaw-agents-pack`): **v2026.06.10**
> - Тест-драйв (`openclaw-test-drive`): **v2026.06.09**
>
> Если что-то в этой инструкции расходится с поведением установщика —
> верь установщику и эскалируй Антону, чтобы обновить документ.

---

## 0. Главный принцип куратора

**Не лечи клиента, пока не понял ситуацию.** Перед любой командой выясни:

1. **Какой продукт у клиента?** (тест-драйв по TRY-токену / платный Base /
   платный Pro / только движок). Токен подскажет: `TRY-…` → тест-драйв,
   `STD-…` → Base, `VIP-…` → Pro, `SUB-…` → подписка (только движок).
2. **Какая ОС?** (macOS / Linux-VPS / Windows). Команды и подводные камни
   отличаются.
3. **На каком шаге застрял?** (движок / мозги-модель / Telegram-бот /
   создание агентов / бот молчит). Не лечи «вообще не работает».
4. **Точный текст ошибки** — дословно, не пересказ.

Без этих 4 ответов **команды не давай.** Это правило №1.

---

## 1. Наши продукты — три трека установки

У клиента всегда **сначала ставится движок OpenClaw**, потом (если тариф
платный с агентами) — **второй установщик** ставит AI-команду. Это **две
разные команды**. Куратор обязан это проговорить, иначе клиент путается.

| Трек | Репо | Кто получает | Что ставит |
|---|---|---|---|
| **Тест-драйв** | `openclaw-test-drive` | Оплатил пробный доступ (TRY-токен после оплаты на Prodamus) | Движок + 1 агент на бесплатной модели, минимум вопросов |
| **Платный движок** | `openclaw-factory` | Любой платный клиент (Base/Pro/подписка) — это **шаг 1** | OpenClaw движок + main-агент + Telegram |
| **Платные агенты** | `openclaw-agents-pack` | Base / Pro — это **шаг 2** поверх движка | 3 агента (Base) или **8 агентов + база знаний** (Pro) |

### Чем тест-драйв отличается от платного

- Тест-драйв = **«тупо далее-далее»**: модель захардкожена
  (`opencode-go/deepseek-v4-flash`, бесплатно), меню выбора нет,
  минимум трения для не-технического клиента. В финале **открывается
  сайт-продажник** (serditov.tonytrue.pro) — это апселл в платный продукт.
- Платный = полный контроль: выбор тарифа (Base/Pro), 8 агентов, база
  знаний, выбор модели, embedding-память.

---

## 2. Команды по трекам (для копирования)

### A. Тест-драйв (по TRY-токену)

Токен клиент получает **от бота после оплаты**. Без токена установщик не
запустится (это by design).

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-test-drive/main/scripts/install-trial.sh) --token TRY-XXXXXXXX
```

- Спросит **один** opencode.ai API-ключ (бесплатный, **карта не нужна**) —
  он нужен даже для бесплатной модели.
- Модель ставится автоматически: `opencode-go/deepseek-v4-flash`.
- Удаление: тот же скрипт с флагом `--uninstall`.

### B. Платный — ОДНА команда (тариф из токена решает) ⭐

С `2026.06.06` платный клиент запускает **одну** команду (factory). Что
поставится — решает тариф в токене: **SUB** → только движок; **STD** →
движок + 3 агента; **VIP** → движок + 8 агентов + база знаний. Агенты
доустанавливаются автоматически **в той же сессии** — отдельного второго
шага больше нет (и `command not found` между шагами исчез).

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh) --course-token <ТОКЕН>
```

- Без `--course-token` — сначала демо/меню, токен спросит при установке.
- `--vps` / `--headless` — для Linux-сервера (без Homebrew/браузера, автофикс bonjour, см. §6).
- `--engine-only` — поставить **только движок** (отладка / переустановка).

### C. Доустановка / обслуживание агентов (обычно НЕ нужно)

Если движок уже стоит, а агентов надо доустановить/обновить **вручную**
(напр. автодокачка сорвалась по сети) — bundled-релиз; токен подхватится
из кэша `~/.openclaw/course-token`, набор — по тарифу:

```bash
bash <(curl -fsSL https://github.com/tonytrue92-beep/openclaw-agents-pack/releases/latest/download/install-agents-bundled.sh)
```

### D. Windows-интерфейс (Companion GUI)

В финале установки Windows-клиенту (Git Bash / WSL) предлагается официальный
**OpenClaw Windows Hub** — трей, командный центр, диагностика, без терминала.
Страница загрузки: `https://docs.openclaw.ai/platforms/windows`. Опционально;
gateway — наш стандартный. Если клиент спрашивает «что это» — удобная
альтернатива терминалу, ставится отдельным `.exe`.

Полезные флаги обслуживания (raw-версия `…/main/scripts/install-agents.sh`):

```bash
# Обновить агентов БЕЗ потери памяти/онбординга:
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh) --refresh-templates

# Диагностика (ничего не меняет):
bash <(curl -fsSL .../install-agents.sh) --diagnose-only

# Debug-bundle для саппорта (секреты замаскированы):
bash <(curl -fsSL .../install-agents.sh) --collect-debug

# Проверить версию:
bash <(curl -fsSL .../install-agents.sh) --version
```

> ⚠️ **Доставка agents-pack идёт через `releases/latest`**, а релиз
> появляется только после git-тега. Если клиент жалуется «новых агентов
> нет» сразу после апдейта — у CDN бывает лаг 1-2 минуты. Если дольше —
> возможно не выпущен тег: эскалируй Антону.

---

## 3. Что входит в платные тарифы

### Base (STD-токен) — 3 агента
- 🔧 **Технарь** — техника, интеграции, настройка
- 📈 **Маркетолог** — стратегия, трафик, воронки
- 🎬 **Продюсер** — запуски, упаковка, продукт

### Pro (VIP-токен) — **8 агентов** (3 выше + 5)
- 🎨 **Дизайнер** — визуал, картинки, палитры
- 🧭 **Координатор** — оркестрация команды агентов
- ✍️ **Копирайтер** — тексты, посты, сценарии
- 💰 **Лидоруб** — продажи: закрытие заявок, ответы клиентам, переписка
  (готовность к интеграциям с CRM/чат-платформами — подключается позже)
- 🎥 **Контент-агент** — картинки + видео (Hugging Face / Hyperframes) +
  озвучка (ElevenLabs) + сведение ролика (живая генерация — позже,
  пока навыки + готовность)

> На Pro-установке клиент **выбирает, сколько и каких** агентов поставить
> (нумерованный список; ввод номеров «1 2 7» или Enter — все 8). Сколько
> агентов выбрал — столько Telegram-токенов и попросит. Меньше агентов =
> меньше ботов = ниже флуд-риск (см. §4 «флуд-блок»: всё равно создавать
> **партиями по 2-3 с паузой**).

### База знаний (только Pro) — 11 выжимок
На Pro ставится **общая база знаний** (knowledge base) — 11 заметок по
продажам/воронкам/прогреву/офферам и т.д. Агенты ищут по ней через
семантический поиск (`memory_search`). Клиенту объяснять так: «твои агенты
знают методологию курса и подтягивают её, когда отвечают». Технически: KB
качается в `~/.openclaw/knowledge`, индексируется, подключается через
`agents.defaults.memorySearch.extraPaths`.

---

## 4. Мозги (AI-модель) — что у клиента и как

### По умолчанию — бесплатная модель, без карты
Все наши установщики ставят **бесплатную модель opencode.ai**:
- factory / Base / Pro: `opencode-go/deepseek-v4-flash`
- тест-драйв: `opencode-go/deepseek-v4-flash`

Нужен **бесплатный API-ключ opencode.ai** (формат `sk-…`, **карта не
нужна**). Регистрация на https://opencode.ai → создать ключ. Ключ пишется
в `~/.openclaw/agents/main/agent/auth-profiles.json` (chmod 600), профиль
`opencode:default`. Это рабочее состояние — **бот уже отвечает**.

### Codex (ChatGPT) — опциональный апгрейд на умную модель
Если клиент хочет более умные мозги (GPT-5.x через аккаунт ChatGPT) —
**одна команда** (хелпер ставится установщиком в `~/.openclaw/bin/`):

```bash
openclaw-add-codex
```
Сам ставит Codex-плагин, перезапускает gateway, логинит в ChatGPT и ставит
модель `openai/gpt-5.5`. `openclaw-add-codex --device-code` — если браузер не открылся.

> ⚠️ **Важные нюансы (OpenClaw 2026.6.x — объясняй клиенту честно):**
> - Вход в ChatGPT теперь через provider **`openai`**, а `openai-codex` —
>   **legacy-имя** (отсюда `No provider plugins found`). Хелпер это уже учитывает.
> - Это **апгрейд, не обязательный шаг.** Бесплатная модель уже работает —
>   если с Codex возня, спокойно остаёмся на бесплатной. Не блокер.
> - Codex берёт **все** агенты на ChatGPT-аккаунт клиента. Откат на бесплатную:
>   `openclaw-switch-model opencode-go/deepseek-v4-flash`.

### Сменить модель вручную
```bash
openclaw models list --all
openclaw config set agents.defaults.model.primary <провайдер/модель>
openclaw gateway restart
```

---

## 5. 🔴 Известные ошибки и готовые фиксы

> Порядок — от самых частых/свежих к редким. Сначала спроси ОС и точный
> текст, потом давай команду.

### 5.1. `openclaw: command not found` сразу после установки ⭐ ЧАСТОЕ
**Симптом:** установка прошла (бот отвечает, gateway работает), но в
терминале `openclaw …` → `command not found`. Чаще на bash.

**Причина:** `openclaw` стоит под **nvm**, а PATH в **текущем** окне
терминала не обновился. Установка НЕ сломана — gateway это launchd/systemd
сервис, он работает независимо.

**Фикс (немедленно, в текущем окне):**
```bash
export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"; openclaw doctor --fix
```
**Или проще:** открыть **новое окно терминала** — там `openclaw` уже есть.
**Или:** `source ~/.zshrc` (zsh) / `source ~/.bash_profile` (bash).

> С factory v2026.06.04.1 установщик в финале сам прописывает nvm в профили
> и показывает эту подсказку. На более старых — давай команду выше.

### 5.2. Codex/ChatGPT: `No provider plugins found` при подключении мозгов ⭐ СВЕЖЕЕ
**Симптом:** `openclaw models auth login --provider openai-codex` →
`Error: No provider plugins found`.

**Причина (важно, OpenClaw 2026.6.x):** `openai-codex` — **legacy-имя**.
Во-первых, нужен установленный Codex-плагин; во-вторых, вход теперь через
provider **`openai`** (не `openai-codex`).

**Самый простой фикс — наш хелпер (одна команда):**
```bash
openclaw-add-codex
```
(ставится установщиком в `~/.openclaw/bin/`; делает всё сам — плагин, рестарт,
вход через `openai`, модель `openai/gpt-5.5`. Флаг `--device-code` если браузер не открылся.)

**Если хелпера нет / руками:**
```bash
openclaw plugins install clawhub:@openclaw/codex   # или: @openclaw/codex
openclaw plugins enable codex && openclaw plugins registry --refresh
openclaw gateway restart
openclaw models auth login --provider openai        # НЕ openai-codex! (+ --device-code при нужде)
openclaw models set openai/gpt-5.5 && openclaw gateway restart
```
И помни: бесплатная модель уже работает, Codex — **опциональный** апгрейд.

### 5.3. Telegram блокирует создание ботов («флуд») ⭐ ВАЖНО для Pro
**Симптом:** клиент быстро создаёт у @BotFather много ботов подряд →
Telegram выдаёт ограничение, новые боты не создаются ~сутки.

**Профилактика (говори ДО создания токенов):** на Pro нужно 8 ботов —
создавать **партиями по 2-3 с паузой** между партиями, не все подряд.

**Если уже поймал блок:** подождать (обычно до суток), потом доделать
оставшихся ботов партиями. Установщик можно прервать и продолжить позже
(`--refresh-templates` / повторный запуск довносит недостающих).

### 5.4. Российская карта не проходит в OpenAI (для embedding-памяти)
**Симптом:** на шаге embedding (Pro) нужен OpenAI-ключ, но карта РФ не
принимается. **Обхода нет — это политика OpenAI.** Решения:
1. Виртуальная зарубежная карта через бот (~10 мин):
   `https://t.me/WantToPayBot?start=w17851188--GUSNM`
2. Уже есть зарубежная карта (KZ/AM/GE/TR/AE/EU/US) — использовать её.
3. Друг с зарубежной картой кладёт $5 на свой OpenAI, выдаёт ключ.

Embedding **опционален** — без него агенты работают, просто память
перечитывается целиком. Подробно: `docs/openai-key-setup.md`.

### 5.5. Бот в Telegram молчит после /start
**НЕ переустанавливай.** По порядку:
```bash
openclaw agents list                 # агент есть?
openclaw agents bindings             # привязка к каналу?
openclaw channels status --probe     # канал жив?
openclaw logs --tail 50 --follow     # смотри логи, параллельно пиши боту /start
```
Частые причины:
- **Pairing/allowlist:** твой Telegram ID не в allowFrom. Узнать ID —
  написать `/start` боту [@userinfobot](https://t.me/userinfobot). Фикс:
  ```bash
  openclaw config set channels.telegram.dmPolicy allowlist
  openclaw config set channels.telegram.allowlistAllowFrom '["123456789"]'
  openclaw gateway restart
  ```
  Либо одобрить pairing-код: `openclaw pairing approve telegram <КОД>`.
- API-ключ модели исчерпан/неверный.
- Routing перепутан (написал боту А — маршрут к Б).

### 5.6. VPS: gateway циклически рестартится, бот молчит (`bonjour`)
**Симптом:** на VPS gateway падает каждые ~45 сек, в логах
`CIAO PROBING CANCELLED`. **Причина:** плагин `bonjour` (mDNS) не работает
без локальной сети.
```bash
openclaw config set plugins.entries.bonjour.enabled false
openclaw gateway restart
```
> На factory это делается автоматически при запуске с `--vps`.

### 5.7. `npm error network ETIMEDOUT` при установке движка
Встроены 3 ретрая. Если упало всё равно — провайдер/VPN/DNS режет npm:
```bash
curl -I https://registry.npmjs.org/openclaw      # проверить доступ
npm config set registry https://registry.npmjs.org/
npm install -g openclaw@latest
```
Если регион блокирует — VPN или DNS `1.1.1.1`.

### 5.8. Скачивание зависает / `exit=28` / `curl: (56) … 504` / raw тупит
**Не долби curl по кругу.** Для agents-pack — bundled (один файл):
```bash
bash <(curl -fsSL https://github.com/tonytrue92-beep/openclaw-agents-pack/releases/latest/download/install-agents-bundled.sh)
```
**Если именно `504` на `releases/latest/download/…`** — это сбой гитхабовского
редиректа `/latest/`. Дай **прямую ссылку по тегу** (обходит редирект):
```bash
bash <(curl -fsSL https://github.com/tonytrue92-beep/openclaw-agents-pack/releases/download/v2026.06.10/install-agents-bundled.sh)
# ↑ подставь ПОСЛЕДНИЙ тег со страницы Releases — пример может протухнуть
```
Если и так не качается — `git clone`:
```bash
git clone https://github.com/tonytrue92-beep/openclaw-agents-pack && bash openclaw-agents-pack/scripts/install-agents.sh
```
> Объединённый установщик (factory) с `2026.06.06.1` **сам** пробует
> latest → прямой тег → git clone, так что у платных это автоматом.

### 5.9. `openclaw onboard` виснет / зацикливается
Мы onboard **не используем** (известный баг визарда). Если клиент сам
запустил и застрял: **Ctrl+C**, дальше настройка через CLI
(`openclaw channels add … / agents add / agents bind / gateway restart`).

### 5.10. `command not found: $` при копировании
Клиент скопировал prompt-значок `$`. Команды копировать **без** `$`.

### 5.11. Context overflow / агент тормозит, сессия раздулась
```bash
openclaw sessions cleanup --agent <имя>     # один
openclaw sessions cleanup --all-agents      # все
openclaw gateway restart
```

### 5.12. `Config validation failed: agents: Invalid input` (embedding)
**Это была наша внутренняя бага — исправлена в v2026.06.02+.** Если
клиент видит её на свежей установке Pro — у него старая версия:
переустанови agents-pack из `releases/latest` (bundled). Сообщи Антону.

### 5.13a. `Unknown model: opencode/minimax-m2.5-free` ⭐ НОВОЕ (2026-06-10)
**Причина:** OpenClaw обновился — провайдер переименован `opencode` → **`opencode-go`**,
старые модели (`opencode/minimax-m2.5-free`, `opencode/deepseek-v4-flash-free`)
больше не существуют. Бьёт и старые установки после апдейта движка.
**Фикс (одной командой):**
```bash
openclaw-switch-model opencode-go/deepseek-v4-flash
```
Если ключ opencode не подхватился (401) — перевыпустить профиль:
`openclaw-factory-reauth` (тот же ключ с opencode.ai подойдёт). Альтернатива —
умные мозги OpenAI: `openclaw models auth login --provider openai` (бесплатный
ChatGPT-аккаунт; актуальная линия Антона).

### 5.13b. agents-pack падает на R1.5 (embedding) ⭐ топ-краш 2026-06-10
**Причина:** «умная память» требует OpenAI-ключ с billing (зарубежная карта).
С `2026.06.10.3` дефолт R1.5 = **без памяти** (Enter), а ошибки embedding не
валят установку. Старым клиентам: `--install --no-embedding`. Включить позже:
`--enable-embedding`.

### 5.13c. «Disable N unavailable skills?» → No → Setup cancelled
**Причина:** интерактивный вопрос openclaw при битом конфиге; ответ No отменял
установку. С `2026.06.10.3` установщик превентивно гоняет `openclaw doctor
--fix --yes`. Старым клиентам: выполнить это руками и перезапустить установщик.

### 5.13d. Windows/WSL — выжимка саппорта
- `bash <(curl …)` в **PowerShell** не работает (символ `<`) → WSL/Ubuntu или Git Bash.
- Gateway в WSL требует **systemd**: в `/etc/wsl.conf` → `[boot]\nsystemd=true`,
  затем `wsl --shutdown`; проверка `ps -p 1 -o comm=` = systemd.
- Если после фиксов PID 1 всё равно `init` (старый Windows) — не мучить, **вести на VPS**.
- Пропал интернет после `wsl --install`: `ipconfig /flushdns`, `netsh winsock reset`,
  `netsh int ip reset`, перезагрузка.

### 5.13. Конфиг-ошибки: `Unrecognized key` / `plugin not found`
```bash
openclaw doctor --fix --yes
openclaw config validate
```
Руками `~/.openclaw/openclaw.json` **не правим** до `doctor --fix`.

---

## 6. Команды на каждый день
```bash
openclaw status --all              # полный статус
openclaw gateway status            # статус шлюза (running + RPC probe ok)
openclaw gateway restart           # перезапуск
openclaw logs --tail 50 --follow   # логи
openclaw channels status --probe   # проверка каналов
openclaw doctor --fix              # автопочинка
openclaw agents list               # агенты
openclaw models list --all         # модели
openclaw --version                 # версия движка
```
> На Windows — `openclaw.cmd …`. Если `command not found` — см. §5.1.

---

## 7. Структура файлов (где что лежит)
```
~/.openclaw/
├── openclaw.json                       # основной конфиг (JSON5)
├── agents/<имя>/agent/auth-profiles.json  # API-ключи (chmod 600)
├── agents/<имя>/sessions/              # диалоги
├── knowledge/                          # база знаний Pro (KB)
├── logs/                               # логи gateway
└── workspace-<имя>/                    # рабочая папка агента (MEMORY, USER)
```
Ключевые поля конфига: `agents.defaults.model.primary` (модель),
`channels.telegram.dmPolicy` (`pairing`/`allowlist`/`open`),
`channels.telegram.allowlistAllowFrom` (массив ID — **строками**),
`agents.defaults.memorySearch.extraPaths` (база знаний).

---

## 8. Обновление и важное про память
`--refresh-templates` обновляет **характер** агентов (IDENTITY/AGENTS/SOUL/
LEARNING/skills), но **НЕ трогает** MEMORY (контекст сессий), USER (ответы
онбординга) и Telegram-привязки. Старое бэкапится в
`~/.openclaw/workspace-<agent>/.backups/<timestamp>/`.

Движок и Hermes установщики **всегда тянут последнюю версию**
(`openclaw@latest`, официальный installer Hermes) — у клиента всегда
свежак, отдельных действий не требуется.

---

## 9. Эскалация

### На технаря (вне нашей зоны — это движок/ядро OpenClaw)
| Симптом | Куда |
|---|---|
| `gateway closed (1006 abnormal closure)`, `missing gateway.mode` | factory / OpenClaw core |
| `Cannot find package 'openclaw'`, `Cannot find module 'typebox'` | factory / OpenClaw core |
| `HTTP 401 Invalid API key` после смены модели, `Model is disabled` | OpenClaw core |
| `EACCES` / root-owned `~/.npm`, Xcode CLT не подхватились | factory bootstrap |

### На Антона
- Сменился токен / Telegram-аккаунт (нужно обновить привязку в `@AITeamVIPBot`).
- Подписка истекла (`expired`) — клиент продлевает на странице курса,
  потом `/start` боту за новым токеном.
- TRY-токены не выдаются после оплаты (бот ещё дорабатывается).
- Любая ситуация, которой нет в этой инструкции.

Перед эскалацией собери debug:
```bash
bash <(curl -fsSL .../install-agents.sh) --collect-debug
```
Файл `~/openclaw-agents-pack-debug-*.zip` (секреты замаскированы) → Антону,
с описанием: что делал клиент, какие шаги, точный текст ошибки, ОС, версия.

---

## 10. Чего куратору делать НЕЛЬЗЯ
- ❌ Давать команды без выяснения ОС/трека/шага/текста ошибки.
- ❌ Советовать `curl … | bash` для интерактивных установщиков (ломает
  ввод) — только `bash <(curl …)`.
- ❌ Советовать `openclaw onboard` (баг зацикливания).
- ❌ Править `~/.openclaw/openclaw.json` руками до `openclaw doctor --fix`.
- ❌ «Снеси всё и поставь заново» при любой проблеме — клиент потеряет
  MEMORY. Сначала `--diagnose-only` / `--collect-debug` / `--refresh-templates`.
- ❌ Команды PowerShell клиенту на macOS/Linux и наоборот.
- ❌ Делиться чужими/общими OpenAI/opencode-ключами в чате (бан-риск, TOS).
- ❌ Обещать клиенту живые CRM-интеграции Лидоруба / живую генерацию видео
  Контент-агента **сейчас** — это готовность, подключается позже. Говори честно.

---

## 11. Стиль общения
- Всегда по-русски, спокойно, на «ты» или «вы» по тону клиента.
- Команды — целиком, готовые к копированию, в блоках кода, **без `$`**.
- Объясняй **почему** возникла ошибка, не только как исправить.
- Перед `restart`/`cleanup`/`config set` — предупреди, что произойдёт.
- Если застрял в интерактивном меню — первый совет всегда **Ctrl+C**,
  дальше CLI.
- Не уверен — скажи прямо, предложи `openclaw logs --follow` /
  `openclaw doctor --fix` или эскалируй.
- **Закрывай задачу подтверждением:** попроси клиента подтвердить, что
  бот ответил в Telegram. Без подтверждения задача не закрыта.

---

## 12. Если ты — AI-куратор-агент: рабочий протокол
1. Поздоровайся, спроси: продукт/токен, ОС, на каком шаге, текст ошибки (§0).
2. Определи трек (§1) и дай **правильную команду** для него (§2).
3. Проговори двухшаговость: сначала движок, потом агенты (для платных).
4. При ошибке — найди её в §5, дай готовый фикс, объясни причину.
5. Не нашёл ситуацию в инструкции — **эскалируй Антону** (§9), не выдумывай.
6. Подтверди результат, поблагодари.

### Ссылки под рукой
```
Движок (factory):   https://github.com/tonytrue92-beep/openclaw-factory
Агенты (pack):      https://github.com/tonytrue92-beep/openclaw-agents-pack
Тест-драйв:         https://github.com/tonytrue92-beep/openclaw-test-drive
Эта инструкция:     https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/docs/curator-guide.md
```

### Карта подробных доков (давать клиенту по ситуации)
| Документ | Когда |
|---|---|
| `docs/mac-install-guide.md` | macOS, не-технический клиент (путь через DMG) |
| `docs/windows-install-guide.md` | любой Windows-клиент (**обязательно**, 7 правил) |
| `docs/vps-install.md` | установка на сервер |
| `docs/openai-key-setup.md` | embedding + карты РФ |
| `docs/group-mode.md` | агенты в общей TG-группе |
| `docs/bot-to-bot-setup.md` | агенты пишут друг другу напрямую |
| `CHANGELOG.md` | «что нового» |

---

🔗 Документ живой — смотри последнюю версию по
[прямой ссылке](https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/docs/curator-guide.md).
Расхождение с реальностью установщика → пиши Антону, обновим.
