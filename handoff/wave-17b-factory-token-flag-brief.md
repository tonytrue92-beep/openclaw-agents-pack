# ТЗ: `--course-token` флаг и `COURSE_TOKEN` env в factory `demo-install.sh`

**Дата:** 2026-05-17
**Кому:** технарь Антона (`openclaw-factory`)
**Автор запроса:** Антон Поляков
**Приоритет:** 🚨 СРОЧНО (тот же горящий клиент — Надежда Sagitova)
**Estimate:** 10 минут работы

## TL;DR

Установщик должен принимать курс-токен **тремя способами**:
1. **CLI-флаг**: `--course-token VIP-...`
2. **Env-переменная**: `COURSE_TOKEN=VIP-... bash <(curl ...)`
3. Interactive prompt в R0 (как сейчас) — как fallback

Сейчас по факту работает только #3 (interactive). Это **критично**
для саппорт-кейсов: когда у клиента ломается копи-паста на мобильном
(реальный кейс — Надежда теряла символы при ручном вводе), мы не
можем передать ей готовую команду со встроенным токеном.

## Реальный мотив

Кейс Надежды (15-17.05.2026): её токен — валидный (мы проверили
криптографически на стороне agents-pack, `rc=0`), но при копировании
с iPhone в Telegram → Терминал она физически теряет символы
(пропала цифра `9` в hash, поплыли символы в подписи).

Wave 17 санитизация не помогает — она убирает мусор (пробелы /
тире / кавычки), но не вставляет обратно потерянные символы.

**Единственный надёжный обход** — передать токен как параметр
команды, чтобы клиент копировал ОДНУ длинную строку:

```bash
bash <(curl -fsSL .../demo-install.sh) --course-token VIP-...
```

Так Надежда копирует ВСЁ за один Cmd+C — нет шансов потерять
байт. Но для этого нужен флаг.

## Конкретный патч

### Шаг 1. Парсинг аргументов

В блоке парсинга флагов (обычно в начале `demo-install.sh`,
там где обрабатываются `--install`, `--dry-run`, и т.д.)
добавь два case'а:

```bash
# Уже должно быть выше:
COURSE_TOKEN="${COURSE_TOKEN:-}"   # ← важно: читаем env как fallback

while [[ $# -gt 0 ]]; do
  case "$1" in
    # ... существующие cases ...

    --course-token)
      COURSE_TOKEN="${2:-}"
      if [[ -z "$COURSE_TOKEN" ]]; then
        echo "ERROR: --course-token требует значение" >&2
        exit 1
      fi
      shift 2
      ;;

    --course-token=*)
      COURSE_TOKEN="${1#*=}"
      shift
      ;;

    # legacy alias для backward-compat с возможными старыми скриптами
    --vip-token)
      COURSE_TOKEN="${2:-}"
      shift 2
      ;;

    --vip-token=*)
      COURSE_TOKEN="${1#*=}"
      shift
      ;;

    # ... остальные cases ...
  esac
done
```

### Шаг 2. Передача в `acquire_course_token_for_install`

Убедись что переменная `$COURSE_TOKEN` передаётся в функцию
получения токена как preset (первый аргумент). Должно быть
что-то вроде:

```bash
acquire_course_token_for_install "$COURSE_TOKEN" "$MACHINE_TG_ID"
```

Если функция называется иначе — главное чтобы preset-токен из
$COURSE_TOKEN попал внутрь.

Если **preset не пуст и валиден** → функция должна **пропустить
R0 prompt** и сразу подтвердить токен. У вас это уже должно работать
(это стандартный паттерн с wave 12), но проверь.

### Шаг 3. Обновить help

```bash
echo "Options:"
echo "  --install              Skip menu, go to real install"
echo "  --dry-run              Simulate install (nothing changed)"
echo "  --vps                  Show VPS deployment guide and exit"
echo "  --course-token TOKEN   Course-token from @AITeamVIPBot (skip R0 prompt)"
echo "  --collect-debug        Collect debug-bundle (no token required)"
echo "  --diagnose-only        Check installation health (no token required)"
echo "  --help                 Show this help"
echo ""
echo "Environment variables:"
echo "  COURSE_TOKEN           Same as --course-token (для CI/non-interactive)"
```

### Шаг 4. INSTALLER_VERSION bump

Подними версию factory (например, `2026.05.17` или твоя следующая).

### Шаг 5. Commit

```
Wave 17b: --course-token флаг + COURSE_TOKEN env в demo-install.sh

Триггер — продолжение кейса Надежды Sagitova. Wave 17 санитизация
не помогает когда клиент физически теряет символы при копировании
с iPhone. Единственный надёжный обход — передать токен как параметр
команды, чтобы клиент копировал ОДНУ длинную строку без шансов
потерять байт.

Добавлено:
  • Флаг --course-token TOKEN (с алиасом --vip-token для legacy)
  • Поддержка --course-token=VALUE (knit-syntax)
  • Чтение COURSE_TOKEN из env как fallback (для CI/non-interactive)
  • Help обновлён

Аналогично openclaw-agents-pack где это с wave 12.
```

## Как протестировать (3 минуты)

```bash
# 1. Флаг через пробел
bash scripts/demo-install.sh --course-token VIP-TEST-12345
# Ожидаемое: установщик подхватит токен из аргумента, R0 не запросит

# 2. Флаг через =
bash scripts/demo-install.sh --course-token=VIP-TEST-12345
# Ожидаемое: то же что #1

# 3. Env-переменная
COURSE_TOKEN=VIP-TEST-12345 bash scripts/demo-install.sh
# Ожидаемое: то же

# 4. Без токена (legacy interactive — должно работать как раньше)
bash scripts/demo-install.sh
# Ожидаемое: R0 спросит ввод как сейчас

# 5. Невалидный флаг
bash scripts/demo-install.sh --course-token
# Ожидаемое: error "требует значение", exit 1

# 6. Help содержит --course-token
bash scripts/demo-install.sh --help | grep -- '--course-token'
# Ожидаемое: строка про --course-token найдена
```

## Что НЕ делать (out of scope)

- НЕ менять логику валидации токена (`verify_vip_token`)
- НЕ менять формат токена / Ed25519-ключи
- НЕ занимайся token-first flow (это **отдельный** бриф 13.05.2026)
- НЕ занимайся wave 17 санитизацией (это **отдельный** бриф 15.05.2026)
- НЕ убирай интерактивный prompt — он остаётся как fallback

## Reference

В нашем `openclaw-agents-pack` это сделано в `scripts/install-agents.sh`,
строка ~236:
```bash
--course-token)
  COURSE_TOKEN="${2:-}"
  shift 2
  ;;
```

Полностью: https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/scripts/install-agents.sh

## Что после деплоя

Когда задеплоишь — напиши Антону одну строку:
```
Wave 17b готов, флаг --course-token и env COURSE_TOKEN работают.
Версия factory: 2026.MM.DD
```

Антон передаст Надежде команду с зашитым токеном — она пройдёт
установку без копи-паста.
