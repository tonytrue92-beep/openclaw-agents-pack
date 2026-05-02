# 🎫 Course-token v3 — бриф для технаря

**Дата:** 2026-05-02
**От:** Антон (через Claude)
**Для:** технарь (тот же что делал `@AITeamVIPBot` v2)
**Срок:** 1-2 недели
**Зависимость:** требуется новый payment-flow для Standard-клиентов

## TL;DR

Wave 12 в `openclaw-agents-pack` сделал **course-token mandatory** для любой свежей установки (Standard и VIP). До wave 12 Standard-клиенты ставились без авторизации — команду `bash <(curl)` мог скопировать кто угодно.

Чтобы это заработало end-to-end, нужно:
1. **Обновить `@AITeamVIPBot`** — добавить выдачу токенов Standard-клиентам.
2. **Обновить openclaw-factory `demo-install.sh`** — также требовать course-token.

## Что уже сделано на стороне agents-pack (wave 12)

- `scripts/lib/vip.sh` поддерживает **v3-формат** токена:
  ```
  TIER-<email_hash16>-<tg_user_id>-<signature_b64url>
  ```
  где `TIER ∈ {VIP, STD}`. Payload подписывается:
  ```
  <TIER>|<email_hash16>|<tg_user_id>
  ```
  То есть `tier` явно в payload — нельзя «переделать» STD-токен в VIP подменой prefix в строке.

- v2 (легаси VIP без явного tier) **продолжает работать** — `_verify_v3` с fallback на `_verify_v2`.

- `~/.openclaw/course-token` — кэш-файл с `chmod 600`, не просим токен дважды.

## Что нужно от тебя

### 1. Расширить `@AITeamVIPBot`

#### Текущее состояние

Бот принимает `/start` → email/phone → ищет в базе `vip` → выдаёт `VIP-<hash>-<tg>-<sig>`.

#### Нужно добавить

Расширить базу на **Standard**-клиентов. Структура:

```
vip_clients     — таблица оплативших VIP (как сейчас)
standard_clients — НОВАЯ таблица оплативших Standard
```

Логика выдачи:
```python
@bot.command("/start")
async def start(msg):
    email_or_phone = await ask("Введите email или телефон оплаты")

    # Ищем сначала в VIP — если там, выдаём VIP-токен
    if vip_clients.find(email_or_phone):
        token = sign_token("VIP", hash16(email_or_phone), msg.from_user.id)
        await msg.reply(f"Ваш VIP-токен: VIP-{...}-{tg}-{sig}")
        return

    # Если нет в VIP — ищем в Standard
    if standard_clients.find(email_or_phone):
        token = sign_token("STD", hash16(email_or_phone), msg.from_user.id)
        await msg.reply(f"Ваш Standard-токен: STD-{...}-{tg}-{sig}")
        return

    # Не нашли нигде
    await msg.reply("Email/phone не найден в списке оплативших...")
```

#### Подпись (Ed25519)

Тот же приватный ключ что у v2 (зашит в `scripts/lib/vip.sh` публичной частью). Payload теперь содержит tier:

```python
def sign_token(tier: str, email_hash16: str, tg_user_id: int) -> str:
    payload = f"{tier}|{email_hash16}|{tg_user_id}".encode()
    sig = ed25519_signing_key.sign(payload)
    sig_b64 = base64.urlsafe_b64encode(sig).rstrip(b'=').decode()
    return f"{tier}-{email_hash16}-{tg_user_id}-{sig_b64}"
```

**Public key не меняется** — установщик уже умеет проверять v3.

#### Заливка Standard-клиентов

Ты уже принимаешь CSV для VIP через `/admin_upload`. Нужна **аналогичная** команда для Standard:

```
/admin_upload_std → reply с CSV → парсим → standard_clients таблица
```

Формат CSV — тот же что для VIP (email, email_normalized, phone_normalized, phone_raw, paid_at, amount).

Антон **сам зальёт** Standard-клиентов первый раз — выгрузит из Prodamus, отфильтрует по «Товар содержит Standard», пришлёт CSV.

### 2. Обновить `openclaw-factory/scripts/demo-install.sh`

Сейчас первый установщик не требует токен — это значит злоумышленник может поставить **OpenClaw движок** + main-агент сам, без оплаты курса. Хотя без второго установщика «AI-команды» нет, но всё равно — Антон хочет полную защиту.

#### Что добавить

В начало `demo-install.sh` (после shell-gate):

```bash
# Course-token валидация (как в openclaw-agents-pack)
COURSE_TOKEN_CACHE="$HOME/.openclaw/course-token"
COURSE_TOKEN=""

# Если кэш есть и valid — используем
if [[ -f "$COURSE_TOKEN_CACHE" ]]; then
    COURSE_TOKEN=$(cat "$COURSE_TOKEN_CACHE")
fi

# Если нет — prompt с инструкцией
if [[ -z "$COURSE_TOKEN" ]]; then
    echo "Для установки OpenClaw нужен course-token."
    echo "Получи его в @AITeamVIPBot → /start → email/phone оплаты."
    read -r COURSE_TOKEN
fi

# Локальная Ed25519-валидация (см. vip.sh из agents-pack как референс)
verify_course_token "$COURSE_TOKEN" "$MACHINE_TG_ID" || {
    echo "Токен невалиден или просрочен. Получи новый в @AITeamVIPBot."
    exit 1
}

# Сохраняем в кэш для второго установщика (он его прочитает)
mkdir -p "$(dirname "$COURSE_TOKEN_CACHE")"
( umask 077; printf '%s\n' "$COURSE_TOKEN" > "$COURSE_TOKEN_CACHE" )
chmod 600 "$COURSE_TOKEN_CACHE"
```

**Альтернативный вариант:** просто скопируй `scripts/lib/vip.sh` и `scripts/lib/course-token.sh` из `openclaw-agents-pack` в `openclaw-factory` и source'и их.

### 3. Кэш-совместимость между установщиками

`~/.openclaw/course-token` — **общий** для обоих установщиков. Первый установщик пишет → второй читает (и наоборот при `--refresh-templates`).

После того как клиент успешно прошёл первый установщик с токеном → второй установщик автоматически использует тот же токен из кэша. Клиент не вводит дважды.

### 4. Кросс-чекинг в `@AITeamVIPBot`

Дополнительно (опционально): бот логирует **активации** через `POST /webhook/activation` (это уже есть — `vip_log_activation`). Сейчас оба установщика дёргают этот endpoint.

Расширь логику алертинга:
- Если **один и тот же `email_hash16`** активируется с **3+ разных IP** за неделю → algorт админу (старый функционал из v2)
- Если **token используется из IP не из той страны** что email-домен (например, `@yandex.ru` оплатил, а активирует с США) → soft-warn (это редкий, но возможный кейс шаринга)

## Тестирование

### Локально (без участия `@AITeamVIPBot`)

В `openclaw-agents-pack/scripts/smoke-test.sh` есть тестовые токены:

```bash
# v2 VIP-токен (legacy) — должен пройти как VIP
REAL_VIP_TOKEN="VIP-4EAF70B1F7A79796-123456789-Luu9d94qEEvJxrBZkQiRHJo2sdunPjmIh6SOAMh4aVyInPzMs3iDDV5tlJVGztUQk0P5wIIyESLtBUPbHzDEAw"
```

Для v3 нужен **новый** тест-токен — подписан тем же приватным ключом, но с tier-префиксом. Сгенерируй и пришли — добавим в smoke.

### End-to-end (после твоей работы)

1. Антон / тестовый клиент пишет `/start` боту
2. Получает токен
3. Запускает первый установщик — токен принимается, кэшируется
4. Запускает второй установщик — токен из кэша, проходит без вопросов
5. `--refresh-templates` через год — токен в кэше, проходит мгновенно

## Текущий статус и follow-up

### Сейчас
- `agents-pack` ждёт твою работу с ботом
- До тех пор клиенты `agents-pack` запускают с `--course-token VIP-...` (легаси VIP-токены работают)
- Standard-клиенты **не могут установить** пока ты не добавишь STD-токены в бот

### После твоей работы (примерно 1-2 недели)
- Антон зальёт CSV Standard-клиентов
- Standard-клиенты получают токены через `/start`
- Через 2 недели после этого — переименуем `install-agents.sh` → `install-agents-v2.sh`, на старом URL stub. Это **окончательно** убьёт «утёкшие» команды из чатов / постов / гайдов.

### Контакт
Любые вопросы — в саппорт-чат курса с Антоном.

## Связанные файлы (для референса)

В `openclaw-agents-pack`:
- `scripts/lib/vip.sh` — Ed25519-логика, v1/v2/v3 формат
- `scripts/lib/course-token.sh` — token cache + prompt + validation
- `scripts/install-agents.sh` — V1 step (вызов `acquire_course_token`)

Public key (зашит в `vip.sh`):
```
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAQIjPPB5LB1R3outrY1HMaVRVUB2tkDhHtpC8LLJ+8rA=
-----END PUBLIC KEY-----
```

Удачи 🚀
