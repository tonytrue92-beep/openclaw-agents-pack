# 🚪 START HERE — OpenClaw Agents Pack Handoff

**Для кого**: новая сессия Claude (или я сам через неделю)
**Дата создания**: 2026-04-19

---

## Что это за проект

**Второй установщик OpenClaw** — ставится поверх уже работающего OpenClaw и
добавляет трёх предустановленных агентов: **Технарь 🔧 / Маркетолог 📈 / Продюсер 🎬**.

Репозиторий: https://github.com/tonytrue92-beep/openclaw-agents-pack (public)
Локально: `/Users/antonpolakov/git/openclaw-agents-pack/`

**Первый установщик** (базовый OpenClaw) — отдельная репа:
https://github.com/tonytrue92-beep/openclaw-factory (там в `Downloads/openclaw-installer-handoff/`
лежит его handoff — много полезного контекста про решения #1-17).

---

## Команда для клиентов

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh)
```

Требование: OpenClaw уже должен быть установлен (через первый установщик).

---

## Ключевые артефакты

| Путь | Что внутри |
|------|-----------|
| `scripts/install-agents.sh` | Главный скрипт (R1-R5: модель → токены → проверка коллизий → установка × 3 → gateway restart) |
| `scripts/lib/` | Вендорные helpers из первого установщика (ui / preflight / telemetry / debug-bundle / agents) |
| `scripts/diagnose-agents.sh` | `--diagnose-only` режим — проверка трёх агентов без изменений |
| `scripts/security-audit.sh` | 6 статических проверок, включая **что в templates/ нет личных данных автора** |
| `templates/{tech,marketer,producer}/{IDENTITY,AGENTS,MEMORY,USER}.md` | 12 шаблонов — средняя сокращённая версия агентов |
| `.github/workflows/ci.yml` | 6 jobs: shellcheck, bash -n, smoke, security-audit, checksums, docker (debian+alpine) |

---

## Ключевые решения

1. **Одна Telegram-установка = один агент** (роутинг через `accountId`). Клиент создаёт 3 бота через @BotFather.
2. **Модель по умолчанию: `openai-codex/gpt-5.4`** (то что сам Антон использует). Fallback — `opencode/minimax-m2.5-free`.
3. **Средняя сокращённая версия**: IDENTITY + AGENTS + MEMORY + USER, без SOUL/skills/MARKETING-MASTER.
4. **templates/ — БЕЗ личных данных автора**. Security-audit блокирует коммиты с `antonpolakov|tonytrue|vip-factory|openclaw-factory\b` в шаблонах.
5. **Vendored helpers, не `curl | source`** — избегаем рантайм-зависимости от сети и drift.
6. **VPS-режим `--vps`** с тем же поведением что в первом: skip macOS-проверок, SSH-tunnel инструкция.
7. **Commit-pin для templates** — при скачивании шаблоны привязаны к `INSTALLER_COMMIT`, чтобы не рассинхронизировать контент и скрипт.

---

## Как продолжить работу в новой сессии

Копируй промпт:

```
Продолжаю работу над установщиком openclaw-agents-pack (надстройка над
openclaw-factory). Контекст:

- Handoff этого репо: /Users/antonpolakov/git/openclaw-agents-pack/handoff/
- Handoff первого установщика: /Users/antonpolakov/Downloads/openclaw-installer-handoff/
- Решение #17 в первом handoff — почему сделали отдельный репо
- Публичный репо: https://github.com/tonytrue92-beep/openclaw-agents-pack

Прочитай handoff/00-START-HERE.md и жди указаний.
```
