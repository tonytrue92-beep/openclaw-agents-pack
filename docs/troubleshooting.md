# 🩺 Troubleshooting — если что-то сломалось

Базовые сценарии и готовые команды. Если ничего из списка не помогло —
собирайте debug-bundle и пишите в саппорт:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh) --collect-debug
```

---

## Бот не отвечает на сообщение

### 1. Проверьте что OpenClaw жив

```bash
openclaw gateway status
```

Должен ответить `running`. Если нет — перезапустите:

```bash
openclaw gateway restart
```

### 2. Запустите диагностику

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh) --diagnose-only
```

Покажет состояние всех трёх агентов: workspace, bindings, auth-profile.

### 3. Проверьте allowlist

По умолчанию `dmPolicy: allowlist` — бот отвечает только тем, чей
Telegram user ID в списке. Если вы ставили с флагом `--config` или
пропустили ввод user ID, вас там нет.

Узнать свой ID: напишите **@userinfobot** в Telegram.

Добавить себя в allowlist бота `tech`:

```bash
openclaw config set 'channels.telegram.accounts.tech.dmPolicy' allowlist
openclaw config set 'channels.telegram.accounts.tech.allowFrom' '["ВАШ_ID"]' --strict-json
openclaw gateway restart
```

То же для marketer / producer.

---

## Отвечает «не тот» агент

Если пишете боту Маркетолога, а отвечает Технарь (или наоборот) — сломан
роутинг. Проверьте:

```bash
openclaw agents bindings
```

Должно быть:
```
- tech     <- telegram accountId=tech
- marketer <- telegram accountId=marketer
- producer <- telegram accountId=producer
```

Если связки отсутствуют или перепутаны — пересоздайте:

```bash
openclaw agents bind --agent tech --bind telegram:tech
openclaw agents bind --agent marketer --bind telegram:marketer
openclaw agents bind --agent producer --bind telegram:producer
openclaw gateway restart
```

---

## Бот отвечает `HTTP 401: Invalid API key`

Auth-profile не скопирован или ключ устарел. Если установлен первый
установщик — используйте его helper:

```bash
openclaw-factory-reauth
```

(Появится интерактивное меню, перезапишет API-ключ opencode.ai, очистит
сессии, рестартит gateway.)

Если helper не ставился — вручную:

```bash
cp ~/.openclaw/agents/main/agent/auth-profiles.json \
   ~/.openclaw/agents/tech/agent/auth-profiles.json
chmod 600 ~/.openclaw/agents/tech/agent/auth-profiles.json
# то же для marketer / producer
openclaw gateway restart
```

---

## Бот отвечает `HTTP 401: Model is disabled`

Модель стоит, но `agents.defaults.model.primary` и `agents.list[i].model`
рассинхронизированы. Проверьте:

```bash
openclaw config get agents.defaults.model.primary
openclaw config get agents.list
```

Привести к одной модели у всех агентов:

```bash
# helper из первого установщика
openclaw-switch-model opencode/minimax-m2.5-free

# или вручную для каждого индекса:
openclaw config set 'agents.list[0].model' '"opencode/minimax-m2.5-free"' --strict-json
openclaw sessions cleanup --all-agents
openclaw gateway restart
```

---

## Хочу изменить поведение агента (тон, стиль, правила)

Редактируйте `AGENTS.md` или `IDENTITY.md` в его workspace:

```bash
# Mac: откроется в редакторе по умолчанию
open ~/.openclaw/workspace-marketer/AGENTS.md

# Linux:
nano ~/.openclaw/workspace-marketer/AGENTS.md
# или
xdg-open ~/.openclaw/workspace-marketer/AGENTS.md
```

После сохранения:

```bash
openclaw sessions cleanup --agent marketer
```

(Чистим кэш сессии, чтобы новые правила применились сразу.)

---

## Хочу чтобы агенты помнили больше контекста

Заполните `USER.md` (кто вы) и `MEMORY.md` (факты о проекте) в каждом
workspace. Агенты читают эти файлы перед каждым ответом.

```bash
open ~/.openclaw/workspace-tech/USER.md
open ~/.openclaw/workspace-tech/MEMORY.md
```

Чем конкретнее — тем точнее ответы.

---

## Хочу удалить одного агента и поставить заново

```bash
# Удалить конкретного:
openclaw agents delete marketer --yes
rm -rf ~/.openclaw/workspace-marketer

# Переустановить только его:
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh) --only marketer
```

---

## Хочу удалить всех трёх агентов

```bash
openclaw agents delete tech --yes
openclaw agents delete marketer --yes
openclaw agents delete producer --yes
rm -rf ~/.openclaw/workspace-tech ~/.openclaw/workspace-marketer ~/.openclaw/workspace-producer
```

Сам OpenClaw и основной агент `main` останутся на месте.

---

## Собрать debug-bundle для саппорта

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh) --collect-debug
```

Файл окажется в `~/openclaw-agents-pack-debug-*.zip`. Все токены и ключи
автоматически маскируются. Пришлите в саппорт — так быстрее всего разберём.

---

## На VPS (через `--vps`)

Вся симптоматика та же, но команды через SSH:

```bash
ssh root@<ip>
# и все те же команды diagnostics / restart
```

Debug-bundle собирается на VPS, забрать к себе:

```bash
# В новом терминале на Mac/Windows (не в SSH):
scp root@<ip>:/root/openclaw-agents-pack-debug-*.zip ~/Downloads/
```
