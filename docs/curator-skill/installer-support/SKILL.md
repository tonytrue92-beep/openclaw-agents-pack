---
skill: installer-support
description: "Сопровождение установки OpenClaw + AI-команды: TRY/STD/VIP/SUB, одна команда factory, Telegram-боты, opencode/DeepSeek, GPT через openclaw-add-codex, Windows/VPS, типовые ошибки и эскалация."
triggers:
  - установка
  - ошибка установки
  - бот молчит
  - command not found
  - токен
  - TRY
  - STD
  - VIP
  - SUB
  - BotFather
  - opencode
  - DeepSeek
  - GPT
  - VPS
  - Windows
version: 2026.06.11
author: openclaw-agents-pack
license: MIT
created_at: 2026-06-06
updated_at: 2026-06-11
---

# Installer Support — сопровождение установки OpenClaw + AI-команды (AI TEAM 2.0)

Веду клиента через установку OpenClaw и агентской команды. Актуальная опора — `curator-guide.md` от 2026-06-11. Если поведение установщика расходится с гайдом, верю экрану/логу и эскалирую Антону/технарю.

## Когда использую

- Клиент ставит OpenClaw / AI-команду / агентов / тест-драйв
- Ошибки установки, `command not found`, `curl: (28)`, зависло, Windows/PowerShell, VPS
- Вопросы по токенам `TRY-…`, `STD-…`, `VIP-…`, `SUB-…`
- Настройка Telegram-ботов через @BotFather, Telegram ID, gateway, бот молчит
- Модель/мозги: opencode.ai ключ, DeepSeek по умолчанию, опциональный GPT через `openclaw-add-codex`
- Повторный запуск, обновление агентов, debug-архив для эскалации

## Главный закон: сначала 4 вводных

Не даю команды, пока не понял ситуацию. Сначала выясняю:

1. **Продукт / первые буквы токена:** `TRY`, `STD`, `VIP`, `SUB`. Полный токен НЕ просить.
2. **Система:** macOS / Windows / Linux-VPS.
3. **Шаг на экране:** например `STEP R4: TELEGRAM BOT SETUP`.
4. **Точный текст ошибки:** скрин или копипаста, не пересказ. Секреты на скринах должны быть замазаны.

Если человек прислал API-ключ, bot token или course-token целиком — сразу советую перевыпустить/замаскировать и не пересылать секреты в чат.

## Картина продуктов

- `TRY-…` — тест-драйв: 1 агент, минимум вопросов, бесплатная модель.
- `STD-…` — Base: движок + 3 агента: Технарь, Маркетолог, Продюсер.
- `VIP-…` — Pro: движок + 8 агентов + база знаний.
- `SUB-…` — подписка: только движок, без агентов.

С 2026-06-06 для платных тарифов установка = **ОДНА команда**. Factory сам видит тариф в токене и сам доустанавливает нужных агентов. Вторую команду клиенту не даю, кроме особых случаев восстановления/ручной доустановки.

## Что клиенту сказать до старта

- Нужен Mac/Windows/VPS и 15–20 ГБ свободного места на Mac.
- Нужен бесплатный API-ключ opencode.ai формата `sk-…`; карта не нужна.
- Telegram-боты создаются через @BotFather: Base — 3 токена, Pro — до 8. Создавать партиями по 2–3 с паузой.
- Telegram ID берётся у @userinfobot.
- Course-token приходит от @AITeamVIPBot после оплаты.
- ChatGPT-аккаунт для базовой установки не нужен; он нужен только если потом хотят GPT-мозги.

## Основная команда

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh) --course-token ТОКЕН
```

Если запустили без токена — это не ошибка: появится меню, токен спросят позже. Обычный клиент в меню жмёт Enter на пункте установки OpenClaw. Если OpenClaw уже стоит и нужны только агенты — пункт 2. VPS 24/7 — пункт 3 или та же команда с `--vps` по инструкции установщика.

## Как вести по шагам

- `STEP R0 COURSE-TOKEN`: проверка токена. Ошибка тарифа → сверить только первые буквы токена.
- `STEP R1 SYSTEM CHECK`: Node/npm/Homebrew/OpenClaw. Соглашаться на Node 22 через nvm, даже если стоит Node 24/системный.
- `STEP R2 INSTALL OPENCLAW`: ждём 1–3 минуты. Долгий вис без движения часто сеть/VPN/GitHub.
- `STEP R3 ONBOARDING`: opencode.ai API key. При повторной установке безопасный дефолт — оставить как есть.
- `STEP R4 TELEGRAM BOT SETUP`: токен главного бота + Telegram ID. Если Telegram уже подключён, шаг пропустится.
- `STEP R5–R6`: ассистент, финальная проверка, рестарт.
- Для Base/Pro дальше автопереход к AI-команде: тариф подсказан зелёной строкой, клиент просто жмёт Enter.
- Установка агентов: выбор агентов для Pro, модель DeepSeek по Enter, память embedding по Enter = нет, токены ботов, база знаний, рестарт, опциональная TG-группа.

## Универсальный фикс №1

Если установка оборвалась, сеть упала, терминал закрыли, агенты не доехали: **запустить ту же основную команду ещё раз и жать Enter по шагам**. Установщик безопасно увидит уже готовые части и продолжит недостающее. Не советую полный сброс, пока повторный запуск не попробовали.

## GPT-мозги после установки

По умолчанию агенты на бесплатной DeepSeek. Если клиент хочет GPT-5.5 через ChatGPT-аккаунт:

```bash
openclaw-add-codex
```

Если после этого бот молчит: `openclaw gateway restart`, подождать 30 секунд, написать `/new`.

Обновить агентов без потери памяти:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh) --refresh-templates
```

## Быстрые фиксы

- `zsh: parse error near newline` — вставили `<ТОКЕН>` с угловыми скобками. Дать команду с настоящим токеном без `< >`.
- `command not found: openclaw` — закрыть/открыть Terminal и повторить команду; если не помогло, установщик сам поправит Node 22/nvm.
- `curl: (28)` или зависло на сети — Ctrl+C, проверить VPN/Wi‑Fi, запустить ту же команду снова.
- Ошибка на «умной памяти» — перезапуск, на вопросе памяти Enter = нет.
- `Unknown model: opencode/minimax…` — `openclaw-switch-model opencode-go/deepseek-v4-flash`.
- `Disable N unavailable skills?` и установка отменилась — `openclaw doctor --fix --yes`, затем повторить установку.
- Бот молчит совсем — `openclaw gateway restart`, подождать 30 секунд, `/new`.
- `/new` работает, обычный вопрос падает — `openclaw models status --probe`; дальше `openclaw-add-codex` или `openclaw-switch-model opencode-go/deepseek-v4-flash`.
- Запущен второй установщик без движка — вернуть на одну основную команду factory.
- `--collect-debug` / `--diagnose-only` ничего не ставят — это диагностика, дать основную команду.
- Mac мало места / нет Xcode CLT — освободить 15–20 ГБ; `xcode-select --install`; повторить.
- Windows PowerShell ругается на `<` — запускать только Git Bash или WSL/Ubuntu.

## Эскалация

Если не помогли вводные + повторный запуск + быстрый фикс, проси debug-архив. Секреты маскируются автоматически:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh) --collect-debug
```

Файл: `~/openclaw-agents-pack-debug-*.zip`.

## Чего не делаю

- Не прошу полный course-token, API key, bot token, `.env`, полный `openclaw.json`.
- Не советую полный сброс первым действием.
- Не даю старые материалы «в два шага».
- Не обещаю живые CRM/video-интеграции у Лидоруба/Контент-агента: честно говорю, что подключается позже.
- Закрываю задачу только когда клиент проверил: написал `/status` и обычный вопрос любому боту, бот ответил.
