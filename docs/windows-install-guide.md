# 🪟 Установка на Windows — рабочий путь

> ⏱ **Время:** 30-45 минут на чистой системе (включая установку Git Bash)
> 💻 **Тестировалось на:** Windows 10 / Windows 11

Этот гайд — для клиентов которые ставят OpenClaw + AI-команду на Windows.
Он отличается от macOS/Linux потому что:

- **bash-скрипты не работают в PowerShell.** Нужен Git Bash или WSL.
- **OpenClaw на Windows ставится нативным установщиком** (`.exe` / `.msi`),
  а не bash-скриптом factory.
- **PATH и среды легко спутать** — если делать половину в PowerShell,
  половину в Git Bash, всё ломается.

**7 правил из реального успешного кейса** — вверху, чтобы не повторять
грабли. Дальше — пошаговая установка.

---

## 📜 7 правил Windows-установки

### 1. На Windows не запускаем `bash <(curl ...)` в PowerShell

PowerShell не знает что такое `bash`, `curl ... | bash`, `<(...)`.
Эти команды работают только в **Git Bash** или **WSL**.

**Базовый путь для OpenClaw на Windows:**
- ✅ Скачать **официальный installer** с [openclaw.ai/download/windows](https://openclaw.ai/download/windows)
- ✅ Дальше команды через `openclaw.cmd` в PowerShell
- ❌ **Не пытаться** использовать bash-скрипт factory

**Для второго установщика (этот pack):**
- ✅ Запускать в **Git Bash** или **WSL**
- ❌ **Не в PowerShell** (там нет `bash`)

### 2. Если OpenClaw уже встал — НЕ переустанавливаем всё заново

Если первый установщик прошёл успешно и `ExecutionPolicy` уже исправлена —
**не сноси всё и не начинай заново**. Идём по нормальной цепочке:

```powershell
# В PowerShell (от обычного юзера, не админа):
openclaw.cmd configure
# → выбрать нужную модель
# → вставить токен бота
openclaw.cmd gateway start
openclaw.cmd channels status --probe
# Должен ответить green / зелёный.
```

### 3. На Windows нельзя смешивать среды

Если второй установщик идёт в **Git Bash**, то и **диагностические
команды** (`getMe` через curl, `which openclaw`, `openclaw agents list`)
делаем там же — **в той же среде**, не половину в PowerShell.

PATH у PowerShell и Git Bash разный. PowerShell видит `openclaw.cmd`,
Git Bash видит `openclaw` (через `openclaw.cmd` обёртку или симлинк).

### 4. Не создаём вручную `auth-profiles.json` и не лечим костылями

Если второй установщик ругается:

```
Не найден auth-profile основного агента (...)
```

Это значит **первый установщик не довёл до конца** — нет настроенного
opencode.ai ключа. **Не пытайся** создавать `auth-profiles.json`
руками, это не поможет.

**Правильно:**
1. Вернись в первый установщик
2. Дойди до того момента когда `main` агент реально создаст профиль
   и заговорит в Telegram
3. Потом возвращайся ко второму установщику

### 5. Если raw.githubusercontent тупит — НЕ долбим `bash <(curl)` по кругу

Иногда GitHub raw.githubusercontent на Windows/WSL отдаёт redirect-loop,
TLS handshake fail или просто 5-минутный timeout. Не нужно перезапускать
команду 10 раз.

**Рабочий путь:**

```bash
# В Git Bash:
git clone https://github.com/tonytrue92-beep/openclaw-agents-pack
cd openclaw-agents-pack
bash scripts/install-agents.sh
```

Скрипт распознает что запущен из репозитория (а не из `bash <(curl)`)
и не будет тянуть свои lib-модули с GitHub — возьмёт локально.

### 6. Если `channels status --probe` уже зелёный, проблема не в токене

Если probe прошёл — значит **Telegram API доступен**, **токен валидный**,
**бот привязан к OpenClaw**. Но бот в Telegram молчит на сообщения?

**Не нужно ломать всё переустановкой.** Смотрим **свежие логи gateway**
сразу после `/start`:

```powershell
openclaw.cmd logs --tail 50 --follow
```

Потом в Telegram пишешь `/start` боту и читаешь что вывалилось в логи.
Обычно проблема одна из:
- Промпт-модель не отвечает (квота / ошибка API-ключа)
- Routing rule неправильный (написал боту А, рутится к агенту Б)
- DM allowlist блокирует — твой TG ID не в `allowFrom`

### 7. Если Windows не достукивается до `api.telegram.org` — это сеть/DNS

Не «битый токен», не «бот удалён». **Сеть.** Проверяй:

```powershell
# В PowerShell:
Test-NetConnection api.telegram.org -Port 443
Resolve-DnsName api.telegram.org
```

Если timeout / `ResolveDns failed`:
- Проверь что не включён VPN с DNS-leak
- Корпоративный фаервол блокирует Telegram
- Антивирус (особенно ESET / Касперский) перехватывает HTTPS
- DNS провайдера в РФ блочит — попробуй `1.1.1.1` (Cloudflare)

---

## 🚀 Полная пошаговая установка

### Шаг 1 — Установить Git Bash

Git Bash — bash-окружение для Windows. Без него bash-скрипты не запустятся.

1. Скачай [git-scm.com/download/win](https://git-scm.com/download/win)
2. Запусти установщик `.exe`
3. **На вопросах оставляй default** (`Next` → `Next` → ...) — кроме
   одного:
   - **«Adjusting your PATH environment»** → выбери
     **«Git from the command line and also from 3rd-party software»**
     (среднее значение). Это нужно чтобы потом OpenClaw мог звать `git`.

После установки:
- В пуске появится **«Git Bash»** — его и будем использовать
- В PowerShell станут доступны `git`, `curl` (но всё ещё нет `bash`)

`[SCREENSHOT: Git Bash в Start menu]`

> 💡 **Не путать** с Git CMD или Git GUI — нам нужен именно Git Bash.

### Шаг 2 — Установить OpenClaw нативным installer'ом

1. Открой [https://openclaw.ai/download/windows](https://openclaw.ai/download/windows)
2. Скачай `OpenClawSetup-x.x.x.exe` (или `.msi`)
3. Запусти от **обычного пользователя** (не «От имени администратора» —
   это важно, иначе PATH прописывается в системную часть)
4. Default `Next → Next → Install`

Установщик:
- Положит `openclaw.cmd` в `C:\Program Files\OpenClaw\` (или в `%LOCALAPPDATA%`)
- Допишет PATH в `User variables` (не в System)
- Создаст ярлык в Start menu

После установки **закрой и снова открой** PowerShell — иначе он не увидит
обновлённый PATH.

### Шаг 3 — Настроить OpenClaw в PowerShell

Открой **PowerShell** (Win → `powershell` → Enter).

Если впервые запускаешь PS-скрипты, может потребоваться:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

(подтверди `Y`). Это **разовая настройка** — не повторять каждый раз.

Дальше:

```powershell
openclaw.cmd configure
```

Установщик спросит:
- **Модель AI:** `1` (default — `openai-codex/gpt-5.4`) или другую
- **opencode.ai API-ключ:** найди в материалах курса (или в OpenAI/Anthropic консоли)
- **Telegram bot token (для main агента):** создан через `@BotFather`

После configure:

```powershell
openclaw.cmd gateway start
openclaw.cmd channels status --probe
```

Probe должен показать **зелёное «✓ ok»**. Если **красное** — иди в
правило 6 / 7 выше.

Открой Telegram, найди бота которого создавал, напиши `/start` —
должен ответить «Привет, я ...». Если ответил — **OpenClaw работает**,
переходи к Шагу 4.

### Шаг 4 — Установить AI-команду через Git Bash

> ⚠️ **Важно:** этот шаг — **в Git Bash**, не в PowerShell.

Открой **Git Bash** (Win → `git bash` → Enter).

#### Вариант A — через `curl | bash` (быстро если сеть стабильная)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh)
```

Если **через 30-60 секунд скрипт не скачался** или вылетает с
TLS / redirect ошибкой — переходи на Вариант B (он надёжнее).

#### Вариант B — через `git clone` (рабочий путь, рекомендуется на Windows)

```bash
cd ~
git clone https://github.com/tonytrue92-beep/openclaw-agents-pack
cd openclaw-agents-pack
bash scripts/install-agents.sh
```

Это надёжнее чем `bash <(curl)` потому что:
- Все файлы скрипта **локально**, ничего не тянется с raw.githubusercontent
- Можно повторять без перекачки
- Видно что скачалось — `ls scripts/`

### Шаг 5 — Пройти меню установщика

Установщик в Git Bash — **тот же что на macOS/Linux**. Просто работает:

1. Меню — выбери `1) Стандарт (3 агента)` или `2) VIP (6 агентов)`
2. **R1** — модель (обычно та же что для main)
3. **R1.5** — embedding-память (рекомендуется включить)
4. **R2** — токены ботов (создаёшь в `@BotFather`, по одному на агента)
5. **R5b** — общая TG-группа (опционально)

Все шаги — **в Git Bash**. Не переключайся в PowerShell посредине.

### Шаг 6 — Проверить что всё работает

```bash
# В Git Bash:
openclaw agents list
openclaw agents bindings
```

Должно показать всех установленных агентов и их роутинг.

В Telegram напиши **каждому** боту `/status` — все должны ответить
в течение 5-10 секунд.

---

## 🆘 Если что-то пошло не так

### `bash: command not found: openclaw` в Git Bash

PATH не обновился. **Закрой Git Bash и открой заново**. Если не
помогло — проверь PATH:

```bash
echo "$PATH" | tr ':' '\n' | grep -i openclaw
```

Должно содержать что-то типа `/c/Program Files/OpenClaw` или
`/c/Users/<username>/AppData/Local/OpenClaw`.

Если пусто — установщик OpenClaw не дописал PATH. Добавь вручную:

```powershell
# В PowerShell от обычного пользователя:
[Environment]::SetEnvironmentVariable("Path", "$env:Path;C:\Program Files\OpenClaw", "User")
```

И снова **закрой + открой** Git Bash.

### `command not found: bash` в PowerShell

Ты пытаешься запустить bash-скрипт в PowerShell. **Закрой PowerShell**,
открой **Git Bash** через Start menu.

### Установщик ругается «Не найден auth-profile»

См. правило **#4** выше. Не лечи руками — иди в первый установщик и
доведи `main` агента до состояния «отвечает в Telegram».

### Скрипт зависает на скачивании lib-файлов

Правило **#5**. Используй `git clone` вместо `bash <(curl)`.

### Бот молчит после `/start`

Правило **#6**:

```powershell
openclaw.cmd logs --tail 50 --follow
```

Напиши `/start` боту, читай логи. Самые частые причины:
- API-ключ модели исчерпан / неверный
- Routing rule перепутан (другому агенту маршрутизируется)
- DM allowlist блокирует — нет твоего TG ID в `allowFrom`

### `api.telegram.org` недоступен

Правило **#7**. Это сеть, не наш скрипт.

---

## ❓ FAQ для Windows

**Q: Можно ли всё сделать в PowerShell без Git Bash?**
A: Нет. Наш установщик второй ступени написан на bash и использует
`<(...)`, `curl`, `read -rs` и другие unix-конструкции. PowerShell
их не понимает. Альтернатива — WSL (Linux подсистема Windows).

**Q: WSL или Git Bash — что лучше?**
A: **Git Bash** проще: ставится за 5 минут, работает с Windows-OpenClaw
напрямую (через PATH).
**WSL** мощнее но сложнее: нужно поставить Ubuntu/Debian отдельно,
получить там доступ к Windows-OpenClaw (через `/mnt/c/...`),
работать с двумя файловыми системами.

Я рекомендую **Git Bash** для большинства клиентов. WSL — если уже
работаешь в Linux-окружении.

**Q: У меня корпоративный Windows с групповой политикой — установится?**
A: Скорее всего **нет**, без помощи админа. Symptoms:
- `Set-ExecutionPolicy` падает с «Group Policy disallowed»
- `npm install` в первом установщике лочится антивирусом
- PATH не записывается (write-protected)
Попроси админа снять ограничения **только для твоего профиля**, либо
ставь на личный ноут / VPS.

**Q: Можно ли поставить на Windows Server (RDP)?**
A: Да, если есть админ-доступ. Используй Git Bash. ExecutionPolicy
`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

**Q: Антивирус блокирует установщик OpenClaw**
A: Обычно ESET / Avast / Kaspersky показывают warning на `.exe` от
маленьких разработчиков. **Добавь в исключения** папку
`C:\Program Files\OpenClaw\` или временно отключи антивирус на
время установки.

**Q: Команды `curl`, `git`, `bash` нужны в обеих средах?**
A: Git Bash из коробки даёт `curl + git + bash`. В PowerShell
(после установки Git for Windows) `curl` и `git` доступны, но
`bash` — только через Git Bash. Для нашего скрипта PowerShell
не нужен после Шага 3.

**Q: Я уже всё установил через PowerShell когда-то — пропускать Git Bash?**
A: PowerShell мог поставить только OpenClaw (первая ступень). **Вторая
ступень (этот pack) всё равно требует Git Bash или WSL** — bash-скрипт
по определению.

---

## 📎 Ссылки

- [Git for Windows (Git Bash)](https://git-scm.com/download/win)
- [OpenClaw Windows installer](https://openclaw.ai/download/windows)
- [Windows Subsystem for Linux (WSL) гайд](https://learn.microsoft.com/windows/wsl/install)
- [docs/openai-key-setup.md](./openai-key-setup.md) — где взять OpenAI API-ключ
- [docs/vip-install-guide.md](./vip-install-guide.md) — общий VIP-гайд
- [docs/group-mode.md](./group-mode.md) — группа агентов
