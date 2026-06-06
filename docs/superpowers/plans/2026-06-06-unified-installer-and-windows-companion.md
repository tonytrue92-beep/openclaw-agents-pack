# Unified Installer + Windows Companion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Одна команда на всех платных клиентов — factory ставит движок и в финале сам дотягивает agents-pack по тарифу из токена (SUB=движок / STD=+3 / VIP=+8+KB); Windows-клиентам в финале agents-pack и trial предлагается официальный Companion-GUI.

**Architecture:** factory (bash, mac/Linux) — точка входа; в финале R6 при `COURSE_TIER ∈ {STD,VIP}` докачивает `install-agents-bundled.sh` и запускает в той же сессии (nvm уже загружен → нет `command not found`). Windows-offer — в platform-aware финалах agents-pack и trial. Тест = grep-ассерты в `scripts/smoke-test.sh` (как в прошлых волнах).

**Tech Stack:** bash 3.2-совместимый; smoke-test.sh (grep-asserts); shellcheck; SHA256SUMS; GitHub Actions CI; bundled-релиз по тегу.

**Спека:** `docs/superpowers/specs/2026-06-06-unified-installer-and-windows-companion-design.md`

---

## File Structure

| Файл | Ответственность | Действие |
|---|---|---|
| `openclaw-factory/scripts/demo-install.sh` | флаг `--engine-only`; чейн agents-pack в R6 | Modify |
| `openclaw-factory/scripts/smoke-test.sh` | ассерты чейна | Modify |
| `openclaw-factory/CHANGELOG.md` | запись | Modify |
| `openclaw-agents-pack/scripts/install-agents.sh` | Windows-offer в финале | Modify |
| `openclaw-agents-pack/scripts/smoke-test.sh` | ассерт offer | Modify |
| `openclaw-agents-pack/CHANGELOG.md` | запись | Modify |
| `openclaw-test-drive/scripts/install-trial.sh` | Windows-offer в финале | Modify |
| `openclaw-test-drive/scripts/smoke-test.sh` | ассерт offer | Modify |
| `openclaw-test-drive/CHANGELOG.md` | запись | Modify |
| `openclaw-agents-pack/docs/curator-guide.md` (+ cheatsheet) | одна команда + Companion | Modify |
| `openclaw-agents-pack/handoff/unified-install-command-bot-brief.md` | ТЗ боту | Create |
| `openclaw-agents-pack/handoff/STATUS-FOR-TECHIE.md` | одна команда | Modify |

> Версии всех трёх скриптов поднимаем до **`2026.06.06`** (date-based, их конвенция).
> Точные номера строк ниже — ориентир; находи по anchor-строкам (надёжнее).

---

## Task 1: factory — флаг `--engine-only`

**Files:**
- Modify: `openclaw-factory/scripts/demo-install.sh` (defaults ~108; arg-parser ~114-156)
- Test: `openclaw-factory/scripts/smoke-test.sh`

- [ ] **Step 1: Ассерт в smoke (падающий)**

В `openclaw-factory/scripts/smoke-test.sh` добавь проверку (рядом с другими grep-ассертами скрипта):

```bash
# Unified: флаг --engine-only существует и дефолт false
grep -q 'ENGINE_ONLY=false' scripts/demo-install.sh \
  || { echo "FAIL: нет дефолта ENGINE_ONLY=false"; exit 1; }
grep -q '\-\-engine-only) ENGINE_ONLY=true' scripts/demo-install.sh \
  || { echo "FAIL: нет парсинга --engine-only"; exit 1; }
echo "OK: --engine-only флаг на месте"
```

- [ ] **Step 2: Запусти smoke — должен упасть**

Run: `cd ~/git/openclaw-factory && bash scripts/smoke-test.sh`
Expected: FAIL «нет дефолта ENGINE_ONLY=false»

- [ ] **Step 3: Добавь дефолт + парсинг**

В `demo-install.sh` после строки `VPS_MODE=false ...` (~108) добавь:

```bash
ENGINE_ONLY=false         # --engine-only: не дотягивать агентов (отладка/SUB/переустановка движка)
```

В `while`-парсере (после кейса `--vps|--headless) ... ;;`, ~155) добавь кейс:

```bash
    --engine-only)
      ENGINE_ONLY=true
      ;;
```

- [ ] **Step 4: Запусти smoke — должен пройти**

Run: `cd ~/git/openclaw-factory && bash scripts/smoke-test.sh`
Expected: PASS «--engine-only флаг на месте»

- [ ] **Step 5: bash -n**

Run: `bash -n ~/git/openclaw-factory/scripts/demo-install.sh`
Expected: без вывода (синтаксис ок)

- [ ] **Step 6: Commit**

```bash
cd ~/git/openclaw-factory
git checkout -b unified-installer
git add scripts/demo-install.sh scripts/smoke-test.sh
git commit -m "factory: флаг --engine-only (отключить дотяжку агентов)"
```

---

## Task 2: factory — чейн agents-pack в финале R6 (STD/VIP)

**Files:**
- Modify: `openclaw-factory/scripts/demo-install.sh` (R6 финал; вставка ПОСЛЕ блока финального теста `fi` ~3693, ПЕРЕД блоком `if [[ "${COURSE_TIER:-}" == "SUB" ]]` ~3695)
- Modify: `openclaw-factory/scripts/demo-install.sh` (`INSTALLER_VERSION` ~18)
- Test: `openclaw-factory/scripts/smoke-test.sh`

- [ ] **Step 1: Ассерты в smoke (падающие)**

Добавь в `openclaw-factory/scripts/smoke-test.sh`:

```bash
# Unified: чейн agents-pack при STD/VIP
grep -q 'install-agents-bundled.sh' scripts/demo-install.sh \
  || { echo "FAIL: нет чейна на install-agents-bundled.sh"; exit 1; }
# чейн обусловлен тарифом STD/VIP и НЕ engine-only
grep -Eq '"\$\{COURSE_TIER:-\}" == "STD" \|\| "\$\{COURSE_TIER:-\}" == "VIP"' scripts/demo-install.sh \
  || { echo "FAIL: чейн не обусловлен STD/VIP"; exit 1; }
grep -q 'ENGINE_ONLY:-false.*!= true' scripts/demo-install.sh \
  || { echo "FAIL: чейн не уважает --engine-only"; exit 1; }
# чейн НЕ должен срабатывать в симуляции: он внутри ветки [[ "$DRY_RUN" != true ]] (else-блок)
echo "OK: чейн STD/VIP на месте"
```

- [ ] **Step 2: Запусти smoke — должен упасть**

Run: `cd ~/git/openclaw-factory && bash scripts/smoke-test.sh`
Expected: FAIL «нет чейна на install-agents-bundled.sh»

- [ ] **Step 3: Вставь блок чейна**

В `demo-install.sh` найди конец блока финального теста (строка `fi` сразу перед `if [[ "${COURSE_TIER:-}" == "SUB" ]]`, ~3693-3695). ВСТАВЬ между ними:

```bash
  # ─── Объединённый платный поток: STD/VIP — сразу ставим AI-команду ───
  # Тариф из токена решает: SUB → только движок (блок ниже);
  # STD/VIP → докачиваем agents-pack и ставим агентов В ТОЙ ЖЕ сессии
  # (nvm уже загружен в процесс → у дочернего скрипта openclaw в PATH,
  # «command not found» между шагами физически невозможен).
  if [[ "${ENGINE_ONLY:-false}" != true \
        && ( "${COURSE_TIER:-}" == "STD" || "${COURSE_TIER:-}" == "VIP" ) ]]; then

    # nvm в rc заранее — если докачка сорвётся, openclaw всё равно доступен потом
    [[ -d "$HOME/.nvm" ]] && persist_nvm_in_shell_rc >/dev/null 2>&1

    _tier_label="Base (3 агента)"
    [[ "${COURSE_TIER}" == "VIP" ]] && _tier_label="Pro (8 агентов + база знаний)"
    divider
    echo -e "   ${BOLD}${GREEN}✓ Движок и main-агент готовы.${NC}"
    echo -e "   ${BOLD}${WHITE}Тариф ${_tier_label}: ставлю твою AI-команду — это та же установка, НЕ закрывай терминал.${NC}"
    echo ""

    AGENTS_BUNDLED_URL="https://github.com/tonytrue92-beep/openclaw-agents-pack/releases/latest/download/install-agents-bundled.sh"
    _agents_fallback="bash <(curl -fsSL ${AGENTS_BUNDLED_URL}) --course-token ${COURSE_TOKEN}"
    _chain_ok=false
    _agents_tmp="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/oc-agents-$$.sh")"
    if curl -fsSL "$AGENTS_BUNDLED_URL" -o "$_agents_tmp" 2>/dev/null && [[ -s "$_agents_tmp" ]]; then
      if bash "$_agents_tmp" --course-token "$COURSE_TOKEN"; then
        _chain_ok=true
      fi
    fi
    rm -f "$_agents_tmp" 2>/dev/null || true

    if [[ "$_chain_ok" != true ]]; then
      echo ""
      warn "Движок установлен и работает, но автоустановку агентов не удалось завершить."
      echo -e "   ${DIM}Доустанови команду агентов вручную (в новом терминале):${NC}"
      echo -e "      ${GREEN}${_agents_fallback}${NC}"
      echo ""
    fi
    unset _tier_label _agents_fallback _chain_ok _agents_tmp AGENTS_BUNDLED_URL
    break   # агенты поставлены (или показан fallback) — их финал последний, выходим
  fi

```

> Почему `break`: при STD/VIP последним экраном должен быть финал agents-pack (у него свой «что дальше» + platform-block). Поэтому выходим из цикла меню, не печатая остальной factory-финал. SUB и `--engine-only` сюда не заходят → им показывается обычный финал factory ниже.

- [ ] **Step 4: Bump версии + CHANGELOG**

В `demo-install.sh` ~18: `INSTALLER_VERSION="2026.06.04.1"` → `INSTALLER_VERSION="2026.06.06"`.

В начало `openclaw-factory/CHANGELOG.md` (после `---` на ~строке 9) добавь:

```markdown
## 2026-06-06 — Объединённый платный установщик (одна команда)

### Changed
- При тарифе **STD/VIP** в финале R6 factory **сам докачивает и запускает**
  `install-agents-bundled.sh` (agents-pack) с тем же `--course-token` — клиент
  ставит движок + агентов **одной командой**. Агенты ставятся в той же
  сессии терминала, поэтому `command not found` между шагами исключён.
- **SUB** — без изменений: только движок + main-агент.
- Demo / симуляция / dry-run агентов не тянут.

### Added
- Флаг `--engine-only` — отключить дотяжку агентов (отладка / переустановка движка).

### Fixed
- Если докачка агентов сорвётся (сеть/CDN) — движок уже установлен, скрипт не
  падает, показывает ручную команду-fallback.

`INSTALLER_VERSION 2026.06.04.1 → 2026.06.06`

---
```

- [ ] **Step 5: smoke + bash -n**

Run: `cd ~/git/openclaw-factory && bash -n scripts/demo-install.sh && bash scripts/smoke-test.sh`
Expected: PASS «чейн STD/VIP на месте» + все прежние ассерты зелёные

- [ ] **Step 6: Commit**

```bash
cd ~/git/openclaw-factory
git add scripts/demo-install.sh scripts/smoke-test.sh CHANGELOG.md
git commit -m "factory: дотягивать agents-pack в финале при STD/VIP (одна команда)"
```

---

## Task 3: factory — линт, checksums, PR

**Files:** `openclaw-factory/SHA256SUMS`

- [ ] **Step 1: shellcheck**

Run:
```bash
cd ~/git/openclaw-factory
shellcheck -S warning -e SC1090,SC1091,SC2155,SC2086,SC2034 scripts/demo-install.sh
```
Expected: без новых warning (если есть — поправь по месту)

- [ ] **Step 2: Обнови SHA256SUMS**

Run: `cd ~/git/openclaw-factory && bash scripts/update-checksums.sh`
Expected: SHA256SUMS обновлён

- [ ] **Step 3: Commit checksums**

```bash
cd ~/git/openclaw-factory
git add SHA256SUMS
git commit -m "factory: обновить SHA256SUMS (unified installer)"
```

- [ ] **Step 4: Push + PR**

```bash
cd ~/git/openclaw-factory
git push -u origin unified-installer
gh pr create --title "factory: объединённый платный установщик (одна команда, STD/VIP дотягивает агентов)" \
  --body "Спека: docs/superpowers/specs/2026-06-06-unified-installer-and-windows-companion-design.md. STD/VIP → factory сам ставит agents-pack в той же сессии; SUB → только движок; --engine-only отключает; fallback при сбое докачки.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 5: Дождись CI и смержи**

```bash
cd ~/git/openclaw-factory
gh pr checks unified-installer --watch
# если зелёно:
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only
```
Expected: CI зелёный (7 джоб), PR в main

---

## Task 4: agents-pack — Windows Companion offer в финале

**Files:**
- Modify: `openclaw-agents-pack/scripts/install-agents.sh` (финал, кейс `windows-bash|wsl)` ~2151-2156; `INSTALLER_VERSION` ~ начало)
- Modify: `openclaw-agents-pack/scripts/smoke-test.sh`
- Modify: `openclaw-agents-pack/CHANGELOG.md`, `SHA256SUMS`

- [ ] **Step 1: Ассерт в smoke (падающий)**

В `openclaw-agents-pack/scripts/smoke-test.sh` добавь:

```bash
# Windows Companion offer в финале
grep -q 'docs.openclaw.ai/platforms/windows' scripts/install-agents.sh \
  || { echo "FAIL: нет offer Companion (docs.openclaw.ai/platforms/windows)"; exit 1; }
grep -q 'OpenClaw Windows Hub\|удобный интерфейс для Windows' scripts/install-agents.sh \
  || { echo "FAIL: нет текста offer Companion"; exit 1; }
echo "OK: Windows Companion offer на месте (agents-pack)"
```

- [ ] **Step 2: smoke — падает**

Run: `cd ~/git/openclaw-agents-pack && bash scripts/smoke-test.sh`
Expected: FAIL «нет offer Companion»

- [ ] **Step 3: Вставь offer**

В `install-agents.sh` в кейсе `windows-bash|wsl)` (после строки с `docs/windows-install-guide.md`, перед `;;` ~2155) добавь:

```bash
    # ─── Windows-интерфейс (Companion GUI) — официальное приложение OpenClaw ───
    echo -e "   ${BOLD}${WHITE}🪟 Хочешь удобный интерфейс для Windows? (OpenClaw Windows Hub)${NC}"
    echo -e "   ${DIM}   Трей-иконка, командный центр, диагностика — без терминала.${NC}"
    echo -e "   ${BOLD}${WHITE}   Открыть страницу загрузки? [y/N]:${NC}"
    read -r _companion_ans || true
    if [[ "${_companion_ans:-}" =~ ^[Yy]$ ]]; then
      _companion_url="https://docs.openclaw.ai/platforms/windows"
      if   command -v cmd.exe        >/dev/null 2>&1; then cmd.exe /c start "" "$_companion_url" >/dev/null 2>&1 || true
      elif command -v powershell.exe >/dev/null 2>&1; then powershell.exe -NoProfile -Command "Start-Process '$_companion_url'" >/dev/null 2>&1 || true
      elif command -v explorer.exe   >/dev/null 2>&1; then explorer.exe "$_companion_url" >/dev/null 2>&1 || true
      elif command -v start          >/dev/null 2>&1; then start "" "$_companion_url" >/dev/null 2>&1 || true
      fi
      echo -e "   ${GREEN}✓${NC} Страница загрузки: ${CYAN}${_companion_url}${NC}"
      echo -e "   ${DIM}   Если не открылось — открой ссылку вручную. Прямой .exe:${NC}"
      echo -e "   ${DIM}   …/releases/latest/download/OpenClawCompanion-Setup-x64.exe (или -arm64)${NC}"
      unset _companion_url
    fi
    unset _companion_ans
```

- [ ] **Step 4: smoke — проходит**

Run: `cd ~/git/openclaw-agents-pack && bash scripts/smoke-test.sh`
Expected: PASS «Windows Companion offer на месте (agents-pack)»

- [ ] **Step 5: Bump версии + CHANGELOG**

`INSTALLER_VERSION="2026.06.04.3"` → `INSTALLER_VERSION="2026.06.06"`.

В начало `CHANGELOG.md`:

```markdown
## 2026-06-06 — Windows: предложение Companion GUI + объединённый поток

### Added
- В финале для Windows-клиентов (Git Bash / WSL) — опциональное предложение
  установить официальный **OpenClaw Windows Hub** (трей, командный центр,
  диагностика): с согласия открывается страница загрузки.

### Changed
- Платный поток теперь запускается **одной командой** из factory (STD/VIP
  дотягивают этот установщик автоматически). Отдельный запуск agents-pack
  по-прежнему работает (перезапуск / `--refresh-templates`).

`INSTALLER_VERSION 2026.06.04.3 → 2026.06.06`

---
```

- [ ] **Step 6: bash -n + shellcheck + bundled + checksums**

Run:
```bash
cd ~/git/openclaw-agents-pack
bash -n scripts/install-agents.sh
shellcheck -S warning -e SC1090,SC1091,SC2155,SC2086,SC2034 scripts/install-agents.sh
bash scripts/build-bundle.sh && bash -n dist/install-agents-bundled.sh
bash scripts/update-checksums.sh
```
Expected: синтаксис ок, нет новых warning, bundled собрался и валиден, SHA256SUMS обновлён

- [ ] **Step 7: Commit + PR + merge**

```bash
cd ~/git/openclaw-agents-pack
git checkout -b windows-companion
git add scripts/install-agents.sh scripts/smoke-test.sh CHANGELOG.md SHA256SUMS dist/ 2>/dev/null
git commit -m "agents-pack: Windows Companion GUI offer в финале + bump 2026.06.06"
git push -u origin windows-companion
gh pr create --title "agents-pack: Windows Companion GUI offer" --body "Спека 2026-06-06. Windows (Git Bash/WSL) — предложить официальный OpenClaw Windows Hub в финале.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
gh pr checks windows-companion --watch
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only
```

- [ ] **Step 8: Релиз-тег (иначе чейн factory скачает старый bundled!)**

```bash
cd ~/git/openclaw-agents-pack
git tag v2026.06.06
git push origin v2026.06.06
# дождись, пока release.yml опубликует bundled (~1-2 мин), затем проверь:
curl -fsSL "https://github.com/tonytrue92-beep/openclaw-agents-pack/releases/latest/download/install-agents-bundled.sh" | grep -m1 INSTALLER_VERSION
```
Expected: `INSTALLER_VERSION="2026.06.06"`

---

## Task 5: trial — Windows Companion offer в финале

**Files:**
- Modify: `openclaw-test-drive/scripts/install-trial.sh` (финал ~703; `TRIAL_VERSION` ~35; использует `OS_NAME` из `detect_os`, значения `wsl`/`windows-bash`)
- Modify: `openclaw-test-drive/scripts/smoke-test.sh`, `CHANGELOG.md`, `SHA256SUMS`

- [ ] **Step 1: Ассерт в smoke (падающий)**

В `openclaw-test-drive/scripts/smoke-test.sh` добавь:

```bash
grep -q 'docs.openclaw.ai/platforms/windows' scripts/install-trial.sh \
  || { echo "FAIL: trial — нет offer Companion"; exit 1; }
echo "OK: Windows Companion offer на месте (trial)"
```

- [ ] **Step 2: smoke — падает**

Run: `cd ~/git/openclaw-test-drive && bash scripts/smoke-test.sh`
Expected: FAIL «trial — нет offer Companion»

- [ ] **Step 3: Вставь offer в финал**

В `install-trial.sh` в финальном блоке (после `#  Финал` ~703, рядом с показом `COURSE_URL`) добавь:

```bash
# ─── Windows: предложить официальный интерфейс (Companion GUI) ───
if [[ "$OS_NAME" == "windows-bash" || "$OS_NAME" == "wsl" ]]; then
  echo ""
  echo -e "${BOLD}${WHITE}🪟 Хочешь удобный интерфейс для Windows? (OpenClaw Windows Hub)${NC}"
  echo -e "${DIM}   Трей-иконка, командный центр, диагностика — без терминала.${NC}"
  echo -e "${BOLD}${WHITE}   Открыть страницу загрузки? [y/N]:${NC}"
  read -r _companion_ans || true
  if [[ "${_companion_ans:-}" =~ ^[Yy]$ ]]; then
    _companion_url="https://docs.openclaw.ai/platforms/windows"
    if   command -v cmd.exe        >/dev/null 2>&1; then cmd.exe /c start "" "$_companion_url" >/dev/null 2>&1 || true
    elif command -v powershell.exe >/dev/null 2>&1; then powershell.exe -NoProfile -Command "Start-Process '$_companion_url'" >/dev/null 2>&1 || true
    elif command -v explorer.exe   >/dev/null 2>&1; then explorer.exe "$_companion_url" >/dev/null 2>&1 || true
    elif command -v start          >/dev/null 2>&1; then start "" "$_companion_url" >/dev/null 2>&1 || true
    fi
    echo -e "${GREEN}✓${NC} Страница загрузки: ${CYAN}${_companion_url}${NC}"
    unset _companion_url
  fi
  unset _companion_ans
fi
```

- [ ] **Step 4: smoke — проходит**

Run: `cd ~/git/openclaw-test-drive && bash scripts/smoke-test.sh`
Expected: PASS «Windows Companion offer на месте (trial)»

- [ ] **Step 5: Bump + CHANGELOG + линт + checksums**

`TRIAL_VERSION="2026.05.28.16"` → `TRIAL_VERSION="2026.06.06"`. Добавь запись в `CHANGELOG.md` (Added: Windows Companion offer в финале). Затем:

```bash
cd ~/git/openclaw-test-drive
bash -n scripts/install-trial.sh
shellcheck -S warning -e SC1090,SC1091,SC2155,SC2086,SC2034 scripts/install-trial.sh
bash scripts/update-checksums.sh
```
Expected: ок, без новых warning, SHA256SUMS обновлён

- [ ] **Step 6: Commit + PR + merge**

```bash
cd ~/git/openclaw-test-drive
git checkout -b windows-companion
git add scripts/install-trial.sh scripts/smoke-test.sh CHANGELOG.md SHA256SUMS
git commit -m "trial: Windows Companion GUI offer в финале + bump 2026.06.06"
git push -u origin windows-companion
gh pr create --title "trial: Windows Companion GUI offer" --body "Спека 2026-06-06.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
gh pr checks windows-companion --watch
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only
```

---

## Task 6: Доки куратора — одна команда + Companion

**Files:**
- Modify: `openclaw-agents-pack/docs/curator-guide.md`
- Modify: `openclaw-agents-pack/docs/curator-skill/installer-support/SKILL.md`

- [ ] **Step 1: Обнови §2 «Команды по трекам» в curator-guide.md**

Замени блок про платные «шаг 1 / шаг 2» на **одну** команду:

```markdown
### Платный (одна команда — тариф из токена решает)
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh) --course-token <ТОКЕН>
# SUB → только движок; STD → +3 агента; VIP → +8 агентов + база знаний.
# Агенты ставятся автоматически в той же сессии. Старый ручной шаг-2 — только fallback.
```

- [ ] **Step 2: Добавь раздел про Windows Companion в curator-guide.md**

```markdown
### Windows-интерфейс (Companion GUI)
В финале установки Windows-клиенту предлагается официальный OpenClaw Windows
Hub (трей, командный центр, диагностика). Страница: https://docs.openclaw.ai/platforms/windows
Опционально; gateway наш стандартный. Если клиент спрашивает «что это» — это
удобная альтернатива терминалу, ставится отдельным .exe.
```

- [ ] **Step 3: Подправь скилл installer-support (одна команда)**

В `docs/curator-skill/installer-support/SKILL.md` в разделе «Три трека → команда» замени два платных шага на одну команду (как Step 1). Добавь триггер «интерфейс / GUI / трей / Windows Hub» в «Когда использую».

- [ ] **Step 4: Commit + push (main, docs)**

```bash
cd ~/git/openclaw-agents-pack
git add docs/curator-guide.md docs/curator-skill/installer-support/SKILL.md
git commit -m "docs: куратор — одна платная команда + Windows Companion"
git push origin HEAD
```

---

## Task 7: ТЗ технарю (бот шлёт одну команду)

**Files:**
- Create: `openclaw-agents-pack/handoff/unified-install-command-bot-brief.md`
- Modify: `openclaw-agents-pack/handoff/STATUS-FOR-TECHIE.md`

- [ ] **Step 1: Создай бриф боту**

Создай `openclaw-agents-pack/handoff/unified-install-command-bot-brief.md`:

```markdown
# Бриф боту @AITeamVIPBot — одна команда установки

## Что изменилось
Платный установщик объединён: factory сам дотягивает агентов по тарифу из
токена. Значит бот должен слать **одну** команду вместо двух.

## Что сделать в боте
1. После выдачи токена слать ОДНУ команду с подставленным токеном:
   `bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh) --course-token <ВЫДАННЫЙ_ТОКЕН>`
   - VIP/STD → агенты доставятся сами; SUB → только движок.
2. Убрать из сообщений «теперь запусти вторую команду …».
3. Windows-инструкция (опц.): «в конце установщик предложит удобный
   интерфейс (Companion) — соглашайся».
4. Тест-драйв — команда без изменений (одна). Блокер прежний: бот должен
   выдавать TRY-токен после оплаты Prodamus.

## Совместимость
Токен-ключ Ed25519, payload-префиксы, кэш — без изменений. Старые отдельные
команды продолжают работать (перезапуск/refresh).
```

- [ ] **Step 2: Обнови STATUS-FOR-TECHIE.md**

В приоритетный блок добавь пункт «Одна команда установки» со ссылкой на новый бриф; в install-command секции — что теперь одна команда.

- [ ] **Step 3: Commit + push**

```bash
cd ~/git/openclaw-agents-pack
git add handoff/unified-install-command-bot-brief.md handoff/STATUS-FOR-TECHIE.md
git commit -m "handoff: ТЗ боту — одна команда установки (unified)"
git push origin HEAD
```

---

## Task 8: Финальная проверка прод + чек-лист живого теста

- [ ] **Step 1: Версии в проде совпадают**

```bash
curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh | grep -m1 INSTALLER_VERSION
curl -fsSL https://github.com/tonytrue92-beep/openclaw-agents-pack/releases/latest/download/install-agents-bundled.sh | grep -m1 INSTALLER_VERSION
curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-test-drive/main/scripts/install-trial.sh | grep -m1 TRIAL_VERSION
```
Expected: factory=2026.06.06, agents-pack bundled=2026.06.06, trial=2026.06.06

- [ ] **Step 2: Живой тест (чистая машина) — отметить факт**

  - [ ] mac/Linux, VIP-токен: одна команда → движок + 8 агентов + база знаний, без ручного шага-2, без `command not found`.
  - [ ] STD → движок + 3 агента. SUB → только движок.
  - [ ] Симуляция сбоя докачки (отключить сеть после движка) → движок стоит, показан fallback, скрипт не упал.
  - [ ] Windows (платно + trial): в финале предложен Companion, открылась страница; Companion подключился к нашему gateway (см. спеку §4.4).

---

## Self-Review (выполнено при написании плана)

- **Покрытие спеки:** Фича 1 → Task 1-3; Фича 2 → Task 4-5; доки → Task 6; технарь (§7 спеки) → Task 7; верификация/релиз (§6 спеки) → Task 3/4.8/8. SUB-ветка уже существует в factory (3695) — отдельной задачи не требует, чейн её не трогает (guard `STD||VIP`).
- **Плейсхолдеры:** `<ТОКЕН>` / `<ВЫДАННЫЙ_ТОКЕН>` — намеренные шаблоны для бота, не код.
- **Консистентность имён:** `COURSE_TIER`, `COURSE_TOKEN`, `ENGINE_ONLY`, `persist_nvm_in_shell_rc`, `detect_environment` (agents-pack), `OS_NAME`/`detect_os` (trial) — совпадают с фактическим кодом (сверено чтением).
```
