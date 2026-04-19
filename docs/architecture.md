# 🏗️ Архитектура: один бот = один агент

Коротко о том, как работает роутинг Telegram ↔ агент в OpenClaw, чтобы было
понятно, зачем три разных токена от @BotFather и что происходит под капотом.

---

## Схема

```
┌─────────────────┐       ┌─────────────────┐       ┌─────────────────┐
│   Telegram      │       │   Telegram      │       │   Telegram      │
│   Bot «Technar» │       │   Bot «Marketer»│       │   Bot «Producer»│
│  token: 7111:…  │       │  token: 7222:…  │       │  token: 7333:…  │
└────────┬────────┘       └────────┬────────┘       └────────┬────────┘
         │                         │                         │
         │ polling/webhook         │                         │
         ▼                         ▼                         ▼
┌────────────────────────────────────────────────────────────────────────┐
│                      OpenClaw Gateway                                   │
│                      (127.0.0.1:18789, локально у клиента)             │
│                                                                         │
│   channels.telegram.accounts:                                          │
│     tech:      { botToken: 7111:…, dmPolicy: allowlist, … }            │
│     marketer:  { botToken: 7222:…, dmPolicy: allowlist, … }            │
│     producer:  { botToken: 7333:…, dmPolicy: allowlist, … }            │
│                                                                         │
│   Routing bindings:                                                    │
│     tech     <- telegram accountId=tech                                │
│     marketer <- telegram accountId=marketer                            │
│     producer <- telegram accountId=producer                            │
└────┬──────────────────────┬───────────────────────┬────────────────────┘
     │                      │                       │
     ▼                      ▼                       ▼
┌─────────────┐      ┌──────────────┐      ┌──────────────┐
│  Agent:     │      │  Agent:      │      │  Agent:      │
│  tech       │      │  marketer    │      │  producer    │
│  🔧         │      │  📈          │      │  🎬          │
│             │      │              │      │              │
│  workspace- │      │  workspace-  │      │  workspace-  │
│  tech/      │      │  marketer/   │      │  producer/   │
│    IDENTITY │      │    IDENTITY  │      │    IDENTITY  │
│    AGENTS   │      │    AGENTS    │      │    AGENTS    │
│    MEMORY   │      │    MEMORY    │      │    MEMORY    │
│    USER     │      │    USER      │      │    USER      │
└──────┬──────┘      └──────┬───────┘      └──────┬───────┘
       │                    │                     │
       │ запрос к модели    │                     │
       ▼                    ▼                     ▼
    ┌─────────────────────────────────────────────────┐
    │  LLM provider (OpenCode / OpenRouter / …)       │
    │  модель: openai-codex/gpt-5.4 (по умолчанию)   │
    └─────────────────────────────────────────────────┘
```

---

## Ключевые концепты

### `accountId`

В OpenClaw у каждого канала (telegram, whatsapp, discord…) можно быть
**несколько аккаунтов**. Telegram-бот = один аккаунт = один токен.
`accountId` — это имя аккаунта в конфиге. Мы используем имя агента
как accountId: `tech`, `marketer`, `producer`.

Это даёт детерминированный роутинг: сообщение из бота с accountId=`tech`
**всегда** идёт к агенту `tech`.

### `bindings`

Таблица маршрутизации `channel:accountId → agent`. Для нашей установки:

```
tech     <- telegram:tech
marketer <- telegram:marketer
producer <- telegram:producer
```

Создаётся командой:
```bash
openclaw agents add tech --bind telegram:tech
```

### `workspace`

Папка `~/.openclaw/workspace-<agent>/` со следующими файлами:

- `IDENTITY.md` — кто я (имя, роль, стиль)
- `AGENTS.md` — как работаю (правила, границы, куда передаю коллеге)
- `MEMORY.md` — что помнить про этот аккаунт/проект
- `USER.md` — кто такой пользователь (клиент заполняет про себя)

При каждом запросе агент читает их перед тем как ответить. Редактируете
вручную — меняется поведение.

### `auth-profiles.json`

`~/.openclaw/agents/<agent>/agent/auth-profiles.json` — файл с API-ключами
провайдера LLM (OpenCode / OpenRouter). Установщик копирует его из
основного агента `main`, который настроен первым установщиком.

---

## Что происходит при каждом сообщении

1. Пользователь пишет «привет» в Telegram-бот «Маркетолог».
2. Telegram отправляет update на webhook (или gateway забирает через polling).
3. Gateway видит `bot_token` → ищет в `channels.telegram.accounts` → находит
   accountId=`marketer`.
4. Проверка `dmPolicy`: в allowlist есть user_id отправителя? Если нет — игнор
   (или pairing-код).
5. Ищет в `bindings` маршрут: `marketer <- telegram:marketer` → направляет к
   агенту `marketer`.
6. Агент читает `workspace-marketer/IDENTITY.md` + `AGENTS.md` + `MEMORY.md`
   + `USER.md` — собирает системный промпт.
7. Отправляет запрос в LLM с системным промптом + сообщением пользователя.
8. Получает ответ → отправляет обратно через Telegram API.

---

## Почему именно эта схема

- **Изоляция**: один агент не видит переписку другого. Это делает их
  независимыми; можно параллельно писать про технику, маркетинг и продукт
  без смешения контекстов.
- **Гибкость**: можно сменить модель у одного агента, не трогая других:
  ```bash
  openclaw config set 'agents.list[N].model' '"opencode/claude-sonnet-4-5"' --strict-json
  ```
- **Простота**: в Telegram каждый бот выглядит как отдельный контакт — удобно
  переключаться и психологически, и технически (свайп влево/вправо между тремя
  чатами).

---

## Связанное

- [`docs/telegram-setup.md`](./telegram-setup.md) — как получить три токена
- [`docs/troubleshooting.md`](./troubleshooting.md) — что делать если роутинг
  не работает
- [Архитектура первого установщика](https://github.com/tonytrue92-beep/openclaw-factory/blob/main/docs/)
