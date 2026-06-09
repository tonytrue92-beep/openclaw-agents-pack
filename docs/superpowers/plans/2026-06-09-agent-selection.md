# Agent Selection (Pro) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development или superpowers:executing-plans. Steps — чекбоксы `- [ ]`.

**Goal:** На Pro-установке дать клиенту выбрать, сколько и каких из 8 агентов поставить (нумерованный список, Enter = все).

**Architecture:** Новая функция `select_pro_agents()` в `scripts/install-agents.sh` переопределяет `AGENTS_TO_INSTALL` выбранным подмножеством. Вызывается только при `VIP_MODE` в интерактиве (не `--only`/`--install`/`--vps`/non-TTY). R2 (бот-токены) и R4 (создание) уже итерируют `AGENTS_TO_INSTALL` — не трогаем.

**Tech Stack:** bash 3.2; grep-smoke; shellcheck; bundled-релиз по тегу.

**Спека:** `docs/superpowers/specs/2026-06-09-agent-selection-design.md`

---

## Task 1: Флаг `ASSUME_ALL_AGENTS` (гейт против автоматизации)

**Files:** Modify `scripts/install-agents.sh` (defaults ~152; arg-parser ~199-200)

- [ ] **Step 1: Дефолт переменной**

Рядом с `ONLY_AGENT=""` (~строка 152) добавь:
```bash
ASSUME_ALL_AGENTS=false   # --install / --vps → ставим всех агентов без меню выбора
```

- [ ] **Step 2: Ставить флаг в --install и --vps**

Найди в while-парсере (~199-200):
```bash
    --install) SKIP_MENU=true; shift ;;
    --vps|--headless) VPS_MODE=true; SKIP_MENU=true; shift ;;
```
Замени на:
```bash
    --install) SKIP_MENU=true; ASSUME_ALL_AGENTS=true; shift ;;
    --vps|--headless) VPS_MODE=true; SKIP_MENU=true; ASSUME_ALL_AGENTS=true; shift ;;
```

- [ ] **Step 3: bash -n**

Run: `cd ~/git/openclaw-agents-pack && bash -n scripts/install-agents.sh`
Expected: без вывода.

---

## Task 2: Функция `select_pro_agents()` + вызов

**Files:** Modify `scripts/install-agents.sh` (вставка ПЕРЕД блоком `AGENTS_TO_INSTALL=()` ~строка 1323; вызов ПОСЛЕ этого блока)

- [ ] **Step 1: Прочитать точную структуру блока AGENTS_TO_INSTALL**

Run: `cd ~/git/openclaw-agents-pack && sed -n '1320,1335p' scripts/install-agents.sh`
Ожидаемо: `AGENTS_TO_INSTALL=()` → `if [[ -n "$ONLY_AGENT" ]]` (single) → ветка VIP `AGENTS_TO_INSTALL=(tech marketer producer designer coordinator copywriter leadcloser content)` → ветка STD `=(tech marketer producer)` → `fi`. Запомни строку с `fi`, закрывающую этот блок.

- [ ] **Step 2: Определить функцию ПЕРЕД блоком**

Прямо ПЕРЕД строкой `AGENTS_TO_INSTALL=()` вставь функцию:
```bash
# ── Pro: интерактивный выбор «сколько и каких агентов» ──
# Переопределяет AGENTS_TO_INSTALL выбранным подмножеством. Пусто/ошибка → все 8.
select_pro_agents() {
  local ids=(tech marketer producer designer coordinator copywriter leadcloser content)
  local labels=("🔧 Технарь" "📈 Маркетолог" "🎬 Продюсер" "🎨 Дизайнер" \
                "🧭 Координатор" "✍️ Копирайтер" "💰 Лидоруб" "🎥 Контент-агент")
  local installed=""
  installed="$(openclaw agents list 2>/dev/null || echo "")"

  echo ""
  echo -e "   ${BOLD}${WHITE}Каких агентов поставить? (Pro — до 8)${NC}"
  local i mark
  for i in "${!ids[@]}"; do
    mark="  "
    case "$installed" in *"${ids[$i]}"*) mark="✓ " ;; esac
    echo -e "     $((i + 1))) ${mark}${labels[$i]}"
  done
  echo -e "   ${DIM}Введи номера через пробел (напр. 1 2 7) — или Enter, чтобы поставить всех 8:${NC}"

  local _attempt=0 _sel n seen
  local _chosen=()
  while [[ $_attempt -lt 2 ]]; do
    _attempt=$((_attempt + 1))
    printf "   > "
    read -r _sel || _sel=""
    # Enter (пусто) → все 8 (AGENTS_TO_INSTALL не трогаем)
    [[ -z "${_sel// /}" ]] && return 0
    _chosen=()
    seen=" "
    for n in $_sel; do
      if [[ "$n" =~ ^[1-8]$ ]]; then
        case "$seen" in
          *" $n "*) : ;;  # уже выбран — пропуск (дедуп)
          *) _chosen+=("${ids[$((n - 1))]}"); seen="$seen$n " ;;
        esac
      fi
    done
    [[ ${#_chosen[@]} -gt 0 ]] && break
    warn "Не распознал номера. Введи числа 1–8 через пробел (или Enter — все 8)."
  done

  # после 2 неудач — все 8
  [[ ${#_chosen[@]} -eq 0 ]] && { warn "Ставлю всех 8."; return 0; }

  AGENTS_TO_INSTALL=("${_chosen[@]}")

  # подтверждение выбора
  local _names="" id2 j
  for id2 in "${AGENTS_TO_INSTALL[@]}"; do
    for j in "${!ids[@]}"; do
      [[ "${ids[$j]}" == "$id2" ]] && _names="${_names}${labels[$j]} · "
    done
  done
  _names="${_names% · }"
  echo ""
  ok "Поставлю: ${_names} (${#AGENTS_TO_INSTALL[@]}). Дальше попрошу ${#AGENTS_TO_INSTALL[@]} бот-токен(ов)."
}

```

- [ ] **Step 3: Вызвать функцию ПОСЛЕ блока AGENTS_TO_INSTALL**

Сразу после `fi`, закрывающего блок `AGENTS_TO_INSTALL=()` (после ветки STD,
~строка 1333), вставь:
```bash

# Pro: дать клиенту выбрать сколько/каких агентов — только интерактив,
# не при --only / --install / --vps / non-TTY (там ставим всех).
if [[ "$VIP_MODE" == true && -z "$ONLY_AGENT" \
      && "${ASSUME_ALL_AGENTS:-false}" != true && -t 0 ]]; then
  select_pro_agents
fi
```

- [ ] **Step 4: bash -n + shellcheck**

Run:
```bash
cd ~/git/openclaw-agents-pack
bash -n scripts/install-agents.sh && echo OK
shellcheck -S warning -e SC1090,SC1091,SC2155,SC2086,SC2034 scripts/install-agents.sh 2>&1 | head -20
```
Expected: bash -n OK; нет новых warning. (SC2086 на `for n in $_sel` — намеренный
word-split, в exclude.)

- [ ] **Step 5: Функц-тест парсинга (без openclaw)**

Run:
```bash
cd ~/git/openclaw-agents-pack
bash -c '
BOLD=""; WHITE=""; DIM=""; NC=""; ok(){ echo "OK:$*"; }; warn(){ echo "WARN:$*"; }
AGENTS_TO_INSTALL=(tech marketer producer designer coordinator copywriter leadcloser content)
'"$(sed -n "/^select_pro_agents() {/,/^}/p" scripts/install-agents.sh)"'
printf "1 2 7\n" | select_pro_agents >/dev/null
echo "chosen: ${AGENTS_TO_INSTALL[*]}"
'
```
Expected: `chosen: tech marketer leadcloser`

- [ ] **Step 6: Commit**

```bash
cd ~/git/openclaw-agents-pack
git checkout -b agent-selection
git add scripts/install-agents.sh
git commit -m "agents-pack: выбор агентов на Pro (select_pro_agents, номера, Enter=все)"
```

---

## Task 3: Smoke + версия + CHANGELOG + дока + bundle + checksums + PR

**Files:** Modify `scripts/smoke-test.sh`, `scripts/install-agents.sh` (версия), `CHANGELOG.md`, `docs/curator-guide.md`, `SHA256SUMS`

- [ ] **Step 1: Smoke-ассерты (падающие сначала)**

В `scripts/smoke-test.sh` перед финальным `echo "=== All smoke tests passed ==="` добавь:
```bash
# Pro: интерактивный выбор агентов
grep -q 'select_pro_agents()' scripts/install-agents.sh \
  || fail "нет функции select_pro_agents"
grep -Eq 'VIP_MODE" == true && -z "\$ONLY_AGENT".*ASSUME_ALL_AGENTS' scripts/install-agents.sh \
  || fail "select_pro_agents не за-гейчен (VIP + не-only + не-assume-all)"
grep -q 'ASSUME_ALL_AGENTS=true' scripts/install-agents.sh \
  || fail "--install/--vps не ставят ASSUME_ALL_AGENTS"
pass "Pro: выбор агентов (select_pro_agents) на месте + гейты"
```

- [ ] **Step 2: Запусти smoke**

Run: `cd ~/git/openclaw-agents-pack && bash scripts/smoke-test.sh 2>&1 | tail -3`
Expected: PASS «Pro: выбор агентов … на месте + гейты» + прежние asserts зелёные.
(Если упал — поправь grep-паттерн под фактический текст гейта из Task 2 Step 3.)

- [ ] **Step 3: Bump версии + CHANGELOG**

`INSTALLER_VERSION` → `2026.06.09`. В начало `CHANGELOG.md`:
```markdown
## 2026-06-09 — Pro: выбор сколько/каких агентов ставить

### Added
- На Pro-установке клиент выбирает агентов из 8 нумерованным списком
  (`select_pro_agents`): ввод номеров «1 2 7», Enter — все 8. Меньше агентов =
  меньше бот-токенов (ниже флуд-риск Telegram).
- Гейты: меню только в интерактиве и только для Pro; при `--only` / `--install`
  / `--vps` / non-TTY ставятся все 8 (обратная совместимость).

`INSTALLER_VERSION → 2026.06.09`

---
```

- [ ] **Step 4: Строка в curator-guide**

В `docs/curator-guide.md` в §3 (что входит в Pro) добавь после описания 8 агентов:
```markdown
> На Pro-установке клиент выбирает, **сколько и каких** агентов поставить
> (нумерованный список; Enter — все 8). Меньше агентов — меньше бот-токенов.
```

- [ ] **Step 5: Линт + bundle + checksums**

```bash
cd ~/git/openclaw-agents-pack
bash -n scripts/install-agents.sh scripts/smoke-test.sh
shellcheck -S warning -e SC1090,SC1091,SC2155,SC2086,SC2034 scripts/install-agents.sh
bash scripts/build-bundle.sh && bash -n dist/install-agents-bundled.sh
grep -c 'select_pro_agents()' dist/install-agents-bundled.sh   # ожидаем 1
bash scripts/update-checksums.sh
```
Expected: всё ок; функция попала в bundled (1).

- [ ] **Step 6: Commit + PR + merge + тег**

```bash
cd ~/git/openclaw-agents-pack
git add scripts/install-agents.sh scripts/smoke-test.sh CHANGELOG.md docs/curator-guide.md SHA256SUMS
git commit -m "agents-pack: smoke+версия+CHANGELOG+дока для выбора агентов (2026.06.09)"
git push -u origin agent-selection
gh pr create --title "agents-pack: выбор сколько/каких агентов на Pro" --body "Спека docs/superpowers/specs/2026-06-09-agent-selection-design.md. select_pro_agents: номера/Enter=все, гейты (VIP+интерактив, не --only/--install/--vps/non-TTY). 🤖 Generated with [Claude Code](https://claude.com/claude-code)"
gh pr checks agent-selection --watch
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only
git tag v2026.06.09 && git push origin v2026.06.09   # bundled пересоберётся
```

- [ ] **Step 7: Проверка прод**

```bash
sleep 90
curl -fsSL "https://github.com/tonytrue92-beep/openclaw-agents-pack/releases/latest/download/install-agents-bundled.sh" | grep -m1 INSTALLER_VERSION
```
Expected: `INSTALLER_VERSION="2026.06.09"`.

---

## Self-Review (выполнено)
- **Покрытие спеки:** §3.1 функция → Task 2; §3.2 меню → Task 2 Step 2; §3.3 парсинг
  (Enter=все, дедуп, 1 перепрос, мин.1) → Task 2 Step 2; §3.4 гейты → Task 1 + Task 2 Step 3;
  §6 тесты → Task 2 Step 4-5, Task 3 Step 1-2,5; релиз-тег → Task 3 Step 6.
- **Плейсхолдеры:** нет (весь код приведён).
- **Консистентность имён:** `select_pro_agents`, `ASSUME_ALL_AGENTS`, `AGENTS_TO_INSTALL`,
  `ONLY_AGENT`, `VIP_MODE`, `ok`/`warn` (ui.sh), `${ids[@]}`/`labels` — совпадают везде.
- **bash 3.2:** пустой `_chosen=()` разворачивается `"${_chosen[@]}"` только под guard
  `count>0`; `${!ids[@]}`, `[[ =~ ]]`, `case`-glob — совместимы.
