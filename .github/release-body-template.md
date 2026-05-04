## OpenClaw Agents Pack — релиз

## 🍎 Для macOS — двойной клик (новинка, wave 13)

Скачай **`OpenClaw-Setup.dmg`** ниже → открой → запусти 2 файла
по очереди двойным кликом. Никакого терминала.

Внутри DMG:
- `1. Установить OpenClaw.command` — запусти первым
- `2. Установить AI-команду.command` — запусти вторым
- `README.txt` — инструкция (включая что делать с Gatekeeper-warning
  при первом запуске)

Полный гайд: [`docs/mac-install-guide.md`](https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/docs/mac-install-guide.md)

## 🐧 Для Linux / VPS / корп. сетей — bundled-installer

Один файл — без зависимости от `raw.githubusercontent.com`.
Стабильно работает где обычная команда падает.

```bash
bash <(curl -fsSL https://github.com/tonytrue92-beep/openclaw-agents-pack/releases/latest/download/install-agents-bundled.sh)
```

SHA256 — см. файл `install-agents-bundled.sh.sha256` в этом релизе.

## 💻 Стандартная команда (стабильная сеть)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh)
```

## 🪟 Windows

См. [`docs/windows-install-guide.md`](https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/docs/windows-install-guide.md) — Windows ставится по другому пути (Git Bash + нативный installer OpenClaw, без bash-скриптов в PowerShell).

---

### Подробности

См. [`CHANGELOG.md`](https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/CHANGELOG.md) в корне репозитория для списка изменений.
