# Бриф технарю — вернуть ChatGPT Codex-вход в factory (с тестом на чистой машине)

> ## ✅ РЕШЕНО (2026-06-08)
> Разобрались на машине клиента (OpenClaw **2026.6.1**): `openai-codex` —
> **legacy provider id**. Рабочий рецепт для **2026.6.x**:
> ```
> openclaw plugins install clawhub:@openclaw/codex   # или: @openclaw/codex
> openclaw plugins enable codex && openclaw plugins registry --refresh
> openclaw gateway restart
> openclaw models auth login --provider openai        # НЕ openai-codex! (+ --device-code если надо)
> openclaw models set openai/gpt-5.5 && openclaw gateway restart
> ```
> Зашито в **opt-in хелпер `openclaw-add-codex`** (factory `2026.06.06.2`,
> ставится в `~/.openclaw/bin/`). Клиенту — одна команда `openclaw-add-codex`.
> На стороне бота ничего не нужно. Ниже — историческое расследование (для контекста).

## Контекст

Хотим, чтобы платный установщик (**`openclaw-factory`**, шаг «мозги» / R3)
подключал модель через **вход в аккаунт ChatGPT** (Codex), а не через
API-ключ opencode.

Я это уже пробовал — и **откатил**, потому что на свежей машине клиента
оно падало (см. ниже). Сейчас в `demo-install.sh` снова рабочий
opencode-поток. Твоя задача — вернуть Codex-вход ПРАВИЛЬНО и проверить
на **чистой машине** (у меня её нет — поэтому я и обжёгся).

## Что именно падало (две причины — обе надо закрыть)

1. **`Error: No provider plugins found. Install one via openclaw plugins install`**
   при `openclaw models auth login --provider openai-codex`. На свежей
   установке OpenClaw провайдер-плагин для Codex **не загружен**. На моей
   машине он был → я не поймал.
2. **`err: command not found` → exit 127.** В `demo-install.sh` нет функции
   `err` (есть только `ok` и `warn`). Любой вызов `err` валит скрипт.

## ✅ Подтверждено в проде + найдена рабочая команда (2026-06-05)

Клиентка (Naila, свежий Mac, **OpenClaw 2026.6.1**) вручную попробовала
`openclaw models auth login --provider openai-codex` — получила ровно ту же
ошибку: `Error: No provider plugins found. Install one via openclaw plugins install`.

Разобрал по своей машине, **где провайдеры есть**, какой плагин что даёт:

| Плагин (npm spec) | id | Какие провайдеры | На свежей машине |
|---|---|---|---|
| `@openclaw/openai-provider` (**стоковый**, в `dist/extensions/openai/`) | `openai` | `openai`, **`openai-codex`** | НЕ загружен → ошибка |
| `@openclaw/codex` (ставится отдельно) | `codex` | `codex` (Codex-managed GPT catalog) | ставится через `plugins install` |

Вывод: `openai-codex` живёт в **стоковом** `@openclaw/openai-provider`, который
на чистой 2026.6.1 почему-то не подгружается. А вот `@openclaw/codex` — это
**отдельно устанавливаемый** Codex-провайдер (`Spec: @openclaw/codex`,
`openclaw plugins inspect codex` → «model provider plugin with a Codex-managed
GPT catalog»). Поэтому надёжный путь — ставить `@openclaw/codex` и логиниться
через **`--provider codex`** (а НЕ `openai-codex`).

Команда, которую дал клиентке (ждём подтверждения end-to-end):
```bash
openclaw plugins install @openclaw/codex
openclaw gateway restart
openclaw models auth login --provider codex --set-default
```

## Что нужно сделать

Заменить шаг «мозги» (сейчас opencode-ключ) на Codex-вход, но устойчиво:

### 1. Гарантировать провайдер-плагин ПЕРЕД `models auth login`
Основной путь (см. таблицу выше) — установить **`@openclaw/codex`** и
перезапустить gateway, чтобы плагин подгрузился:
```bash
openclaw plugins install @openclaw/codex   # идемпотентно
openclaw gateway restart                    # чтобы провайдер загрузился
```
Проверка: после этого `openclaw plugins inspect codex` показывает провайдер
`codex`, и `openclaw models auth login --provider codex` НЕ пишет
«No provider plugins found».

> Если по какой-то причине нужен именно `openai-codex` — его даёт стоковый
> `@openclaw/openai-provider`; на чистой машине проверь, грузится ли он
> (`openclaw plugins list`), и при необходимости `openclaw plugins enable openai`.
> Но проще и надёжнее идти через `@openclaw/codex` + `--provider codex`.

### 2. Сам вход
```bash
# TTY есть при обычной установке. На --vps добавить --device-code.
openclaw models auth login --provider codex --set-default
```
`--set-default` сам ставит рекомендованную Codex-модель (GPT-5.4/5.5).
(`--provider codex` — из установленного `@openclaw/codex`, а не `openai-codex`.)

### 3. Обработка ошибок — БЕЗ `err`
Используй `warn` (есть в factory) или `echo`. Никаких `err`. На неудаче —
не падать с exit 127, а:
- либо повторить (как сейчас в opencode-блоке),
- либо **fallback на opencode-ключ** (чтобы клиент в любом случае поставился).

### 4. Простое объяснение клиенту (RU)
Нужен аккаунт ChatGPT (бесплатного хватит; Plus $20 — умнее). Ссылку для
входа покажет сам `openclaw` — клиент открывает её и логинится. API-ключ
не нужен.

## Где менять
- Файл: `openclaw-factory/scripts/demo-install.sh`, шаг **R3 «ONBOARDING»**
  (блок, где сейчас `Вставьте API-ключ opencode.ai` + запись `auth-profiles.json`).
- Эталон моего откатанного кода (для справки, что я делал): factory PR #7
  «Brain via ChatGPT Codex login» (закрыт/откатан) — там видно структуру,
  но НЕ копируй слепо (там и был баг с `err` + без установки плагина).

## ⚠️ Обязательное условие — тест на ЧИСТОЙ машине
Главная причина прошлого фейла: тестировали на машине, где провайдер уже
стоял. Прогони полный сценарий на **свежей** ОС (или свежий `~/.openclaw`):
1. `bash <(curl -fsSL .../openclaw-factory/main/scripts/demo-install.sh)`
2. Дойти до шага «мозги» → вход в ChatGPT по ссылке от openclaw
3. Убедиться: `openclaw status` показывает Codex-модель, агент отвечает.
4. Проверить, что без аккаунта/при отмене — установщик НЕ падает (fallback/повтор).

## Чек-лист готовности
- [ ] `openclaw plugins install @openclaw/codex` + `gateway restart` перед login (не «No provider plugins found»)
- [ ] вход через `--provider codex` (не `openai-codex`)
- [ ] нет вызовов `err` (только `warn`/`echo`)
- [ ] fallback или мягкий повтор при неудаче входа (без exit 127)
- [ ] `--set-default` ставит Codex-модель
- [ ] протестировано на ЧИСТОЙ машине end-to-end
- [ ] bump `INSTALLER_VERSION`, `bash scripts/update-checksums.sh`, PR, CI зелёный

Когда готово и проверено на чистой машине — пиши Антону, смержим.
