# 🌐 Развёртывание agent-pack на VPS

Если сам OpenClaw уже поставлен на VPS через [первый установщик](https://github.com/tonytrue92-beep/openclaw-factory/blob/main/docs/vps-install.md),
второй этап — накатить поверх трёх предустановленных агентов.

---

## Предусловия

- VPS куплен (Timeweb / Beget / Hetzner / DigitalOcean — не важно)
- Ubuntu 22.04+ или Debian 12+
- `openclaw` уже установлен и gateway отвечает `running`
- У вас три Telegram bot токена (см. [`telegram-setup.md`](./telegram-setup.md))

Если OpenClaw ещё не стоит — сначала **первый установщик**:
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh) --vps --install
```

---

## Установка agent-pack на VPS

### Интерактивно

```bash
ssh root@<ip>
# внутри VPS:
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh) --vps --install
```

Ответите на вопросы (три токена + user ID), через 3-5 минут всё готово.

### Неинтерактивно через `--config`

Если ставите на несколько VPS или через ansible/terraform:

```bash
ssh root@<ip>
cat > /tmp/agents.env <<'ENV'
BOT_TOKEN_TECH=7111111111:AAXxxxxx...
BOT_TOKEN_MARKETER=7222222222:AAYyyyyy...
BOT_TOKEN_PRODUCER=7333333333:AAZzzzzz...
AGENT_MODEL=openai-codex/gpt-5.4
OWNER_TG_ID=975494053
ENV
chmod 600 /tmp/agents.env

bash <(curl -fsSL .../install-agents.sh) --vps --install --config /tmp/agents.env

# сразу удалить конфиг с токенами:
shred -u /tmp/agents.env
```

---

## Проверить что работает

```bash
bash <(curl -fsSL .../install-agents.sh) --diagnose-only
```

Должны быть зелёные галочки у всех трёх агентов. Затем напишите каждому боту
`/start` из Telegram — отвечают три разных агента.

---

## Dashboard через SSH-туннель

Dashboard OpenClaw работает на `127.0.0.1:18789` на вашем VPS — снаружи не
виден. Чтобы открыть у себя в браузере:

```bash
# На Mac/Windows (в НОВОМ окне терминала, не SSH):
ssh -L 18789:127.0.0.1:18789 root@<ip>
```

Пока эта команда висит — браузер: `http://127.0.0.1:18789`.

`Ctrl+C` в терминале — закрывает туннель. Бот продолжает работать.

---

## Отключиться не потеряв ботов

Просто `exit` в SSH. Боты работают как systemd-сервис — переживут ваш
logout, reboot VPS и так далее.

---

## Траблшутинг

Общие проблемы — в [`troubleshooting.md`](./troubleshooting.md).

Для VPS-специфичных:

- **Бот отвечает с задержкой 10-20 секунд** — обычно сеть VPS к
  провайдеру модели (OpenCode/OpenRouter). Попробуйте регион ближе, или
  модель со стабильным латентностью.
- **После `apt upgrade` OpenClaw сломался** — перезапустите gateway:
  `openclaw gateway restart`. Если не помогло — пройдите первый установщик
  снова (он обновит CLI без потери конфига).
- **Не могу подключиться по SSH после ребута** — зайдите через VNC-консоль
  провайдера (у всех есть). Проверьте `systemctl status sshd`.

---

## Обновить agent-pack на VPS

Просто запустите установщик ещё раз — он предложит переустановить:

```bash
bash <(curl -fsSL .../install-agents.sh) --vps --install
```

При коллизии агентов выберите «Пересоздать» — ваши USER.md и MEMORY.md
**не сохранятся** (перезапишутся шаблонами). Если хотите сохранить — сделайте
бэкап перед:

```bash
for a in tech marketer producer; do
  cp ~/.openclaw/workspace-$a/MEMORY.md ~/memory-$a.bak
  cp ~/.openclaw/workspace-$a/USER.md ~/user-$a.bak
done
# после переустановки — руками вернуть
```

(Эту задачу планируем автоматизировать флагом `--update-templates-only` в
следующих версиях.)
