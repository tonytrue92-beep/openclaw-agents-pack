# Changelog

История изменений в установщике OpenClaw Agents Pack.

Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/).

---

## 2026-05-28 — Wave 41 (trial: gateway реально запускается — launchctl bootstrap)

### Триггер

Лог Антона показал что wave 40 не сработал: `openclaw gateway install`
вручную выдал «No gateway.mode found» + «Installed LaunchAgent», но
gateway всё равно не запущен.

### Два реальных бага (найдены по логу, не гаданием)

**1. Хрупкий grep ловил «not running».** Условие
`if ! openclaw gateway status | grep -qE "running"` — подстрока
«running» содержится в «not running» → grep=true → `! true`=false →
**install пропускался**. Классический баг частичного совпадения.

**2. `gateway start` не грузит LaunchAgent.** После `gateway install`
openclaw явно подсказывает:
`launchctl bootstrap gui/$UID ~/Library/LaunchAgents/ai.openclaw.gateway.plist`
— а я делал `gateway start`, который этого не делает.

### Fix (по факту, проверено на рабочей машине)

```bash
openclaw config set gateway.mode local        # всегда (Updated gateway.mode)
openclaw gateway install                        # БЕЗУСЛОВНО (идемпотентно)
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/ai.openclaw.gateway.plist
openclaw gateway start
# проверка на НАДЁЖНЫЙ маркер из рабочего status:
gateway status | grep "LaunchAgent (loaded)|RPC probe: ok"
```

Убран хрупкий `grep running`. install теперь безусловный (не за
ложным условием). Добавлен `launchctl bootstrap` (fallback на
`launchctl load`). Проверка на «LaunchAgent (loaded)» — реальный
маркер из рабочего `gateway status`.

Если не поднялось — чёткая инструкция: 2 команды в новом терминале.

### Compatibility

- `TRIAL_VERSION` `2026.05.28.9` → `2026.05.28.10`
- Smoke 6.42 (новый). ShellCheck чистый.

---

## 2026-05-28 — Wave 40 (trial: правильный запуск gateway — бот оживает)

### Триггер

После установки `openclaw` работает (wave 38/39), но бот молчит.
`openclaw` TUI показал корень: **`Gateway: not reachable at
ws://127.0.0.1:18789`** — gateway не запущен.

### Корень проблемы

Trial делал только `openclaw gateway restart || start`. Но на свежей
машине **launchd-сервис gateway ещё не создан** — `restart` нечего
перезапускать, `start` без установленного сервиса не персистит.
Factory делает правильно: `gateway.mode local` → **`gateway install`**
(создаёт launchd-сервис) → `gateway start`.

### Fix — последовательность как factory

```bash
openclaw config set gateway.mode local        # ДО install (иначе 1006)
if ! gateway status | grep running; then
  openclaw gateway install                     # launchd-сервис
  openclaw gateway start
fi
# проверка + recovery (restart если не поднялся)
```

С проверкой статуса + recovery-перезапуском + понятным сообщением
если не поднялось («openclaw gateway install && openclaw gateway start»).

### Compatibility

- `TRIAL_VERSION` `2026.05.28.8` → `2026.05.28.9`
- Это последний известный барьер — после него бот должен отвечать
- Smoke 6.41 (новый). ShellCheck чистый.

---

## 2026-05-28 — Wave 39 (trial: рабочий telegram-бот + openclaw в PATH)

### Триггер

Полный лог установки на чистом маке показал: установка проходит
(OpenClaw 2026.5.27 ставится), НО:
1. `openclaw --version` → «command not found» (даже после wave 38)
2. В логе: `⚠ Не смог записать токен в конфиг` → бот молчит

### 4 реальных бага (все исправлены по образцу factory)

**1. openclaw не в PATH** — wave 38 прописал nvm в rc, но не сделал
`nvm alias default`. В новом терминале nvm загружается, но не
активирует node без default-алиаса. → Добавлен `nvm alias default 22`.

**2. Telegram-токен не записывался** — использовал
`openclaw config set channels.telegram.accounts.assistant.token`
(неправильно). Factory использует `openclaw channels add --channel
telegram --name ... --token ...`. → Заменено.

**3. Бот просил pairing code** — не настроена DM-политика. Без неё
бот отвечает «access not configured» вместо общения. → Добавлены
`config set channels.telegram.dmPolicy allowlist` + `allowFrom`
(запрос TG user ID владельца).

**4. Неправильный bind** — `--bind telegram:assistant` (такого
аккаунта нет). Factory: `--bind telegram`. → Исправлено.

### Added — подсказка про новый терминал

Если `openclaw` не в PATH текущей сессии (rc ещё не перечитан) —
финал показывает: «открой новый терминал или `source ~/.zshrc`».

### Compatibility

- `TRIAL_VERSION` `2026.05.28.7` → `2026.05.28.8`
- Telegram-настройка теперь 1-в-1 как рабочий factory
- Smoke 6.40 (новый, 6 ассертов). ShellCheck чистый.

---

## 2026-05-28 — Wave 38 (trial: persist nvm — openclaw доступен после установки)

### Триггер

Антон: «openclaw сам не устанавливается — какая-то херня накатывается,
а openclaw команду не вызвать в терминале, ничего не сделать».

### Корень проблемы

Trial ставит Node.js через **nvm**, но **не прописывал nvm в shell
rc-файлы**. В рамках trial-сессии node/openclaw доступны (nvm загружен),
но после закрытия терминала nvm не загружается автоматически →
node не в PATH → `openclaw` «команда не найдена». Установка вроде
прошла, а движка «нет».

Factory решает это через `persist_nvm_in_shell_rc` — я его пропустил.

### Fix

Добавлена функция `persist_nvm_in_shell_rc` (1-в-1 как factory) +
вызов после `nvm install 22`. Прописывает в `~/.zshrc`, `~/.bashrc`,
`~/.bash_profile`:

```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
```

Идемпотентно (маркер «AI TEAM 2.0 trial installer» не дублирует блок).
Теперь в **новом** терминале nvm загружается → node + openclaw в PATH.

### Compatibility

- `TRIAL_VERSION` `2026.05.28.6` → `2026.05.28.7`
- Только когда Node ставится через nvm
- Smoke 6.39 (новый). ShellCheck чистый.

---

## 2026-05-28 — Wave 37 (trial подключает модель — агент больше не молчит)

### Триггер

Антон: «ставишь trial-агента, нажимаешь /start — он молчит. Модель
не подключена. Нужно чтобы шёл по шагам как реальный установщик и
подключал мозги (minimax-free от opencode).»

### Корень проблемы

Trial регистрировал агента с `--model minimax`, но **не настраивал
auth** к provider. Без `auth-profiles.json` агент не может обратиться
к модели → молчит. Реальный установщик (factory R3) это делает —
запрашивает opencode API-ключ и пишет auth-profile.

### Changed — T2 теперь «Подключение модели»

Был интерактивный `openclaw onboard` (непредсказуемый). Стал явный
шаг как factory R3:

1. Объяснение: агенту нужна модель, используем **MiniMax Free**
   (бесплатно, карта не нужна)
2. Авто-открытие `https://opencode.ai` в браузере
3. Запрос API-ключа (скрытый ввод, `sk-` проверка, 3 попытки)
4. `openclaw config set agents.defaults.model.primary opencode/minimax-m2.5-free`

### Changed — T4 пишет auth-profile

После `openclaw agents add assistant` создаётся
`~/.openclaw/agents/assistant/agent/auth-profiles.json` (формат 1-в-1
как factory):

```json
{
  "version": 1,
  "profiles": {
    "opencode:default": { "type": "api_key", "provider": "opencode", "key": "..." }
  },
  "lastGood": { "opencode": "opencode:default" }
}
```

chmod 600 + `unset OPENCODE_KEY` после записи (не держим ключ в памяти).

Потом `openclaw gateway restart` — агент поднимается **с моделью и
авторизацией**. Теперь `/start` → агент отвечает.

### Compatibility

- `TRIAL_VERSION` `2026.05.28.5` → `2026.05.28.6`
- Security-audit чистый (ключ — runtime-ввод, не в коде)
- Smoke 6.38 (новый). ShellCheck чистый.

---

## 2026-05-28 — Wave 36 (флаг --uninstall в trial)

### Триггер

Антон: «если я остановил установку на полпути — нужно удалить OpenClaw,
всё что поставилось, чтобы пройти заново с чистого листа».

### Added — флаг `--uninstall` (и алиас `--reset`)

```
bash <(curl -fsSL .../install-trial.sh) --uninstall
```

Что делает (с confirm `[y/N]`):
1. Останавливает gateway (`openclaw gateway stop` + `launchctl unload`)
2. Удаляет агента-ассистента (`openclaw agents delete assistant`)
3. Удаляет движок (`npm uninstall -g openclaw`)
4. Удаляет данные (`rm -rf ~/.openclaw`)

**Не трогает** Node.js и Xcode CLT — они не мешают и ускоряют
повторную установку (не придётся ставить заново).

После — «запусти установку снова чтобы начать с чистого листа».

### Compatibility

- `TRIAL_VERSION` `2026.05.28.4` → `2026.05.28.5`
- Confirm перед удалением (защита от случайного сноса данных)
- Smoke 6.37 (новый). ShellCheck чистый.

---

## 2026-05-28 — Wave 35 (auto-install Xcode CLT в trial)

### Триггер

Прогон на чистом маке (новый юзер, без Xcode): trial запустил nvm,
а nvm использует `git`, которого на свежем маке нет → Apple выбросил
«You may be on a Mac, and need to install the Xcode Command Line
Developer Tools. Run `xcode-select --install`». Пользователь увидел
ошибку и был вынужден делать это вручную.

Антон: «пользователь не должен сталкиваться с ошибками. Если что-то
нужно доустановить — система сама накатывает.»

### Added — авто-установка Command Line Tools

В T1 (до Node.js), только на macOS:

1. Проверка `xcode-select -p` — есть ли CLT
2. Если нет → `xcode-select --install` (открывает Apple-окно)
3. Понятное сообщение: «нажми Установить в окне, жду автоматически»
4. **Wait-loop**: опрос `xcode-select -p` каждые 5 сек, прогресс
   каждые 30 сек, таймаут 15 минут
5. Когда CLT готовы → продолжаем установку Node автоматически

Пользователь видит только: дружелюбное сообщение + один клик
«Установить» в Apple-окне. Никакой криптовой ошибки, скрипт сам
ждёт и продолжает.

### Ограничение Apple

`xcode-select --install` **обязательно** открывает GUI-окно (Apple
не даёт ставить CLT полностью без подтверждения пользователя — это
защита). Мы автоматизируем всё кроме одного клика «Установить»,
и сами ждём результат.

### Compatibility

- `TRIAL_VERSION` `2026.05.28.3` → `2026.05.28.4`
- Только macOS (Linux/VPS CLT не нужны; Windows — свой путь)
- Smoke 6.36 (новый). ShellCheck чистый.

---

## 2026-05-28 — Wave 34 (trial: OpenClaw через npm, как factory)

### Триггер

Антон: «в прошлом установщике (factory) всё это уже было». Верно —
factory ставит OpenClaw через **`npm install -g openclaw@latest`**,
а я в trial ошибочно использовал `brew install --cask openclaw`.

### Проблема brew-cask пути (waves 30-32)

- `brew install --cask` — **macOS-only** формат (.app), не работает
  на Linux/VPS
- Требует **macOS 15 (Sequoia)** — отсюда вся боль на старых маках
  (wave 32 macOS-check был «лечением симптома», а не причины)

### Fix — npm-путь (как factory demo-install.sh)

T1 переписан 1-в-1 по образцу factory:

1. **Node.js**: если нет — ставим через nvm (`nvm install 22`)
2. **OpenClaw**: `npm install -g openclaw@latest` + retry-конфиг
   (fetch-retries 5, таймауты) для плохой сети
3. EACCES-обработка (подсказка про sudo / npm prefix)

### Что это решает

| Платформа | brew-cask (было) | npm (стало) |
|---|---|---|
| macOS 15+ | ✅ | ✅ |
| **macOS < 15** | ❌ требует Sequoia | ✅ **работает** |
| **Linux / VPS** | ❌ cask macOS-only | ✅ **работает** |
| Windows (с Node) | ❌ | ✅ работает |

**npm не требует macOS 15** — твой Mac на 13.7 теперь сможет
поставить trial.

### Removed

- `brew install --cask openclaw` (заменён на npm)
- macOS 15+ pre-check (wave 32 — был основан на ложной предпосылке
  brew-cask; npm-путь его не требует)
- Homebrew-установка для trial (не нужна для npm-пути — быстрее)

### Compatibility

- `TRIAL_VERSION` `2026.05.28.2` → `2026.05.28.3`
- Smoke 6.35 переписан под npm-путь (wave 34)
- ShellCheck чистый

---

## 2026-05-28 — Wave 33 (тест-драйв нейминг + Windows-ветка)

### Триггер

Антон: «убрать "бесплатно" из баннера → "тест-драйв версия". И чтобы
trial сам определял платформу — работал на macOS либо Windows.»

### Changed — нейминг «бесплатно» → «тест-драйв»

| Где | Было | Стало |
|---|---|---|
| Баннер | «ДЕМО — БЕСПЛАТНАЯ ВЕРСИЯ» | «ТЕСТ-ДРАЙВ ВЕРСИЯ» |
| Pitch | «Попробуй ... бесплатно» | «Попробуй ... в деле» |
| `--help` | «Бесплатная тестовая установка» | «Тест-драйв: установка» |
| T2-подсказка | «выбирай бесплатную модель» | «выбирай модель minimax» |
| `assistant/IDENTITY.md` | «попробовать бесплатно» | «попробовать в деле» |

Слово «бесплатно» убрано из всех user-facing мест (осталось только
в internal-комментариях кода про модель minimax).

### Added — Windows-ветка (auto-detect платформы)

Trial теперь **определяет платформу** и ведёт себя корректно на обеих:

- **macOS 15+** → ставит OpenClaw через `brew install --cask` (работает)
- **macOS < 15** → понятное сообщение (wave 32)
- **Windows / WSL** → проверяет есть ли `openclaw`/`openclaw.cmd`:
  - стоит → продолжает с агентом
  - нет → направляет на официальный Windows-установщик (graceful
    `exit 0`, не ошибка) с инструкцией «поставь движок → запусти снова»

### Compatibility

- `TRIAL_VERSION` `2026.05.28.1` → `2026.05.28.2`
- macOS-путь не изменился (для 15+)
- Smoke + ShellCheck зелёные

### Что осталось (известное ограничение)

**Linux/VPS-путь** OpenClaw движка — `brew install --cask` это
macOS-only формат (.app). На чистом Linux движок ставится иначе
(нужно уточнить у технаря как именно). Сейчас `--vps` на Linux
дойдёт до установки движка но cask не сработает. Для полноценного
VPS-пути нужен отдельный wave после уточнения Linux-установки.

---

## 2026-05-28 — Wave 32 (macOS 15+ pre-check в trial)

### Триггер

Прогон trial на macOS 13.7 (Ventura): `brew install --cask openclaw`
упал с `Error: This software does not run on macOS versions older
than Sequoia`. Наше сообщение было бесполезным («попробуй ещё раз» —
упадёт снова). OpenClaw **физически требует macOS 15 (Sequoia)+**
(brew cask: `Required: macOS >= 15`).

### Added — pre-check версии macOS

В `install-trial.sh` (T1, до установки) проверка `sw_vers
-productVersion`. Если major < 15 — понятное сообщение **сразу**,
не дожидаясь криптовой brew-ошибки:

```
✗  OpenClaw требует macOS 15 (Sequoia) или новее.
   У тебя сейчас: macOS 13.7

Что можно сделать:
1. Обнови macOS до Sequoia (Системные настройки → Обновление ПО)
2. Или поставь на VPS (Linux-сервер) — там нет этого ограничения
3. Или попробуй на другом, более новом Mac

Это требование самого OpenClaw, не нашего установщика.
Полная версия (6 агентов): https://serditov.tonytrue.pro/
```

### Improved — error-handler brew install

Если pre-check пропустил (edge case) и `brew install --cask openclaw`
всё же упал — ловим вывод, распознаём Sequoia-ошибку, даём понятное
сообщение вместо повтора команды.

### Compatibility

- `TRIAL_VERSION` `2026.05.28` → `2026.05.28.1`
- Не затрагивает машины с macOS 15+ (pre-check молча пропускает)
- Smoke 6.35 (новый). ShellCheck чистый.

### Важно для бизнеса

Клиенты на macOS < 15 (Ventura/Monterey/...) **не смогут** поставить
OpenClaw на сам Mac — это ограничение OpenClaw. Им нужен:
- macOS 15+ (обновить), или
- VPS (Linux — без ограничения версии)

Trial теперь честно об этом говорит вместо непонятного фейла.

---

## 2026-05-28 — Wave 31 (снят bash 4+ барьер — работаем на 3.2)

### Триггер

Антон прогнал установщик на чистой macOS 13 (Intel, bash 3.2.57).
Установщик упал с «нужен bash 4+» → заставил ставить Homebrew +
`brew install bash`, а на старом Intel-маке brew **компилирует bash
из исходников** (ncurses, readline, gettext...) — минуты ожидания
на каждую зависимость. Клиент «захлёбывается» на barrier'е ещё до
реальной установки.

### Корень проблемы

Требование bash 4+ было **избыточной перестраховкой**. Проверка:
весь код `install-agents.sh` / `install-trial.sh` / `lib/*.sh` НЕ
использует bash-4-only фичи (`declare -A`, `mapfile`, `${var^^}`...) —
он намеренно переписан под 3.2 ещё в wave 11. Подтверждено: оба
установщика запускаются на штатном `/bin/bash` 3.2.57 без ошибок.

Factory `demo-install.sh` всё это время работал на 3.2 — а наш
agents-pack искусственно требовал 4+.

### Changed

Логика bash-проверки в обоих установщиках:

**Было**: hard-exit на bash<4 + попытка авто `brew install bash`
(долгая компиляция) + инструкция и `exit 1` если не вышло.

**Стало**: если свежий bash УЖЕ есть в brew-путях → переключаемся
(стабильнее). Если нет → **спокойно работаем на 3.2** (код совместим).
Никакого hard-exit, никакой авто-установки bash.

```bash
if (( BASH_VERSINFO[0] < 4 )); then
  for _newer_bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    [[ -x "$_newer_bash" && "$_newer_bash" != "$BASH" ]] && exec "$_newer_bash" "$0" "$@"
  done
  # не нашли — продолжаем на 3.2
fi
```

### Эффект

- Новый клиент на macOS запускает установщик → он работает **сразу**
  на штатном bash 3.2, без Homebrew/компиляции bash
- Снят главный барьер на входе (особенно для старых Intel-маков)

### Compatibility

- `INSTALLER_VERSION` / `TRIAL_VERSION` `2026.05.26` → `2026.05.28`
- Если bash 4+ есть — используется (как раньше), просто больше не
  требуется
- Проверено: оба установщика `--version` работают на `/bin/bash` 3.2.57
- Smoke + ShellCheck зелёные

---

## 2026-05-26 — Wave 30 (TRIAL/демо установщик — лидген-воронка)

### Триггер

Антон: «нужна отдельная команда-установщик для бесплатной тестовой
установки. Ставит OpenClaw + одного агента-ассистента. Агент через
каждые 2-3 сообщения предлагает полную версию со ссылкой
serditov.tonytrue.pro. Никак не связано с текущим установщиком.»

Цель: дать людям попробовать систему бесплатно → конвертировать
в полную версию.

### Added — отдельный установщик `scripts/install-trial.sh`

**Полностью изолирован** от `install-agents.sh` (не source'ит, не
вызывает). Самодостаточный (все функции inline).

Flow:
1. **T1** — Preflight: Homebrew (ставит если нет) → OpenClaw (`brew
   install --cask openclaw`)
2. **T2** — Онбординг OpenClaw (`openclaw onboard` если gateway не настроен)
3. **T3** — Telegram-бот для ассистента (валидация через getMe)
4. **T4** — Установка одного assistant-агента (`openclaw agents add`),
   модель `minimax-m2.5-free` (бесплатная для демо)

**Без курс-токена** — это бесплатное демо. Banner «ДЕМО — БЕСПЛАТНАЯ
ВЕРСИЯ». Работает на macOS / Linux / VPS (`--vps`). На Windows —
указывает на официальный installer.

### Added — шаблон `templates/assistant/` (5 файлов)

Личный AI-ассистент с **offer-логикой**:
- `IDENTITY.md` / `AGENTS.md` / `SOUL.md` / `USER.md` / `MEMORY.md`
- **Главная механика**: агент каждые 2-3 ответа вставляет в конце
  ненавязчивый оффер на полный курс + ссылку `serditov.tonytrue.pro`
- Польза первична: ответ 1 — без оффера (доверие), 2-3 — первый оффер,
  дальше каждые 2-3 с чередованием формулировок
- Честный: говорит что это демо, не притворяется полной версией
- При раздражении клиента — пауза на офферы

### Security

- `security-audit.sh` Check 6 обновлён: course-offer URL
  `serditov.tonytrue.pro` разрешён в templates/ (публичный
  маркетинговый адрес, не утечка). `serditov` в других контекстах —
  по-прежнему блокируется.

### Tests

- Smoke 6.34 (новый): install-trial.sh + 5 файлов assistant +
  offer-ссылка + offer-ритм + изоляция от install-agents + нет токена
- Docker run-checks: templates/*.md 49 → 54 (+5 assistant)
- ShellCheck чистый
- Все ассерты зелёные

### Команда для клиентов

```
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-trial.sh)
```

### Что НЕ затронуто

- `install-agents.sh` — **не тронут** (полная изоляция)
- Существующие templates/ агентов — не тронуты
- Тарифы Base/Pro/OpenClaw/Hermes — без изменений

---

## 2026-05-26 — Wave 29 (обогащение базовой тройки для Pro)

### Триггер

Сравнили наши шаблоны с живой командой Антона. Выяснилось: базовая
тройка (tech/marketer/producer) — **обеднённая** (только 4 базовых
md-файла), тогда как VIP-тройка (designer/coordinator/copywriter) —
полная (SOUL + LEARNING + skills). Антон: «сделать чтобы у Pro-тарифа
базовые агенты тоже стали нашего уровня».

### Added — обогащение tech/marketer/producer

Каждому из базовой тройки добавлены (по образцу VIP-тройки + контекст
из живых агентов Антона):

| Агент | SOUL.md | LEARNING.md | skills |
|---|---|---|---|
| **tech** | характер инженера, диагностический workflow, guardrails | 5 правил (бэкап до фикса, логи перед гипотезой...) | `diagnostic-checklist`, `safe-rollback` |
| **marketer** | характер маркетолога, воронка, evidence-first | 5 правил (диагноз стадии, не блефуй метрикой...) | `funnel-diagnosis`, `channel-unit-economics` |
| **producer** | характер продюсера, маршруты запуска, экономика | 5 правил (не выдумывай цифры, один маршрут...) | `launch-route-selector`, `product-unit-economics` |

### Дифференциация тарифов

В `scripts/lib/agents.sh` обогащение **гейтится по VIP_MODE**:

```bash
case "$agent_id" in
  designer|coordinator|copywriter)
    has_extras=true ;;                          # VIP-only — всегда
  tech|marketer|producer)
    [[ "${VIP_MODE:-false}" == true ]] && has_extras=true ;;  # Pro — да, Base — нет
esac
```

- **Pro** (VIP-токен) → базовая тройка получает SOUL + LEARNING + skills
- **Base** (STD-токен) → базовая тройка остаётся минимальной (4 файла)

Это разделение тарифов: Pro-клиент получает «прокачанных» базовых
агентов с характером, уроками и навыками; Base — функциональных но
без extras.

### Что НЕ копировалось

`MEMORY.md` живых агентов Антона **не копировался** — там личный
накопленный опыт + данные. Обобщена только **структура качества**
(SOUL/LEARNING/skills), память у клиента стартует чистой под него.

### Compatibility

- `INSTALLER_VERSION` `2026.05.25.6` → `2026.05.26`
- **Base-установки не меняются** — базовая тройка как раньше (4 файла)
- VIP-тройка не затронута
- Smoke 6.4b (новый, проверяет файлы + VIP_MODE-гейт). Все ассерты зелёные.

---

## 2026-05-25 — Wave 28 (auto-detect ОС в баннере)

### Added

Сразу под версией в баннере клиент теперь видит **что детектировано**:

```
   v2026.05.25.6
   🖥  Система определена автоматически: macOS.
      Если ты на VPS / сервере по SSH — перезапусти с флагом --vps.
```

Варианты `_os_label`:
- `macOS`
- `Linux`
- `Windows (WSL)`
- `Windows (Git Bash)`
- `неизвестная ОС` (fallback)

Если запущено с `--vps` — приоритетная плашка остаётся прежней:

```
🌐 VPS-режим: Linux-сервер, headless
```

### Why

До wave 28 клиент **не видел** что установщик понимает его систему.
Auto-detect срабатывал, но индикации не было — на Mac/Linux только
по косвенным признакам (Windows-hints для WSL/Git Bash).

Теперь:
- Клиент **уверен** что система понята правильно
- Знает что есть **флаг `--vps`** на случай сервера (вторая частая
  проблема — клиент сидит на VPS и не знает про флаг)

### Compatibility

- `INSTALLER_VERSION` `2026.05.25.5` → `2026.05.25.6`
- Smoke 6.33 (новый, 3 ассерта). 38/38 PASS
- VPS-режим не затронут

---

## 2026-05-25 — Wave 27 (ANSI 3D-куб intro для Hermes)

### Added

При выборе опции **4) Hermes** в главном меню теперь играет
**3.5-секундная ANSI 3D-куб анимация** — вращающийся цветной куб
с 6 цветными гранями (red/green/yellow/blue/purple/orange) и
белыми ребрами.

Это вау-эффект перед запросом HRM-токена — клиент видит «магию»
до начала установки super-agent'а.

### Реализация

- **Inline Python heredoc** `<<'HERMES_CUBE_EOF'` в bash-функции
  `install_hermes_super_agent`
- Алгоритм портирован 1-в-1 из React-компонента `CubeAnimation`
  (присланного Антоном)
- 80×24 терминал, 30 FPS, ANSI 256-color
- Z-buffer + backface culling + edges всегда сверху
- Hide cursor на время анимации (`\033[?25l`)
- После анимации `clear` → переход к заголовку Hermes

### Graceful fallbacks

- **Нет `python3`** (Windows Git Bash без Python) → анимация
  пропускается, сразу заголовок Hermes
- **`HERMES_NO_INTRO=1`** в env → анимация пропускается (CI /
  non-interactive)
- **Ctrl+C во время анимации** → выход из анимации, cursor
  восстанавливается, переход к Hermes flow

### Compatibility

- `INSTALLER_VERSION` `2026.05.25.4` → `2026.05.25.5`
- Не ломает существующий Hermes-flow (анимация — pre-step)
- Smoke 6.32 (новый, 4 ассерта). 37/37 PASS

---

## 2026-05-25 — Wave 26 (порядок V_MAIN: ladder снизу вверх)

### Changed

Порядок пунктов главного меню изменён на «по нарастающей» — от
самого базового к самому продвинутому:

**Было** (wave 21):
```
1) Pro       — 6 агентов  ← рекомендуется
2) Base      — 3 агента
3) OpenClaw  — только движок
4) Hermes    — super-agent (если OpenClaw обнаружен)
```

**Стало** (wave 26):
```
1) OpenClaw  — только движок
2) Base      — 3 агента
3) Pro       — 6 агентов  ← рекомендуется
4) Hermes    — super-agent (если OpenClaw обнаружен)
```

### Default по Enter

Изменён с **1** (первый пункт) на **3** (Pro) — потому что Pro
остаётся **рекомендуемым** тарифом. Если клиент просто жмёт Enter
не глядя — он попадёт на Pro, как и раньше.

`case "${_main_menu_input:-3}"` вместо `case "${_main_menu_input:-1}"`.

### Why ladder

UX-исследования продуктовых линеек: клиенту легче считать снизу
вверх («что я смотрю по минимуму → что максимум»), особенно когда
он не уверен какой тариф ему нужен. Pro в середине списка визуально
не как «случайный default», а как «золотая середина».

### Compatibility

- `INSTALLER_VERSION` `2026.05.25.3` → `2026.05.25.4`
- Логика выбора tier не изменилась — это просто перестановка пунктов
  + новый default
- Smoke 6.31 (новый, 4 ассерта) + smoke 6.25 расширен под новый
  default. 36/36 PASS.

---

## 2026-05-25 — Wave 25 (Hermes super-agent в главном меню)

### Триггер

Антон попросил: «Если система видит что стоит OpenClaw — в главном
меню должна появиться опция установки супер-агента Hermes (так же
как мы устанавливали его себе — анализируя и сканируя текущую
OpenClaw-систему). Hermes требует отдельный платный токен.»

### Добавлено

#### Детекция OpenClaw

Новая функция `detect_openclaw()` в `install-agents.sh`:
```bash
detect_openclaw() {
  command -v openclaw &>/dev/null && return 0
  [[ -d "$HOME/.openclaw" ]] && return 0
  return 1
}
```

Выставляет переменную `OPENCLAW_INSTALLED=true/false`. Используется
в V_MAIN для условного показа 4-го пункта.

#### 4-й пункт «Hermes» в V_MAIN — условно

Показывается **только если** `OPENCLAW_INSTALLED=true`:

```
   1)  Pro        — 6 агентов (полный набор)  ← рекомендуется
   2)  Base       — 3 базовых агента
   3)  OpenClaw   — только движок (без агентов)
   4)  Hermes     — супер-агент над всей командой  ★
       Анализирует твою OpenClaw-установку и оркестрирует агентов
       Требует отдельный HRM-токен (платный SKU)
```

На свежей машине без OpenClaw — пункт **скрыт** (нельзя поставить
super-agent если нет основы).

#### Новый tier HRM (Hermes) в `vip.sh`

- Регекс `^HRM-...` распознаётся как `v3-hrm`
- `course_token_get_tier()` возвращает `HRM`
- `verify_vip_token` → `_verify_v3` с TIER=HRM (тот же Ed25519-ключ,
  payload `HRM|<hash>|<tg>`)
- Все вспомогательные функции (`vip_token_get_expected_tg`,
  `vip_token_get_hash`) расширены на HRM

Это backwards-compat расширение — старые VIP/STD/SUB-токены не
затронуты.

#### Функция `install_hermes_super_agent()`

Запускается при выборе опции 4 в V_MAIN. Шаги:

1. **Запрос HRM-токена** — отдельный prompt с wave 17 санитизацией
   (whitespace / юникод-тире / кавычки)
2. **Валидация HRM-токена** через `verify_vip_token` (3 попытки)
3. **Сканирование OpenClaw-системы**:
   - Список агентов из `~/.openclaw/agents/`
   - Количество workspaces (`~/.openclaw/workspace*`)
   - Доступность CLI `openclaw`
   - Сохраняется в JSON-скан-файл во временной директории
4. **Confirm от клиента** — мы явно показываем что запустим
   third-party installer от NousResearch (~200MB Python venv +
   macOS LaunchAgent), просим подтверждение `[y/N]`
5. **Запуск официального Hermes installer**:
   ```
   curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
   ```
6. **Verify** — `hermes --version` или fallback на venv-binary
7. **Финал** — команды для запуска (`hermes gateway status`,
   `hermes config path`, путь к логам)

### Безопасность

- Hermes installer запускается **только после явного `y` подтверждения**
  клиента — не silent install
- Confirm-блок указывает **источник** (URL репо) и **что будет создано**
  (~/.hermes/, LaunchAgent, размер)
- HRM-токен валидируется через **наш** Ed25519-ключ (не Hermes-ключ)
  — это **наша** платная гейт-проверка
- Telemetry-маркеры (`hermes_install_success`, `hermes_install_declined`,
  `hermes_installer_failed`) — для понимания конверсии

### Сканирование — что собирается

JSON-файл во временной директории:
```json
{
  "scan_at": "2026-05-25T20:45:00Z",
  "openclaw_home": "/Users/.../openclaw",
  "agents_installed": "brain,coordinator,copywriter,...",
  "workspaces_count": 7,
  "openclaw_cli_available": true
}
```

Этот файл передаётся Hermes как контекст (путь печатается в финале
для клиента — он может прокинуть его в `hermes config` если нужно).

### Compatibility

- **Полная backwards-compat**: новый tier HRM не ломает старые
  VIP/STD/SUB-токены
- Если бот ещё не выдаёт HRM-токены — клиенту просто не пройдёт
  валидация на шаге 2, отказ
- `INSTALLER_VERSION` `2026.05.25.2` → `2026.05.25.3`

### Что нужно технарю

На стороне `@AITeamVIPBot` — отдельный handoff:
- Новая таблица `hermes_buyers` (email → tg_id → expires_at)
- Команда `/admin_upload_hermes_buyers <csv>`
- 4-level поиск при `/start`: Hermes → VIP → STD → SUB
- Выдача HRM-токенов формата `HRM-<hash>-<tg>-<sig>` (тот же
  Ed25519-ключ что v3)

Handoff будет в следующем коммите.

### Tests

- Smoke 6.30 (новый, 7 ассертов): функции detect_openclaw +
  install_hermes_super_agent + URL Hermes installer + OPENCLAW_INSTALLED
  + HRM-tier в vip.sh
- Все 35 ассертов зелёные

---

## 2026-05-25 — Wave 24 (co-branding подзаголовок TONY TRUE × СЕРДИТОВ)

### Added

Сразу под ASCII-баннером **AI TEAM 2.0** добавлен co-branding
подзаголовок:

```
    _    ___   _____ _____    _    __  __   ____    ___
   / \  |_ _| |_   _| ____|  / \  |  \/  | |___ \  / _ \
  / _ \  | |    | | |  _|   / _ \ | |\/| |   __) || | | |
 / ___ \ | |    | | | |___ / ___ \| |  | |  / __/ | |_| |
/_/   \_\___|   |_| |_____/_/   \_\_|  |_| |_____(_)___/
              T O N Y   T R U E   ×   С Е Р Д И Т О В
```

Стиль: **BOLD MAGENTA**, разреженный шрифт (по букве через пробел) —
визуально продолжает figlet-эстетику самого баннера.

### Compatibility

- `INSTALLER_VERSION` `2026.05.25.1` → `2026.05.25.2`
- Smoke 6.29 (новый, 1 ассерт). 34/34 PASS

---

## 2026-05-25 — Wave 23 (продающий pitch под баннером)

Технические описания тарифов под баннером заменены на маркетинговый
pitch — текст, который продаёт продукт за 3 секунды чтения.

### Changed

**Было**:
```
   Base: Технарь 🔧  Маркетолог 📈  Продюсер 🎬
   Pro: + Дизайнер 🎨  Координатор 🧭  Копирайтер ✍️
   Installer v2026.05.25 (49c2a18)
```

**Стало**:
```
   Собери команду ИИ-агентов,
   которая работает на тебя 24/7
   и становится умнее каждую неделю

   Не просто боты — готовая ИИ-команда с супер-агентом
   и ролями под бизнес. Не нанимать, не обучать,
   не увольнять — установил, работает.

   v2026.05.25.1
```

### Why

Старый текст был **техническим** — клиент видел «Технарь, Маркетолог,
Продюсер» и не понимал что это даёт. Новый pitch:
- Чётко говорит **что клиент получит** («команда ИИ-агентов»)
- Показывает **выгоду** («работает 24/7», «становится умнее»)
- Снимает **возражения** («не нанимать, не обучать, не увольнять»)

Информация про конкретных агентов (Технарь / Маркетолог / Продюсер
/ Дизайнер / Координатор / Копирайтер) **никуда не делась** — она
теперь показывается в **главном меню** (V_MAIN) при выборе тарифа.

### Compatibility

- Версия установщика **сохранена** в баннере (мелким DIM-текстом
  под pitch) — для саппорта «у вас какая версия?»
- Commit-хэш убран из баннера (был `v2026.05.25 (49c2a18)`) —
  доступен через `--version`
- `INSTALLER_VERSION` `2026.05.25` → `2026.05.25.1`

### Tests

- Smoke 6.28 (новый, 5 ассертов на ключевые фразы pitch'а + что
  старая «Installer v...(COMMIT)» строка убрана)
- Smoke 6.25 (wave 20) **смягчён**: «Base/Pro» проверяется в **меню**,
  не в баннере
- 33/33 PASS

---

## 2026-05-25 — Wave 22 (banner: AI TEAM 2.0)

ASCII-баннер «OpenClaw Agents Pack» заменён на **AI TEAM 2.0** —
новое имя бренда для главного экрана установщика.

### Changed

**Было**:
```
    ___                    ____ _                    _                    _
   / _ \ _ __   ___ _ __  / ___| | __ ___      __   / \   __ _  ___ _ __ | |_ ___
  | | | | '_ \ / _ \ '_ \| |   | |/ _` \ \ /\ / /  / _ \ / _` |/ _ \ '_ \| __/ __|
  | |_| | |_) |  __/ | | | |___| | (_| |\ V  V /  / ___ \ (_| |  __/ | | | |_\__ \
   \___/| .__/ \___|_| |_|\____|_|\__,_| \_/\_/  /_/   \_\__, |\___|_| |_|\__|___/
        |_|                                              |___/   T R U E   P A C K
```

**Стало**:
```
    _    ___   _____ _____    _    __  __   ____    ___
   / \  |_ _| |_   _| ____|  / \  |  \/  | |___ \  / _ \
  / _ \  | |    | | |  _|   / _ \ | |\/| |   __) || | | |
 / ___ \ | |    | | | |___ / ___ \| |  | |  / __/ | |_| |
/_/   \_\___|   |_| |_____/_/   \_\_|  |_| |_____(_)___/
```

Сгенерировано через `figlet -f standard "AI TEAM 2.0"`.

### Что НЕ менялось

- Слово «OpenClaw» **остаётся** в:
  - Пункте меню «3) OpenClaw — только движок» (это название тарифа SUB)
  - Внутренних переменных (`COURSE_TIER` и др.)
  - Имя репозитория и URL'ы
- Имя бота `@AITeamVIPBot` — без изменений
- Tier-структура, токены, payload — без изменений

### Compatibility

- `INSTALLER_VERSION` `2026.05.24.1` → `2026.05.25`
- Smoke 6.27 (новый, 3 ассерта на новый банер + что старый удалён)
- 32/32 PASS

---

## 2026-05-24 — Wave 21 (главное меню V_MAIN до токена)

**Триггер**: Антон зафиксировал — после wave 20 чистка прошла, но
не хватает **главного меню в начале**. Клиент должен видеть линейку
продуктов СРАЗУ после баннера — выбрать что хочет — потом
подтверждать токеном.

Это UX как у любого интернет-магазина: «витрина → корзина →
оплата». До wave 21 было: «оплата → витрина» (сначала токен, потом
меню для Pro-клиентов). Wave 21 переворачивает порядок.

### Added — V_MAIN блок после banner, до V0

```
   ╔════════════════════════════════════════════════════════╗
   ║                  Г Л А В Н О Е   М Е Н Ю               ║
   ╚════════════════════════════════════════════════════════╝

   Что ставим?

     1)  Pro        — 6 агентов (полный набор)  ← рекомендуется
         🔧 Технарь  📈 Маркетолог  🎬 Продюсер
         🎨 Дизайнер 🧭 Координатор ✍️  Копирайтер

     2)  Base       — 3 базовых агента
         🔧 Технарь  📈 Маркетолог  🎬 Продюсер

     3)  OpenClaw   — только движок (без агентов)

   Выбор [1/2/3, Enter = 1]:
```

После выбора:
- **Pro / Base** → V0 (запрос токена) → валидация что tier токена
  совпадает с выбором → установка
- **OpenClaw** → graceful exit без токена (движок уже стоит из
  factory, агенты не нужны)

### Tier-валидация (после V0)

| MAIN_CHOICE | Допустимые токены | Действие |
|---|---|---|
| `pro` | VIP | VIP_MODE=true, ставим 6 агентов |
| `base` | STD, VIP | VIP_MODE=false, ставим 3 (downgrade Pro→Base разрешён) |
| `openclaw` | (не запрашивается) | graceful exit |

Если выбран `pro` с STD-токеном → новый red-блок «не соответствие
тарифа», с подсказкой получить новый токен или выбрать Base.

### Когда V_MAIN пропускается (backwards-compat)

V_MAIN **не показывается** если запуск non-interactive:
- `--install` или `--skip-menu` → клиент знает что хочет
- `--course-token TOKEN` → tier из токена сам определит режим
- `--only-agent <name>` → явный запрос конкретного агента
- `--config <file>` → CI / автоматический
- `VPS_MODE=true` → headless

В этих случаях работает **старый flow** (V0 → V0b) без изменений.

### Compatibility

- **Полная backwards-compat**. Все существующие команды (с любыми
  флагами) работают точно как раньше.
- Старые токены (v2 / v3-vip / v3-std / v3-sub) — без изменений.
- Внутренний `COURSE_TIER` — без изменений.
- `INSTALLER_VERSION` `2026.05.24` → `2026.05.24.1`.

### Tests

- Smoke 6.26 (новый, 6 grep-ассертов): V_MAIN блок + ASCII-баннер
  + переменная MAIN_CHOICE + telemetry-маркеры + tier-mismatch logic
- Все 31 ассерт зелёные

---

## 2026-05-24 — Wave 20 (публичные тарифы Base/Pro + меню 3 пункта)

**Триггер**: Антон зафиксировал публичный нейминг продуктовой
линейки. До этого использовались внутренние термины (Standard, VIP,
Subscription / SUB), которые путали клиентов.

**Финальная линейка**:

| Внутренний tier (токен) | Публичное название | Что включает |
|---|---|---|
| `SUB` (subscription) | **OpenClaw** | Только движок + main-агент |
| `STD` (Standard) | **Base** | + 3 базовых агента (Технарь, Маркетолог, Продюсер) |
| `VIP` | **Pro** | + 6 агентов (всё + Дизайнер, Координатор, Копирайтер) |

### Changed

#### Banner

```
БЫЛО:    Standard: Технарь 🔧  Маркетолог 📈  Продюсер 🎬
         VIP: + Дизайнер 🎨  Координатор 🧭

СТАЛО:   Base: Технарь 🔧  Маркетолог 📈  Продюсер 🎬
         Pro: + Дизайнер 🎨  Координатор 🧭  Копирайтер ✍️
```

#### V0b — Меню для Pro-клиента (5 → 3 пункта)

**Было** (5 опций):
```
1) VIP — 6 агентов
2) Только Standard — 3 агента
3) Установить только одного
4) Диагностика
5) Debug-bundle
```

**Стало** (3 опции по продуктовой линейке):
```
1) Pro — 6 агентов  ← рекомендуется
2) Base — 3 агента
3) Только OpenClaw  (без агентов, чистый движок)
```

Убраны из меню:
- «Установить только одного» — остаётся доступным через `--only-agent <name>`
- «Диагностика» — остаётся доступной через `--diagnose-only`
- «Debug-bundle» — остаётся доступным через `--collect-debug`

Эти эксперт-режимы не нужны в основном меню — продакт-ориентированный
UX = только выбор тарифа.

#### V0b — Сообщение для Base-клиента (STD-tier)

```
БЫЛО:   ✓ Тариф Standard — установлю 3 агента...
        Если нужна диагностика или debug-bundle — запусти с флагом
          --diagnose-only
          --collect-debug

СТАЛО:  ✓ Тариф Base — установлю 3 агента...
        (без подсказок про диагностику — они в --help)
```

#### V0c — Сообщение для OpenClaw-клиента (SUB-tier)

```
БЫЛО:   ℹ️  SUB-тариф (подписка) — базовая установка
        В SUB-тарифе они недоступны — это для Standard / VIP.
        Апгрейд на Standard (3 агента) или VIP (6 агентов)

СТАЛО:  ℹ️  Тариф OpenClaw (подписка) — базовая установка
        В тарифе OpenClaw они недоступны — это для Base / Pro.
        Апгрейд на Base (3 агента) или Pro (6 агентов)
```

#### Tier-mismatch red-блок

```
БЫЛО:   Запрошен VIP-набор (6 агентов), но твой токен — STD-тарифа.
        STD-токен даёт доступ только к Standard-набору.
        Если ты оплатил VIP → новый токен
        Если оплачивал Standard → запусти без флагов VIP-режима

СТАЛО:  Запрошен Pro-набор (6 агентов), но твой токен — STD-тарифа.
        STD-токен даёт доступ только к Base-набору.
        Если ты оплатил Pro → новый токен
        Если оплачивал Base → запусти без флагов Pro-режима
```

### Compatibility

- **Внутренние tier-имена остались прежними** (STD/VIP/SUB) — токены
  и payload-формат не меняются, backwards-compat 100%
- **`COURSE_TIER` переменная** не меняется — внутренние скрипты
  ориентируются на STD/VIP/SUB
- **Telegram-бот** (`@AITeamVIPBot`) пока выдаёт сообщения с старыми
  названиями (Standard/VIP/SUB) — на стороне бота переименование
  делается отдельным handoff'ом для технаря
- **CLI-флаги** не меняются (`--course-token`, `--install` и т.д.)
- **`INSTALLER_VERSION`** `2026.05.17.1` → `2026.05.24`

### Tests

- Smoke 6.25 (новый): 6 grep-ассертов на новые названия + проверка
  что меню сужено до 3 пунктов (нет `[1/2/3/4/5]`)
- Smoke 6.19 (wave 14) **расширен**: принимает оба варианта названий
- Smoke 6.22 (wave 16) **расширен**: принимает оба варианта SUB-сообщения
- Все 30 ассертов зелёные

### Что нужно ещё сделать (handoff)

- `openclaw-factory/scripts/demo-install.sh` — переименовать тарифы
  в выводе (если упоминаются)
- `@AITeamVIPBot` — переименовать в сообщениях клиентам и в боте
  при выдаче токенов
- `docs/vip-install-guide.md` → возможно переименовать в `pro-install-guide.md`
- Лендинг / маркетинг-материалы — по решению Антона

---

## 2026-05-17 — Wave 19 (платформо-aware финал)

**Триггер**: Антон спросил «а есть ли в установщике пункты по
macOS / Windows / VPS?». Ревизия показала что установщик **умеет**
все 4 платформы (auto-detect через `detect_environment` в
`scripts/lib/preflight.sh`), но в **финальном экране** клиент не
видит «куда читать дальше по своей платформе».

Wave 19 это исправляет — добавляет **одну целевую ссылку** на
гайд для платформы клиента в конце установки.

### Added

В `install-agents.sh` после dashboard-блока и перед github-ссылкой
добавлен auto-detect блок:

```bash
case "$(detect_environment)" in
  macos)
    echo "🍎 На Mac есть DMG-установщик: docs/mac-install-guide.md"
    ;;
  windows-bash|wsl)
    echo "🪟 Гайд для Git Bash / WSL: docs/windows-install-guide.md"
    ;;
esac
```

- **macOS**: подсказка про DMG + гайд (wave 13 канал доставки)
- **Windows (Git Bash / MSYS)**: гайд с правилами «PowerShell не
  работает» / «git clone fallback» / «не смешивай среды»
- **WSL**: тот же гайд (всё одно)
- **Linux desktop**: ничего лишнего (всё работает по умолчанию)
- **VPS**: подсказка про SSH-tunnel уже показана **выше** в
  VPS_MODE-блоке — здесь не дублируем

### Why one link, not menu

Принцип wave 18 продолжается: **«тупо не показываем то что
неприменимо»**. Клиент на macOS видит **только** Mac-гайд, на
Windows — **только** Windows-гайд. Меню «выбери платформу» в
начале установщика **не добавляется** — auto-detect лучше.

### Tests

- Smoke 6.24 (новый): 4 grep-маркера про wave 19
- Все 29 ассертов зелёные

### Compatibility

- `INSTALLER_VERSION` `2026.05.17` → `2026.05.17.1` (patch-bump)
- Все CLI-флаги работают без изменений
- На Linux desktop финал **визуально не изменился** (case без
  matching env-name = ничего не печатает)

---

## 2026-05-17 — Wave 18 (UX-чистка установщика)

**Триггер**: Антон попросил убрать «всю лишнюю информацию» из
установщика. Не-технические клиенты (особенно VIP-уровня — продюсеры,
бабушки) тонут в длинных explain-блоках, не понимают что выбирать.

Принцип wave 18: **«тупо нажимай далее»** — на каждом шаге клиент
должен видеть минимум текста, по умолчанию — рекомендуемая опция,
лишние детали (как сменить модель потом / технические термины
типа `MEMORY.md` / ссылки на docs/) **убраны**.

### Changed

#### R1 — выбор модели (5 опций → 3)

- Только **GPT-5.4 codex** (рекомендуется) + **minimax** (бесплатная)
  + «Своя»
- Убраны `opencode/claude-sonnet-4-5` и `opencode/gpt-5-mini` из меню
  (всё ещё доступны через «Своя»)
- Убраны технические префиксы (`openai-codex/`, `opencode/`) из
  отображаемых названий
- Убрана ссылка на `openclaw-switch-model` команду (для технарей)

#### R1.5 — embedding-память (18 строк → 8 строк)

**Было** — длинный технический разбор: «MEMORY.md перечитывается
целиком», «через 2-3 месяца 50+ КБ», «семантический поиск», «копейки
в месяц», ссылка на `docs/openai-key-setup.md`, упоминание `\$5 на
счёт в Settings → Billing`.

**Стало** — простой язык:
- «С памятью агенты становятся **гораздо умнее** — помнят всё что
  ты им говорил»
- «Стоит в среднем **\$15/месяц**»
- «Нужна **иностранная карта**»
- Ссылка на нашу реферальную @WantToPayBot

Опция остаётся opt-in (клиент выбирает 1/2).

#### R1.5 fallback при отсутствии ключа (5 строк → 2 строки)

- Убрано «не нашёл OPENAI_API_KEY в конфиге» (внутренний детайл)
- Убрана подсказка про «положить \$5 в Settings → Billing»
- Оставлено только: ссылка на api-keys + ссылка на @WantToPayBot

#### R2 — Telegram bot tokens (6 строк → 1 строка)

- Убрано «Названия на ваш вкус, например: 'Мой Технарь', 'Мой
  Маркетолог', 'Мой Продюсер'» (самоочевидно)
- Убрана ссылка на `docs/telegram-setup.md`

**Стало**: «Создай по боту для каждого агента через @BotFather (/newbot).»

### Tests

- Smoke 6.10 (wave 8.2 — карта-warning) **смягчён**: теперь regex
  принимает любой вариант предупреждения про карту («Российская
  карта в OpenAI НЕ», «иностранная карта», «зарубежная карта»).
  Суть теста — клиент **должен** быть предупреждён про карту;
  точная фраза не важна.
- Все 28 ассертов остались зелёными.

### Чистый эффект

| Метрика | До | После |
|---|---|---|
| Длина `install-agents.sh` | 1656 строк | ~1600 строк (−56) |
| Кол-во explain-вызовов | 6 | 3 |
| Время чтения текстов клиентом | ~3 минуты | ~30 секунд |
| Опций моделей | 5 | 3 |

### Compatibility

- Все CLI-флаги работают без изменений
- Все ENV-переменные работают без изменений
- Модели `opencode/claude-sonnet-4-5` и `opencode/gpt-5-mini`
  продолжают работать (через флаг `--model` или опцию «Своя» в R1)
- `INSTALLER_VERSION` `2026.05.15` → `2026.05.17`

### Что НЕ менялось

- V0 (токен) — wave 17 санитизация на месте
- V0b (VIP меню) — нетронут (важное решение клиента)
- V0c (SUB graceful exit) — нетронут (анти-обход)
- Финальный экран — нетронут (нужный результат)
- Red-блоки «УСТАНОВКА ОТКЛОНЕНА» — нетронуты (критичный UX wave 15.1)

---

## 2026-05-15 — Wave 17 (санитизация ввода токена)

**Триггер**: реальный кейс клиента (Надежда Sagitova, 15.05.2026).
Валидный VIP-токен отклонялся с кодом 5 — оказалось, при копировании
из Telegram-десктопа в Терминал к токену прилипал trailing-whitespace,
из-за которого `verify_vip_token` падал на проверке подписи.

Локальный прогон того же токена через `verify_vip_token` после
очистки → `rc=0`. То есть токен сам валиден, ломалась копипаста.

### Added — автоочистка пользовательского ввода

- **`scripts/lib/course-token.sh`** в `_course_token_validate_and_set`:
  - Убираются все whitespace-символы (пробел / tab / `\n` / `\r`)
  - Длинное тире `—` (U+2014, em dash) → обычный дефис `-`
  - Среднее тире `–` (U+2013, en dash) → обычный дефис `-`
  - Юникод-дефис `‐` (U+2010) → обычный дефис `-`
  - Неразрывный дефис `‑` (U+2011) → обычный дефис `-`
  - Обрамляющие кавычки `"…"` и `'…'` срезаются (на случай если
    клиент скопировал «`"TOKEN"`»)
  - Если оригинал отличался от очищенного — клиент видит
    `ℹ️ Очистил токен от лишних символов`

Санитизация работает **во всех трёх точках** входа токена
(preset через `--course-token`, кэшированный, prompt) — потому что
все они проходят через единую функцию `_course_token_validate_and_set`.

### Why now

Это не cosmetic — это снимает большой класс саппорт-тикетов вида
«мой токен не работает». Особенно для не-техничных VIP-клиентов
(продюсеры, бабушки), которые копируют токены с мобильных, где
iOS-автокоррекция любит заменять `-` на `—`.

Ожидаемый эффект: **~95% «токен не работает» тикетов закроется
автоматически** ещё до того как клиент пишет в саппорт.

### Compatibility

- **Backward-compat**: чистые токены продолжают работать без
  изменений (санитизация — no-op если ввод уже чистый).
- **Версия установщика**: `2026.05.11` → `2026.05.15`.
- Никаких изменений в формате токена / payload / Ed25519-ключе.

### Tests

- Smoke-test 6.23 (новый): 5 grep-ассертов на маркеры санитизации
  + runtime-проверка что чистый STD-токен распознаётся как STD.
- Все остальные 27 ассертов остались зелёными.

---

## 2026-05-11 — Wave 16 (SUB-tier: подписка на базовую установку)

Антон ввёл новый продуктовый tier — **SUB** (subscription). Это
**самый базовый** тариф, ниже Standard:

| Tier | Включает |
|---|---|
| **SUB** (новый, подписка ежемесячная) | OpenClaw + main-агент (через factory) |
| **STD** (как раньше, разовая) | + 3 агента (Технарь / Маркетолог / Продюсер) |
| **VIP** (как раньше, разовая) | + 6 агентов (+ Дизайнер / Координатор / Копирайтер) |

41 текущий подписчик готов к импорту в `@AITeamVIPBot` v4 — CSV
прилагается в `handoff/active_subscribers-2026-05-11.csv`.

### Added — наш agents-pack уже готов принять SUB-токены

- **`scripts/lib/vip.sh`**:
  - `vip_token_version()` распознаёт `SUB-...` → `v3-sub`
  - `vip_token_get_expected_tg()` + `vip_token_get_hash()` поддерживают SUB
  - `verify_vip_token` → `_verify_v3` с TIER=SUB через тот же
    Ed25519-публичный ключ (новых ключей не нужно)
  - `course_token_get_tier()` возвращает `SUB`

- **`scripts/install-agents.sh` V0c (новый шаг)**:
  - Между V0 (валидация токена) и V0b (tier-меню) добавлен SUB graceful-exit
  - Если COURSE_TIER=SUB → большой жёлтый info-блок:
    > ℹ️ SUB-тариф (подписка) — базовая установка
    > Твой тариф включает: OpenClaw движок + main-агент (ставится первым установщиком).
    > Этот установщик добавляет дополнительных агентов — они для Standard / VIP.
    > Хочешь больше? Апгрейд → саппорт-чат курса.
  - `exit 0` (graceful, не failure) — клиент видит инструкцию, не ошибку

- **`handoff/subscription-tier-brief-for-techie.md`** (~340 строк) —
  бриф для технаря:
  - 1.1 Новая таблица `subscribers` (схема SQL)
  - 1.2 Команда `/admin_upload_subscribers` для импорта CSV
  - 1.3 Логика поиска: VIP → STD → SUB (3-level)
  - 1.4 v4 payload `SUB|hash|tg` (тот же приватный ключ)
  - 1.5 Telemetry/алерты
  - Часть 2: обновление `openclaw-factory/demo-install.sh` для SUB-tier
  - Тестовые SUB-токены — нужны от технаря после деплоя
  - Estimate: 5-6 часов работы

- **`handoff/active_subscribers-2026-05-11.csv`** — CSV с 41 емэйлом
  первой партии (привязан к дате, чтобы видеть когда импортировано)

- **`docs/curator-cheatsheet.md` СЦЕНАРИЙ 13** «У меня SUB-токен —
  установщик отказал»: объясняем что это не отказ а graceful-exit,
  что делать клиенту (запустить factory или апгрейднуться)

- **`docs/curator-cheatsheet.md` СЦЕНАРИЙ 14** «Подписка истекла»:
  бот отказал в выдаче токена → продлить через страницу курса.
  Уже установленные main-агенты **продолжают работать** локально —
  мы не «выключаем» по истечении.

### Changed

- **INSTALLER_VERSION** `2026.05.07.1` → `2026.05.11`
- **`scripts/smoke-test.sh`** — 9 новых runtime/static ассертов
  для SUB-tier (распознавание формата, tier-extraction, V0c блок,
  бриф+CSV прикреплены, curator scenarios)

### Зависимости (ждём от технаря)

Наш agents-pack **готов** принять SUB-токены, но клиенты не смогут их
**получить** пока технарь не обновит:

1. **`@AITeamVIPBot` v4** — новая таблица `subscribers`,
   `/admin_upload_subscribers`, 3-level поиск, expiration check
2. **`openclaw-factory/scripts/demo-install.sh`** — SUB-режим
   установки (только main-агент + понятное info клиенту)

После деплоя бота — технарь пришлёт 2 тестовых SUB-токена (нормальный
+ с истёкшим expires_at) для CI.

### Что НЕ делали (out of scope)

- **Auto-renewal интеграция с Prodamus** — Антон вручную загружает
  CSV. Wave 17+ если будет нужно
- **Принудительное отключение установленных агентов после истечения** —
  машина клиента под его контролем, не «выключаем» удалённо. Блокируем
  только новую установку / refresh при невалидном токене
- **Email-уведомления когда expires < 7 дней** — отдельная задача
  (предпочтительнее через Telegram-уведомление)
- **Refund / cancellation logic** — на стороне платёжной системы

### Verification

- bash -n: OK
- smoke-test: 50/50 pass (+9 wave-16 ассертов)
- security-audit: 8/8 pass

---

## 2026-05-07 — Wave 15.1 (token UX clarity: явные сообщения)

Антон в чате: «открыл команду — ничего не запросило». Оказалось он
запустил `--refresh-templates` (или другой read-only режим) — токен
там по дизайну не нужен. Но клиент это **не знал**.

Wave 15.1 закрывает 2 UX-дыры:

### Added — info-сообщения в early-exit режимах

В каждом из 4 read-only/admin-режимов теперь явно сообщается что
токен не запрашивается **по дизайну**:

```
--collect-debug:    ℹ️ Курс-токен не запрашивается — read-only режим.
--diagnose-only:    ℹ️ Курс-токен не запрашивается — read-only режим.
                       Если хочешь установить новых агентов — запусти
                       команду без флагов.
--refresh-templates: ℹ️ Курс-токен не запрашивается — обновление
                        существующих, MEMORY.md и USER.md не тронутся.
                        Если хочешь установить новых агентов — без флага.
--enable-group-mode: ℹ️ Курс-токен не запрашивается — конфигурируем
                        уже установленных.
```

### Changed — явный отказ при невалидном токене

Раньше при отказе была короткая строчка «Course-token не получен.
Установка прервана.» Теперь — **большой красный блок** с инструкцией:

```
╔════════════════════════════════════════════════════════════════╗
║   ✗  УСТАНОВКА ОТКЛОНЕНА — курс-токен не валиден              ║
╚════════════════════════════════════════════════════════════════╝

Что произошло:
  • Ты не ввёл токен (или ввёл пустую строку), либо
  • Токен не прошёл проверку (отозван / битая подпись / другой TG)

Что делать:
  1. Открой @AITeamVIPBot в Telegram
  2. Напиши /start
  3. Введи email или телефон которыми оплачивал курс
  4. Бот пришлёт токен вида STD-... или VIP-...
  5. Скопируй ВЕСЬ токен и запусти установщик снова

Если бот говорит «email не найден»:
  • Проверь что вводишь email с которого реально оплачивал
  • Возможно оплата ещё не дошла до базы (до 30 минут)
  • Если уверен что оплачивал — пиши в саппорт-чат курса

Если используешь токен с другого Telegram-аккаунта:
  • Токены привязаны к TG (анти-шаринг). С чужим TG не работают.
  • Открой @AITeamVIPBot с ТОГО ЖЕ аккаунта что используешь сейчас.
```

Аналогичный red-block добавлен для **tier-mismatch**:
- VIP-набор запрошен с STD-токеном → явное «УСТАНОВКА ОТКЛОНЕНА —
  несоответствие тарифа» с инструкцией как получить VIP-токен или
  установить Standard-набор.

### Verification

- bash -n: OK
- smoke-test: 41/41 pass (+5 wave-15.1 ассертов)
- security-audit: 8/8 pass

### Changed (тех.)

- INSTALLER_VERSION `2026.05.07` → `2026.05.07.1`
- `_last_exit_reason` теперь устанавливается при отказе токена
  (`token_rejected` / `tier_mismatch`) — для telemetry + EXIT trap
  чтобы не печатать «exit unexpected» на легитимный отказ.

---

## 2026-05-07 — Wave 15 (Bot-to-Bot Communication — Telegram май 2026)

[Telegram добавил 11 новых фич для ботов](https://telegram.org/blog/ai-bot-revolution-11-new-features/ru),
самая важная для нас — **Bot-to-Bot Communication Mode**: боты могут
отвечать другим ботам напрямую, без посредника-человека.

Для нашей VIP-команды из 6 агентов это даёт **прямые цепочки
делегирования** (Координатор → Маркетолог → Копирайтер → результат)
**без** общей TG-группы. Альтернатива (или дополнение) к group-mode
из wave 8.

### Added

- **`docs/bot-to-bot-setup.md`** (~280 строк) — гайд для VIP-клиентов:
  - Зачем (сравнение с group-mode wave 8)
  - Loop-prevention предупреждения (Telegram официально требует чтобы
    бот не зацикливался — наша ответственность)
  - Пошаговая настройка в `@BotFather` (точная команда UI пока не
    опубликована Telegram — даём варианты «Bot-to-Bot Mode / Allow
    Bot Messages / Talk to Other Bots» + рекомендация искать в
    Bot Settings меню; обновим когда Telegram зафиксирует)
  - Откат (как отключить если боты зациклились)
  - FAQ из 6 вопросов (Standard или VIP, лимиты, безопасность, и т.д.)

- **Финальный экран установщика** для VIP — info-блок про
  Bot-to-Bot Communication с указанием шагов и ссылкой на
  `docs/bot-to-bot-setup.md`. Только для VIP-набора (≥4 агентов).

- **Smoke-test ассерты (4 шт)** — проверка наличия
  `bot-to-bot-setup.md`, упоминания в `group-mode.md`, сценария
  в `curator-cheatsheet.md`, info-блока в установщике.

### Changed

- **`docs/group-mode.md`** — info-блок в начало:
  > 🆕 Май 2026 — новая альтернатива: Bot-to-Bot Communication
  С таблицей «когда какой механизм использовать» и ссылкой на
  новый гайд. Group-mode остаётся **полностью валидным** — оба
  механизма работают параллельно.

- **`docs/curator-cheatsheet.md`** — СЦЕНАРИЙ 7 переписан:
  - Раздел A: Group-mode (wave 8) — как раньше
  - Раздел B: Bot-to-Bot Communication (wave 15) — новый
  - Подсказка куратору когда что предлагать клиенту
  - Новый **СЦЕНАРИЙ 7а: «Боты зациклились»** с пошаговым recovery
    (BotFather → Disable Mode → Block bot → найти причину в
    MEMORY/LEARNING → revert через `--refresh-templates`)

- **INSTALLER_VERSION** `2026.05.04` → `2026.05.07`

### Что НЕ делаем (намеренно — out of scope)

- **НЕ меняем шаблоны `templates/<vip>/AGENTS.md`** — текущие правила
  в блоке «Если ты в группе» (`requireMention=true` + «отвечай
  только когда тегают») **уже** защищают от bot-to-bot loops. Не
  переписываем шаблоны чтобы клиенты не получили вынужденный
  ребоарингунг.

- **НЕ автоматизируем включение Bot-to-Bot Mode** — это настройка
  в @BotFather, требует ручного клика клиента. Telegram Bot API
  не предоставляет endpoint для программного включения (как и
  privacy mode в wave 8).

- **НЕ блокируем установку без Bot-to-Bot** — это **дополнение**, не
  обязательное. Group-mode из wave 8 продолжает работать без
  изменений.

### Verification

- bash -n: OK
- smoke-test: 40/40 pass (+4 wave-15 ассерта)
- security-audit: 8/8 pass

### Что осталось зависимостями (не наша зона)

- **Telegram опубликует точные UI-команды @BotFather** для Bot-to-Bot
  Mode → обновим `docs/bot-to-bot-setup.md` с точными названиями
  опций когда станут доступны
- **OpenClaw Gateway** должен корректно обрабатывать входящие
  сообщения от других ботов (`from.is_bot=true`) — потенциально
  понадобится обновление OpenClaw core. На дату wave 15 ожидаем
  что Gateway уже это умеет (адаптивный routing)

---

## 2026-05-04 — Wave 14 (token-first flow: токен раньше меню)

### Проблема (как было до wave 14)

Сначала клиент видел меню «Standard / VIP / диагностика / debug»,
выбирал, и только потом установщик просил курс-токен. Это создавало
два неприятных конфликта:

1. **Mismatch**: клиент выбирает в меню «VIP — 6 агентов», а у него
   на руках STD-токен (Standard-тариф). Установщик в самом конце
   сообщает «STD-токен не даёт VIP-набор» → надо начинать заново.
2. **Лишний клик**: STD-клиент выбирает «Стандарт», потом всё равно
   просят токен — меню избыточно.

### Что поменялось

**Новый flow (wave 14):**

```
запуск
  ↓
banner + preflight (как раньше)
  ↓
V0 — ПРОВЕРКА КУРС-ТОКЕНА (новое — самое первое интерактивное действие)
  - читаем кэш ~/.openclaw/course-token (от первого установщика)
  - если нет → просим вставить + валидация
  - на выходе известен COURSE_TIER (STD или VIP)
  ↓
[STD-токен]  → автоматически Standard (3 агента), без меню
[VIP-токен]  → меню «1) VIP-набор (6) [рекомендуется] /
                     2) Только Standard (3) /
                     3) Только один агент /
                     4) Диагностика /
                     5) Debug-bundle»
  ↓
R0 → R1 → R1.5 → R2 → ...
```

**Ключевое:**
- Токен запрашивается **до** меню → больше нет конфликта tier-mismatch
- STD-клиенты видят меньше шагов (без меню Standard/VIP — оно для них
  избыточно)
- VIP-клиенты получают меню как **подтверждение**: можно поставить
  полный набор или ограничиться Standard если хотят
- `--diagnose-only`, `--collect-debug`, `--refresh-templates`,
  `--enable-group-mode` early-exit **до** V0 — старые сценарии не
  ломаются
- `--vps`, `--install`, `--config` (non-interactive) определяют
  VIP_MODE автоматически из COURSE_TIER

### Changed

- **`scripts/install-agents.sh`**: блок V1 переименован в **V0** и
  перемещён ВЫШЕ старого места меню. Прежняя логика старого меню
  (Standard / VIP / Установить только одного / Диагностика / Debug)
  удалена. Заменена на tier-based ветвление после V0:
  - `COURSE_TIER=STD` → авто Standard, без меню (info-сообщение)
  - `COURSE_TIER=VIP` → новое VIP-меню с подтверждением
- Защита от mismatch (`VIP_MODE=true && COURSE_TIER=STD`) перенесена
  ниже tier-логики на случай non-interactive с CLI-override.

- **INSTALLER_VERSION** `2026.05.03` → `2026.05.04`
- **smoke-test**: 4 новых ассерта (V0 идёт до R0, старое меню
  удалено, новые сообщения на месте)

### UX-моменты

- **Banner всё ещё показывается** до V0 — это просто шапка с
  логотипом, не меню. Убирать его не имеет смысла (пользователь
  должен понимать что запустилось).
- **Сообщение для STD**: «✓ Тариф Standard — установлю 3 агента» +
  подсказка что при необходимости диагностика/debug доступны через
  CLI-флаги.
- **Сообщение для VIP**: «У тебя VIP-тариф — можешь поставить полный
  набор или урезанный» + меню с default=1 (VIP).

### Backward-compat

- Кэш `~/.openclaw/course-token` от первого установщика
  (openclaw-factory wave 12) подхватывается → V0 не просит повторно.
- Флаги `--vip-token` и `--course-token` работают как раньше.
- `--config` non-interactive: COURSE_TIER в env → VIP_MODE auto.
- Старые DMG (wave 13) продолжают работать — они просто вызывают
  `bash <(curl ... bundled)`, а bundled теперь с wave 14 flow.

### Verification

- bash -n: OK
- smoke-test: 36/36 pass (+4 wave-14 ассерта)
- security-audit: 8/8 pass

---

## 2026-05-04 — Wave 13 (DMG-установщик для macOS — двойной клик)

После wave 12 (course-token mandatory) система стабильна, но барьер
входа всё ещё «открой Терминал → вставь команду». Для не-технических
клиентов (продюсеры, маркетологи, бизнес-аудитория) это пугает.

Wave 13 даёт **параллельный канал доставки** для macOS: DMG-файл с
двумя `.command`-обёртками. Двойной клик → запускается Terminal с
уже вставленной командой → клиент только видит вывод и вводит токены.

**Старый путь (curl-bash команды) продолжает работать без изменений.**
DMG — это **дополнение**, не замена.

### Added

- **`dmg-template/`** — шаблон содержимого DMG (3 файла):
  - `1-Установить-OpenClaw.command` — обёртка над первым установщиком
    (`bash <(curl ... openclaw-factory/.../demo-install.sh)`)
  - `2-Установить-AI-команду.command` — обёртка над bundled-installer
    (wave 10) с `releases/latest/download/install-agents-bundled.sh`
  - `README.txt` — инструкция для клиента, ВКЛЮЧАЯ объяснение
    Gatekeeper-warning при первом запуске и как его обойти
    (правый клик → Открыть → Open — один раз)

- **`scripts/build-dmg.sh`** (~140 строк) — локальный сборщик DMG:
  - macOS-only guard (`uname -s != Darwin` → exit с понятным сообщением)
  - Sanity-check на наличие dmg-template/ и всех 3 файлов
  - Копирование в mktemp + `chmod +x` на .command файлы
  - `hdiutil create` (UDZO compressed)
  - `hdiutil verify` + тестовый mount/detach + проверка содержимого
    DMG (что 3 файла на месте и .command'ы executable)
  - SHA256 рядом с DMG
  - Локальный тест: 24 KB DMG, монтируется чисто

- **`.github/workflows/release.yml`** расширен новым **отдельным job
  `build-dmg`** на `runs-on: macos-latest`:
  - Параллельно с release-job (на ubuntu-latest)
  - Build → integrity verify (mount/detach) → attach к существующему
    GitHub Release через `softprops/action-gh-release@v2`
  - Один Release с 4 assets: bundled.sh, bundled.sh.sha256,
    OpenClaw-Setup.dmg, OpenClaw-Setup.dmg.sha256

- **`docs/mac-install-guide.md`** (~250 строк) — гайд для клиентов:
  - 5 шагов установки со скриншот-метками
  - Подробный раздел про Gatekeeper-warning (что это, почему,
    как обойти)
  - Решения типичных проблем (двойной клик не работает,
    quarantine на Apple Silicon, `bash <(curl)` падает)
  - FAQ из 7 вопросов

- **`.github/release-body-template.md`** переписан:
  - macOS DMG — первой секцией (рекомендуется не-техническим клиентам)
  - Bundled — для VPS / корп. сетей
  - Стандартная команда — для технических
  - Windows — отдельная ссылка на гайд

- **Smoke-test ассерты (10 шт)** для wave 13: build-dmg.sh executable,
  dmg-template/ содержит 3 файла, .command файлы executable и проходят
  bash -n, build-dmg.sh имеет macOS-only guard.

- **Security-audit Check 6b** для `dmg-template/`: real-secret patterns
  (sk-, Telegram tokens) + личные TG IDs (975494053, email).
  **НЕ ловит** легитимные публичные URL'ы (`tonytrue92-beep/openclaw-factory`)
  — это публичный GitHub-путь, не утечка.

### Changed

- **`README.md`**: добавлен блок «🍎 На macOS — двойной клик вместо
  терминала» в начало Quickstart с прямой ссылкой на DMG.
- **`docs/vip-install-guide.md`** Шаг 2: новая секция «🍎 На macOS — DMG
  (рекомендуется для не-технических клиентов)» перед обычными
  bash-командами.
- **`docs/curator-cheatsheet.md`** СЦЕНАРИЙ 1: для macOS-клиентов
  куратор теперь **по умолчанию даёт DMG**, bash-команды — fallback
  для тех кто хочет/умеет в терминал.
- **INSTALLER_VERSION** `2026.05.02.1` → `2026.05.03`
- **`.gitignore`** — `/dist/` уже исключён (wave 10), DMG туда выходит
  но не коммитится. Релизный artifact только в GitHub Releases.

### Что НЕ делали (намеренно — out of scope)

- **Apple Developer Program signing** ($99/год) — Gatekeeper-warning
  один раз при первом запуске. Если будет реальная проблема в проде —
  Wave 13.1.
- **Полноценное `.app` GUI** — это 2-4 недели, дублирует bash-логику.
  Можем сделать когда будет реальный спрос.
- **Windows `.bat` / Linux `.AppImage`** — Антон зафиксировал: только
  macOS на этой итерации.
- **Embedded bundled-installer внутри DMG** (offline-режим) — сейчас
  `.command` тянет с GitHub Releases; интернет нужен. Wave 13.1 если
  будут VPS-клиенты с резанием.
- **Брендированный фон DMG** с логотипом — нужен дизайнер. Wave 13.1.
- **Notarization через Apple** — без Apple Developer Program не
  делается.

### Верификация

- `bash -n` всех модифицированных скриптов и `.command` файлов: OK
- `bash scripts/build-dmg.sh` локально на macOS: 24 KB DMG, mount/detach
  тест проходит, все 3 файла внутри executable (для .command)
- `scripts/smoke-test.sh`: 32/32 pass (+10 wave-13 ассертов)
- `scripts/security-audit.sh`: 8/8 pass (Check 6, 6b, 7 + предыдущие)

### Новая команда установки для клиентов macOS

```
1. https://github.com/tonytrue92-beep/openclaw-agents-pack/releases/latest
2. Скачать OpenClaw-Setup.dmg
3. Открыть DMG → двойной клик на «1. Установить OpenClaw.command»
4. Дождаться пока бот ответит в Telegram (~10 минут)
5. Двойной клик на «2. Установить AI-команду.command»
6. Готово
```

При **первом** запуске .command — Gatekeeper-warning, обходится один
раз через правый клик → Открыть. Подробно в `docs/mac-install-guide.md`.

---

## 2026-05-02 — Wave 12.1 (real v3 token tests + end-to-end готов)

Технарь сделал свою часть wave 12 (см. `handoff/course-token-brief-for-techie.md`):

- **`@AITeamVIPBot`** обновлён до v3:
  - Таблица `standard_clients`
  - Команда `/admin_upload_std` для загрузки CSV Standard-клиентов
  - Поиск: VIP → Standard, выдаёт соответствующий токен
  - v3 payload: `TIER|email_hash16|tg_user_id`
  - Старые VIP-токены остались совместимыми
  - 21 pytest passed
  - Коммит технаря: `fbb8443 Add standard course tokens`
  - **Деплой и push в GitHub** не сделаны — в очереди

- **`openclaw-factory/scripts/demo-install.sh`** обновлён:
  - Course-token валидация ДО реальной установки
  - Поддержка STD-... и VIP-...
  - Общий кэш `~/.openclaw/course-token` с нашим установщиком
  - Поддержка `--course-token`, `--vip-token`, env `COURSE_TOKEN`
  - Обновлены обе копии (git-репо + локальная)
  - Коммит технаря: `1ae70e9 Require course token in installer`

### Added

- **6 новых runtime-тестов в `scripts/smoke-test.sh`** для v3-токенов:
  - `v3-STD` форма распознаётся как `v3-std`
  - `v3-VIP` имеет v2-совместимую форму (различается по payload)
  - `verify_vip_token` принимает оба тип-токена с правильным TG
  - Anti-share: чужой TG → rc=3
  - `course_token_get_tier` корректно извлекает `STD` / `VIP`

- **2 публичных тестовых токена** (для CI, бесполезны злоумышленнику —
  привязаны к несуществующему TG=`123456789`):
  ```
  STD-83E4E94BC01F3E0E-123456789-c9H1UYJVjqbu5MCuw0Dwq5rWhqxl4cZRtSCXud3IeBBoG4pnVy4N7iJud6c5oo1fgGKaxSE4JXH_OwIOwSPvDQ
  VIP-377D8277E363B9B3-123456789-B1VpzqPSalsWOzpm-lPX1E6JR8wYTDvNi6THaF2eAkXafCmbaTbPOKf7mk1NPt6gdINAszG7IlIARf0a2dRZDA
  ```

### Status — wave 12 end-to-end теперь работает

| Layer | Status |
|---|---|
| `@AITeamVIPBot` v3 (выдаёт STD/VIP) | ✅ Технарь готово (не задеплоено) |
| `openclaw-factory/demo-install.sh` (требует токен) | ✅ Технарь готово (не запушено) |
| `openclaw-agents-pack` (требует токен через V1) | ✅ Wave 12 в main (v2026.05.02) |
| Локальный smoke-test для v3-STD/VIP | ✅ Wave 12.1 (этот PR) |
| Общий кэш `~/.openclaw/course-token` | ✅ Согласован |

### Что ещё надо от технаря

- **Задеплоить** обновлённый `@AITeamVIPBot` v3 на VPS
- **Запушить** обновлённый `openclaw-factory` в GitHub (чтобы `bash <(curl)` команда первого установщика тянула новую версию)

После этих 2 действий wave 12 полностью live для клиентов.

### Changed

- INSTALLER_VERSION `2026.05.02` → `2026.05.02.1`
- `scripts/smoke-test.sh`: 6 новых runtime-ассертов (всего 31 тест)

### Verification

- bash -n: OK
- smoke-test: 31/31 pass (+6 wave-12.1 runtime-тестов)
- security-audit: 7/7 pass (включая новый Check 7)

---

## 2026-05-02 — Wave 12 (course-token mandatory + защита от утечки команд)

Стратегическая задача: защитить установщик от использования теми кто
не платил за курс. До wave 12 команда `bash <(curl)` могла быть
скопирована из чата / поста / гайда и поставлена бесплатно.

С wave 12 любая свежая установка требует **course-token** — выдаётся
ботом `@AITeamVIPBot` на основе email/phone оплаты. Token bound to
TG user ID, не работает у других людей.

### Added

- **`scripts/lib/course-token.sh`** (~150 строк) — единая система
  токенов для Standard и VIP:
  - `acquire_course_token()` — main entry point: preset / cache / prompt
  - `_course_token_load_cache()` / `_save_cache()` — кэш в
    `~/.openclaw/course-token` с проверкой `chmod 600`
  - `_course_token_validate_and_set()` — Ed25519-валидация + установка
    `COURSE_TOKEN`, `COURSE_TIER`
  - `_course_token_prompt_loop()` — 3 попытки + подсказка про
    `--refresh-templates` для уже-установленных
  - `course_token_required_for_mode()` — helper для решения
    «нужен ли токен в этом сценарии»

- **v3-формат токена** в `scripts/lib/vip.sh`:
  ```
  TIER-<email_hash16>-<tg_user_id>-<signature_b64url>
  ```
  где `TIER ∈ {VIP, STD}`. Payload подписывается с tier явно:
  `<TIER>|<email_hash16>|<tg_user_id>` — нельзя «переделать»
  STD-токен в VIP подменой prefix.

- **Backward-compat:** v2 (legacy VIP без tier в payload)
  продолжает работать через fallback в `verify_vip_token`. Старые
  VIP-токены клиентов не отзываются.

- **Новый CLI флаг `--course-token <token>`** — алиас для `--vip-token`
  с tier-detection по prefix. `--vip-token` сохранён для backward-compat.

- **`handoff/course-token-brief-for-techie.md`** — полный бриф для
  технаря по обновлению `@AITeamVIPBot` (Standard-таблица, выдача
  STD-токенов) и `openclaw-factory/scripts/demo-install.sh` (та же
  course-token валидация в первом установщике).

### Changed

- **V1 step переименован** «ПРОВЕРКА VIP-ТОКЕНА» → «ПРОВЕРКА COURSE-ТОКЕНА»
  и теперь применяется **ко всем установкам** (Standard + VIP), не
  только VIP.
- **Standard-mode без токена больше не возможен** для свежих
  установок. Уже-установленные клиенты с wave 11 и раньше — могут
  использовать `--refresh-templates` (без токена) для обновления.
- `scripts/build-bundle.sh` — добавлен `course-token` в `LIB_ORDER`.
- INSTALLER_VERSION `2026.04.30.2` → `2026.05.02`.

### Что нужно от технаря (вне нашей зоны)

См. `handoff/course-token-brief-for-techie.md`. Краткое резюме:

1. **`@AITeamVIPBot` v3:** добавить выдачу STD-токенов для Standard-
   клиентов. Та же подпись (Ed25519 same key), новый payload-формат
   `TIER|hash|tg`. Антон зальёт CSV Standard-клиентов.
2. **`openclaw-factory/scripts/demo-install.sh`:** добавить такую же
   course-token валидацию в начало (либо source `vip.sh` +
   `course-token.sh` из `agents-pack`).
3. **Кэш `~/.openclaw/course-token`** — общий для обоих установщиков.
   Первый пишет → второй читает (и наоборот при `--refresh-templates`).

### Backward-compat матрица

| Сценарий | Что происходит wave 12+ |
|---|---|
| Свежая установка с VIP-токеном (--vip-token) | ✅ Как раньше + tier=VIP в кэш |
| Свежая установка с STD-токеном | ✅ Standard 3 агента, tier=STD |
| Свежая установка без токена | ❌ Prompt просит токен (3 попытки) |
| `--refresh-templates` (уже установленные) | ✅ Без токена, как было |
| `--diagnose-only` / `--collect-debug` | ✅ Без токена |
| `--enable-group-mode <id>` | ✅ Без токена |
| `--config <file>` без COURSE_TOKEN env | ❌ exit 1 |
| Legacy v2 VIP-токен | ✅ Принимается (fallback в `_verify_v3`) |

### Этап 2 (через 2 недели после готовности технаря)

После того как @AITeamVIPBot выдаёт токены всем оплатившим:

- Переименовать `scripts/install-agents.sh` → `scripts/install-agents-v2.sh`
- На старом URL оставить stub: `echo "Получи новую команду в @AITeamVIPBot"; exit 1`
- Это окончательно убьёт «утёкшие» команды в постах / чатах / гайдах
  даже если кто-то знал старый URL

### Verification

- `bash -n` всех скриптов: OK
- `scripts/smoke-test.sh`: 25/25 pass (+2 wave-12 ассертов)
- `scripts/security-audit.sh`: 6/6 pass
- `bash scripts/build-bundle.sh`: bundle собирается с course-token.sh
- Bundle `--version`: показывает v2026.05.02

---

## 2026-04-26 — Wave 11 (system audit fixes: P0 + P1)

Полный системный аудит установщика по 3 направлениям (security,
edge cases, compatibility) выявил 11 проблем. Закрыты все P0 и
ключевые P1. Остальные (P2 / nice-to-have) — отложены.

### Fixed — P0 (критичные)

- **Python path injection в `preflight.sh`** (wave 9 BUG-05 JSON
  validation) — путь к `auth-profiles.json` интерполировался через
  heredoc. Если `$HOME` содержит `'` или `"` — Python падал
  с syntax error. Теперь путь передаётся через `sys.argv[1]`.
- **`disable_bonjour_for_vps` без openclaw** (wave 10.1 регрессия) —
  функция вызывалась в `--vps` режиме до того как preflight
  проверил `command -v openclaw`. На свежей VPS без OpenClaw
  падало бы с `command not found`. Добавлен guard
  `[[ "$VPS_MODE" == true ]] && command -v openclaw &>/dev/null`.

### Fixed — P1 (важные)

- **`mapfile` несовместимость с bash 3.2** — `find_installed_agents`
  использовал `mapfile -t` (bash 4+). Хотя shebang-gate
  перезапускает в новом bash, lib-файлы могут source'иться где
  угодно. Заменено на portable `while IFS= read -r ... done < <(...)`
  паттерн.
- **Stale `BOT_TOKEN_*` в shell-сессии** — если клиент прервал
  предыдущий запуск Ctrl+C после ввода 2-3 токенов, переменные
  `BOT_TOKEN_TECH/MARKETER/...` остаются в env. На следующем
  запуске установщик подбирал их как preset_token и пытался
  использовать (возможно отозванные) токены. Теперь в начале
  скрипта делается `unset BOT_TOKEN_TECH ... BOT_TOKEN_COPYWRITER`.
- **`prepare_workspace_from_templates` без error-handling в R4** —
  при сетевом сбое curl падал, оставляя workspace частично
  заполненным, установщик продолжал создавать агентов без
  шаблонов. Теперь обёрнуто в `if ! ...; then warn + telemetry`.
- **TG self-test rate-limit на 6 ботах** (wave 9 BUG-03) — 6 быстрых
  `getMe`-запросов в Telegram API могли ловить `429 Too Many Requests`
  и давать ложные fail'ы. Добавлен `sleep 0.5` между вызовами.
- **Empty `BOT_TOKEN_*` в `--config` режиме** — `BOT_TOKEN_TECH=" "`
  (только пробелы) проходил проверку `[[ -z ]]` и падал позже
  без понятного сообщения. Теперь явная проверка через `tr -d`
  + информативное сообщение «проверь что в config-файле не пустой».
- **`umask 077` для temp-файлов с секретами** — `debug-bundle.sh` и
  `vip.sh` создают `mktemp` файлы с PEM-ключами / debug-логами.
  Без `umask 077` они на multi-user системе могли быть читаемыми
  чужими. Добавлен `umask 077` в начало обоих модулей.
- **`README.md` устаревал на 3 агентах** (wave 5 регрессия) — текст
  начинался с «трёх предустановленных агентов», игнорируя VIP
  с 6 агентами + расширения. Переписано на актуальный набор
  (Standard 3 / VIP 6 + SOUL / LEARNING / skills / онбординг /
  embedding / group-mode).

### Skipped — P2 / nice-to-have (на потом)

- **Trap для orphan-канала между `add_telegram_channel` и
  `create_agent_with_bind`** — если критичный fail между этими
  двумя — channel создан, агент нет. Текущий cleanup при
  `--install` overwrite уже это решает на повторном запуске.
  Trap-based fix рискует ложными срабатываниями.
- **Template count formula** в `tests/docker/run-checks.sh` —
  жёсткий список 12/24/37. CI friction для dev. Решим позже,
  когда появится новый шаблон.
- **Mock Telegram/OpenAI API** для unit-тестов — серьёзная работа,
  требует выбор фреймворка (bats-core?). Wave 12 если будет
  сценарий ломки в проде.
- **Telemetry IP-correlation note** в SECURITY.md — низкий риск,
  оставим документировать в будущей публичной security-policy.
- **Locale-зависимое regex matching** в `vip.sh` — теоретическая
  проблема на не-UTF-8 локалях. Большинство VPS UTF-8.

### Changed

- INSTALLER_VERSION `2026.04.30.1` → `2026.04.30.2`.
- 7 новых smoke-test ассертов (P0 + P1 фиксы).

### Verification

- `bash -n` всех модифицированных скриптов: OK
- `scripts/smoke-test.sh`: 23/23 pass
- `scripts/security-audit.sh`: 6/6 pass

### Атрибуция

3 параллельных Explore-агента из системного аудита нашли проблемы.
Реальный кейс с bonjour на VPS (благодарность Анатолию в чате)
закрыт ещё в wave 10.1.

---

## 2026-04-26 — Wave 10.1 (hotfix: bonjour на VPS ломал Gateway)

Реальный кейс из чата клиентов (благодарность Анатолию за репорт):
- Клиент ставил установщик на VPS дважды
- Один раз сразу заработало, второй раз — боты молчали
- Curator-агент в его инстансе нашёл причину: плагин `bonjour`
  пытается анонсировать Gateway через mDNS в локальной сети, на
  VPS падает с `CIAO PROBING CANCELLED` каждые ~45 сек, циклично
  рестартит Gateway. Telegram-канал не успевает стабильно
  подключиться — бот молчит.

Bonjour полезен только в одном кейсе: авто-обнаружение Gateway
iOS/macOS-приложением OpenClaw в локальной сети. На VPS / cloud
бесполезен.

Это плагин из OpenClaw core — не наш репо. Но у нашего установщика
есть флаг `--vps`, и мы знаем «клиент на VPS». Defensive fix:

### Added — `disable_bonjour_for_vps()` в `scripts/lib/agents.sh`

Проверяет `openclaw config get plugins.entries.bonjour.enabled`,
выставляет `false` если ещё не выставлено. Печатает короткое
объяснение зачем (чтобы клиент не паниковал «что вы выключили?»).

Вызывается **автоматически** в `--vps` режиме нашего установщика —
сразу после `preflight_openclaw + preflight_network_check`, до
создания агентов. Идемпотентно: повторный запуск ничего не ломает.

### Added — bonjour-check в `scripts/diagnose-agents.sh`

На Linux / WSL окружениях (не macOS) проверяет состояние
`plugins.entries.bonjour.enabled` через `openclaw config get`:
- `false` → ✓ зелёный (правильно для VPS)
- `true` → ⚠️ жёлтый с инструкцией как отключить + ссылкой на
  symptom `CIAO PROBING CANCELLED` в логах

### Added — recovery hint в Telegram self-test (R5)

Wave 9 BUG-03 self-test после R5 уже выводил список «что проверить
если бот молчит». Добавлен пункт #6:
> Если в логах видишь `CIAO PROBING CANCELLED` (mDNS) или gateway
> циклически рестартится — выключи bonjour:
>   `openclaw config set plugins.entries.bonjour.enabled false`

### Added — СЦЕНАРИЙ 4а в `docs/curator-cheatsheet.md`

Новый сценарий «Бот молчит на VPS, Gateway циклически рестартится»
с конкретным симптомом (`CIAO PROBING CANCELLED` в логах) и одной
командой фикса. Куратор сможет локализовать за минуту.

### Changed

- INSTALLER_VERSION `2026.04.30` → `2026.04.30.1` (hotfix-style suffix).
- 5 новых smoke-test ассертов (по одному на каждый слой).

### Verification

- bash -n всех скриптов: OK
- smoke-test: 22/22 pass (+5 wave-10.1 ассертов)
- security-audit: 6/6 pass

### Эскалация в openclaw-factory (вне нашей зоны)

Правильный фикс — отключать bonjour by default в первом установщике
для VPS-окружений. Это работа технаря для `openclaw-factory` /
OpenClaw core. Описано в curator-cheatsheet эскалации.

---

## 2026-04-30 — Wave 10 (self-contained bundle для VPS / корп. сетей)

Wave 9 BUG-06 показал в сообщении ошибки `git clone` как fallback при
сбое `raw.githubusercontent.com`. Wave 10 идёт дальше — даёт **второй
канал доставки** установщика через GitHub Release CDN, минуя
`raw.githubusercontent.com` полностью.

Зачем: на VPS / корпоративных сетях / медленном интернете nested curl
к raw.githubusercontent.com часто падает с timeout (=BUG-06). Bundled
подход — один файл, никаких nested curl-ов после первого скачивания.

### Added

- **`scripts/build-bundle.sh`** — локальная утилита-сборщик. Берёт
  `scripts/install-agents.sh` + все `scripts/lib/*.sh` (6 модулей)
  и склеивает в один self-contained `dist/install-agents-bundled.sh`
  (~150 KB, ~3000 строк):
  - Использует sentinel-маркеры `=== BUNDLE_LIB_BEGIN ===` /
    `=== BUNDLE_LIB_END ===` в `install-agents.sh` чтобы найти где
    заменять `source/curl` блок на inline-контент.
  - Удаляет дубликаты `#!/usr/bin/env bash` и `set -euo pipefail`
    из lib-файлов (они уже есть в начале install-agents.sh).
  - Прогоняет `bash -n` на bundled-выходе, проверяет что валидный.
  - Печатает sanity-команды (`--version` / `--help`) для проверки.
- **`.github/workflows/release.yml`** — авто-публикация bundled-релиза:
  - Триггер: push тега `v2026.*` или `v2027.*`.
  - Sanity-check что тег совпадает с `INSTALLER_VERSION` в скрипте.
  - Подмена `__COMMIT_PLACEHOLDER__` на реальный short commit hash.
  - Запуск `scripts/build-bundle.sh`.
  - Sanity bundled `--version` / `--help`.
  - Генерация `install-agents-bundled.sh.sha256`.
  - GitHub Release с двумя assets и body из
    `.github/release-body-template.md`.
- **`.github/release-body-template.md`** — шаблон body для релизов
  (зачем bundle, две команды установки).
- **CI job `build-bundle`** в `.github/workflows/ci.yml` — на каждом
  PR проверяет что `scripts/build-bundle.sh` собирает валидный bundle
  и что в нём нет остатков `source ${SCRIPT_DIR}/lib/...` (защита от
  битой сборки).

### Changed

- **`scripts/install-agents.sh`** — добавлены sentinel-маркеры вокруг
  блока подключения lib/* (для build-bundle.sh).
- **`scripts/install-agents.sh`** — сообщение об ошибке curl при
  сбое `raw.githubusercontent.com` (wave 9 BUG-06) теперь указывает
  **bundled-URL как первое решение**, потом `git clone` как второе:
  ```
  Рабочее решение №1 — self-contained bundle (один файл, без nested curl):
      bash <(curl -fsSL https://github.com/.../releases/latest/download/install-agents-bundled.sh)
  Рабочее решение №2 — git clone репозитория и запустить локально: ...
  ```
- **`README.md`**: новый блок про bundled путь как fallback.
- **`docs/vip-install-guide.md`**: команда установки теперь имеет
  два варианта — обычный curl и bundle.
- **`docs/windows-install-guide.md`**: bundle стал Вариант B
  (рекомендуется), git clone сдвинут в Вариант C.
- **`docs/curator-cheatsheet.md`**: новый блок «Self-contained bundle»
  в команды-памятке + СЦЕНАРИЙ 6 переписан с приоритетом bundle.
- **`.gitignore`**: добавлено `/dist/` (build-артефакты не коммитим).
- **INSTALLER_VERSION** 2026.04.29 → 2026.04.30.

### Команда для клиента (новая)

```bash
bash <(curl -fsSL https://github.com/tonytrue92-beep/openclaw-agents-pack/releases/latest/download/install-agents-bundled.sh)
```

URL стабильный — `releases/latest/download/...` редиректится на
конкретный последний релиз.

### Verification

- `bash -n` всех скриптов: OK
- `scripts/smoke-test.sh`: 21/21 pass (+1 wave-10 ассерт-блок)
- `scripts/security-audit.sh`: 6/6 pass
- `bash scripts/build-bundle.sh` локально: собирает bundle ~150 KB,
  bundle проходит `--version` / `--help` / `--diagnose-only`.
- CI build-bundle job: будет проверен после merge.

### Что осталось (out of scope)

- Релиз `v2026.04.30` с bundled-asset — будет создан после merge
  через `git tag v2026.04.30 && git push --tags`. Workflow сам
  опубликует.
- Пост в чат VIP про bundled-команду — отдельно после релиза.

---

## 2026-04-29 — Wave 9 (system hardening: BUG-01/03/05/06 из техотчёта)

Куратор-агент собрал по реальным кейсам клиентов из чата ИИ Team
техотчёт от 2026-04-26 (источник:
`/Users/antonpolakov/openclaw-factory/agents/curator/tmp/openclaw-install-fix-report-2026-04-26.md`).
Главная боль не в «есть баги», а в том что **продукт даёт ложный
прогресс и не локализует слой сбоя** — саппорт ловит каскад
«токен невалидный / бот молчит / установщик завис / модель не
работает» под разными масками, хотя в основе один из 6 системных
классов.

Wave 9 закрывает **4 P0-класса в нашей зоне** — `openclaw-agents-pack`.
Остальные 3 (BUG-02 gateway.mode / BUG-04 provider+model key /
BUG-07 macOS UX) — эскалируются на технаря через
`docs/curator-cheatsheet.md`.

### Added — BUG-01: hard preflight базовых утилит

В `scripts/lib/preflight.sh` → `preflight_openclaw()` в самом начале
теперь проверяется наличие `bash`, `python3`, `curl` через
`command -v`. Если хоть одна утилита отсутствует — hard-stop с
**ОС-специфичной** инструкцией как поставить:

- На Windows (Git Bash) → ссылка на git-scm.com/download/win
- На macOS → `brew install <missing>`
- На Linux/WSL → `apt-get install -y <missing>`

Раньше клиент уезжал в R0 и висел там бесконечно с непонятной
ошибкой если в системе не было python3 или curl.

### Added — BUG-05: hard JSON validation `main/auth-profiles.json`

В `preflight_openclaw()` блок проверки auth-profile расширен:
1. **Файл существует** (как раньше — `[[ -f ]]`)
2. **Файл не пустой** (`[[ -s ]]`) — раньше `{}` или 0 байт проходили
3. **Валидный JSON** (через `python3 json.load`) — раньше любой мусор
   проходил
4. **Не пустой объект** — `len(d) == 0` или not dict → fail

При любом нарушении — hard-stop с прямой инструкцией:
> Не лечи файл вручную (это приведёт к 401 у новых агентов) —
> перезапусти первый установщик начисто.

Из техотчёта: «частый кейс ложного фикса — клиент сам создаёт `{}`
чтобы обойти отсутствие файла → потом получает 401 у новых агентов».

**Guard для `--refresh-templates`:** этот режим не использует
main/auth-profile для копирования, поэтому пропускает deep-validation
через флаг `SKIP_AUTH_PROFILE_CHECK=true`. Иначе клиент с битым main
не сможет даже refresh применить.

### Added — BUG-06: localized curl-error messages

Блок lib-fetch (~строки 270-300 в `scripts/install-agents.sh`) при
сбое curl на `raw.githubusercontent.com` теперь печатает:

```
ERROR: не смог скачать scripts/lib/<mod>.sh с GitHub raw.
       Хост: raw.githubusercontent.com
       Commit: <commit>
       Timeout: 10 сек

Возможные причины:
  • raw.githubusercontent.com временно недоступен или режется фаерволом
  • Корпоративный VPN / прокси не пропускает HTTPS к GitHub
  • Слишком медленное соединение (10 сек на файл не хватило)
  • Указанный коммит не существует на GitHub

Рабочее решение — скачать репозиторий целиком и запустить локально:
    git clone https://github.com/tonytrue92-beep/openclaw-agents-pack
    cd openclaw-agents-pack
    bash scripts/install-agents.sh

Локальный запуск минует raw.githubusercontent...
```

Раньше было голое «не смог скачать X» + `exit=28` без объяснения.

### Added — BUG-03: Telegram-канал self-test после R5

В `scripts/lib/agents.sh` новая функция `telegram_channel_self_test(account_id)`:
- Достаёт сохранённый токен через `openclaw config get`
- Пингует `getMe` через уже существующую `validate_telegram_token`
- Не печатает токен в stdout

В `scripts/install-agents.sh` сразу **после** `R5 gateway restart` для каждого
установленного агента:

```
Проверяю что каждый бот отвечает в Telegram (5-10 сек)...
✓ tech: бот отвечает
✓ marketer: бот отвечает
○ producer: бот НЕ отвечает (gateway running, но Telegram-канал лежит)

⚠️ Telegram-каналы не работают для: producer
Это означает: gateway запущен, но Telegram-токен/привязка не работает.
Не запускай reinstall — проблема в Telegram access layer. Что проверить:
  1. Токен бота в @BotFather (мог быть сброшен через /revoke)
  2. Бот не заблокирован тобой в Telegram
  3. api.telegram.org не блокируется фаерволом / VPN
  4. Запусти: openclaw channels status --probe
  5. Логи gateway: openclaw logs --tail 50 --follow
```

Раньше после R5 клиент видел только «Gateway: running» — но это не
гарантия что Telegram-канал работает.

`INSTALLED_LIST` сформирован раньше R5 (после R4 цикла), теперь доступен
для self-test и для R5b group-mode.

### Added — Эскалация на технаря в `docs/curator-cheatsheet.md`

Новая секция «Эскалация на технаря (вне нашей зоны)» со таблицей
симптом → BUG-класс → куда эскалировать. Покрывает 3 класса вне
нашей зоны:

- BUG-02 (gateway.mode / plugin-runtime-deps / typebox)
- BUG-04 (provider/model/key/auth-profile flow)
- BUG-07 (macOS / Homebrew / Xcode UX)

Со ссылкой на полный техотчёт. Куратор знает когда **не лечить**, а
сразу слать в backlog `openclaw-factory`.

### Changed

- **INSTALLER_VERSION** 2026.04.28 → 2026.04.29.
- **smoke-test.sh** — 8 новых ассертов (по одному на каждый под-фикс
  wave 9 + эскалация в curator).

### Verification

- `bash -n`: OK
- `scripts/smoke-test.sh`: 20/20 pass (+1 wave-9 ассерт-блок)
- `scripts/security-audit.sh`: 6/6 pass

### Live-testing план

После выкатки:
1. **BUG-01** — `PATH=/tmp bash scripts/install-agents.sh --diagnose-only`
   → должен упасть с указанием каких утилит не хватает
2. **BUG-05** — `echo '{}' > ~/.openclaw/agents/main/agent/auth-profiles.json`
   → запустить установщик → должен упасть **до** R0 с понятным сообщением
3. **BUG-06** — симулировать сетевой сбой → проверить что в сообщении
   есть `git clone …` команда
4. **BUG-03** — намеренно сломать токен в `openclaw config set` →
   запустить `--diagnose-only` или установщик → R5 self-test должен
   найти проблему и не предложить reinstall

### Что не сделано в wave 9 (out of scope)

- BUG-02 / BUG-04 / BUG-07 — переданы в backlog `openclaw-factory`
  через `curator-cheatsheet.md`
- P1 пункты (Windows quoting / health summary / macOS UX) — wave 10
- Self-contained payload (bundled archive вместо `git clone` fallback)
  — wave 10 если будет нужно

---

## 2026-04-27 — Wave 8.5 (шпаргалка для куратора курса)

Куратор курса (AI-агент или живой человек) — главная точка контакта
для клиентов с проблемами установки. Раньше у него не было единого
источника правды: документация раскидана по 5 файлам, версионная
история в CHANGELOG, типичные сценарии нигде не описаны.

### Added

- **`docs/curator-cheatsheet.md`** (~400 строк) — единая шпаргалка для
  куратора:
  - Главный принцип: «не лечи не разобравшись» (3 вопроса перед командой)
  - Карта документации (что когда давать клиенту)
  - Команды-памятка (установка / refresh / diagnose / debug-bundle / group-mode / embedding / version)
  - Шаги установщика по порядку (R0 / R1 / R1.5 / R2 / R2.5 / R3 / R4 / R5 / R5b)
  - **12 типичных сценариев клиентов** с готовыми ответами:
    1. Только что купил VIP / ничего не работает
    2. Уже стоит, как обновиться
    3. РФ-карта не принимается в OpenAI
    4. Бот в Telegram молчит после `/start`
    5. Установщик ругается на auth-profile
    6. Скачивание зависает / raw.githubusercontent тупит
    7. Хочу команду в общем TG-чате
    8. У меня Windows
    9. Embedding-память — что это, нужно ли
    10. Ноут + VPS на одной установке
    11. Удалить одного агента
    12. Поменялся VIP-токен / TG-аккаунт → эскалация на Антона
  - Что НЕ делать (5 anti-patterns: руками править openclaw.json,
    `auth-profiles.json`, «снеси и поставь заново», команды для не-той
    ОС, общие OpenAI-ключи)
  - Эскалация (debug-bundle → саппорт → Антон с описанием)
  - История версий (последние 8)
  - Раздел «Если ты — AI-куратор-агент» с ссылками для копирования
- **`scripts/smoke-test.sh`** — 1 новый ассерт на наличие
  `docs/curator-cheatsheet.md` (защита от случайного удаления).

### Why

В чате запрос Антона: «Дай ссылку для агента-куратора, чтобы он
понимал всё». Куратору нужен один документ, по которому он отвечает
на любой вопрос клиента — без этого он:
- даёт команды для не-той ОС (Mac-команды Windows-клиенту);
- советует «снеси всё и переустанови» (потеря MEMORY);
- говорит «карта может не пройти» вместо конкретного решения;
- лечит auth-profile вручную вместо первого установщика.

Шпаргалка кодифицирует best practices.

### Прямая ссылка для куратора

```
https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/docs/curator-cheatsheet.md
```

---

## 2026-04-27 — Wave 8.4 (РФ-карта warning + бот-ссылка прямо в R1.5)

В предыдущих версиях (wave 8.1 / 8.2) предупреждение «карта РФ не
пройдёт» и ссылка на бот для выпуска виртуальной зарубежной карты
были **только в docs/**. Установщик в шаге R1.5 этого не показывал.

Сценарий бага: клиент в RU проходит R1.5, идёт в OpenAI billing с
российской картой, получает отказ → не понимает что делать → пишет
в саппорт. Открыть `docs/openai-key-setup.md` ему не приходит в голову.

### Changed

- **R1.5 explain-блок** в `scripts/install-agents.sh` дополнен:
  ```
  ⚠️  Российская карта в OpenAI НЕ пройдёт (санкции, обхода нет).
  Самый быстрый способ выпустить виртуальную зарубежную карту:
     https://t.me/WantToPayBot?start=w17851188--GUSNM
  Или используй уже имеющуюся карту KZ/AM/GE/TR/ОАЭ/EU/US.
  ```
- **Sub-prompt при вводе ключа** (оба варианта — «тот же что для модели»
  и «отдельный») получили краткую строку с тем же ссылкой:
  ```
  РФ-карта НЕ пройдёт. Виртуальная зарубежная:
  https://t.me/WantToPayBot?start=w17851188--GUSNM
  ```
- **`scripts/smoke-test.sh`** — 1 новый ассерт: проверка что
  installer содержит ссылку на @WantToPayBot и явное предупреждение
  «Российская карта в OpenAI НЕ» (wave 8.2-8.4 защита от регрессии).
- **INSTALLER_VERSION** 2026.04.27 → 2026.04.28.

### Why

Антон в чате обратил внимание: ref-ссылка есть в docs, но **в установщике
её нет**. Клиент видит docs только если уже запутался — а должен видеть
прямо в момент когда установщик просит ключ. Исправлено.

---

## 2026-04-26 — Wave 8.3 (Windows-путь установки + 7 правил из success kit)

В предыдущих версиях `docs/vip-install-guide.md` и `workbook-source.md`
говорили клиенту «На Windows: Win → powershell» и потом давали
`bash <(curl)` команду. **Это неверно** — в PowerShell нет `bash`,
команда падает молча. Плюс OpenClaw на Windows ставится не bash-скриптом
factory, а нативным `.exe` installer'ом.

Wave 8.3 — фикс этой дыры: установщик распознаёт Windows-окружения,
печатает 7 правил из реального успешного кейса, доки переписаны под
правильный путь (Git Bash + нативный installer).

### Added

- **`scripts/lib/preflight.sh`** — две новые функции:
  - `detect_environment()` — возвращает `windows-bash` / `wsl` /
    `linux` / `macos` / `unknown` через `$OSTYPE` + `uname -r`.
  - `print_windows_hints()` — печатается **один раз** при первом
    `preflight_openclaw()` если детектировали Windows. Доносит
    4 главных правила из success kit Антона:
    1. Не запускать в PowerShell — Git Bash или WSL
    2. OpenClaw ставится официальным `.exe`, не bash-скриптом
    3. Если raw.githubusercontent тупит — `git clone` + `bash scripts/install-agents.sh`
    4. Не смешивать среды (всё в Git Bash, не половину в PowerShell)
- **`preflight_openclaw()` расширен** — если OpenClaw не найден и
  окружение `windows-bash`, печатается **другая** инструкция:
  скачать installer с openclaw.ai/download/windows + последовательность
  `openclaw.cmd configure → gateway start → channels status --probe`
  в **PowerShell**, потом возвращаться сюда (в Git Bash) для второго установщика.
- **`docs/windows-install-guide.md`** (новый, ~450 строк):
  - **7 правил** из success kit (вверху, чтобы не повторять грабли):
    1. Не `bash <(curl)` в PowerShell
    2. Если OpenClaw уже встал — не сносить, а идти по `openclaw.cmd configure → gateway start → channels status --probe`
    3. Не смешивать среды (Git Bash ↔ PowerShell)
    4. Не лечить вручную `auth-profiles.json` — добивать первый установщик
    5. Если raw.githubusercontent тупит — `git clone` + локальный запуск
    6. `channels status --probe` зелёный = проблема не в токене, смотри `openclaw.cmd logs --tail 50 --follow`
    7. Если не достучаться до api.telegram.org — это сеть/DNS (`Test-NetConnection`, `Resolve-DnsName`)
  - Полная пошаговая установка (Git Bash → нативный OpenClaw → PowerShell configure → Git Bash для agents-pack)
  - Раздел «Если что-то пошло не так» с типичными проблемами
  - FAQ из 7 вопросов (PowerShell без Git Bash, WSL vs Git Bash, корпоративный Windows, антивирус, …)

### Changed

- **`docs/vip-install-guide.md`** — Шаг 2 переписан: была одна
  команда «На Mac/Windows/VPS», теперь развилка с явным Windows-блоком
  ссылающимся на `docs/windows-install-guide.md`.
- **`docs/workbook-source.md`** — Модуль 1:
  - Шаг 1.1 для Windows переписан: «другой путь!» — сначала Git Bash
    + OpenClaw installer, потом Шаг 1.2-Windows вместо обычного 1.2.
  - Новый **Шаг 1.2-Windows**: установка OpenClaw через .exe + настройка
    в PowerShell с командами `openclaw.cmd configure / gateway start /
    channels status --probe`.
  - Модуль 3 шаг 3.1: добавлена развилка Mac/Linux vs Windows
    с двумя вариантами (curl-bash и git clone).
- **INSTALLER_VERSION** 2026.04.26 → 2026.04.27.
- **`scripts/smoke-test.sh`** — 1 новый ассерт: `docs/windows-install-guide.md`
  + `detect_environment` + `print_windows_hints` + `windows-bash/wsl` упоминания.

### Что увидит Windows-клиент при запуске

При `bash scripts/install-agents.sh` в Git Bash на Windows (даже если
OpenClaw не установлен):

```
🪟 Обнаружено окружение: Git Bash / MSYS
Несколько правил чтобы не получить -ой:
  1. Не запускайте этот скрипт в PowerShell/cmd — нужен bash.
  2. OpenClaw на Windows ставится официальным installer'ом
     (НЕ bash-скриптом factory). После установки команды
     запускаются как openclaw.cmd.
  3. Если raw.githubusercontent тупит — скачайте репо:
     git clone https://github.com/tonytrue92-beep/openclaw-agents-pack
     cd openclaw-agents-pack && bash scripts/install-agents.sh
  4. Не смешивайте среды: если запустили в Git Bash —
     все диагностические команды (которые установщик
     просит выполнить) тоже в Git Bash, не в PowerShell.

Полный гайд: docs/windows-install-guide.md в репо.
```

И **если openclaw не найден** — выдаст ссылку на нативный installer
(`https://openclaw.ai/download/windows`), а не на bash-скрипт factory.

### Why

Антон в чате прислал «success kit» из 7 правил после реального опыта
поддержки Windows-клиента. Они не были отражены ни в установщике, ни
в доках — клиенты на Windows натыкались на одни и те же грабли и
писали в саппорт. Это исправлено в wave 8.3.

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
