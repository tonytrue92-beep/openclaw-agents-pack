# Бриф технарю — вернуть ChatGPT Codex-вход в factory (с тестом на чистой машине)

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

## Что нужно сделать

Заменить шаг «мозги» (сейчас opencode-ключ) на Codex-вход, но устойчиво:

### 1. Гарантировать провайдер-плагин ПЕРЕД `models auth login`
На чистой машине выясни точную команду (кандидаты — проверь по факту):
- `openclaw plugins install @openclaw/codex` (отдельный плагин, на моей
  машине лежал в `~/.openclaw/npm/.../@openclaw/codex`)
- или `openclaw plugins install <marketplace-name>` / `openclaw plugins enable <id>`

Проверка: после установки `openclaw models auth login --provider openai-codex`
не должен писать «No provider plugins found». Идемпотентно (повторный
запуск не ломает).

### 2. Сам вход
```bash
# TTY есть при обычной установке. На --vps добавить --device-code.
openclaw models auth login --provider openai-codex --set-default
```
`--set-default` сам ставит рекомендованную Codex-модель (GPT-5.4/5.5).

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
- [ ] провайдер-плагин ставится/включается перед login (не «No provider plugins found»)
- [ ] нет вызовов `err` (только `warn`/`echo`)
- [ ] fallback или мягкий повтор при неудаче входа (без exit 127)
- [ ] `--set-default` ставит Codex-модель
- [ ] протестировано на ЧИСТОЙ машине end-to-end
- [ ] bump `INSTALLER_VERSION`, `bash scripts/update-checksums.sh`, PR, CI зелёный

Когда готово и проверено на чистой машине — пиши Антону, смержим.
