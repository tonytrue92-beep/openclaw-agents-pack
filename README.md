# 🤖 OpenClaw Agents Pack

**Второй установщик** для курса Антона Полякова: добавляет поверх уже работающего OpenClaw трёх предустановленных агентов — **Технаря 🔧**, **Маркетолога 📈**, **Продюсера 🎬**. Каждый агент — в своём Telegram-боте.

> Это **надстройка** к первому установщику [openclaw-factory](https://github.com/tonytrue92-beep/openclaw-factory). Сначала нужно поставить OpenClaw оттуда, потом запустить этот установщик.

---

## 🚀 Быстрый старт

**Шаг 1 — убедись, что OpenClaw уже установлен:**

```bash
openclaw --version
# Если команда не найдена — сначала:
# bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh)
```

**Шаг 2 — создай три Telegram-бота через [@BotFather](https://t.me/BotFather)**:

Отправь `/newbot` трижды, получи три токена. Названия — на твой вкус
(например: «Мой технарь», «Мой маркетолог», «Мой продюсер»).

**Шаг 3 — запусти установщик агентов:**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh)
```

> 🛡 **Если raw.githubusercontent.com режется фаерволом / VPN / медленно**
> (типичная проблема на VPS и корпоративных сетях) — используй
> **self-contained bundle** из GitHub Releases:
>
> ```bash
> bash <(curl -fsSL https://github.com/tonytrue92-beep/openclaw-agents-pack/releases/latest/download/install-agents-bundled.sh)
> ```
>
> Один файл — никаких nested curl. Версия совпадает с последним
> релизным тегом. SHA256 — в файле `install-agents-bundled.sh.sha256`
> рядом с asset'ом.

Установщик спросит три токена, модель (по умолчанию `openai-codex/gpt-5.4`), проверит что OpenClaw жив, и за 3-5 минут развернёт всех трёх агентов. Напиши каждому боту — он ответит.

---

## 📦 Что внутри

### Три агента (средние сокращённые версии)

| Агент | Emoji | Что делает |
|-------|-------|-----------|
| **Технарь** | 🔧 | Помогает с техническими задачами — настройкой, отладкой, автоматизацией. Прагматичный, через логи. |
| **Маркетолог** | 📈 | Аналитический — помогает с контентом, воронкой, трафиком. Даёт одну лучшую рекомендацию, не «5 вариантов». |
| **Продюсер** | 🎬 | Практичный — помогает с запусками, продуктами, unit-экономикой. Через цифры и результаты. |

У каждого — свой `IDENTITY.md` (кто я), `AGENTS.md` (как работаю), `MEMORY.md` (что помнить), `USER.md` (инфа о тебе). Лежат в `~/.openclaw/workspace-<agent>/`.

### Флаги установщика

```bash
install-agents.sh                 # интерактивный режим (меню)
install-agents.sh --install       # сразу к установке всех трёх
install-agents.sh --vps           # для развёртывания на VPS
install-agents.sh --only tech     # поставить только одного
install-agents.sh --diagnose-only # проверить что все три живы (ничего не меняет)
install-agents.sh --collect-debug # собрать debug-bundle для саппорта
install-agents.sh --refresh-templates  # обновить шаблоны (IDENTITY/AGENTS/SOUL/LEARNING/skills) без потери MEMORY + USER
install-agents.sh --config <file> # неинтерактивно, читать токены из env-файла
install-agents.sh --version       # версия установщика
install-agents.sh --help          # полная справка
```

### Проверить целостность перед запуском

```bash
curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh -o install-agents.sh
shasum -a 256 install-agents.sh  # macOS
# или
sha256sum install-agents.sh       # Linux
# сравнить со значением в SHA256SUMS
bash install-agents.sh
```

---

## 📖 Документация

- [`docs/telegram-setup.md`](./docs/telegram-setup.md) — как создать три бота через @BotFather
- [`docs/architecture.md`](./docs/architecture.md) — как устроен роутинг bot → agent
- [`docs/vps-install.md`](./docs/vps-install.md) — установка на VPS (через `--vps`)
- [`docs/vip-install-guide.md`](./docs/vip-install-guide.md) — VIP-гайд (6 агентов с расширенными шаблонами)
- [`docs/troubleshooting.md`](./docs/troubleshooting.md) — если что-то сломалось
- [`CHANGELOG.md`](./CHANGELOG.md) — что нового в каждой версии

### MIT-атрибуция импортированных скиллов

VIP-агенты (Дизайнер, Координатор, Копирайтер) включают по 2 «smart
wrapper»-скилла, импортированных из репозитория
[awesome-openclaw-skills](https://github.com/VoltAgent/awesome-openclaw-skills)
под **MIT-лицензией**. Полный список авторов, ссылок на оригиналы и
текст лицензии — в [`templates/LICENSE-skills.md`](./templates/LICENSE-skills.md).

---

## 🔗 Связанные проекты

- **[openclaw-factory](https://github.com/tonytrue92-beep/openclaw-factory)** — первый установщик (ставит сам OpenClaw).
- **[OpenClaw](https://openclaw.ai)** — AI-шлюз между мессенджерами и языковыми моделями.

---

## 🧑‍💻 Контрибьюция

Это коммерческий артефакт курса, но баг-репорты приветствуются через GitHub Issues. Pull requests — только для правок в документации и бэкпортов фиксов из openclaw-factory.
