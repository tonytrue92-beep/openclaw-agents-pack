# Changelog

История изменений в установщике OpenClaw Agents Pack.

Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/).

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
