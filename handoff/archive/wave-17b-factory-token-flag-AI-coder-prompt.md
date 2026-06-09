# Промпт для AI-coder — Wave 17b: `--course-token` флаг в factory

**Кому**: технарю Антона, у которого открыт `openclaw-factory` репозиторий
**Что делать**: скопируй промпт ниже целиком и вставь в Cursor / Claude Code /
Aider / GitHub Copilot Workspace. Агент закроет за 5 минут.

---

## ⤵️ Скопируй всё что между `BEGIN` и `END` и вставь в AI-coder

```
BEGIN PROMPT ─────────────────────────────────────────────────────

Ты работаешь в репозитории openclaw-factory. Задача: добавить
CLI-флаг --course-token и поддержку env-переменной COURSE_TOKEN
в scripts/demo-install.sh.

═══ КОНТЕКСТ ═══

Реальный VIP-клиент (Надежда Sagitova) теряет символы при ручном
вводе курс-токена с iPhone в Терминал. Wave 17 санитизация не
помогает — она убирает мусор (пробелы/тире), но не вставляет
обратно потерянные байты.

Единственный надёжный обход — передать токен как параметр
команды, чтобы клиент копировал ОДНУ длинную строку без шансов
потерять символ. Для этого установщик должен принимать токен
через флаг и/или env-переменную.

═══ ЧТО ДЕЛАТЬ ═══

1. Открой scripts/demo-install.sh.

2. Найди блок парсинга аргументов (обычно `while [[ $# -gt 0 ]]`
   с case'ами для --install, --dry-run, --vps и т.п.).

3. ПЕРЕД этим блоком добавь чтение env-переменной как fallback:

   COURSE_TOKEN="${COURSE_TOKEN:-}"

   Это позволит пользователю запускать как:
     COURSE_TOKEN=VIP-... bash scripts/demo-install.sh

4. ВНУТРЬ блока парсинга добавь четыре новых case'а:

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

   --vip-token)
     COURSE_TOKEN="${2:-}"
     shift 2
     ;;

   --vip-token=*)
     COURSE_TOKEN="${1#*=}"
     shift
     ;;

5. Убедись что переменная $COURSE_TOKEN передаётся в функцию
   получения токена как первый аргумент (preset). Должно быть
   что-то вроде:

   acquire_course_token_for_install "$COURSE_TOKEN" "$MACHINE_TG_ID"

   Если функция называется иначе — главное чтобы preset-токен
   из $COURSE_TOKEN попал внутрь. Если такого вызова нет — найди
   где функция вызывается и добавь $COURSE_TOKEN первым аргументом.

6. Обнови блок help (там где `--help` печатает Options:).
   Добавь две строки:

   echo "  --course-token TOKEN   Course-token from @AITeamVIPBot (skip R0 prompt)"

   И отдельным блоком после Options:

   echo ""
   echo "Environment variables:"
   echo "  COURSE_TOKEN           Same as --course-token (для CI/non-interactive)"

7. Подними INSTALLER_VERSION в начале файла. Поставь "2026.05.17"
   (или текущая дата если позже).

8. Сделай `bash -n scripts/demo-install.sh` — проверка синтаксиса
   должна пройти без ошибок.

9. Прогони smoke-тест если есть в репо (или запусти установщик
   локально с тестовым токеном чтобы убедиться что парсинг работает):

   bash scripts/demo-install.sh --course-token VIP-TEST-12345 --help
   # Должен показать help и не упасть

10. Закоммить:

    Wave 17b: --course-token флаг + COURSE_TOKEN env в demo-install.sh

    Триггер — продолжение кейса Надежды. Wave 17 санитизация не
    помогает когда клиент физически теряет символы при копировании
    с iPhone. Единственный надёжный обход — передать токен как
    параметр команды.

    Добавлено:
      • Флаг --course-token TOKEN (с алиасом --vip-token)
      • Поддержка --course-token=VALUE (knit-syntax)
      • Чтение COURSE_TOKEN из env как fallback
      • Help обновлён

    Аналогично openclaw-agents-pack где это с wave 12.

11. Создай PR на main.

═══ ЧТО НЕ ДЕЛАТЬ ═══

- НЕ меняй логику verify_vip_token / валидацию токена
- НЕ меняй формат токена / Ed25519-ключи
- НЕ убирай интерактивный prompt в R0 — он остаётся как fallback
  для тех кто не использует флаг
- НЕ занимайся token-first flow (вынос R0 выше меню) — это
  отдельный тикет
- НЕ занимайся wave 17 санитизацией — это отдельный тикет

═══ КАК ПРОВЕРИТЬ ЧТО РАБОТАЕТ ═══

После применения прогони 6 тест-кейсов:

  # 1. Флаг через пробел
  bash scripts/demo-install.sh --course-token VIP-TEST-12345 --help
  # → help, exit 0

  # 2. Флаг через =
  bash scripts/demo-install.sh --course-token=VIP-TEST-12345 --help
  # → help, exit 0

  # 3. Env-переменная
  COURSE_TOKEN=VIP-TEST-12345 bash scripts/demo-install.sh --help
  # → help, exit 0

  # 4. Help содержит новую опцию
  bash scripts/demo-install.sh --help | grep -- '--course-token'
  # → строка про --course-token найдена

  # 5. Невалидный флаг (без значения)
  bash scripts/demo-install.sh --course-token
  # → "ERROR: --course-token требует значение", exit 1

  # 6. Без флага (legacy interactive)
  echo "" | timeout 5 bash scripts/demo-install.sh
  # → начинает работу, доходит до R0 prompt (пустой stdin → таймаут — ОК)

═══ REFERENCE ═══

Готовая реализация в соседнем репо openclaw-agents-pack:
https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/scripts/install-agents.sh

Поиск: "--course-token)" — там case с shift 2.

END PROMPT ───────────────────────────────────────────────────────
```

---

## После применения фикса

1. AI-coder создаёт PR → технарь ревьюит → мержит
2. Технарь пишет Антону: «Wave 17b готов, версия factory: 2026.MM.DD»
3. Антон передаёт Надежде команду с зашитым токеном:
   ```
   bash <(curl -fsSL .../demo-install.sh) --course-token 'VIP-...'
   ```
4. Надежда копирует одной строкой → токен передан флагом → нет
   шансов потерять байт → R0 пропускается → установка идёт

## Fallback — если AI-coder не справился

Открой `handoff/wave-17b-factory-token-flag-brief.md` в этом же
репо — там пошаговый ручной патч с конкретными строками кода.
Это займёт ~10 минут вручную.
