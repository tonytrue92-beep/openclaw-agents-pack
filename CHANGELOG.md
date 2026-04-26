# Changelog

История изменений в установщике OpenClaw Agents Pack.

Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/).

---

## 2026-04-30 — Wave 10 (self-contained bundle для VPS / корп. сетей)

Wave 9 BUG-06 показал в сообщении ошибки `git clone` как fallback при
сбое `raw.githubusercontent.com`. Wave 10 идёт дальше — даёт **второй
канал доставки** установщика через GitHub Release CDN, минуя
`raw.githubusercontent.com` полностью.

Зачем: на VPS / корпоративных сетях / медленном интернете nested curl
к raw.githubusercontent.com часто падает с timeout (=BUG-06). Bundled
подход — один файл, никаких nested curl-ов после первого скачивания.

### Added

- **`scripts/build-bundle.sh`** — локальная утилита-сборщик. Берёт
  `scripts/install-agents.sh` + все `scripts/lib/*.sh` (6 модулей)
  и склеивает в один self-contained `dist/install-agents-bundled.sh`
  (~150 KB, ~3000 строк):
  - Использует sentinel-маркеры `=== BUNDLE_LIB_BEGIN ===` /
    `=== BUNDLE_LIB_END ===` в `install-agents.sh` чтобы найти где
    заменять `source/curl` блок на inline-контент.
  - Удаляет дубликаты `#!/usr/bin/env bash` и `set -euo pipefail`
    из lib-файлов (они уже есть в начале install-agents.sh).
  - Прогоняет `bash -n` на bundled-выходе, проверяет что валидный.
  - Печатает sanity-команды (`--version` / `--help`) для проверки.
- **`.github/workflows/release.yml`** — авто-публикация bundled-релиза:
  - Триггер: push тега `v2026.*` или `v2027.*`.
  - Sanity-check что тег совпадает с `INSTALLER_VERSION` в скрипте.
  - Подмена `__COMMIT_PLACEHOLDER__` на реальный short commit hash.
  - Запуск `scripts/build-bundle.sh`.
  - Sanity bundled `--version` / `--help`.
  - Генерация `install-agents-bundled.sh.sha256`.
  - GitHub Release с двумя assets и body из
    `.github/release-body-template.md`.
- **`.github/release-body-template.md`** — шаблон body для релизов
  (зачем bundle, две команды установки).
- **CI job `build-bundle`** в `.github/workflows/ci.yml` — на каждом
  PR проверяет что `scripts/build-bundle.sh` собирает валидный bundle
  и что в нём нет остатков `source ${SCRIPT_DIR}/lib/...` (защита от
  битой сборки).

### Changed

- **`scripts/install-agents.sh`** — добавлены sentinel-маркеры вокруг
  блока подключения lib/* (для build-bundle.sh).
- **`scripts/install-agents.sh`** — сообщение об ошибке curl при
  сбое `raw.githubusercontent.com` (wave 9 BUG-06) теперь указывает
  **bundled-URL как первое решение**, потом `git clone` как второе:
  ```
  Рабочее решение №1 — self-contained bundle (один файл, без nested curl):
      bash <(curl -fsSL https://github.com/.../releases/latest/download/install-agents-bundled.sh)
  Рабочее решение №2 — git clone репозитория и запустить локально: ...
  ```
- **`README.md`**: новый блок про bundled путь как fallback.
- **`docs/vip-install-guide.md`**: команда установки теперь имеет
  два варианта — обычный curl и bundle.
- **`docs/windows-install-guide.md`**: bundle стал Вариант B
  (рекомендуется), git clone сдвинут в Вариант C.
- **`docs/curator-cheatsheet.md`**: новый блок «Self-contained bundle»
  в команды-памятке + СЦЕНАРИЙ 6 переписан с приоритетом bundle.
- **`.gitignore`**: добавлено `/dist/` (build-артефакты не коммитим).
- **INSTALLER_VERSION** 2026.04.29 → 2026.04.30.

### Команда для клиента (новая)

```bash
bash <(curl -fsSL https://github.com/tonytrue92-beep/openclaw-agents-pack/releases/latest/download/install-agents-bundled.sh)
```

URL стабильный — `releases/latest/download/...` редиректится на
конкретный последний релиз.

### Verification

- `bash -n` всех скриптов: OK
- `scripts/smoke-test.sh`: 21/21 pass (+1 wave-10 ассерт-блок)
- `scripts/security-audit.sh`: 6/6 pass
- `bash scripts/build-bundle.sh` локально: собирает bundle ~150 KB,
  bundle проходит `--version` / `--help` / `--diagnose-only`.
- CI build-bundle job: будет проверен после merge.

### Что осталось (out of scope)

- Релиз `v2026.04.30` с bundled-asset — будет создан после merge
  через `git tag v2026.04.30 && git push --tags`. Workflow сам
  опубликует.
- Пост в чат VIP про bundled-команду — отдельно после релиза.

---

## 2026-04-29 — Wave 9 (system hardening: BUG-01/03/05/06 из техотчёта)

Куратор-агент собрал по реальным кейсам клиентов из чата ИИ Team
техотчёт от 2026-04-26 (источник:
`/Users/antonpolakov/openclaw-factory/agents/curator/tmp/openclaw-install-fix-report-2026-04-26.md`).
Главная боль не в «есть баги», а в том что **продукт даёт ложный
прогресс и не локализует слой сбоя** — саппорт ловит каскад
«токен невалидный / бот молчит / установщик завис / модель не
работает» под разными масками, хотя в основе один из 6 системных
классов.

Wave 9 закрывает **4 P0-класса в нашей зоне** — `openclaw-agents-pack`.
Остальные 3 (BUG-02 gateway.mode / BUG-04 provider+model key /
BUG-07 macOS UX) — эскалируются на технаря через
`docs/curator-cheatsheet.md`.

### Added — BUG-01: hard preflight базовых утилит

В `scripts/lib/preflight.sh` → `preflight_openclaw()` в самом начале
теперь проверяется наличие `bash`, `python3`, `curl` через
`command -v`. Если хоть одна утилита отсутствует — hard-stop с
**ОС-специфичной** инструкцией как поставить:

- На Windows (Git Bash) → ссылка на git-scm.com/download/win
- На macOS → `brew install <missing>`
- На Linux/WSL → `apt-get install -y <missing>`

Раньше клиент уезжал в R0 и висел там бесконечно с непонятной
ошибкой если в системе не было python3 или curl.

### Added — BUG-05: hard JSON validation `main/auth-profiles.json`

В `preflight_openclaw()` блок проверки auth-profile расширен:
1. **Файл существует** (как раньше — `[[ -f ]]`)
2. **Файл не пустой** (`[[ -s ]]`) — раньше `{}` или 0 байт проходили
3. **Валидный JSON** (через `python3 json.load`) — раньше любой мусор
   проходил
4. **Не пустой объект** — `len(d) == 0` или not dict → fail

При любом нарушении — hard-stop с прямой инструкцией:
> Не лечи файл вручную (это приведёт к 401 у новых агентов) —
> перезапусти первый установщик начисто.

Из техотчёта: «частый кейс ложного фикса — клиент сам создаёт `{}`
чтобы обойти отсутствие файла → потом получает 401 у новых агентов».

**Guard для `--refresh-templates`:** этот режим не использует
main/auth-profile для копирования, поэтому пропускает deep-validation
через флаг `SKIP_AUTH_PROFILE_CHECK=true`. Иначе клиент с битым main
не сможет даже refresh применить.

### Added — BUG-06: localized curl-error messages

Блок lib-fetch (~строки 270-300 в `scripts/install-agents.sh`) при
сбое curl на `raw.githubusercontent.com` теперь печатает:

```
ERROR: не смог скачать scripts/lib/<mod>.sh с GitHub raw.
       Хост: raw.githubusercontent.com
       Commit: <commit>
       Timeout: 10 сек

Возможные причины:
  • raw.githubusercontent.com временно недоступен или режется фаерволом
  • Корпоративный VPN / прокси не пропускает HTTPS к GitHub
  • Слишком медленное соединение (10 сек на файл не хватило)
  • Указанный коммит не существует на GitHub

Рабочее решение — скачать репозиторий целиком и запустить локально:
    git clone https://github.com/tonytrue92-beep/openclaw-agents-pack
    cd openclaw-agents-pack
    bash scripts/install-agents.sh

Локальный запуск минует raw.githubusercontent...
```

Раньше было голое «не смог скачать X» + `exit=28` без объяснения.

### Added — BUG-03: Telegram-канал self-test после R5

В `scripts/lib/agents.sh` новая функция `telegram_channel_self_test(account_id)`:
- Достаёт сохранённый токен через `openclaw config get`
- Пингует `getMe` через уже существующую `validate_telegram_token`
- Не печатает токен в stdout

В `scripts/install-agents.sh` сразу **после** `R5 gateway restart` для каждого
установленного агента:

```
Проверяю что каждый бот отвечает в Telegram (5-10 сек)...
✓ tech: бот отвечает
✓ marketer: бот отвечает
○ producer: бот НЕ отвечает (gateway running, но Telegram-канал лежит)

⚠️ Telegram-каналы не работают для: producer
Это означает: gateway запущен, но Telegram-токен/привязка не работает.
Не запускай reinstall — проблема в Telegram access layer. Что проверить:
  1. Токен бота в @BotFather (мог быть сброшен через /revoke)
  2. Бот не заблокирован тобой в Telegram
  3. api.telegram.org не блокируется фаерволом / VPN
  4. Запусти: openclaw channels status --probe
  5. Логи gateway: openclaw logs --tail 50 --follow
```

Раньше после R5 клиент видел только «Gateway: running» — но это не
гарантия что Telegram-канал работает.

`INSTALLED_LIST` сформирован раньше R5 (после R4 цикла), теперь доступен
для self-test и для R5b group-mode.

### Added — Эскалация на технаря в `docs/curator-cheatsheet.md`

Новая секция «Эскалация на технаря (вне нашей зоны)» со таблицей
симптом → BUG-класс → куда эскалировать. Покрывает 3 класса вне
нашей зоны:

- BUG-02 (gateway.mode / plugin-runtime-deps / typebox)
- BUG-04 (provider/model/key/auth-profile flow)
- BUG-07 (macOS / Homebrew / Xcode UX)

Со ссылкой на полный техотчёт. Куратор знает когда **не лечить**, а
сразу слать в backlog `openclaw-factory`.

### Changed

- **INSTALLER_VERSION** 2026.04.28 → 2026.04.29.
- **smoke-test.sh** — 8 новых ассертов (по одному на каждый под-фикс
  wave 9 + эскалация в curator).

### Verification

- `bash -n`: OK
- `scripts/smoke-test.sh`: 20/20 pass (+1 wave-9 ассерт-блок)
- `scripts/security-audit.sh`: 6/6 pass

### Live-testing план

После выкатки:
1. **BUG-01** — `PATH=/tmp bash scripts/install-agents.sh --diagnose-only`
   → должен упасть с указанием каких утилит не хватает
2. **BUG-05** — `echo '{}' > ~/.openclaw/agents/main/agent/auth-profiles.json`
   → запустить установщик → должен упасть **до** R0 с понятным сообщением
3. **BUG-06** — симулировать сетевой сбой → проверить что в сообщении
   есть `git clone …` команда
4. **BUG-03** — намеренно сломать токен в `openclaw config set` →
   запустить `--diagnose-only` или установщик → R5 self-test должен
   найти проблему и не предложить reinstall

### Что не сделано в wave 9 (out of scope)

- BUG-02 / BUG-04 / BUG-07 — переданы в backlog `openclaw-factory`
  через `curator-cheatsheet.md`
- P1 пункты (Windows quoting / health summary / macOS UX) — wave 10
- Self-contained payload (bundled archive вместо `git clone` fallback)
  — wave 10 если будет нужно

---

## 2026-04-27 — Wave 8.5 (шпаргалка для куратора курса)

Куратор курса (AI-агент или живой человек) — главная точка контакта
для клиентов с проблемами установки. Раньше у него не было единого
источника правды: документация раскидана по 5 файлам, версионная
история в CHANGELOG, типичные сценарии нигде не описаны.

### Added

- **`docs/curator-cheatsheet.md`** (~400 строк) — единая шпаргалка для
  куратора:
  - Главный принцип: «не лечи не разобравшись» (3 вопроса перед командой)
  - Карта документации (что когда давать клиенту)
  - Команды-памятка (установка / refresh / diagnose / debug-bundle / group-mode / embedding / version)
  - Шаги установщика по порядку (R0 / R1 / R1.5 / R2 / R2.5 / R3 / R4 / R5 / R5b)
  - **12 типичных сценариев клиентов** с готовыми ответами:
    1. Только что купил VIP / ничего не работает
    2. Уже стоит, как обновиться
    3. РФ-карта не принимается в OpenAI
    4. Бот в Telegram молчит после `/start`
    5. Установщик ругается на auth-profile
    6. Скачивание зависает / raw.githubusercontent тупит
    7. Хочу команду в общем TG-чате
    8. У меня Windows
    9. Embedding-память — что это, нужно ли
    10. Ноут + VPS на одной установке
    11. Удалить одного агента
    12. Поменялся VIP-токен / TG-аккаунт → эскалация на Антона
  - Что НЕ делать (5 anti-patterns: руками править openclaw.json,
    `auth-profiles.json`, «снеси и поставь заново», команды для не-той
    ОС, общие OpenAI-ключи)
  - Эскалация (debug-bundle → саппорт → Антон с описанием)
  - История версий (последние 8)
  - Раздел «Если ты — AI-куратор-агент» с ссылками для копирования
- **`scripts/smoke-test.sh`** — 1 новый ассерт на наличие
  `docs/curator-cheatsheet.md` (защита от случайного удаления).

### Why

В чате запрос Антона: «Дай ссылку для агента-куратора, чтобы он
понимал всё». Куратору нужен один документ, по которому он отвечает
на любой вопрос клиента — без этого он:
- даёт команды для не-той ОС (Mac-команды Windows-клиенту);
- советует «снеси всё и переустанови» (потеря MEMORY);
- говорит «карта может не пройти» вместо конкретного решения;
- лечит auth-profile вручную вместо первого установщика.

Шпаргалка кодифицирует best practices.

### Прямая ссылка для куратора

```
https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/docs/curator-cheatsheet.md
```

---

## 2026-04-27 — Wave 8.4 (РФ-карта warning + бот-ссылка прямо в R1.5)

В предыдущих версиях (wave 8.1 / 8.2) предупреждение «карта РФ не
пройдёт» и ссылка на бот для выпуска виртуальной зарубежной карты
были **только в docs/**. Установщик в шаге R1.5 этого не показывал.

Сценарий бага: клиент в RU проходит R1.5, идёт в OpenAI billing с
российской картой, получает отказ → не понимает что делать → пишет
в саппорт. Открыть `docs/openai-key-setup.md` ему не приходит в голову.

### Changed

- **R1.5 explain-блок** в `scripts/install-agents.sh` дополнен:
  ```
  ⚠️  Российская карта в OpenAI НЕ пройдёт (санкции, обхода нет).
  Самый быстрый способ выпустить виртуальную зарубежную карту:
     https://t.me/WantToPayBot?start=w17851188--GUSNM
  Или используй уже имеющуюся карту KZ/AM/GE/TR/ОАЭ/EU/US.
  ```
- **Sub-prompt при вводе ключа** (оба варианта — «тот же что для модели»
  и «отдельный») получили краткую строку с тем же ссылкой:
  ```
  РФ-карта НЕ пройдёт. Виртуальная зарубежная:
  https://t.me/WantToPayBot?start=w17851188--GUSNM
  ```
- **`scripts/smoke-test.sh`** — 1 новый ассерт: проверка что
  installer содержит ссылку на @WantToPayBot и явное предупреждение
  «Российская карта в OpenAI НЕ» (wave 8.2-8.4 защита от регрессии).
- **INSTALLER_VERSION** 2026.04.27 → 2026.04.28.

### Why

Антон в чате обратил внимание: ref-ссылка есть в docs, но **в установщике
её нет**. Клиент видит docs только если уже запутался — а должен видеть
прямо в момент когда установщик просит ключ. Исправлено.

---

## 2026-04-26 — Wave 8.3 (Windows-путь установки + 7 правил из success kit)

В предыдущих версиях `docs/vip-install-guide.md` и `workbook-source.md`
говорили клиенту «На Windows: Win → powershell» и потом давали
`bash <(curl)` команду. **Это неверно** — в PowerShell нет `bash`,
команда падает молча. Плюс OpenClaw на Windows ставится не bash-скриптом
factory, а нативным `.exe` installer'ом.

Wave 8.3 — фикс этой дыры: установщик распознаёт Windows-окружения,
печатает 7 правил из реального успешного кейса, доки переписаны под
правильный путь (Git Bash + нативный installer).

### Added

- **`scripts/lib/preflight.sh`** — две новые функции:
  - `detect_environment()` — возвращает `windows-bash` / `wsl` /
    `linux` / `macos` / `unknown` через `$OSTYPE` + `uname -r`.
  - `print_windows_hints()` — печатается **один раз** при первом
    `preflight_openclaw()` если детектировали Windows. Доносит
    4 главных правила из success kit Антона:
    1. Не запускать в PowerShell — Git Bash или WSL
    2. OpenClaw ставится официальным `.exe`, не bash-скриптом
    3. Если raw.githubusercontent тупит — `git clone` + `bash scripts/install-agents.sh`
    4. Не смешивать среды (всё в Git Bash, не половину в PowerShell)
- **`preflight_openclaw()` расширен** — если OpenClaw не найден и
  окружение `windows-bash`, печатается **другая** инструкция:
  скачать installer с openclaw.ai/download/windows + последовательность
  `openclaw.cmd configure → gateway start → channels status --probe`
  в **PowerShell**, потом возвращаться сюда (в Git Bash) для второго установщика.
- **`docs/windows-install-guide.md`** (новый, ~450 строк):
  - **7 правил** из success kit (вверху, чтобы не повторять грабли):
    1. Не `bash <(curl)` в PowerShell
    2. Если OpenClaw уже встал — не сносить, а идти по `openclaw.cmd configure → gateway start → channels status --probe`
    3. Не смешивать среды (Git Bash ↔ PowerShell)
    4. Не лечить вручную `auth-profiles.json` — добивать первый установщик
    5. Если raw.githubusercontent тупит — `git clone` + локальный запуск
    6. `channels status --probe` зелёный = проблема не в токене, смотри `openclaw.cmd logs --tail 50 --follow`
    7. Если не достучаться до api.telegram.org — это сеть/DNS (`Test-NetConnection`, `Resolve-DnsName`)
  - Полная пошаговая установка (Git Bash → нативный OpenClaw → PowerShell configure → Git Bash для agents-pack)
  - Раздел «Если что-то пошло не так» с типичными проблемами
  - FAQ из 7 вопросов (PowerShell без Git Bash, WSL vs Git Bash, корпоративный Windows, антивирус, …)

### Changed

- **`docs/vip-install-guide.md`** — Шаг 2 переписан: была одна
  команда «На Mac/Windows/VPS», теперь развилка с явным Windows-блоком
  ссылающимся на `docs/windows-install-guide.md`.
- **`docs/workbook-source.md`** — Модуль 1:
  - Шаг 1.1 для Windows переписан: «другой путь!» — сначала Git Bash
    + OpenClaw installer, потом Шаг 1.2-Windows вместо обычного 1.2.
  - Новый **Шаг 1.2-Windows**: установка OpenClaw через .exe + настройка
    в PowerShell с командами `openclaw.cmd configure / gateway start /
    channels status --probe`.
  - Модуль 3 шаг 3.1: добавлена развилка Mac/Linux vs Windows
    с двумя вариантами (curl-bash и git clone).
- **INSTALLER_VERSION** 2026.04.26 → 2026.04.27.
- **`scripts/smoke-test.sh`** — 1 новый ассерт: `docs/windows-install-guide.md`
  + `detect_environment` + `print_windows_hints` + `windows-bash/wsl` упоминания.

### Что увидит Windows-клиент при запуске

При `bash scripts/install-agents.sh` в Git Bash на Windows (даже если
OpenClaw не установлен):

```
🪟 Обнаружено окружение: Git Bash / MSYS
Несколько правил чтобы не получить -ой:
  1. Не запускайте этот скрипт в PowerShell/cmd — нужен bash.
  2. OpenClaw на Windows ставится официальным installer'ом
     (НЕ bash-скриптом factory). После установки команды
     запускаются как openclaw.cmd.
  3. Если raw.githubusercontent тупит — скачайте репо:
     git clone https://github.com/tonytrue92-beep/openclaw-agents-pack
     cd openclaw-agents-pack && bash scripts/install-agents.sh
  4. Не смешивайте среды: если запустили в Git Bash —
     все диагностические команды (которые установщик
     просит выполнить) тоже в Git Bash, не в PowerShell.

Полный гайд: docs/windows-install-guide.md в репо.
```

И **если openclaw не найден** — выдаст ссылку на нативный installer
(`https://openclaw.ai/download/windows`), а не на bash-скрипт factory.

### Why

Антон в чате прислал «success kit» из 7 правил после реального опыта
поддержки Windows-клиента. Они не были отражены ни в установщике, ни
в доках — клиенты на Windows натыкались на одни и те же грабли и
писали в саппорт. Это исправлено в wave 8.3.

---

## 2026-04-25 — Wave 8.2 (карты РФ + ref-ссылка на виртуальную карту)

Уточнение к wave 8.1. В первой версии было сказано «РФ-карты могут не
пройти, вот варианты». Это **неточно** — российские карты OpenAI не
принимает 100%. Переписал блок жёстче и добавил конкретный путь решения.

### Changed

- **`docs/openai-key-setup.md`** — раздел «Если карта не проходит (РФ-карты)»:
  - Заголовок: «Карты РФ — что делать (100% не работают напрямую)».
  - Прямой текст: «OpenAI **не принимает** карты выпущенные в России —
    это санкционное ограничение, обходного пути нет».
  - **Вариант 1** — реф-ссылка на бот для выпуска виртуальной зарубежной
    карты (Казахстан/Армения):
    `https://t.me/WhisperSummaryAI_bot?start=ref_1167075209` +
    пошаговая инструкция (открыть → выпустить → пополнить рублями →
    использовать в OpenAI billing).
  - **Вариант 2** — уже есть зарубежная карта (список не-санкционных стран).
  - **Вариант 3** — попросить друга с зарубежной картой.
  - Расчёт реальной стоимости в рублях (~1000-1500₽ первый раз,
    дальше 500-600₽ раз в год-два).
  - Явный «❌ что НЕ работает» список (МИР, криптокарты, российские BIN).
- **`docs/vip-install-guide.md`** — новый FAQ «У меня российская карта —
  что делать?» с краткой версией и ссылкой на бот.
- **`docs/workbook-source.md`** — Модуль 2, шаг 2.3: РФ-карта блок
  переписан на конкретный (открыть бот → выпустить → пополнить).

### Why

Антон в чате сказал: «Карты РФ не работают, это 100%. Нужно дать ссылку
на бот для выпуска виртуальной зарубежной карты». Учёл — гайд теперь
содержит **конкретное действие** вместо обтекаемых «варианты есть».

---

## 2026-04-25 — Wave 8.1 (инструкция «где взять OpenAI-ключ»)

Минорный hotfix для wave 8. В шаге R1.5 теперь есть **прямая ссылка**
на `https://platform.openai.com/api-keys` и краткая инструкция (4 шага),
чтобы клиент не зависал когда установщик попросит ключ.

### Added

- В **R1.5 explain-блок** добавлены 3 строки: ссылка на api-keys,
  краткая инструкция (войти → Create new secret key → скопировать → положить $5).
- В обоих местах ввода ключа (interactive sub-prompt) — короткая подсказка
  «где взять» с тем же URL.
- **`docs/openai-key-setup.md`** — полный пошаговый гайд (~250 строк):
  - Регистрация в OpenAI (или вход через существующий ChatGPT-аккаунт)
  - Создание API-ключа со скриншотами
  - Положить $5 на счёт + расчёт «сколько хватит»
  - Список прокси-сервисов для карт РФ (WireMo / PayPond / GetCard)
  - Проверка ключа через curl
  - Best practices безопасности (не публиковать, лимиты, отдельный ключ под embedding)
  - FAQ (10 вопросов)
- **`docs/vip-install-guide.md`** — новая FAQ-секция «Где взять OpenAI API-ключ для embedding?»
- **`docs/workbook-source.md`** — новый шаг **2.3** в Модуле 2 про получение
  OpenAI-ключа (со скриншотами `[SCREENSHOT: ...]`). Существующий «получить
  VIP-токен» сдвинут в 2.4. Все референсы (типа «из шага 2.3» в 3.2)
  обновлены до 2.4.

### Changed

- INSTALLER_VERSION 2026.04.25 → 2026.04.26.

---

## 2026-04-25 — Wave 8 (embedding-память opt-in + multi-agent в TG-группах)

Две независимо-выкатываемые фичи. Wave 8 не трогает ядро OpenClaw —
только конфигурирует то, что Gateway уже умеет (`memorySearch` и
`channels.telegram.accounts.*.groupPolicy`).

### Added — Feature 1: Opt-in embedding-память

- **Новый шаг R1.5 в установщике** между «выбор модели» и «токены ботов»:
  - Объяснение клиенту зачем нужна embedding-память (3-5 строк):
    без неё MEMORY.md читается целиком при каждом ответе → дороже и
    медленнее с ростом памяти. С ней — семантический поиск, копейки в
    месяц.
  - Меню «1) Включить (рекомендуется) / 2) Без embedding», default 1.
  - Sub-вопрос: использовать тот же OpenAI-ключ что для chat-модели,
    или ввести отдельный «cheap» ключ.
  - Валидация ключа через ping `/v1/embeddings` (5s timeout). На неудаче
    — retry / save-anyway / skip.
- **Новые CLI-флаги:** `--enable-embedding` (non-interactive, берёт ключ
  из `OPENAI_EMBEDDING_API_KEY` или `OPENAI_API_KEY`) и `--no-embedding`
  (пропустить шаг — для CI / скриптов).
- **Новые lib-функции в `scripts/lib/agents.sh`:**
  - `validate_openai_embedding_key(key)` — POST на `/v1/embeddings`.
  - `enable_embedding_for_agent(agent_id)` — пишет per-agent
    `agents.<id>.memorySearch.{enabled,provider,model}`.
  - `write_embedding_env_key(key)` — глобально один раз
    `env.vars.OPENAI_EMBEDDING_API_KEY`.
  - `index_agent_memory(agent_id)` — wrapper над `openclaw memory index`
    с heartbeat + `|| warn`.
  - `embedding_status_for_agent(agent_id)` — для diagnose.
- **Хук в R4** (после `copy_auth_profile_from_main`): если
  `EMBEDDING_ENABLED=true` — записываем env-key (один раз) + включаем
  embedding для агента + запускаем индексацию.
- **`--refresh-templates` НЕ трогает embedding-конфиг** — это
  пользовательская настройка, как MEMORY/USER.

### Added — Feature 2: Multi-agent TG-группы

- **Новый CLI-флаг `--enable-group-mode <chat_id>`** для уже установленных
  агентов:
  - Bypass'ит R0–R5, идёт в dedicated entrypoint.
  - Список агентов через `find_installed_agents()`.
  - Печатает чек-лист «BotFather privacy disable + админы + chat_id».
  - Спрашивает подтверждение.
  - Для каждого агента пишет `groupPolicy=allowlist`,
    `groupAllowFrom += chat_id` (дедуп через JSON-массив),
    `groups.<chat_id>.requireMention=true`.
  - Идемпотентно: повторный запуск с тем же chat_id не создаёт дубли.
- **Новый интерактивный шаг R5b** после установки агентов
  (только если ≥2 агентов установлено и не `--config` режим):
  - «Хочешь чтобы агенты работали как команда в общей TG-группе? [y/N]».
  - Default N (не пугаем).
  - На y → пошаговый чек-лист + ввод chat_id (regex `^-?[0-9]+$`).
  - На пустой ввод — отложено: точная команда для запуска позже.
- **Новая lib-функция `configure_group_membership(agent_id, chat_id)`**.
- **Блок «## Если ты в группе с другими агентами» во все 6 AGENTS.md:**
  правила тегания (только @-mention или reply), делегирования по
  ролям. Координатор получает дополнительную строку «я главный по
  координации».
- **`docs/group-mode.md`** — полный гайд: зачем, как настроить
  (BotFather privacy disable + добавление ботов админами + получение
  chat_id), типичные сценарии (утренний брифинг, запрос на продакшн),
  типичные проблемы, откат.

### Changed

- **`scripts/diagnose-agents.sh`:**
  - Раньше итерировал по жёсткому списку `tech / marketer / producer`.
    Теперь динамически определяет какие установлены через
    `openclaw agents list` (поддерживает 3 / 5 / 6 агентов).
  - Добавлены строки **embedding** и **group-mode** в диагностический
    вывод (зелёный / серый / жёлтый).
- **`templates/<agent>/AGENTS.md`** — добавлен блок про работу в группе
  (все 6 ролей).

### Что нужно от клиента вручную (нельзя автоматизировать)

- **Privacy mode у каждого бота** через `@BotFather` → `/setprivacy` →
  `Disable`. Иначе бот в группе видит только сообщения адресованные ему.
- **Создать TG-группу** и добавить ботов как админов.
- **Узнать chat_id** через `@username_to_id_bot` или из URL супергруппы.

### Что под капотом (для Антона / технаря)

- OpenClaw v2026.4.22+ уже поддерживает `memorySearch` (OpenAI
  text-embedding-3-large + sqlite-vec) и `channels.telegram.accounts.*.
  {groupPolicy,groupAllowFrom,groups,requireMention}`. Wave 8 — это
  тонкая UX-обёртка над тем что уже умеет Gateway.
- Watermark из IDENTITY.md (wave 3) не задействован — embedding и
  group-mode не нуждаются в TG-binding'е VIP-токена.

### Verification

- `bash scripts/smoke-test.sh` — 18/18 pass (13 старых + 5 новых wave-8
  ассертов).
- `bash scripts/security-audit.sh` — 6/6 pass.
- `--refresh-templates` не пишет `memorySearch` (verify через `bash -x`).
- Live-тест embedding: dump в MEMORY.md → переиндексация → запрос с
  перефразированной формулировкой → должна быть сослана на сохранённый
  факт.
- Live-тест group-mode: 2 бота в группе, один тегает другого — оба
  отвечают.

---

## 2026-04-23 — Wave 7 (безопасное обновление шаблонов: `--refresh-templates`)

Для клиентов у которых уже стоят агенты, и которые хотят получить новые
шаблоны (SOUL.md, LEARNING.md, обновлённые skills) **без потери MEMORY.md
и USER.md**. Раньше апдейт требовал полной переустановки с потерей
накопленного контекста — это блокировало обновления у тех кто уже
наработал данные.

### Added

- **Новый флаг `--refresh-templates`** (неинтерактивный):
  ```bash
  bash <(curl -fsSL .../install-agents.sh) --refresh-templates
  ```
  Находит все установленные агенты через `openclaw agents list`, идёт
  по каждому, обновляет шаблоны. Не спрашивает токены / модель /
  каналы. Не нужен VIP-токен.

- **Новый пункт меню в R0 (interactive)**:
  Когда установщик видит что все целевые агенты уже стоят (сценарий
  OVERWRITE), теперь предлагается **3 варианта** вместо 2:
  1. **Обновить шаблоны** (default, безопасно) ← новое
  2. Перезаписать начисто (как раньше, с потерей MEMORY.md)
  3. Ничего не делать

  Старый default «Перезаписать» заменён на «Обновить» — это то что
  в 90% случаев нужно клиенту после выхода новой версии. Кто хочет
  clean reinstall — явно выбирает пункт 2.

- **Бэкапы перед перезаписью**: при любом refresh старые файлы
  сохраняются в `~/.openclaw/workspace-<agent>/.backups/<YYYYMMDD-HHMMSS>/`.
  Если новая версия шаблона что-то сломала — откатиться одной командой:
  ```bash
  cp ~/.openclaw/workspace-designer/.backups/20260423-143022/* \
     ~/.openclaw/workspace-designer/
  ```

### Changed

- **`scripts/lib/agents.sh`** — `prepare_workspace_from_templates()` теперь
  принимает третий аргумент `mode` (`full` | `refresh`):
  - `full` (default, поведение как раньше): качает все 4 md-файла +
    VIP-extras, генерит новый watermark из VIP_TOKEN.
  - `refresh`: качает только **системные** файлы (IDENTITY, AGENTS,
    SOUL, LEARNING, skills) — MEMORY.md и USER.md **не трогает**.
    Сохраняет существующий anti-sharing watermark (из старой IDENTITY.md),
    не перевыпускает — для refresh VIP-токен не нужен.

- **Новая функция `find_installed_agents()`** — итерируется по
  известным ID и возвращает список установленных. Используется
  `--refresh-templates` чтобы не спрашивать клиента.

### Что защищено при refresh

- **MEMORY.md** — контекст накопленных сессий (сработавшие заголовки,
  стоп-слова, история задач) — **не трогается**.
- **USER.md** — ответы клиента на онбординг (ниша, ЦА, тон) —
  **не трогается**.
- **Auth-profile** — `~/.openclaw/agents/<id>/agent/auth-profiles.json` —
  **не трогается**.
- **Telegram channel binding** + `dmPolicy`/`allowFrom` настройки —
  **не трогаются**.
- **Anti-sharing watermark** (wave 3) — переносится из старой
  IDENTITY.md в новую как есть.

### Upgrade scenario

- **Клиенты wave 5 / 6** → запускают тот же `curl | bash`, выбирают
  пункт 1 «Обновить шаблоны» (или сразу `--refresh-templates`) →
  получают новые SOUL/LEARNING/skills при сохранённых MEMORY/USER.
- **Новые клиенты** → всё как раньше, свежая установка через
  wave 6 шаблоны.
- **Standard-клиенты** → тоже получают обновление IDENTITY + AGENTS
  (SOUL/LEARNING/skills у них нет — они только для VIP).

### Verification

- `bash scripts/smoke-test.sh` — добавлен wave-7 тест (проверка что
  refresh mode и `--refresh-templates` на месте).
- `bash -n scripts/install-agents.sh` — OK.
- `--refresh-templates` на свежей машине без агентов → корректно
  выходит без ошибок с подсказкой «сначала обычная установка».

---

## 2026-04-22 — Wave 6 (VIP-агенты становятся умнее: SOUL + LEARNING + skills/)

### Added

Три VIP-агента (Дизайнер, Координатор, Копирайтер) получили **расширенный
набор шаблонов** — теперь это не «роль + правила», а полноценные
AI-сотрудники с явным характером, накопленным опытом и готовыми
инструментами:

- **`SOUL.md`** (по одному на агента) — personality, границы
  компетенции, правила автономии (`plan → approve → execute` для
  опасных операций, `do-it-now` для безопасных), протокол
  взаимодействия с командой, **онбординг-протокол** — 5-6 коротких
  вопросов при первой встрече чтобы заполнить USER.md живыми
  данными вместо плейсхолдеров.

- **`LEARNING.md`** (предзаполненный, по одному на агента) —
  5 правил в формате `[CORRECTION] → [CORRECT] → [RULE]`. Примеры:
  - Дизайнер: «Визуал без брифа = мусор — перед работой сверка с Маркетологом»
  - Координатор: «Не "я сделаю" — "я назначу и проконтролирую"»
  - Копирайтер: «Один сильный вариант > пять средних»

  Плюс раздел «Сюда запиши свои уроки» — клиент может дописывать
  свои корректировки в том же формате.

- **`skills/*/SKILL.md`** (по 2 на агента, 6 всего) — импортированные
  из [awesome-openclaw-skills](https://github.com/VoltAgent/awesome-openclaw-skills)
  под MIT-лицензией «smart wrappers»: краткое описание когда
  применять + attribution + ссылка на оригинал для полной установки:
  - **Дизайнер**: `eachlabs-image-generation` (@eftalyurtseven),
    `color-palette` (@qrost)
  - **Координатор**: `agent-collaboration-network` (@neiljo-gy),
    `close-loop` (@clarezoe)
  - **Копирайтер**: `reef-copywriting` (@staybased) — 6 фреймворков
    (PAS/AIDA/FAB/BAB/4P/Star-Story-Solution), `brand-voice-profile`
    (@dimitripantzos)

- **`templates/LICENSE-skills.md`** — единый attribution-manifest со
  ссылками на авторов всех 6 импортированных скиллов + текст MIT-лицензии.

### Changed

- **`scripts/lib/agents.sh`** — `prepare_workspace_from_templates()`
  теперь скачивает расширенные шаблоны (`SOUL.md`, `LEARNING.md`,
  `skills/*/SKILL.md`) **только** для `designer / coordinator /
  copywriter`. Остальные 3 агента (`tech / marketer / producer`)
  получают базовый набор как раньше. Если VIP-extras не докачались
  — `warn`, но установку не прерываем.

- **`templates/<vip_agent>/IDENTITY.md`** и **`AGENTS.md`** — блок
  **Session Startup** (читать файлы в порядке `IDENTITY → SOUL →
  USER → LEARNING → MEMORY → skills`) и секция **«Первый контакт
  (онбординг)»** со списком вопросов под роль.

- **CI-тесты** (`tests/docker/run-checks.sh`, `scripts/smoke-test.sh`,
  `scripts/security-audit.sh`):
  - Docker smoke принимает template count **37** (wave 6) в дополнение
    к историческим 12/24.
  - smoke-test.sh добавлены 3 новых проверки: SOUL+LEARNING существуют,
    6 SKILL.md на месте, AGENTS.md содержит Session Startup + онбординг.
  - security-audit check #6 расширен новыми паттернами (`serditov`,
    `TRUE AI AGENCY`, `СРАБОТАЛО`, `СВЯЗКИ`, `instapol2136`,
    `ntn_ / cpk_ / pat_FL`-префиксы API-ключей) для защиты от случайной
    утечки личных данных автора при добавлении нового контента.

### Upgrade scenario

- **Новые VIP-клиенты** — получают все расширенные шаблоны автоматически.
- **Уже установленные VIP-клиенты с 5-6 агентами** — R0 при повторном
  запуске увидит что агенты есть, предложит «Перезаписать начисто
  (потеря MEMORY.md)» или «Дополнить недостающих». Для текущих wave-5
  клиентов расширение уже стоящих агентов (добавление SOUL+LEARNING
  без потери MEMORY) требует флага `--refresh-templates` — он придёт
  в wave 7, если будет запрос.
- **Standard-клиенты** (3 агента: tech/marketer/producer) — никаких
  изменений, базовый набор как раньше. Расширения только для VIP.

### Что это даёт клиенту

- **Онбординг при первом контакте**: агент не пишет «обобщённо
  про эксперта», а задаёт короткие вопросы и записывает ответы
  в USER.md. Первая же задача решается с контекстом.
- **Предзаполненный опыт**: LEARNING.md с 5 правилами на роль — агент
  уже «знает» что не делать (типовые грабли копирайтера, дизайнера,
  координатора). Меньше итераций правок.
- **Готовые инструменты**: skills/ дают агенту чёткую инструкцию
  «если задача X — применяй фреймворк Y». Плюс возможность
  апгрейднуть до полной версии через `clawhub install <skill>`.

### MIT-attribution

Все импортированные скиллы — MIT. Оригинальный репозиторий:
[github.com/VoltAgent/awesome-openclaw-skills](https://github.com/VoltAgent/awesome-openclaw-skills)
/ каталог [clawskills.sh](https://clawskills.sh). Список авторов и
оригинальных ссылок — в `templates/LICENSE-skills.md`.

---

## 2026-04-22 — Wave 5 (шестой VIP-агент: Копирайтер ✍️)

### Added

- **Шестой VIP-агент: ✍️ Копирайтер.** Пишет продающие тексты, заголовки,
  посты, сценарии Reels, лид-магниты. Работает в паре с Маркетологом
  (смыслы) и Дизайнером (визуал). Шаблоны в `templates/copywriter/`:
  - `IDENTITY.md` — роль, границы (что делает, что отправляет коллегам)
  - `AGENTS.md` — workspace rules + список форматов которые знает
    (TG-пост, Reels, лендинг, рассылка, welcome-цепочка, заголовок, lead magnet)
  - `MEMORY.md` — рабочая память: твой голос, стоп-слова, сработавшие
    заголовки, словарь клиента
  - `USER.md` — пустой шаблон «заполни сам»: ниша, ЦА, тон, запреты

- VIP-набор теперь **6 агентов** (было 5): Технарь + Маркетолог +
  Продюсер + Дизайнер + Координатор + Копирайтер.
- В `install-agents.sh`: emoji+label для copywriter, добавлен в
  `--only` список, в `AGENTS_TO_INSTALL` для VIP-режима, в текстах
  меню. При выборе `--only copywriter` автоматически включается
  VIP_MODE (как с designer/coordinator).

### Changed

- Docker smoke ожидает **12** (Standard) или **24** (VIP) md-файлов
  в templates/ вместо 12/20.
- Гайд `docs/vip-install-guide.md` обновлён: «5 агентов» → «6», в
  таблице добавлена строка с Копирайтером, пересчитана длительность
  установки (+1 бот = +1 минута).

### Upgrade scenario (важно)

Клиенты, у которых уже стоят 5 VIP-агентов, при повторном запуске
установщика увидят **R0 = UPGRADE** (благодаря коммиту `045fd7d`):

```
🔼 Обнаружен апгрейд:
Уже установлены (будут сохранены):
   ✓ tech, marketer, producer, designer, coordinator
Не хватает (будут добавлены):
   + copywriter

Выбор [1/2/3, Enter = 1]:   ← default «Дополнить»
```

Нажатие Enter → ставится только copywriter, существующие пятеро не
трогаются (их MEMORY.md, подключённые Telegram-боты, personalized
настройки сохраняются). В R2 запрашивается один токен — для бота
Копирайтера, а не все 6.

Для новых VIP-клиентов (свежая установка) — сразу все 6, как раньше
было 5.

---

## 2026-04-21 — Wave 4 (smart upgrade Standard → VIP)

### Changed — R3 перенесён в R0, default теперь зависит от сценария

Раньше при повторном запуске (клиент уже ставил 3, теперь апгрейдится до
VIP) установщик по умолчанию **сносил всех и ставил заново**. Это теряло
накопленную MEMORY.md трёх исходных агентов, заставляло клиента заново
подключать ботов.

Новая логика в R0 (переименован из R3, перенесён ДО R2 чтобы не спрашивать
лишние токены):

- **FRESH** (никого нет) → ставим всех из `AGENTS_TO_INSTALL` без вопросов.
- **UPGRADE** (часть стоит, часть не хватает — типично Standard → VIP):
  default = «Дополнить недостающих, существующих не трогать». Альтернатива
  «Перезаписать всех» осталась как опция 2. `AGENTS_TO_INSTALL` сразу
  фильтруется до missing, и в R2 клиент вводит только 2 новых токена
  (designer + coordinator), а не все 5.
- **OVERWRITE** (все агенты из списка уже стоят — клиент чинит/обновляет):
  default = «Перезаписать начисто».

R3 теперь — просто cleanup-блок, выполняется только если в R0 выбран
overwrite.

### UX-эффект

Клиент, апгрейдящийся Standard → VIP, увидит:

```
━━━ STEP R0: АНАЛИЗ ТЕКУЩЕГО СОСТОЯНИЯ ━━━

🔼 Обнаружен апгрейд (не полная, но частичная установка):

Уже установлены (будут сохранены):
   ✓ tech
   ✓ marketer
   ✓ producer

Не хватает (будут добавлены):
   + designer
   + coordinator

Что делать?
1) Дополнить (поставить только недостающих, существующих не трогать)  ← рекомендуется
2) Перезаписать всех (снести 3 и поставить 5, теряете MEMORY.md)
3) Прервать

Выбор [1/2/3, Enter = 1]: _
```

Enter → автоматически доустановка без потери существующих данных.

---

## 2026-04-21 — Wave 3 (VIP v2: TG-binding, anti-sharing)

### Security — VIP-токен привязывается к Telegram user_id

Раньше токен был детерминирован от email — любой с этим токеном мог
поставить 5 агентов. Если VIP-клиент пересылает токен другу — друг
бесплатно получает VIP. Классическая проблема инфопродуктов.

Фикс: новый формат токена `VIP-<email_hash16>-<tg_user_id>-<signature>`,
где `tg_user_id` зашит в payload и подписан Ed25519 приватным ключом
бота. Установщик:

- Автоматически читает TG ID клиента из `~/.openclaw/openclaw.json`
  (первый установщик уже записал туда `OWNER_TG_ID` для allowlist)
- Сравнивает с tg_user_id внутри токена
- При несовпадении — отказ с объяснением «этот токен выдан для другого TG»
- Retry через `continue` (по правилу #20 в handoff первого установщика)

Подмена чужого TG id невозможна — это аккаунт Telegram. Шаринг
становится бесполезным.

### Added

- **`scripts/lib/vip.sh`** обновлён под v2 формат токена:
  - `verify_vip_token <token> <machine_tg_id>` — раздельные exit codes
    (2=формат, 3=tg-mismatch, 4=base64, 5=bad signature) для точных
    сообщений пользователю
  - `vip_token_get_expected_tg <token>` — извлечь ожидаемый TG ID
    (для show'а пользователю «токен выдан для TG X»)
  - `vip_token_get_hash <token>` — извлечь email_hash16 для fire-and-
    forget логирования
  - `vip_detect_owner_tg_id` — автодетект TG ID из `~/.openclaw/openclaw.json`
    через чтение `channels.telegram.allowFrom` / `allowlistAllowFrom`
  - `vip_log_activation <token_hash> <tg_id>` — fire-and-forget POST
    на `/log/activation` endpoint бота. Таймаут 3 сек, в фоне, при
    недоступности молча пропускаем. Бот ведёт журнал уникальных IP
    по каждому токену и шлёт Антону алерт при ≥3 IP за 7 дней.

- **V1 (`install-agents.sh`)** переписан:
  - Автоматическое чтение TG ID из настроек первого установщика
  - Цикл `while true` с `continue` для retry (правило #20)
  - Точные сообщения под каждый exit code валидации
  - При `--config` режиме — fail-fast, без retry

- **Watermark в IDENTITY.md для VIP-установок**
  (`scripts/lib/agents.sh:prepare_workspace_from_templates`):
  `<!-- issued-to: <hash> | tg:<tg_id> | <agent_id> | YYYY-MM-DD -->`
  Markdown-комментарий не рендерится, агенты его не видят, но если
  VIP-клиент кому-то пришлёт свои файлы — ясно чей это инстанс.
  Психологический сдерживающий слой.

### Breaking

v1-токены (формат `VIP-<hash>-<signature>` без tg_user_id) больше не
валидируются. Все клиенты должны получить свежие токены у
`@AITeamVIPBot`. Для смягчения — см. инструкцию в handoff.

---

## 2026-04-19 — Wave 2 (post-first-client fixes + video demo)

### Added
- **`scripts/demo-simulate.sh`** — автономная симуляция всего флоу установки
  для видеоуроков. Не требует OpenClaw, реальных токенов, API-ключей или
  интернета — просто визуально проигрывает R0-R5 со всеми экранами, цветами
  и таймерами. Три режима:
  - без флагов — интерактивная, Enter между блоками (для подробного объяснения)
  - `--auto` — без пауз, автоматический прогон ~2 мин (для записи видео)
  - `--fast` — ускоренные таймеры ~30 сек (для превью/GIF)
- **Решение #1 в `handoff/01-decisions-log.md`**: повторный запуск =
  clean-reinstall по умолчанию (одно меню + `cleanup_agent_completely()`).
- **Решение #2 там же**: duplicate-bot detection на этапе R2.

### Fixed (по боевому тестированию с первым клиентом)
- **R2 retry через `continue`, не `exit`** — клиент нажимал Y на «попробовать
  ещё» и получал выход в терминал. Переписали цикл сбора токенов на единый
  `while true` со всеми проверками внутри. Зафиксировано правилом #20 в
  handoff первого установщика.
- **bash 3.2 compat** — `declare -A` падал на /bin/bash (macOS по дефолту
  bash 3.2, Apple не обновляет из-за GPLv3). Переделали на динамически-
  именованные переменные + version-gate с auto-brew-install в начале.
  Зафиксировано правилом #19 в handoff первого установщика.
- **R3 clean-reinstall** — повторный запуск больше не показывает три меню
  подряд; одно меню в начале с default'ом «перезаписать начисто» и
  идемпотентной cleanup-функцией.

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
