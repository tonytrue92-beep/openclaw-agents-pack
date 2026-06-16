#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════
#  Bash 4+ required — но сами по себе современные фичи (indirect expansion,
#  printf -v) работают в 3.2. А вот `set -euo pipefail` работает везде.
#
#  НО: macOS по умолчанию даёт /bin/bash 3.2 (GPLv3 lock). Если shebang
#  `#!/usr/bin/env bash` резолвится в старый — перезапускаемся через более
#  новый bash из Homebrew, иначе даём понятное сообщение.
#
#  Причина: bug-репорт 2026-04-19, клиент упал на строке с `declare -A` —
#  ассоциативных массивов нет в bash 3.2. Мы уже переписали без них, но
#  профилактически проверяем версию — мало ли какую bash-фичу понадобится
#  добавить в будущем.
# Wave 31: НЕ требуем bash 4+. Код намеренно 3.2-совместим (wave 11 —
# переписан без declare -A / mapfile), как factory demo-install.sh.
# Раньше hard-exit на bash<4 заставлял клиента ставить Homebrew + долго
# компилировать bash из исходников (особенно на старых Intel-маках) —
# огромный барьер на входе. Теперь: если свежий bash УЖЕ есть в brew —
# переключаемся на него (стабильнее), но если нет — спокойно работаем
# на штатном 3.2.
if (( BASH_VERSINFO[0] < 4 )); then
  for _newer_bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [[ -x "$_newer_bash" && "$_newer_bash" != "$BASH" ]]; then
      exec "$_newer_bash" "$0" "$@"
    fi
  done
  # bash 4+ не найден — продолжаем на текущем 3.2 (код совместим).
fi

# ═══════════════════════════════════════════════════════════════════════
#  OpenClaw Agents Pack — установщик стандартного и VIP-набора агентов
#
#  Ставится поверх уже работающего OpenClaw (который поставлен первым
#  установщиком из openclaw-factory). Создаёт:
#
#    Standard: 🔧 Технарь, 📈 Маркетолог, 🎬 Продюсер
#    VIP:      + 🎨 Дизайнер, 🧭 Координатор
#
#  Каждому агенту — свой workspace в ~/.openclaw/workspace-<agent>/
#  с IDENTITY.md / AGENTS.md / MEMORY.md / USER.md из templates/ репо.
# ═══════════════════════════════════════════════════════════════════════

# ─── Версия установщика ─────────────────────────────────────────
# Обновляется при каждом значимом коммите. INSTALLER_COMMIT подставляется
# через sed в release-workflow; если скрипт запущен из рабочей копии —
# runtime-fallback на git rev-parse.
INSTALLER_VERSION="2026.06.16"
INSTALLER_COMMIT="__COMMIT_PLACEHOLDER__"

if [[ "$INSTALLER_COMMIT" == "__COMMIT_PLACEHOLDER__" ]]; then
  _script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null) || _script_dir=""
  if [[ -n "$_script_dir" && -d "${_script_dir}/../.git" ]] && command -v git &>/dev/null; then
    _commit=$(git -C "${_script_dir}/.." rev-parse --short HEAD 2>/dev/null) || _commit=""
    [[ -n "$_commit" ]] && INSTALLER_COMMIT="${_commit}-dev"
  fi
  unset _script_dir _commit
fi

# ─── Просмотровые флаги — до любой работы с TTY ─────────────────
for arg in "$@"; do
  case "$arg" in
    --version|-V)
      echo "OpenClaw Agents Pack v${INSTALLER_VERSION} (${INSTALLER_COMMIT})"
      exit 0
      ;;
    --help|-h)
      cat <<HELP
OpenClaw Agents Pack v${INSTALLER_VERSION} (${INSTALLER_COMMIT})

Установщик Standard (3 агента) и VIP (8 агентов)
поверх уже работающего OpenClaw.

Usage: bash install-agents.sh [OPTIONS]

Options:
  --install              Пропустить меню, поставить Base-набор (3 агента)
  --course-token <token> Course-token из @AITeamVIPBot. Mandatory для свежей установки.
                         Формат VIP-... → VIP-режим (8 агентов), STD-... → Standard (3).
  --vip-token <token>    Backward-compat алиас для --course-token.
  --vps, --headless      VPS-режим (skip GUI, SSH-tunnel-инструкция для dashboard)
  --only <agent>         Поставить только одного: tech | marketer | producer | designer | coordinator | copywriter | leadcloser | content (последние 5 — Pro, нужен VIP-токен)
  --suffix <str>         Суффикс к id при коллизии (tech-2, marketer-2, …)
  --config <file>        env-файл для неинтерактивной установки:
                           BOT_TOKEN_TECH=...
                           BOT_TOKEN_MARKETER=...
                           BOT_TOKEN_PRODUCER=...
                           BOT_TOKEN_DESIGNER=...      # для VIP
                           BOT_TOKEN_COORDINATOR=...   # для VIP
                           VIP_TOKEN=...               # для VIP
                           AGENT_MODEL=opencode-go/deepseek-v4-flash
                           OWNER_TG_ID=12345678
  --diagnose-only        Проверить что агенты живы (ничего не меняет)
  --collect-debug        Собрать debug-bundle для саппорта (не нужен TTY)
  --refresh-templates    Обновить ТОЛЬКО шаблоны уже установленных агентов
                         (IDENTITY/AGENTS/SOUL/LEARNING/skills), сохранив
                         MEMORY.md + USER.md + настройки каналов. Безопасный
                         апдейт без потери данных. Не нужен VIP-токен.
  --enable-embedding     Включить embedding-память (семантический поиск)
                         неинтерактивно. Берёт ключ из OPENAI_EMBEDDING_API_KEY
                         или OPENAI_API_KEY (env / config).
  --no-embedding         Пропустить шаг embedding (для скриптов / CI).
  --enable-group-mode <chat_id>
                         Настроить уже установленных агентов на работу в
                         общем TG-чате с заданным chat_id. Перед этим
                         нужно вручную: /setprivacy → Disable у каждого
                         бота через @BotFather + добавить ботов в группу.
  --version              Показать версию
  --help                 Показать эту справку

Без флагов — интерактивное меню.

Документация: https://github.com/tonytrue92-beep/openclaw-agents-pack
HELP
      exit 0
      ;;
  esac
done

# ─── TTY для интерактивного ввода (если не --collect-debug / --diagnose-only) ─
NEEDS_TTY=true
for arg in "$@"; do
  [[ "$arg" == "--collect-debug" ]] && NEEDS_TTY=false
  [[ "$arg" == "--diagnose-only" ]] && NEEDS_TTY=false
  [[ "$arg" == "--refresh-templates" ]] && NEEDS_TTY=false
  [[ "$arg" == "--enable-group-mode" ]] && NEEDS_TTY=false
done
# --enable-embedding and --no-embedding still require TTY because the rest
# of the install flow is interactive (model choice, tokens, etc.)
if [[ "$NEEDS_TTY" == true && ! -t 0 ]]; then
  # R2-аудит: exec может упасть (nohup/screen без tty) — ловим и даём
  # понятное сообщение вместо generic-трапа.
  if ! { [[ -e /dev/tty ]] && exec < /dev/tty; } 2>/dev/null; then
    echo "ERROR: скрипту нужен интерактивный терминал."
    echo "Запустите напрямую: bash <(curl -fsSL URL)"
    exit 1
  fi
fi

# ─── Флаги основной логики ──────────────────────────────────────
SKIP_MENU=false
VPS_MODE=false
COLLECT_DEBUG_ONLY=false
DIAGNOSE_ONLY=false
REFRESH_TEMPLATES_ONLY=false
ENABLE_EMBEDDING_FLAG=false
NO_EMBEDDING=false
ENABLE_GROUP_MODE_CHAT_ID=""
VIP_MODE=false
VIP_TOKEN=""
ONLY_AGENT=""
ASSUME_ALL_AGENTS=false   # --install / --vps → ставим всех агентов без меню выбора
SUFFIX=""
CONFIG_FILE=""
# wave 12: course-token (общий для Standard и VIP). VIP_TOKEN — backward-compat alias.
COURSE_TOKEN=""
COURSE_TIER=""

# ─── wave 11 P1 fix: stale-token cleanup ────────────────────────
# Если клиент прервал предыдущий запуск (Ctrl+C в R2 после ввода
# 1-3 токенов из 6) и сразу же запустил установщик снова в той же
# shell-сессии — переменные BOT_TOKEN_<agent> остаются в env.
# В R2 они подберутся как preset_token и попытаются использоваться
# с уже отозванными токенами / другими ботами. Защищаемся: на старте
# чистим все BOT_TOKEN_* которые могут остаться от прошлой сессии.
unset BOT_TOKEN_TECH BOT_TOKEN_MARKETER BOT_TOKEN_PRODUCER \
      BOT_TOKEN_DESIGNER BOT_TOKEN_COORDINATOR BOT_TOKEN_COPYWRITER \
      BOT_TOKEN_LEADCLOSER BOT_TOKEN_CONTENT 2>/dev/null || true

# ─── EXIT trap — не даём тихо уйти в шелл без подсказки ───────
#
# Bug-репорт 2026-04-21: клиенты жаловались что установщик иногда
# «встаёт и выкидывает в терминал» — оказалось что команда exec bash $0
# в пункте 4 меню падала на /dev/fd/N (curl-bash scenario), и exec
# молча выходил. Аналогично любая необработанная ошибка при set -e
# может выйти без визуальной причины.
#
# Этот trap печатает подсказку при exit code != 0, ЕСЛИ мы не поставили
# $_last_exit_reason вручную в месте осознанного выхода. Для нормальных
# выходов (install_complete, manual_menu_5, invalid_menu_choice) —
# trap молчит.
_last_exit_reason=""
# shellcheck disable=SC2154  # _rc присваивается внутри trap action (через $?)
trap '
  _rc=$?
  if [[ $_rc -ne 0 && -z "$_last_exit_reason" ]]; then
    echo ""
    echo "━━━ установщик завершился неожиданно (exit=$_rc) ━━━"
    echo ""
    echo "Если выше в терминале нет понятной ошибки — соберите debug-bundle"
    echo "и пришлите в саппорт. Одна команда:"
    echo ""
    echo "  (команда из @AITeamVIPBot с флагом --collect-debug)"
    echo ""
  fi
' EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) SKIP_MENU=true; ASSUME_ALL_AGENTS=true; shift ;;
    --vps|--headless) VPS_MODE=true; SKIP_MENU=true; ASSUME_ALL_AGENTS=true; shift ;;
    --collect-debug) COLLECT_DEBUG_ONLY=true; shift ;;
    --diagnose-only) DIAGNOSE_ONLY=true; shift ;;
    --refresh-templates) REFRESH_TEMPLATES_ONLY=true; shift ;;
    --enable-embedding) ENABLE_EMBEDDING_FLAG=true; shift ;;
    --no-embedding) NO_EMBEDDING=true; shift ;;
    --enable-group-mode)
      ENABLE_GROUP_MODE_CHAT_ID="${2:-}"
      [[ -z "$ENABLE_GROUP_MODE_CHAT_ID" ]] && { echo "ERROR: --enable-group-mode требует chat_id"; exit 1; }
      [[ ! "$ENABLE_GROUP_MODE_CHAT_ID" =~ ^-?[0-9]+$ ]] && { echo "ERROR: --enable-group-mode chat_id должен быть числом (может быть отрицательным для групп)"; exit 1; }
      shift 2
      ;;
    --vip-token|--course-token)
      # wave 12: --course-token — новый предпочитаемый флаг,
      # --vip-token остаётся как алиас для backward-compat (старые скрипты).
      COURSE_TOKEN="${2:-}"
      [[ -z "$COURSE_TOKEN" ]] && { echo "ERROR: $1 требует значение"; exit 1; }
      VIP_TOKEN="$COURSE_TOKEN"  # старая переменная — для существующего кода
      # Tier определяется по prefix
      case "$COURSE_TOKEN" in
        VIP-*) VIP_MODE=true ;;
        STD-*) VIP_MODE=false ;;
        *)
          echo "ERROR: токен должен начинаться с VIP- или STD-"
          echo "Получи актуальный в @AITeamVIPBot → /start → email/phone"
          exit 1
          ;;
      esac
      SKIP_MENU=true
      shift 2
      ;;
    --only)
      ONLY_AGENT="${2:-}"
      [[ -z "$ONLY_AGENT" ]] && { echo "ERROR: --only требует значение (tech|marketer|producer|designer|coordinator|copywriter|leadcloser|content)"; exit 1; }
      shift 2
      ;;
    --suffix)
      SUFFIX="${2:-}"
      [[ -z "$SUFFIX" ]] && { echo "ERROR: --suffix требует значение"; exit 1; }
      shift 2
      ;;
    --config)
      CONFIG_FILE="${2:-}"
      [[ -z "$CONFIG_FILE" || ! -f "$CONFIG_FILE" ]] && { echo "ERROR: --config требует существующий файл"; exit 1; }
      shift 2
      ;;
    --version|-V|--help|-h) shift ;;  # уже обработано
    *) echo "ERROR: неизвестный флаг: $1 (см. --help)"; exit 1 ;;
  esac
done

# ─── Подключаем helper-библиотеки ───────────────────────────────
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# В CI/Docker scripts/lib лежит рядом; при `bash <(curl ...)` ничего не лежит,
# поэтому скачиваем lib/ с того же commit-pin.
#
# wave 10: маркеры `=== BUNDLE_LIB_BEGIN ===` / `=== BUNDLE_LIB_END ===`
# используются `scripts/build-bundle.sh` чтобы заменить весь этот блок на
# inline-контент lib/*.sh при сборке self-contained `install-agents-bundled.sh`.
# Не удалять и не переименовывать без обновления build-bundle.sh.
# ─── IP-доставка (token-gated, 2026-06-14) ───────────────────────
# IP_BASE пуст (по умолчанию) → качаем с публичного GitHub raw, как сейчас,
# поведение НЕ меняется. IP_BASE задан (команда из бота) → качаем через
# token-gated gateway, Authorization шлём ТОЛЬКО туда (github raw на чужой
# Bearer отдаёт 404 — проверено 2026-06-14).
IP_BASE="${IP_BASE:-}"
_ip_token() {
  printf '%s' "${COURSE_TOKEN:-${VIP_TOKEN:-$(cat "$HOME/.openclaw/course-token" 2>/dev/null || true)}}"
}
ip_dl() {  # $1=путь под /assets/ (gateway)  $2=полный github-url  $3=dest
  if [[ -n "$IP_BASE" ]]; then
    curl -fsSL --max-time 20 -H "Authorization: Bearer $(_ip_token)" "${IP_BASE%/}/assets/$1" -o "$3" 2>/dev/null
  else
    curl -fsSL --max-time 20 "$2" -o "$3" 2>/dev/null
  fi
}

# === BUNDLE_LIB_BEGIN ===
if [[ -d "${SCRIPT_DIR}/lib" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/lib/ui.sh"
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/lib/preflight.sh"
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/lib/telemetry.sh"
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/lib/debug-bundle.sh"
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/lib/agents.sh"
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/lib/vip.sh"
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/lib/course-token.sh"
else
  # Скачиваем lib/ во временную папку
  _LIB_TMP=$(mktemp -d -t openclaw-agents-lib.XXXXXX)
  _LIB_COMMIT="${INSTALLER_COMMIT:-main}"
  if [[ "$_LIB_COMMIT" == "__COMMIT_PLACEHOLDER__" || "$_LIB_COMMIT" == *dev* ]]; then
    _LIB_COMMIT="main"
  fi
  _LIB_BASE="https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/${_LIB_COMMIT}/scripts/lib"
  for _mod in ui preflight telemetry debug-bundle agents vip course-token; do
    if ! ip_dl "openclaw-agents-pack/scripts/lib/${_mod}.sh" "${_LIB_BASE}/${_mod}.sh" "${_LIB_TMP}/${_mod}.sh"; then
      # wave 9 BUG-06: localized curl-error message с хост-разделением
      # и подсказкой про git clone fallback. До этой точки ui.sh ещё
      # не подключён, поэтому plain-text без цветов.
      echo ""
      echo "ERROR: не смог скачать scripts/lib/${_mod}.sh с GitHub raw."
      echo "       Хост: raw.githubusercontent.com"
      echo "       Commit: ${_LIB_COMMIT}"
      echo "       Timeout: 10 сек"
      echo ""
      echo "Возможные причины:"
      echo "  • raw.githubusercontent.com временно недоступен или режется фаерволом"
      echo "  • Корпоративный VPN / прокси не пропускает HTTPS к GitHub"
      echo "  • Слишком медленное соединение (10 сек на файл не хватило)"
      echo "  • Указанный коммит (${_LIB_COMMIT}) не существует на GitHub"
      echo ""
      echo "Что делать:"
      echo "  1. Проверь интернет. Если включён VPN — ВЫКЛЮЧИ его (сервер в РФ,"
      echo "     с заграничным VPN до него бывает не достучаться) и повтори."
      echo "  2. Запусти ту же команду из @AITeamVIPBot ещё раз — она продолжит"
      echo "     с того места и доустановит недостающее."
      echo "  3. Старые команды с github (releases / git clone / raw) больше НЕ"
      echo "     работают — репозитории закрыты. Только команда из бота."
      echo ""
      exit 1
    fi
    # shellcheck disable=SC1090
    source "${_LIB_TMP}/${_mod}.sh"
  done
  # Оставляем _LIB_TMP до конца скрипта (source может подгрузить ещё что-то)
fi
# === BUNDLE_LIB_END ===

# ─── --collect-debug: ничего не ставим, собираем bundle и выходим ─
if [[ "$COLLECT_DEBUG_ONLY" == true ]]; then
  echo ""
  echo -e "${BOLD}${CYAN}📦 Сбор debug-bundle для саппорта${NC}"
  echo -e "${DIM}   agents-pack v${INSTALLER_VERSION} (${INSTALLER_COMMIT})${NC}"
  echo -e "${DIM}   ℹ️  Курс-токен не запрашивается — read-only режим.${NC}"
  echo -e "${BOLD}${YELLOW}   ⚠ Это НЕ установка (только диагностика). Для установки агентов:${NC}"
  echo -e "${GREEN}   запусти команду из @AITeamVIPBot${NC}"
  collect_debug_bundle "manual (user ran --collect-debug)"
  exit 0
fi

# ─── Баннер ──────────────────────────────────────────────────────
# `clear` падает с «TERM environment variable not set» в headless-окружении
# (CI Docker, некоторые SSH-шеллы). Игнорируем, баннер напечатается поверх
# предыдущего вывода — не критично.
clear 2>/dev/null || true
echo ""
echo -e "${BOLD}${MAGENTA}"
cat << 'LOGO'
    _    ___   _____ _____    _    __  __   ____    ___
   / \  |_ _| |_   _| ____|  / \  |  \/  | |___ \  / _ \
  / _ \  | |    | | |  _|   / _ \ | |\/| |   __) || | | |
 / ___ \ | |    | | | |___ / ___ \| |  | |  / __/ | |_| |
/_/   \_\___|   |_| |_____/_/   \_\_|  |_| |_____(_)___/
LOGO
echo -e "${BOLD}${MAGENTA}              T O N Y   T R U E   ×   С Е Р Д И Т О В${NC}"
echo -e "${NC}"
echo ""
echo -e "${BOLD}${WHITE}   Собери команду ИИ-агентов,${NC}"
echo -e "${BOLD}${WHITE}   которая работает на тебя 24/7${NC}"
echo -e "${BOLD}${WHITE}   и становится умнее каждую неделю${NC}"
echo ""
echo -e "${DIM}   Не просто боты — готовая ИИ-команда с супер-агентом${NC}"
echo -e "${DIM}   и ролями под бизнес. Не нанимать, не обучать,${NC}"
echo -e "${DIM}   не увольнять — установил, работает.${NC}"
echo ""
echo -e "${DIM}   v${INSTALLER_VERSION}${NC}"

# Wave 28: показать клиенту что система определяется автоматически.
# В VPS-режиме (флаг --vps) — приоритетная плашка. Иначе — auto-detect
# ОС через detect_environment() из preflight.sh.
if [[ "$VPS_MODE" == true ]]; then
  echo -e "${BOLD}${MAGENTA}   🌐 VPS-режим: Linux-сервер, headless${NC}"
else
  _detected_os=$(detect_environment 2>/dev/null || echo "unknown")
  case "$_detected_os" in
    macos)        _os_label="macOS" ;;
    linux)        _os_label="Linux" ;;
    wsl)          _os_label="Windows (WSL)" ;;
    windows-bash) _os_label="Windows (Git Bash)" ;;
    *)            _os_label="неизвестная ОС" ;;
  esac
  echo -e "${DIM}   🖥  Система определена автоматически: ${BOLD}${_os_label}${NC}${DIM}.${NC}"
  echo -e "${DIM}      Если ты на VPS / сервере по SSH — перезапусти с флагом ${BOLD}--vps${NC}${DIM}.${NC}"
  unset _detected_os _os_label
fi
echo ""
echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ─── --diagnose-only: быстрая проверка без изменений ────────────
if [[ "$DIAGNOSE_ONLY" == true ]]; then
  echo -e "${DIM}   ℹ️  Курс-токен не запрашивается — read-only режим.${NC}"
  echo -e "${BOLD}${YELLOW}   ⚠ Это НЕ установка (только проверка). Для установки агентов:${NC}"
  echo -e "${GREEN}   запусти команду из @AITeamVIPBot${NC}"
  echo ""
  # scripts/diagnose-agents.sh делает всю работу; если его нет — fallback
  DIAG_SCRIPT="${SCRIPT_DIR}/diagnose-agents.sh"
  if [[ -f "$DIAG_SCRIPT" ]]; then
    bash "$DIAG_SCRIPT"
  else
    # minimal inline diagnose
    echo -e "${BOLD}Agents-pack diagnose${NC}"
    echo ""
    preflight_openclaw || true
    echo ""
    if command -v openclaw &>/dev/null; then
      echo -e "${BOLD}Текущие агенты:${NC}"
      openclaw agents list 2>&1 | head -20
      echo ""
      echo -e "${BOLD}Routing bindings:${NC}"
      openclaw agents bindings 2>&1 | head -20
    fi
  fi
  exit 0
fi

# ─── --refresh-templates: обновить только системные md уже стоящих агентов ─
#
# Безопасный апдейт без потери данных:
#   • скачиваются свежие IDENTITY.md, AGENTS.md (+ SOUL/LEARNING/skills для VIP)
#   • MEMORY.md и USER.md НЕ трогаются
#   • настройки каналов / auth-profile / telegram-привязки НЕ трогаются
#   • старые файлы бэкапятся в ~/.openclaw/workspace-<agent>/.backups/<ts>/
#
# Типичный сценарий: вышла новая версия установщика (wave 6 → 7), клиент
# хочет получить обновлённые характеры/онбординг-протоколы, но у него уже
# есть наработанная MEMORY (контекст за недели) и заполненный USER.md
# (ответы на вопросы онбординга). Этот флаг — для них.
if [[ "$REFRESH_TEMPLATES_ONLY" == true ]]; then
  echo ""
  echo -e "${BOLD}${CYAN}♻️  Обновление шаблонов уже установленных агентов${NC}"
  echo -e "${DIM}   agents-pack v${INSTALLER_VERSION} (${INSTALLER_COMMIT})${NC}"
  echo -e "${DIM}   ℹ️  Курс-токен не запрашивается — обновление существующих,${NC}"
  echo -e "${DIM}      MEMORY.md и USER.md не тронутся. Если хочешь установить${NC}"
  echo -e "${DIM}      новых агентов — запусти команду без флага --refresh-templates.${NC}"
  echo ""

  # wave 9 BUG-05 guard: refresh-templates не использует main/auth-profile
  # для копирования (он только обновляет шаблоны workspace'а), так что
  # пропускаем deep JSON-validation. Иначе клиент с битым main не
  # сможет даже refresh применить.
  SKIP_AUTH_PROFILE_CHECK=true preflight_openclaw || exit 1

  # Ищем какие агенты уже стоят
  # wave 11: portable replacement для mapfile (bash 3.2 compat если
  # shebang-gate почему-то не сработал)
  FOUND_AGENTS=()
  while IFS= read -r _agent_id; do
    [[ -n "$_agent_id" ]] && FOUND_AGENTS+=("$_agent_id")
  done < <(find_installed_agents)

  if [[ ${#FOUND_AGENTS[@]} -eq 0 ]]; then
    warn "Не нашёл ни одного установленного агента."
    echo -e "   ${DIM}Если агенты точно стоят — проверьте 'openclaw agents list'.${NC}"
    echo -e "   ${DIM}Если это свежая машина — запустите установщик без флагов.${NC}"
    exit 0
  fi

  echo -e "   ${GREEN}Найдено агентов:${NC} ${FOUND_AGENTS[*]}"
  echo ""
  echo -e "   ${BOLD}Буду обновлять:${NC}"
  echo -e "     • IDENTITY.md, AGENTS.md  ${DIM}(все 6 ролей)${NC}"
  echo -e "     • SOUL.md, LEARNING.md, skills/*/SKILL.md  ${DIM}(только VIP: designer/coordinator/copywriter)${NC}"
  echo ""
  echo -e "   ${BOLD}НЕ буду трогать:${NC}"
  echo -e "     • MEMORY.md  ${DIM}(контекст сессий — ваш наработанный опыт)${NC}"
  echo -e "     • USER.md    ${DIM}(ответы онбординга — ваша ниша/ЦА/тон)${NC}"
  echo -e "     • Настройки каналов, Telegram-привязки, auth-profile"
  echo ""
  echo -e "   ${DIM}Старые файлы бэкапятся в ~/.openclaw/workspace-<agent>/.backups/<timestamp>/${NC}"
  echo ""

  for agent in "${FOUND_AGENTS[@]}"; do
    workspace_dir="$HOME/.openclaw/workspace-${agent}"
    if [[ ! -d "$workspace_dir" ]]; then
      warn "Нет workspace для ${agent} (${workspace_dir}) — пропускаю"
      continue
    fi
    echo -e "${BOLD}${CYAN}━━━ ${agent} ━━━${NC}"
    # R3-аудит: суффиксованный id (tech-2) → шаблоны лежат по роли (tech)
    _role=$(printf '%s' "$agent" | sed -E 's/-[0-9]+$//')
    prepare_workspace_from_templates "$_role" "$workspace_dir" "refresh" || {
      warn "Не получилось обновить ${agent} — продолжаю со следующим"
    }
    echo ""
  done

  record_telemetry "refresh_templates_ok" "ok"
  echo -e "${GREEN}${BOLD}✓ Готово.${NC} Шаблоны обновлены. MEMORY.md и USER.md сохранены."
  echo ""
  echo -e "${DIM}Чтобы откатиться — скопируйте файлы из .backups/<timestamp>/ обратно в workspace.${NC}"
  _last_exit_reason="refresh_complete"
  exit 0
fi

# ─── --enable-group-mode <chat_id>: настроить группу для уже стоящих ─
#
# Обходит R0–R5, идёт по установленным агентам и прописывает каждому:
#   • channels.telegram.accounts.<id>.groupPolicy = allowlist
#   • channels.telegram.accounts.<id>.groupAllowFrom += chat_id (дедуп)
#   • channels.telegram.accounts.<id>.groups.<chat_id>.requireMention = true
#
# Идемпотентно: повторный запуск с тем же chat_id ничего не ломает.
#
# Перед этим клиент ВРУЧНУЮ должен:
#   1. У @BotFather: /setprivacy → выбрать каждого бота → Disable
#   2. Создать TG-группу, добавить ВСЕХ ботов админами
#   3. Узнать chat_id (через @username_to_id_bot)
if [[ -n "$ENABLE_GROUP_MODE_CHAT_ID" ]]; then
  echo ""
  echo -e "${BOLD}${CYAN}👥 Настройка group-mode (TG-группа c командой агентов)${NC}"
  echo -e "${DIM}   agents-pack v${INSTALLER_VERSION} (${INSTALLER_COMMIT})${NC}"
  echo -e "${DIM}   ℹ️  Курс-токен не запрашивается — конфигурируем уже установленных.${NC}"
  echo ""

  preflight_openclaw || exit 1

  # wave 11: portable replacement для mapfile (bash 3.2 compat если
  # shebang-gate почему-то не сработал)
  FOUND_AGENTS=()
  while IFS= read -r _agent_id; do
    [[ -n "$_agent_id" ]] && FOUND_AGENTS+=("$_agent_id")
  done < <(find_installed_agents)

  if [[ ${#FOUND_AGENTS[@]} -eq 0 ]]; then
    warn "Не нашёл ни одного установленного агента."
    echo -e "   ${DIM}Сначала установите агентов обычным запуском без флагов.${NC}"
    exit 0
  fi

  if [[ ${#FOUND_AGENTS[@]} -lt 2 ]]; then
    warn "Найден только 1 агент: ${FOUND_AGENTS[0]}. Group-mode полезен от 2+ агентов."
    echo -e "   ${BOLD}${WHITE}Всё равно настроить? [y/N]:${NC}"
    read -r CONFIRM
    [[ "${CONFIRM:-N}" != "y" && "${CONFIRM:-N}" != "Y" ]] && exit 0
  fi

  echo -e "   ${GREEN}Найдено агентов:${NC} ${FOUND_AGENTS[*]}"
  echo -e "   ${GREEN}Chat ID группы:${NC} ${ENABLE_GROUP_MODE_CHAT_ID}"
  echo ""

  echo -e "   ${BOLD}${YELLOW}⚠️  Важно сделать ВРУЧНУЮ ДО этого шага:${NC}"
  echo -e "   1. У ${BOLD}@BotFather${NC} → /setprivacy → каждый бот → ${BOLD}Disable${NC}"
  echo -e "      (чтобы боты видели сообщения в группе, не только адресованные им)"
  echo -e "   2. Создать TG-группу, добавить ${BOLD}ВСЕХ${NC} ботов из списка как ${BOLD}админов${NC}"
  echo -e "   3. Получить chat_id группы (через ${BOLD}@username_to_id_bot${NC} или из URL супергруппы)"
  echo ""
  echo -e "   ${BOLD}${WHITE}Сделано? Применить настройки группы? [y/N]:${NC}"
  read -r CONFIRM
  if [[ "${CONFIRM:-N}" != "y" && "${CONFIRM:-N}" != "Y" ]]; then
    echo -e "   ${DIM}Отменено. Запустите снова когда будете готовы.${NC}"
    exit 0
  fi

  for aid in "${FOUND_AGENTS[@]}"; do
    configure_group_membership "$aid" "$ENABLE_GROUP_MODE_CHAT_ID"
  done

  record_telemetry "group_mode_configured" "ok"
  echo ""
  echo -e "${GREEN}${BOLD}✓ Готово.${NC} Все агенты настроены на работу в группе ${ENABLE_GROUP_MODE_CHAT_ID}."
  echo ""
  echo -e "${DIM}Проверка: напишите в группе \"@<bot_username>, привет\" — ответит только тегнутый.${NC}"
  _last_exit_reason="group_mode_configured"
  exit 0
fi

# ─── Загружаем --config если указан ─────────────────────────────
if [[ -n "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  # Мост: config-файл документирован с VIP_TOKEN= (см. --help), но валидатор
  # ждёт COURSE_TOKEN. Без этого неинтерактивная VIP-установка падала.
  [[ -z "${COURSE_TOKEN:-}" && -n "${VIP_TOKEN:-}" ]] && COURSE_TOKEN="$VIP_TOKEN"
  # R2-аудит: VIP_MODE по ПРЕФИКСУ токена (раньше любой VIP_TOKEN= в файле
  # включал VIP_MODE — STD-токен в config получал отказ по тарифу).
  case "${COURSE_TOKEN:-}" in
    VIP-*) VIP_MODE=true ;;
    *)     VIP_MODE=false ;;
  esac
  SKIP_MENU=true
  ru "Конфиг загружен из: ${CONFIG_FILE}"
fi

# ─── Preflight: OpenClaw + сеть ─────────────────────────────────
preflight_openclaw || exit 1
preflight_network_check || true

# ─── Всегда подтягиваем АБСОЛЮТНО последнюю версию OpenClaw ──────
# Установщик должен ставить самый свежий движок. Даже если OpenClaw уже
# стоит (например, поставлен factory давно) — обновляем до latest, чтобы
# новые фичи (база знаний/extraPaths, вход в ChatGPT Codex, фикс
# memorySearch) точно работали. `npm install -g openclaw@latest`
# идемпотентен (ставит или обновляет). Без npm/сети — не падаем, идём
# с текущей версией. Сюда доходит только основной install-путь
# (refresh/diagnose возвращаются выше).
if command -v npm &>/dev/null; then
  echo ""
  echo -e "${DIM}   Подтягиваю последнюю версию OpenClaw (npm install -g openclaw@latest)...${NC}"
  _oc_before=$(openclaw --version 2>/dev/null | head -1)
  { npm install -g openclaw@latest 2>&1 || true; } | tail -3 | while IFS= read -r line; do
    echo -e "   ${DIM}${line}${NC}"
  done
  _oc_after=$(openclaw --version 2>/dev/null | head -1)
  if [[ -n "$_oc_after" && "$_oc_after" != "$_oc_before" ]]; then
    ok "OpenClaw обновлён до последней версии: ${_oc_after}"
  else
    ok "OpenClaw уже последней версии: ${_oc_after:-$_oc_before}"
  fi
  unset _oc_before _oc_after
else
  warn "npm не найден — обновление движка пропущено, продолжаю с текущей версией."
fi

# ─── wave 10.1 hotfix: bonjour-плагин на VPS ────────────────────
# Реальный кейс из чата клиентов: bonjour пытается анонсировать
# Gateway через mDNS, на VPS падает `CIAO PROBING CANCELLED` каждые
# ~45 сек, цикличный рестарт Gateway, бот не отвечает в Telegram.
# В --vps режиме отключаем плагин превентивно (он бесполезен на VPS,
# нужен только для авто-обнаружения Gateway iOS/Mac-приложением).
#
# wave 11 fix: добавлен guard на наличие openclaw — если preflight
# выше не сработал (например, openclaw действительно нет в PATH на
# свежей VPS), не пытаемся вызывать `openclaw config`.
if [[ "$VPS_MODE" == true ]] && command -v openclaw &>/dev/null; then
  echo ""
  echo -e "${DIM}--vps режим: проверяю bonjour-плагин (известная проблема на VPS)...${NC}"
  disable_bonjour_for_vps
fi

# ─── Telemetry consent (читаем из первого установщика если уже есть) ─
ensure_telemetry_consent
record_telemetry "agents_pack_start" "ok"

# ═══════════════════════════════════════════════════════════════
#  V_MAIN. ГЛАВНОЕ МЕНЮ (wave 21)
# ═══════════════════════════════════════════════════════════════
#
# Показывается СРАЗУ после banner (и early-exits), ДО запроса токена.
# Клиент видит линейку продуктов → выбирает что хочет → потом подтверждает
# токеном. Это UX как у любого интернет-магазина: «продукт → корзина →
# подтверждение оплаты».
#
# Пропускается если запуск non-interactive (любой из):
#   --install / --skip-menu  → клиент знает что хочет
#   --course-token <T>       → tier определит выбор
#   --only-agent <name>      → явный запрос конкретного агента
#   --config <file>          → CI / автоматический запуск
#   VPS_MODE=true            → headless установка
#
# Backwards-compat 100% — все существующие команды работают как раньше.

# ─────────────────────────────────────────────────────────────────
# Wave 25: установка Hermes super-agent (отдельный платный SKU)
# ─────────────────────────────────────────────────────────────────
#
# Hermes — open-source проект NousResearch (https://github.com/NousResearch/hermes-agent).
# Это «супер-агент» над всей командой OpenClaw — оркестрирует
# существующих агентов, делегирует задачи, держит общий контекст.
#
# Шаги установки (только если клиент выбрал опцию 4 в V_MAIN):
#   1. Запрос HRM-токена (отдельный platный SKU — выдаётся через бота)
#   2. Валидация HRM-токена (Ed25519, тот же ключ что VIP/STD/SUB)
#   3. Сканирование текущей OpenClaw-системы (список агентов + workspace)
#      → передаём как контекст следующему шагу
#   4. Confirm от клиента — мы покажем что собираемся запускать
#      (third-party installer от NousResearch)
#   5. Запуск официального Hermes installer:
#        curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
#   6. Verify (hermes --version)
#   7. Финал: команды для запуска (hermes gateway status, hermes config path)

install_hermes_super_agent() {
  # Wave 27: ANSI 3D-куб анимация (intro). Skip если нет python3 или
  # ENV HERMES_NO_INTRO=1 (для CI / non-interactive / нелюбителей анимаций).
  if [[ "${HERMES_NO_INTRO:-0}" != "1" ]] && command -v python3 &>/dev/null; then
    python3 - <<'HERMES_CUBE_EOF' 2>/dev/null || true
import math, time, sys

W, H = 80, 24
CUBE_WIDTH = 1.32
DISTANCE = 4
K1 = 18
INC = 0.05

FACE_CHARS = ['@', '$', '~', '#', ';', '+']
FACE_COLORS = [196, 46, 226, 33, 129, 208]
FACE_NORMALS = [(0,0,-1),(1,0,0),(-1,0,0),(0,0,1),(0,-1,0),(0,1,0)]
VERTS = [(-CUBE_WIDTH,-CUBE_WIDTH,-CUBE_WIDTH),(CUBE_WIDTH,-CUBE_WIDTH,-CUBE_WIDTH),
         (CUBE_WIDTH,CUBE_WIDTH,-CUBE_WIDTH),(-CUBE_WIDTH,CUBE_WIDTH,-CUBE_WIDTH),
         (-CUBE_WIDTH,-CUBE_WIDTH,CUBE_WIDTH),(CUBE_WIDTH,-CUBE_WIDTH,CUBE_WIDTH),
         (CUBE_WIDTH,CUBE_WIDTH,CUBE_WIDTH),(-CUBE_WIDTH,CUBE_WIDTH,CUBE_WIDTH)]
EDGES = [(0,1),(1,2),(2,3),(3,0),(4,5),(5,6),(6,7),(7,4),(0,4),(1,5),(2,6),(3,7)]

def rot(i,j,k,A,B,C):
    sA,cA=math.sin(A),math.cos(A); sB,cB=math.sin(B),math.cos(B); sC,cC=math.sin(C),math.cos(C)
    x1=i*cC-j*sC; y1=i*sC+j*cC; z1=k
    y2=y1*cA-z1*sA; z2=y1*sA+z1*cA; x2=x1
    z3=z2*cB-x2*sB; x3=z2*sB+x2*cB
    return x3,y2,z3

def frame(A,B,C):
    zbuf=[0.0]*(W*H); chbuf=[' ']*(W*H); cbuf=[0]*(W*H)
    for face in range(6):
        ni,nj,nk = FACE_NORMALS[face]
        sA,cA=math.sin(A),math.cos(A); sB,cB=math.sin(B),math.cos(B)
        if -ni*sB + nj*sA*cB + nk*cA*cB > 0: continue
        ch = FACE_CHARS[face]; col = FACE_COLORS[face]
        u = -CUBE_WIDTH
        while u < CUBE_WIDTH:
            v = -CUBE_WIDTH
            while v < CUBE_WIDTH:
                if face==0: i,j,k = u,v,-CUBE_WIDTH
                elif face==1: i,j,k = CUBE_WIDTH,v,u
                elif face==2: i,j,k = -CUBE_WIDTH,v,-u
                elif face==3: i,j,k = -u,v,CUBE_WIDTH
                elif face==4: i,j,k = u,-CUBE_WIDTH,-v
                else: i,j,k = u,CUBE_WIDTH,v
                x,y,z = rot(i,j,k,A,B,C); z += DISTANCE
                if z > 0.01:
                    ooz = 1.0/z
                    xp = int(W/2 + K1*ooz*x*2); yp = int(H/2 + K1*ooz*y)
                    if 0<=xp<W and 0<=yp<H:
                        idx = xp + yp*W
                        if ooz > zbuf[idx]:
                            zbuf[idx]=ooz; chbuf[idx]=ch; cbuf[idx]=col
                v += INC
            u += INC
    for a,b in EDGES:
        x0,y0,z0 = rot(*VERTS[a],A,B,C); x1,y1,z1 = rot(*VERTS[b],A,B,C)
        z0 += DISTANCE; z1 += DISTANCE
        for s in range(81):
            t = s/80; x=x0+(x1-x0)*t; y=y0+(y1-y0)*t; z=z0+(z1-z0)*t
            if z <= 0.01: continue
            ooz = 1.0/z
            xp = int(W/2 + K1*ooz*x*2); yp = int(H/2 + K1*ooz*y)
            if 0<=xp<W and 0<=yp<H:
                idx = xp + yp*W
                if ooz > zbuf[idx] - 1e-9:
                    zbuf[idx] = ooz + 1e-6; chbuf[idx] = '+'; cbuf[idx] = 231
    out = []
    for y in range(H):
        row = []
        for x in range(W):
            idx = x + y*W
            if chbuf[idx] != ' ':
                row.append(f"\033[38;5;{cbuf[idx]}m{chbuf[idx]}")
            else:
                row.append(' ')
        out.append(''.join(row) + "\033[0m")
    return '\n'.join(out)

A=B=C=0.0
sys.stdout.write("\033[2J\033[?25l")
try:
    for n in range(int(3.5 * 30)):
        sys.stdout.write("\033[H" + frame(A,B,C))
        sys.stdout.flush()
        A += 0.06; B += 0.045; C += 0.025
        time.sleep(1.0/30)
except KeyboardInterrupt:
    pass
finally:
    sys.stdout.write("\033[?25h\033[0m\n")
    sys.stdout.flush()
HERMES_CUBE_EOF
    clear 2>/dev/null || printf '\033[2J\033[H'
  fi

  echo ""
  echo -e "${BOLD}${MAGENTA}   ╔════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${MAGENTA}   ║      H E R M E S   —   С У П Е Р - А Г Е Н Т             ║${NC}"
  echo -e "${BOLD}${MAGENTA}   ╚════════════════════════════════════════════════════════╝${NC}"
  echo ""

  # ── 1. Запрос HRM-токена ────────────────────────────────────────
  echo -e "   ${BOLD}${WHITE}Hermes входит в Pro (VIP).${NC} Если у тебя Pro — токен подхватится сам."
  echo -e "   ${DIM}Отдельный HRM-токен (без Pro) — в ${BOLD}@AITeamVIPBot${NC}${DIM} (/start).${NC}"
  echo ""

  local machine_tg_id
  machine_tg_id=$(vip_detect_owner_tg_id)
  if [[ -z "$machine_tg_id" ]]; then
    echo -e "   ${BOLD}${WHITE}Введите ваш Telegram user ID:${NC}"
    read -r machine_tg_id
    [[ ! "$machine_tg_id" =~ ^[0-9]+$ ]] && { warn "TG ID должен быть числом."; return 1; }
  fi

  local hrm_token=""

  # Решение Антона 2026-06-11: Hermes включён в Pro. Если в кэше лежит
  # валидный VIP-токен — зачитываем его, токен заново не спрашиваем.
  local _hermes_cached=""
  _hermes_cached="$(_course_token_load_cache 2>/dev/null || true)"
  if [[ "$_hermes_cached" == VIP-* ]]; then
    if verify_vip_token "$_hermes_cached" "$machine_tg_id"; then
      echo -e "   ${GREEN}✓ У тебя Pro (VIP) — Hermes включён в твой тариф.${NC}"
      hrm_token="$_hermes_cached"
    fi
  fi

  local attempts=0
  while [[ -z "$hrm_token" && $attempts -lt 3 ]]; do
    attempts=$((attempts + 1))
    echo -e "   ${BOLD}${WHITE}Вставь HRM- или VIP-токен (попытка ${attempts}/3):${NC}"
    read -r hrm_token

    # Wave 17 санитизация — те же правила что для course-token
    hrm_token=$(printf '%s' "$hrm_token" | tr -d '[:space:]')
    hrm_token="${hrm_token//—/-}"
    hrm_token="${hrm_token//–/-}"
    hrm_token="${hrm_token//‐/-}"
    hrm_token="${hrm_token//‑/-}"
    hrm_token="${hrm_token//\"/}"
    hrm_token="${hrm_token//\'/}"

    if [[ -z "$hrm_token" ]]; then
      warn "Пустой ввод."
      continue
    fi

    if [[ ! "$hrm_token" =~ ^(HRM|VIP)- ]]; then
      warn "Нужен токен «HRM-...» или Pro-токен «VIP-...» (Base/подписка не дают Hermes)."
      echo -e "   ${DIM}Pro-клиентам Hermes включён; отдельный HRM — в @AITeamVIPBot.${NC}"
      continue
    fi

    verify_vip_token "$hrm_token" "$machine_tg_id"
    local rc=$?
    case $rc in
      0)
        echo -e "   ${GREEN}✓${NC} HRM-токен подтверждён."
        break
        ;;
      3)
        warn "HRM-токен привязан к другому Telegram ID."
        echo -e "   ${DIM}Используй ТОТ ЖЕ Telegram-аккаунт что при покупке.${NC}"
        ;;
      *)
        warn "HRM-токен не прошёл проверку (код $rc)."
        echo -e "   ${DIM}Возможно: повреждён при копировании / отозван / устарел.${NC}"
        ;;
    esac
    hrm_token=""
  done

  if [[ -z "$hrm_token" ]]; then
    echo ""
    echo -e "${BOLD}${RED}   ✗  Hermes-доступ не подтверждён за 3 попытки (нужен VIP- или HRM-токен). Отказ.${NC}"
    record_telemetry "hermes_token_rejected" "ok"
    return 1
  fi

  # ── 2. Сканирование текущей OpenClaw-системы ────────────────────
  echo ""
  echo -e "   ${DIM}Сканирую твою OpenClaw-установку...${NC}"
  local scan_file
  scan_file=$(mktemp -t openclaw-scan.XXXXXX.json 2>/dev/null || echo "/tmp/openclaw-scan-$$.json")

  local agents_list=""
  if [[ -d "$HOME/.openclaw/agents" ]]; then
    agents_list=$(ls -1 "$HOME/.openclaw/agents" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
  fi
  local workspaces=""
  workspaces=$(ls -1d "$HOME"/.openclaw/workspace* 2>/dev/null | wc -l | tr -d ' ')

  cat > "$scan_file" <<EOF
{
  "scan_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "openclaw_home": "$HOME/.openclaw",
  "agents_installed": "${agents_list}",
  "workspaces_count": ${workspaces},
  "openclaw_cli_available": $(command -v openclaw &>/dev/null && echo true || echo false)
}
EOF

  echo -e "   ${GREEN}✓${NC} Скан сохранён: ${DIM}${scan_file}${NC}"
  echo -e "   ${DIM}Найдено агентов: $(echo "$agents_list" | tr ',' ' ')${NC}"
  echo -e "   ${DIM}Workspaces: ${workspaces}${NC}"
  echo ""

  # ── 3. Confirm перед third-party install ────────────────────────
  echo -e "${BOLD}${YELLOW}   ⚠  ВАЖНО: дальше запустится official installer Hermes${NC}"
  echo -e "   ${DIM}Источник: https://github.com/NousResearch/hermes-agent${NC}"
  echo -e "   ${DIM}Команда: curl -fsSL .../scripts/install.sh | bash${NC}"
  echo -e "   ${DIM}Установит: ~/.hermes/ (~200MB venv + Python deps + macOS LaunchAgent)${NC}"
  echo ""
  echo -e "   ${BOLD}${WHITE}Продолжить? [y/N]:${NC}"
  read -r _hermes_confirm
  if [[ "${_hermes_confirm:-n}" != "y" && "${_hermes_confirm:-n}" != "Y" ]]; then
    echo -e "   ${DIM}Установка Hermes отменена. HRM-токен остался валидным,${NC}"
    echo -e "   ${DIM}можешь запустить ту же команду снова когда будешь готов.${NC}"
    record_telemetry "hermes_install_declined" "ok"
    return 0
  fi

  # ── 4. Запуск Hermes installer ──────────────────────────────────
  echo ""
  echo -e "   ${DIM}Запускаю Hermes installer (это займёт 3-5 минут)...${NC}"
  echo ""
  if curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash; then
    record_telemetry "hermes_installer_completed" "ok"
  else
    warn "Hermes installer завершился с ошибкой. Проверь логи выше."
    record_telemetry "hermes_installer_failed" "ok"
    return 1
  fi

  # ── 5. Verify ───────────────────────────────────────────────────
  echo ""
  if command -v hermes &>/dev/null || [[ -x "$HOME/.hermes/hermes-agent/venv/bin/hermes" ]]; then
    local hermes_version
    if command -v hermes &>/dev/null; then
      hermes_version=$(hermes --version 2>/dev/null | head -1 || echo "unknown")
    else
      hermes_version=$("$HOME/.hermes/hermes-agent/venv/bin/hermes" --version 2>/dev/null | head -1 || echo "unknown")
    fi
    echo -e "   ${GREEN}✓${NC} Hermes установлен: ${BOLD}${hermes_version}${NC}"
  else
    warn "Не нашёл hermes-команду после установки. Возможно installer не завершился."
    return 1
  fi

  # ── 6. Финал ────────────────────────────────────────────────────
  echo ""
  echo -e "${BOLD}${GREEN}   ╔════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${GREEN}   ║   ✓  Hermes готов!                                       ║${NC}"
  echo -e "${BOLD}${GREEN}   ╚════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "   ${BOLD}${WHITE}Что дальше:${NC}"
  echo -e "   ${CYAN}1.${NC} Проверь статус gateway:  ${BOLD}hermes gateway status${NC}"
  echo -e "   ${CYAN}2.${NC} Открой config:           ${BOLD}hermes config path${NC}"
  echo -e "   ${CYAN}3.${NC} Логи gateway:            ${BOLD}~/.hermes/logs/gateway.log${NC}"
  echo ""
  echo -e "   ${DIM}OpenClaw-скан передан Hermes как контекст: ${scan_file}${NC}"
  echo -e "   ${DIM}Документация: https://github.com/NousResearch/hermes-agent${NC}"
  echo ""
  record_telemetry "hermes_install_success" "ok"
  return 0
}

MAIN_CHOICE=""

# Wave 25: детекция установленного OpenClaw.
# Используется в V_MAIN чтобы условно показывать 4-й пункт «Hermes»
# (super-agent над OpenClaw), который имеет смысл только если движок
# уже стоит. На свежей машине без OpenClaw — Hermes-опция скрыта.
detect_openclaw() {
  command -v openclaw &>/dev/null && return 0
  [[ -d "$HOME/.openclaw" ]] && return 0
  return 1
}

OPENCLAW_INSTALLED=false
if detect_openclaw; then
  OPENCLAW_INSTALLED=true
fi

# Объединённый поток (R2-аудит): factory уже сохранил токен в кэш — тариф
# известен ДО меню. Подставляем правильный дефолт Enter (раньше дефолт был
# всегда Pro, и STD-клиент в чейне падал «несоответствие тарифа»).
_cached_tier=""
_ct="$(_course_token_load_cache 2>/dev/null || true)"
case "${_ct:-}" in
  VIP-*) _cached_tier="VIP" ;;
  STD-*) _cached_tier="STD" ;;
  SUB-*) _cached_tier="SUB" ;;
  HRM-*) _cached_tier="HRM" ;;
esac
unset _ct
_menu_default=3
case "$_cached_tier" in
  STD) _menu_default=2 ;;
  SUB) _menu_default=1 ;;
  HRM) _menu_default=4 ;;   # HRM-токен = Hermes; пункт 4 и есть его покупка
esac

if [[ "$SKIP_MENU" != true && \
      -z "$ONLY_AGENT" && \
      -z "$COURSE_TOKEN" && \
      -z "${CONFIG_FILE:-}" && \
      "$VPS_MODE" != true ]]; then

  echo ""
  echo -e "${BOLD}${MAGENTA}   ╔════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${MAGENTA}   ║                  Г Л А В Н О Е   М Е Н Ю               ║${NC}"
  echo -e "${BOLD}${MAGENTA}   ╚════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "   ${BOLD}${WHITE}Что ставим?${NC}"
  echo ""
  echo -e "   ${BOLD}${CYAN}  1)${NC}  ${BOLD}OpenClaw${NC}   ${DIM}— только движок (без агентов)${NC}"
  echo ""
  echo -e "   ${BOLD}${GREEN}  2)${NC}  ${BOLD}Base${NC}       ${DIM}— 3 базовых агента${NC}"
  echo -e "       🔧 Технарь  📈 Маркетолог  🎬 Продюсер"
  echo ""
  echo -e "   ${BOLD}${YELLOW}  3)${NC}  ${BOLD}Pro${NC}        ${DIM}— 8 агентов (полный набор)${NC}  ${GREEN}← рекомендуется${NC}"
  echo -e "       🔧 Технарь  📈 Маркетолог  🎬 Продюсер  🎨 Дизайнер"
  echo -e "       🧭 Координатор  ✍️ Копирайтер  💰 Лидоруб  🎥 Контент-агент"
  if [[ "$OPENCLAW_INSTALLED" == true ]]; then
    echo ""
    echo -e "   ${BOLD}${MAGENTA}  4)${NC}  ${BOLD}Hermes${NC}     ${DIM}— супер-агент над всей командой${NC}  ${YELLOW}★${NC}"
    echo -e "       ${DIM}Анализирует твою OpenClaw-установку и оркестрирует агентов${NC}"
    echo -e "       ${DIM}Входит в Pro (VIP) · отдельно — по HRM-токену${NC}"
  fi
  echo ""
  divider
  if [[ -n "$_cached_tier" ]]; then
    case "$_cached_tier" in
      VIP) echo -e "   ${GREEN}✓ Твой тариф по токену: Pro — просто нажми Enter.${NC}" ;;
      STD) echo -e "   ${GREEN}✓ Твой тариф по токену: Base — просто нажми Enter.${NC}" ;;
      SUB) echo -e "   ${DIM}Твой тариф: OpenClaw (подписка) — доп. агенты в него не входят.${NC}" ;;
      HRM) echo -e "   ${DIM}Твой токен — Hermes (HRM): это пункт 4. Просто нажми Enter.${NC}" ;;
    esac
    echo ""
  fi
  _vmain_tries=0
  while :; do
  _vmain_tries=$((_vmain_tries + 1))
  if [[ "$OPENCLAW_INSTALLED" == true ]]; then
    echo -e "   ${BOLD}${WHITE}Выбор [1/2/3/4, Enter = ${_menu_default}]:${NC}"
  else
    echo -e "   ${BOLD}${WHITE}Выбор [1/2/3, Enter = ${_menu_default}]:${NC}"
  fi
  echo ""
  read -r _main_menu_input || _main_menu_input=""

  case "${_main_menu_input:-$_menu_default}" in
    1)
      # OpenClaw — движок уже стоит (поставлен factory'ем на шаге 1).
      # Этот установщик ставит АГЕНТОВ — а клиент не хочет агентов.
      # Graceful exit без запроса токена.
      MAIN_CHOICE="openclaw"
      echo ""
      echo -e "   ${BOLD}${GREEN}✓${NC} Ок — оставляю только OpenClaw движок (без AI-агентов)."
      echo ""
      echo -e "   ${DIM}OpenClaw уже работает (поставлен первым установщиком).${NC}"
      echo -e "   ${DIM}Если захочешь добавить агентов — запусти эту команду снова,${NC}"
      echo -e "   ${DIM}выбери 2 (Base) или 3 (Pro).${NC}"
      echo ""
      record_telemetry "main_menu_openclaw_exit" "ok"
      _last_exit_reason="main_menu_openclaw"
      exit 0
      ;;
    2)
      MAIN_CHOICE="base"
      record_telemetry "main_menu_base" "ok"
      break
      ;;
    3|"")
      MAIN_CHOICE="pro"
      record_telemetry "main_menu_pro" "ok"
      break
      ;;
    4)
      if [[ "$OPENCLAW_INSTALLED" != true ]]; then
        echo ""
        echo -e "   ${YELLOW}Опция 4 (Hermes) доступна только если OpenClaw уже установлен.${NC}"
        echo -e "   ${DIM}Сначала запусти первый установщик (factory) — поставь OpenClaw движок.${NC}"
        _last_exit_reason="hermes_no_openclaw"
        exit 0
      fi
      MAIN_CHOICE="hermes"
      record_telemetry "main_menu_hermes" "ok"
      install_hermes_super_agent
      _last_exit_reason="hermes_install_done"
      exit 0
      ;;
    *)
      # R2-аудит: раньше тут был exit 0 — опечатка завершала установку «успехом»
      # (и чейн factory считал, что агенты поставлены). Теперь переспрашиваем.
      if [[ $_vmain_tries -ge 3 ]]; then
        echo ""
        echo -e "   ${YELLOW}Не распознал ввод трижды. Выход.${NC}"
        _last_exit_reason="main_menu_invalid"
        exit 1
      fi
      echo -e "   ${YELLOW}Не распознал «${_main_menu_input}». Введи 1, 2 или 3 (Enter = ${_menu_default}).${NC}"
      continue
      ;;
  esac
  done
fi

# ═══════════════════════════════════════════════════════════════
#  V0. COURSE-ТОКЕН — самое первое действие после preflight
# ═══════════════════════════════════════════════════════════════
#
# Wave 14: запрос токена ДО меню. Раньше клиент сначала видел меню
# Standard/VIP, выбирал, и только потом ему говорили «вставь токен».
# Это создавало конфликт: клиент мог выбрать VIP в меню, а у него на
# руках STD-токен → переустанавливать. Теперь:
#
#   1. Сразу спрашиваем токен (или берём из кэша от первого установщика)
#   2. Распознаём tier из payload (STD-... или VIP-...)
#   3. Дальше:
#      - STD-токен → автоматически Standard (3 агента), без меню
#      - VIP-токен → меню «VIP-набор (6) [рекомендуется] / Только Standard (3) /
#                    Только один агент / Диагностика / Debug»
#
# Wave 12 background: до wave 12 токен требовался только для VIP. С wave
# 12 любая свежая установка нуждается в course-token из @AITeamVIPBot:
#   - VIP-... → VIP-режим
#   - STD-... → Standard
#
# Кэш в ~/.openclaw/course-token (chmod 600) — на следующих запусках
# не просим снова. При неудачной валидации (отзыв / смена TG) — кэш
# сбрасывается автоматически.
#
# Backward-compat: --refresh-templates / --diagnose-only /
# --collect-debug / --enable-group-mode early-exit ДО этого блока,
# поэтому уже-установленные клиенты не страдают.
step_header "V0" "ПРОВЕРКА КУРС-ТОКЕНА"

# Автоматически берём TG ID клиента из настроек первого установщика.
# Если не нашли — попросим ввести руками.
MACHINE_TG_ID=$(vip_detect_owner_tg_id)

if [[ -z "$MACHINE_TG_ID" ]]; then
  explain "Не нашёл ваш Telegram ID в настройках OpenClaw." \
    "Возможно вы ещё не настраивали Telegram-канал в первом установщике." \
    "Узнать свой TG ID: напишите @userinfobot в Telegram."
  echo -e "   ${BOLD}${WHITE}Введите ваш Telegram user ID:${NC}"
  read -r MACHINE_TG_ID
  [[ ! "$MACHINE_TG_ID" =~ ^[0-9]+$ ]] && { warn "TG ID должен быть числом."; exit 1; }
else
  echo -e "   ${GREEN}✓${NC} Ваш Telegram ID (из настроек первого установщика): ${BOLD}${MACHINE_TG_ID}${NC}"
fi

# Mode: non-interactive если есть --config (acquire_course_token не пытается prompt)
_token_mode="interactive"
[[ -n "$CONFIG_FILE" ]] && _token_mode="non-interactive"

if ! acquire_course_token "$COURSE_TOKEN" "$MACHINE_TG_ID" "$_token_mode"; then
  echo ""
  echo -e "${BOLD}${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${RED}║                                                                ║${NC}"
  echo -e "${BOLD}${RED}║   ✗  УСТАНОВКА ОТКЛОНЕНА — курс-токен не валиден              ║${NC}"
  echo -e "${BOLD}${RED}║                                                                ║${NC}"
  echo -e "${BOLD}${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "   ${BOLD}${WHITE}Что произошло:${NC}"
  echo -e "   ${DIM}• Ты не ввёл токен (или ввёл пустую строку), либо${NC}"
  echo -e "   ${DIM}• Токен не прошёл проверку (отозван / битая подпись / другой TG)${NC}"
  echo ""
  echo -e "   ${BOLD}${WHITE}Что делать:${NC}"
  echo -e "   ${CYAN}1.${NC} Открой ${BOLD}@AITeamVIPBot${NC} в Telegram"
  echo -e "   ${CYAN}2.${NC} Напиши ${BOLD}/start${NC}"
  echo -e "   ${CYAN}3.${NC} Введи ${BOLD}email${NC} или ${BOLD}телефон${NC} которыми оплачивал курс"
  echo -e "   ${CYAN}4.${NC} Бот пришлёт токен вида ${BOLD}STD-...${NC} или ${BOLD}VIP-...${NC}"
  echo -e "   ${CYAN}5.${NC} Скопируй ВЕСЬ токен (часто длинная строка) и запусти установщик снова"
  echo ""
  echo -e "   ${BOLD}${WHITE}Если бот говорит «email не найден»:${NC}"
  echo -e "   ${DIM}• Проверь что вводишь email с которого реально оплачивал${NC}"
  echo -e "   ${DIM}• Возможно оплата ещё не дошла до базы (до 30 минут)${NC}"
  echo -e "   ${DIM}• Если уверен что оплачивал — пиши в саппорт-чат курса${NC}"
  echo ""
  echo -e "   ${BOLD}${WHITE}Если используешь токен с другого Telegram-аккаунта:${NC}"
  echo -e "   ${DIM}• Токены привязаны к TG (анти-шаринг). С чужим TG не работают.${NC}"
  echo -e "   ${DIM}• Открой @AITeamVIPBot с ТОГО ЖЕ аккаунта что используешь сейчас.${NC}"
  echo ""
  _last_exit_reason="token_rejected"
  exit 1
fi
unset _token_mode

# Backward-compat: VIP_TOKEN используется в остальном коде
VIP_TOKEN="$COURSE_TOKEN"

# Fire-and-forget аналитика установки (no-op пока VIP_ACTIVATION_ENDPOINT пуст).
# Передаём ПОЛНЫЙ токен — хэш считается внутри как sha256 (канон, совпадает с ботом).
vip_log_activation "$COURSE_TOKEN" "$MACHINE_TG_ID" "$COURSE_TIER" || true

ok "Курс-токен подтверждён: ${BOLD}${COURSE_TIER}${NC}-тариф. TG ID: ${MACHINE_TG_ID}"

# ═══════════════════════════════════════════════════════════════
#  V_MAIN валидация — соответствует ли выбор в главном меню токену
# ═══════════════════════════════════════════════════════════════
#
# Wave 21: если клиент выбрал в V_MAIN продукт выше своего тарифа —
# отказ с подсказкой как получить нужный токен.
#
# Матрица доступа:
#   MAIN_CHOICE=pro       требует токен VIP
#   MAIN_CHOICE=base      требует токен STD или VIP (Pro→Base downgrade OK)
#   MAIN_CHOICE=openclaw  — обработан в V_MAIN graceful-exit'ом ДО V0
#
# Если MAIN_CHOICE пуст (запуск через флаги --install/--course-token) —
# tier определяет режим автоматически через V0b (старая логика).

if [[ -n "$MAIN_CHOICE" ]]; then
  case "$MAIN_CHOICE" in
    pro)
      if [[ "$COURSE_TIER" != "VIP" ]]; then
        echo ""
        echo -e "${BOLD}${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}${RED}║   ✗  УСТАНОВКА ОТКЛОНЕНА — несоответствие тарифа              ║${NC}"
        echo -e "${BOLD}${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "   ${BOLD}${WHITE}Что произошло:${NC}"
        echo -e "   Ты выбрал ${BOLD}Pro${NC} (8 агентов), но твой токен — ${BOLD}${COURSE_TIER}${NC}-тарифа."
        echo ""
        echo -e "   ${BOLD}${WHITE}Что делать:${NC}"
        echo -e "   ${CYAN}•${NC} Если ты оплачивал ${BOLD}Pro${NC} — получи новый токен:"
        echo -e "     ${BOLD}@AITeamVIPBot${NC} → /start → email/телефон оплаты"
        echo -e "   ${CYAN}•${NC} Если оплачивал меньше — запусти установщик снова и выбери Base"
        echo ""
        _last_exit_reason="main_choice_tier_mismatch_pro"
        exit 1
      fi
      VIP_MODE=true
      SKIP_MENU=true  # V0b пропускаем — уже выбрали в V_MAIN
      ;;
    base)
      if [[ "$COURSE_TIER" != "STD" && "$COURSE_TIER" != "VIP" ]]; then
        echo ""
        echo -e "${BOLD}${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}${RED}║   ✗  УСТАНОВКА ОТКЛОНЕНА — несоответствие тарифа              ║${NC}"
        echo -e "${BOLD}${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "   ${BOLD}${WHITE}Что произошло:${NC}"
        echo -e "   Ты выбрал ${BOLD}Base${NC} (3 агента), но твой токен — ${BOLD}${COURSE_TIER}${NC}-тарифа."
        echo ""
        echo -e "   ${BOLD}${WHITE}Что делать:${NC}"
        echo -e "   ${CYAN}•${NC} Если оплачивал ${BOLD}Base${NC} — получи новый токен в ${BOLD}@AITeamVIPBot${NC}"
        echo -e "   ${CYAN}•${NC} Если у тебя ${BOLD}OpenClaw${NC} (подписка) — запусти снова и выбери опцию 1"
        echo ""
        _last_exit_reason="main_choice_tier_mismatch_base"
        exit 1
      fi
      VIP_MODE=false
      SKIP_MENU=true
      ;;
  esac
fi

# ═══════════════════════════════════════════════════════════════
#  V0c. SUB-tier — graceful exit (wave 16)
# ═══════════════════════════════════════════════════════════════
#
# SUB (subscription) = подписка на базовую установку. У клиента уже
# должен быть установлен OpenClaw + main-агент через первый установщик
# (factory). Дополнительных агентов в этом тарифе НЕТ — для них нужен
# Standard или VIP.
#
# Наш установщик (agents-pack) ставит ДОПОЛНИТЕЛЬНЫХ агентов, поэтому
# для SUB-tier — graceful exit с info-сообщением что делать.

if [[ "$COURSE_TIER" == "SUB" ]]; then
  echo ""
  echo -e "${BOLD}${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${YELLOW}║                                                                ║${NC}"
  echo -e "${BOLD}${YELLOW}║   ℹ️   Тариф OpenClaw (подписка) — базовая установка         ║${NC}"
  echo -e "${BOLD}${YELLOW}║                                                                ║${NC}"
  echo -e "${BOLD}${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "   ${BOLD}${WHITE}Твой тариф включает:${NC}"
  echo -e "   ${GREEN}✓${NC} OpenClaw движок + main-агент (ставится первым установщиком)"
  echo ""
  echo -e "   ${BOLD}${WHITE}Что это значит:${NC}"
  echo -e "   ${DIM}Этот установщик добавляет ${BOLD}дополнительных${NC}${DIM} агентов${NC}"
  echo -e "   ${DIM}(Технаря / Маркетолога / Продюсера / Дизайнера / Координатора /${NC}"
  echo -e "   ${DIM}Копирайтера). В тарифе OpenClaw они недоступны — это для Base / Pro.${NC}"
  echo ""
  echo -e "   ${BOLD}${WHITE}Что у тебя уже работает:${NC}"
  echo -e "   ${CYAN}•${NC} Открой Telegram, найди бота которого настраивал в первом установщике"
  echo -e "   ${CYAN}•${NC} Напиши ему ${BOLD}/start${NC} или просто сообщение — main-агент ответит"
  echo ""
  echo -e "   ${BOLD}${WHITE}Хочешь больше агентов?${NC}"
  echo -e "   ${DIM}Апгрейд на Base (3 агента) или Pro (8 агентов) — пиши в саппорт-чат курса.${NC}"
  echo -e "   ${DIM}После апгрейда получишь новый токен в @AITeamVIPBot и запустишь этот${NC}"
  echo -e "   ${DIM}установщик снова — он распознает новый тариф и поставит агентов.${NC}"
  echo ""
  record_telemetry "sub_tier_graceful_exit" "ok"
  _last_exit_reason="sub_tier_no_agents"
  exit 0
fi

# HRM — токен Hermes-агента (отдельный SKU). Агентов Base/Pro по нему НЕТ —
# раньше HRM проскальзывал как course-token и открывал Base-установку (R2-аудит).
if [[ "$COURSE_TIER" == "HRM" ]]; then
  echo ""
  echo -e "${BOLD}${YELLOW}ℹ️  Твой токен — HRM (супер-агент Hermes).${NC}"
  echo -e "   ${DIM}Агенты Base/Pro по нему не ставятся — HRM даёт Hermes.${NC}"
  echo ""
  echo -e "   ${BOLD}${WHITE}Поставить Hermes:${NC} запусти установщик ещё раз и выбери пункт ${BOLD}4 (Hermes)${NC}."
  echo ""
  record_telemetry "hrm_tier_graceful_exit" "ok"
  _last_exit_reason="hrm_tier_no_agents"
  exit 0
fi

# ═══════════════════════════════════════════════════════════════
#  V0b. Tier-based меню (wave 14)
# ═══════════════════════════════════════════════════════════════
#
# Логика:
#   - STD-tier: автоматически Standard (3 агента), без меню. Опции
#     diagnostic/debug всё равно доступны через CLI-флаги.
#   - VIP-tier: показываем меню. Default = VIP-набор (это и так есть
#     у клиента по тарифу). Опции:
#       1) VIP — 8 агентов  ← рекомендуется
#       2) Только Standard (3) — если клиент не хочет ставить всё
#       3) Только один агент — для диагностики/тестов
#       4) Диагностика — без изменений
#       5) Debug-bundle — собрать для саппорта
#   - SKIP_MENU=true (флаги --install / --vps / --vip-token прямо в CLI):
#     меню пропускаем, tier определяется автоматически (или через
#     --vip-token override для назад-совместимости).
#
# Если клиент пришёл с VIP-tier, но передал --install (без меню), и
# не указал --only — ставим VIP-набор (это его право по тарифу).

if [[ "$SKIP_MENU" != true && -z "$ONLY_AGENT" ]]; then
  if [[ "$COURSE_TIER" == "STD" ]]; then
    # STD (Base): без меню. Сообщение для прозрачности.
    echo ""
    echo -e "   ${GREEN}✓${NC} Тариф ${BOLD}Base${NC} — установлю 3 агента: 🔧 Технарь, 📈 Маркетолог, 🎬 Продюсер."
    VIP_MODE=false
    record_telemetry "menu_skipped_std_tier" "ok"
  else
    # VIP (Pro): меню — 3 пункта, по продуктовой линейке.
    # Wave 20: Pro / Base / OpenClaw как публичные названия тарифов.
    # Убраны «Установить только одного», «Диагностика», «Debug-bundle» —
    # это эксперт-флаги, в основном меню не нужны.
    explain "Выбери что поставить:"
    echo -e "   ${BOLD}${YELLOW}  1)${NC}  ${BOLD}Pro — 8 агентов${NC}  ${GREEN}← рекомендуется (по тарифу)${NC}"
    echo -e "       🔧 Технарь  📈 Маркетолог  🎬 Продюсер  🎨 Дизайнер"
    echo -e "       🧭 Координатор  ✍️ Копирайтер  💰 Лидоруб  🎥 Контент-агент"
    echo ""
    echo -e "   ${BOLD}${GREEN}  2)${NC}  ${BOLD}Base — 3 агента${NC}"
    echo -e "       🔧 Технарь  📈 Маркетолог  🎬 Продюсер"
    echo ""
    echo -e "   ${BOLD}${CYAN}  3)${NC}  ${BOLD}Только OpenClaw${NC}  ${DIM}(без агентов, чистый движок)${NC}"
    echo ""
    divider
    echo -e "   ${BOLD}${WHITE}Выбор [1/2/3, Enter = 1]:${NC}"
    echo ""
    read -r MENU_CHOICE
    case "${MENU_CHOICE:-1}" in
      1|"")
        VIP_MODE=true
        record_telemetry "menu_vip_full" "ok"
        ;;
      2)
        VIP_MODE=false
        record_telemetry "menu_vip_chose_std" "ok"
        ;;
      3)
        # «Только OpenClaw» — клиент с Pro решил оставить только базовый
        # движок без AI-агентов. Graceful exit с инструкцией как добавить
        # агентов потом.
        echo ""
        echo -e "   ${BOLD}${WHITE}Ок — оставляю только OpenClaw движок (без AI-агентов).${NC}"
        echo -e "   ${DIM}OpenClaw уже стоит (первая ступень установки). Этот шаг ничего не меняет.${NC}"
        echo -e "   ${DIM}Если захочешь агентов потом — запусти эту команду снова, выбери 1 или 2.${NC}"
        echo ""
        record_telemetry "menu_only_openclaw" "ok"
        _last_exit_reason="menu_only_openclaw"
        exit 0
        ;;
      *)
        echo "Не распознал выбор «$MENU_CHOICE». Выход."
        _last_exit_reason="invalid_menu_choice"
        exit 0
        ;;
    esac
  fi
elif [[ "$SKIP_MENU" == true && -z "$ONLY_AGENT" ]]; then
  # Non-interactive: tier определяет VIP_MODE автоматически
  if [[ "$COURSE_TIER" == "VIP" ]]; then
    VIP_MODE=true
  else
    VIP_MODE=false
  fi
fi

# Если клиент через меню выбрал «только один агент» и это VIP-агент —
# включаем VIP_MODE для корректной работы prepare_workspace_from_templates
# (SOUL/LEARNING/skills качаются только для VIP-ролей).
if [[ "$ONLY_AGENT" == "designer" || "$ONLY_AGENT" == "coordinator" || "$ONLY_AGENT" == "copywriter" \
      || "$ONLY_AGENT" == "leadcloser" || "$ONLY_AGENT" == "content" ]]; then
  VIP_MODE=true
fi

# Защита от попытки поставить VIP-набор имея STD-токен. Возможный путь
# сюда: --install через CLI с STD-токеном в кэше (SKIP_MENU=true) +
# --vip-token override (но wave 12 переименовал в --course-token, так
# что override-сценарий редок). Защищаемся всё равно.
if [[ "$VIP_MODE" == true && "$COURSE_TIER" != "VIP" ]]; then
  echo ""
  echo -e "${BOLD}${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${RED}║   ✗  УСТАНОВКА ОТКЛОНЕНА — несоответствие тарифа              ║${NC}"
  echo -e "${BOLD}${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "   ${BOLD}${WHITE}Что произошло:${NC}"
  echo -e "   Запрошен Pro-набор (8 агентов), но твой токен — ${BOLD}${COURSE_TIER}${NC}-тарифа."
  echo -e "   ${COURSE_TIER}-токен даёт доступ только к Base-набору (3 агента)."
  echo ""
  echo -e "   ${BOLD}${WHITE}Что делать:${NC}"
  echo -e "   ${CYAN}•${NC} Если ты оплатил ${BOLD}Pro${NC} — получи новый токен:"
  echo -e "     ${BOLD}@AITeamVIPBot${NC} → /start → email/phone оплаты"
  echo -e "   ${CYAN}•${NC} Если оплачивал ${BOLD}Base${NC} — запусти без флагов Pro-режима:"
  echo -e "     ${GREEN}запусти команду из @AITeamVIPBot (с Base-токеном)${NC}"
  echo ""
  _last_exit_reason="tier_mismatch"
  exit 1
fi

# ── Pro: интерактивный выбор «сколько и каких агентов» ──
# Переопределяет AGENTS_TO_INSTALL выбранным подмножеством. Пусто/ошибка → все 8.
select_pro_agents() {
  local ids=(tech marketer producer designer coordinator copywriter leadcloser content)
  local labels=("🔧 Технарь" "📈 Маркетолог" "🎬 Продюсер" "🎨 Дизайнер" \
                "🧭 Координатор" "✍️ Копирайтер" "💰 Лидоруб" "🎥 Контент-агент")
  local installed=""
  # </dev/null — чтобы openclaw НЕ съел наш stdin (иначе read ниже получит EOF)
  installed="$(openclaw agents list </dev/null 2>/dev/null || echo "")"

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

# ─── Определяем список агентов для установки ────────────────────
AGENTS_TO_INSTALL=()
if [[ -n "$ONLY_AGENT" ]]; then
  case "$ONLY_AGENT" in
    tech|marketer|producer|designer|coordinator|copywriter|leadcloser|content) AGENTS_TO_INSTALL=("$ONLY_AGENT") ;;
    *) echo "ERROR: --only должен быть tech/marketer/producer/designer/coordinator/copywriter/leadcloser/content, получено: $ONLY_AGENT"; exit 1 ;;
  esac
elif [[ "$VIP_MODE" == true ]]; then
  AGENTS_TO_INSTALL=(tech marketer producer designer coordinator copywriter leadcloser content)
else
  AGENTS_TO_INSTALL=(tech marketer producer)
fi

# Pro: дать клиенту выбрать сколько/каких агентов — только интерактив,
# не при --only / --install / --vps / non-TTY (там ставим всех 8).
if [[ "$VIP_MODE" == true && -z "$ONLY_AGENT" \
      && "${ASSUME_ALL_AGENTS:-false}" != true && -t 0 ]]; then
  select_pro_agents
fi

# ─── Активируем trap для auto debug-bundle на ERR ───────────────
trap 'on_installer_error $LINENO' ERR

# ═══════════════════════════════════════════════════════════════
#  R0. АНАЛИЗ ТЕКУЩЕГО СОСТОЯНИЯ
# ═══════════════════════════════════════════════════════════════
#
# Определяем что уже установлено, чтобы не просить у клиента токены
# на тех агентов, которых не надо ставить. Три сценария:
#
#   FRESH      — никого нет → просто ставим всех из AGENTS_TO_INSTALL
#   UPGRADE    — стоят 3 (Standard), ставим 5 (VIP) → default «дополнить
#                недостающих», существующих не трогаем (их Telegram-боты,
#                MEMORY.md, настроенная личность — всё сохраняется)
#   OVERWRITE  — уже стоит то же количество что ставим (напр. 3=3 или
#                5=5) → клиент чинит/обновляет → default «перезаписать»
#
# Этот шаг идёт ДО R2 (токены) — чтобы при upgrade клиент вводил 2 токена
# вместо 5 (только для недостающих), это не теряет время впустую.

step_header "R0" "АНАЛИЗ ТЕКУЩЕГО СОСТОЯНИЯ"

EXISTING_AGENTS=()
MISSING_AGENTS=()
for agent in "${AGENTS_TO_INSTALL[@]}"; do
  target_id="${agent}${SUFFIX:+-$SUFFIX}"
  if agent_exists "$target_id"; then
    EXISTING_AGENTS+=("$target_id")
  else
    MISSING_AGENTS+=("$agent")
  fi
done

CLEANUP_EXISTING=false  # ставим true если в R4 надо сначала снести старых

if [[ ${#EXISTING_AGENTS[@]} -eq 0 ]]; then
  # Сценарий FRESH (или доустановка непересекающегося набора — R3-аудит:
  # раньше при других установленных агентах это маскировалось под «свежую»)
  _all_installed="$(find_installed_agents 2>/dev/null | tr '\n' ' ')"
  if [[ -n "${_all_installed// /}" ]]; then
    echo -e "   ${GREEN}✓${NC} Нашёл следы прошлой установки — это доустановка."
    echo -e "   ${DIM}Следы ≠ принятый токен; безопасный путь — доустановить недостающее (Enter).${NC}"
    echo -e "   ${DIM}   (в системе уже есть: ${_all_installed})${NC}"
  else
    echo -e "   ${GREEN}✓${NC} Свежая установка — агентов в системе ещё нет"
  fi
  unset _all_installed
  record_telemetry "R0_fresh" "ok"

elif [[ ${#MISSING_AGENTS[@]} -eq 0 ]]; then
  # Сценарий OVERWRITE — всё из AGENTS_TO_INSTALL уже стоит.
  #
  # Wave 7: по умолчанию предлагаем «Обновить шаблоны» — безопасный апдейт
  # без потери MEMORY/USER. Это то что в 90% случаев нужно клиенту после
  # выхода новой версии установщика. Полная перезапись остаётся как опция
  # 2 — только для «сломалось, хочу с нуля».
  echo ""
  warn "Все агенты уже установлены:"
  for aid in "${EXISTING_AGENTS[@]}"; do
    echo -e "   ${YELLOW}○${NC} ${aid}"
  done
  echo ""
  if [[ -n "$CONFIG_FILE" ]]; then
    CLEANUP_EXISTING=true
    echo -e "   ${DIM}--config режим: перезаписываю начисто без вопросов.${NC}"
  else
    echo -e "   ${BOLD}${WHITE}Что делать?${NC}"
    echo -e "   ${CYAN}1)${NC} ${BOLD}Обновить шаблоны${NC} ${DIM}(безопасно: IDENTITY/AGENTS/SOUL/LEARNING/skills,${NC}"
    echo -e "       ${DIM}MEMORY.md + USER.md + настройки сохраняются)${NC}  ${GREEN}← рекомендуется${NC}"
    echo -e "   ${CYAN}2)${NC} Перезаписать начисто ${DIM}(снести всех и поставить заново — теряется MEMORY.md)${NC}"
    echo -e "   ${CYAN}3)${NC} Ничего не делать — выйти"
    echo ""
    echo -e "   ${BOLD}${WHITE}Выбор [1/2/3, Enter = 1]:${NC}"
    read -r R0_CHOICE
    case "${R0_CHOICE:-1}" in
      1)
        # Обновляем шаблоны в существующих workspace'ах и выходим —
        # никаких токенов, моделей, каналов спрашивать не надо.
        echo ""
        echo -e "${BOLD}${CYAN}♻️  Обновление шаблонов${NC}"
        echo ""
        for aid in "${EXISTING_AGENTS[@]}"; do
          workspace_dir="$HOME/.openclaw/workspace-${aid}"
          if [[ ! -d "$workspace_dir" ]]; then
            warn "Нет workspace для ${aid} — пропускаю"
            continue
          fi
          echo -e "${BOLD}${CYAN}━━━ ${aid} ━━━${NC}"
          # R3-аудит: суффиксованный id (tech-2) → шаблоны лежат по роли (tech)
          _role=$(printf '%s' "$aid" | sed -E 's/-[0-9]+$//')
          prepare_workspace_from_templates "$_role" "$workspace_dir" "refresh" || {
            warn "Не получилось обновить ${aid} — продолжаю со следующим"
          }
          echo ""
        done
        record_telemetry "R0_overwrite_refresh" "ok"
        echo -e "${GREEN}${BOLD}✓ Готово.${NC} Шаблоны обновлены. MEMORY.md и USER.md сохранены."
        echo ""
        echo -e "${DIM}Если что-то сломалось — старые файлы лежат в ~/.openclaw/workspace-<agent>/.backups/<timestamp>/${NC}"
        _last_exit_reason="refresh_complete"
        exit 0
        ;;
      2) CLEANUP_EXISTING=true ;;
      3) echo -e "   ${DIM}Выхожу. Для диагностики: ${GREEN}--diagnose-only${NC}"; exit 0 ;;
      *) warn "Не распознал выбор. Прерываю."; exit 1 ;;
    esac
  fi
  record_telemetry "R0_overwrite" "ok"

else
  # Сценарий UPGRADE — часть стоит, часть не хватает.
  # Типичный кейс: клиент апгрейднулся Standard→VIP, был на 3 агентах,
  # теперь ставит 5 → default «дополнить, сохранить старых».
  echo ""
  echo -e "   ${BOLD}${WHITE}🔼 Обнаружен апгрейд (не полная, но частичная установка):${NC}"
  echo ""
  echo -e "   ${GREEN}Уже установлены${NC} ${DIM}(будут сохранены; обновить их шаблоны — --refresh-templates):${NC}"
  for aid in "${EXISTING_AGENTS[@]}"; do
    echo -e "      ${GREEN}✓${NC} ${aid}"
  done
  echo ""
  echo -e "   ${YELLOW}Не хватает${NC} ${DIM}(будут добавлены):${NC}"
  for aid in "${MISSING_AGENTS[@]}"; do
    echo -e "      ${YELLOW}+${NC} ${aid}"
  done
  echo ""

  if [[ -n "$CONFIG_FILE" ]]; then
    # В non-interactive всегда upgrade (минимум действий)
    AGENTS_TO_INSTALL=("${MISSING_AGENTS[@]}")
    echo -e "   ${DIM}--config режим: доустанавливаю только недостающих.${NC}"
  else
    echo -e "   ${BOLD}${WHITE}Что делать?${NC}"
    echo -e "   ${CYAN}1)${NC} ${BOLD}Дополнить${NC} ${DIM}(поставить только недостающих, существующих не трогать)${NC}  ${GREEN}← рекомендуется${NC}"
    echo -e "   ${CYAN}2)${NC} Перезаписать всех ${DIM}(снести ВСЕХ ${#EXISTING_AGENTS[@]} и поставить заново ${#AGENTS_TO_INSTALL[@]}, теряете MEMORY.md)${NC}"
    echo -e "   ${CYAN}3)${NC} Прервать"
    echo ""
    echo -e "   ${BOLD}${WHITE}Выбор [1/2/3, Enter = 1]:${NC}"
    read -r R0_CHOICE
    case "${R0_CHOICE:-1}" in
      1)
        # Дополнить: AGENTS_TO_INSTALL = только missing, существующих не трогаем
        AGENTS_TO_INSTALL=("${MISSING_AGENTS[@]}")
        echo -e "   ${GREEN}✓${NC} Буду ставить только: ${AGENTS_TO_INSTALL[*]}"
        echo -e "   ${DIM}Существующие агенты (${EXISTING_AGENTS[*]}) остаются как есть${NC}"
        record_telemetry "R0_upgrade_add_missing" "ok"
        ;;
      2)
        CLEANUP_EXISTING=true
        echo -e "   ${YELLOW}!${NC} Перезапишу всех ${#AGENTS_TO_INSTALL[@]} агентов начисто. MEMORY.md существующих будет потеряна."
        record_telemetry "R0_upgrade_overwrite_all" "ok"
        ;;
      3) echo -e "   ${DIM}Прервано.${NC}"; exit 0 ;;
      *) warn "Не распознал выбор. Прерываю."; exit 1 ;;
    esac
  fi
fi

# ═══════════════════════════════════════════════════════════════
#  R1. Выбор модели
# ═══════════════════════════════════════════════════════════════
# R1 (тихий): никаких упоминаний моделей в процессе установки (решение
# Антона 2026-06-11). Агенты наследуют модель системы; если она не задана —
# техдефолт в конфиг (невидимо), модель клиент выбирает ПОСЛЕ установки.
DEFAULT_MODEL="opencode-go/deepseek-v4-flash"
AGENT_MODEL="${AGENT_MODEL:-}"  # из --config если задан
if [[ -z "$AGENT_MODEL" ]]; then
  _sys_model="$(openclaw config get agents.defaults.model.primary 2>/dev/null </dev/null | tr -d '\n\" ' )"
  AGENT_MODEL="${_sys_model:-$DEFAULT_MODEL}"
fi
record_telemetry "R1_model_chosen" "ok"

# ═══════════════════════════════════════════════════════════════
#  R1.5. EMBEDDING-ПАМЯТЬ (opt-in)
# ═══════════════════════════════════════════════════════════════
#
# Спрашиваем клиента, нужна ли ему «умная память» с семантическим поиском.
# OpenClaw v2026.4.22+ умеет text-embedding-3-large + sqlite-vec,
# но при свежей установке embedding не включён — это явный opt-in.
#
# Зачем нужно объяснение:
#   • Без embedding агент перечитывает MEMORY.md ЦЕЛИКОМ при каждом
#     ответе. Через 2-3 месяца это 50+ КБ контекста = долго и дорого.
#   • С embedding ищется СЕМАНТИЧЕСКИ — находит «ты говорил про
#     лендинг неделю назад» даже если сейчас спрашиваешь по-другому.
#   • Стоимость ≈$0.13 за 1M токенов = копейки в месяц для одного клиента.
#
# Флаги для non-interactive:
#   --enable-embedding — включить без вопросов (нужен OPENAI_EMBEDDING_API_KEY в env)
#   --no-embedding — пропустить шаг (в т.ч. для --config режима)

step_header "R1.5" "ПАМЯТЬ С СЕМАНТИЧЕСКИМ ПОИСКОМ (EMBEDDING)"

EMBEDDING_ENABLED=false
EMBEDDING_KEY=""
EMBEDDING_ENV_WRITTEN=false

if [[ "$NO_EMBEDDING" == true ]]; then
  echo -e "   ${DIM}--no-embedding: пропускаю шаг (память будет без семантического поиска).${NC}"
  record_telemetry "R1_5_skipped_flag" "ok"
elif [[ "$ENABLE_EMBEDDING_FLAG" == true ]]; then
  # Non-interactive: ключ должен быть в OPENAI_EMBEDDING_API_KEY или OPENAI_API_KEY
  if [[ -n "${OPENAI_EMBEDDING_API_KEY:-}" ]]; then
    EMBEDDING_KEY="$OPENAI_EMBEDDING_API_KEY"
  elif [[ -n "${OPENAI_API_KEY:-}" ]]; then
    EMBEDDING_KEY="$OPENAI_API_KEY"
  else
    warn "--enable-embedding: но не найден OPENAI_EMBEDDING_API_KEY / OPENAI_API_KEY. Пропускаю."
    EMBEDDING_KEY=""
  fi
  if [[ -n "$EMBEDDING_KEY" ]]; then
    EMBEDDING_ENABLED=true
    echo -e "   ${GREEN}✓${NC} --enable-embedding: ключ найден, включу embedding."
    record_telemetry "R1_5_enabled_flag" "ok"
  fi
elif [[ -n "$CONFIG_FILE" ]]; then
  # --config: пропускаем (можно добавить EMBEDDING_ENABLED=true в config-файле)
  if [[ "${EMBEDDING_ENABLED:-false}" == true ]]; then
    EMBEDDING_KEY="${OPENAI_EMBEDDING_API_KEY:-${OPENAI_API_KEY:-}}"
    if [[ -z "$EMBEDDING_KEY" ]]; then
      warn "--config: EMBEDDING_ENABLED=true но нет ключа. Пропускаю."
      EMBEDDING_ENABLED=false
    fi
  fi
else
  # Интерактивный путь: короткое объяснение + меню
  explain "Подключить ${BOLD}умную память${NC}? С ней агенты становятся ${BOLD}гораздо умнее${NC} —" \
    "помнят всё что ты им говорил, накапливают опыт работы с тобой." \
    "" \
    "Без памяти каждый разговор начинается с нуля." \
    "" \
    "${BOLD}Это НЕ подписка ChatGPT и не вход через браузер${NC} — нужен отдельный" \
    "API-ключ с platform.openai.com (sk-…) с подключённым billing." \
    "Стоит в среднем ${BOLD}\$15/месяц${NC} (платишь напрямую OpenAI)." \
    "Нужна ${BOLD}иностранная карта${NC} — российские не работают." \
    "" \
    "Виртуальная зарубежная карта за 5 минут:" \
    "   ${CYAN}https://t.me/WantToPayBot?start=w17851188--GUSNM${NC}"

  echo -e "   ${BOLD}${WHITE}Подключить умную память?${NC}"
  echo -e "   ${CYAN}1)${NC} Да ${DIM}(нужен OpenAI-ключ с billing — зарубежная карта)${NC}"
  echo -e "   ${CYAN}2)${NC} ${BOLD}Нет — установить без памяти${NC}  ${GREEN}← по умолчанию${NC}"
  echo -e "   ${DIM}      (включить позже одной командой: --enable-embedding)${NC}"
  echo ""
  echo -e "   ${BOLD}${WHITE}Выбор [1/2, Enter = 2]:${NC}"
  read -r EMB_CHOICE || EMB_CHOICE=""

  # Саппорт-данные 2026-06-10: дефолт «Да» валил установку у клиентов без
  # зарубежной карты. Теперь дефолт — без embedding (включается позже).
  case "${EMB_CHOICE:-2}" in
    1)
      echo ""
      echo -e "   ${BOLD}${WHITE}Использовать тот же ключ что для chat-модели?${NC}"
      echo -e "   ${CYAN}1)${NC} ${BOLD}Да${NC}, тот же OPENAI_API_KEY  ${GREEN}← по умолчанию${NC}"
      echo -e "   ${CYAN}2)${NC} Нет, введу отдельный (например, дешёвый ключ только под embedding)"
      echo ""
      echo -e "   ${BOLD}${WHITE}Выбор [1/2, Enter = 1]:${NC}"
      read -r KEY_CHOICE

      case "${KEY_CHOICE:-1}" in
        1)
          # Берём существующий из openclaw.json
          existing_key=$(openclaw config get 'env.vars.OPENAI_API_KEY' 2>/dev/null | tr -d '"' | tr -d ' ')
          if [[ -n "$existing_key" && "$existing_key" != "null" ]]; then
            EMBEDDING_KEY="$existing_key"
            echo -e "   ${GREEN}✓${NC} Использую существующий ключ"
          else
            echo -e "   ${DIM}Где взять ключ: ${CYAN}https://platform.openai.com/api-keys${NC}"
            echo -e "   ${DIM}Карта зарубежная: ${CYAN}https://t.me/WantToPayBot?start=w17851188--GUSNM${NC}"
            echo -e "   ${BOLD}${WHITE}OpenAI API-ключ (sk-...):${NC}"
            read -rs EMBEDDING_KEY
            echo ""
          fi
          ;;
        2)
          echo -e "   ${DIM}Где взять ключ: ${CYAN}https://platform.openai.com/api-keys${NC}"
          echo -e "   ${DIM}Карта зарубежная: ${CYAN}https://t.me/WantToPayBot?start=w17851188--GUSNM${NC}"
          echo -e "   ${BOLD}${WHITE}OpenAI API-ключ для embedding (sk-...):${NC}"
          read -rs EMBEDDING_KEY
          echo ""
          ;;
        *)
          warn "Не распознал выбор, использую тот же ключ."
          existing_key=$(openclaw config get 'env.vars.OPENAI_API_KEY' 2>/dev/null | tr -d '"' | tr -d ' ')
          [[ -n "$existing_key" && "$existing_key" != "null" ]] && EMBEDDING_KEY="$existing_key"
          ;;
      esac

      if [[ -z "$EMBEDDING_KEY" ]]; then
        warn "Ключ не введён. Пропускаю embedding."
        EMBEDDING_ENABLED=false
        record_telemetry "R1_5_no_key" "ok"
      else
        # Валидация ключа через ping
        echo -e "   ${DIM}Проверяю ключ через api.openai.com/v1/embeddings (5 сек)...${NC}"
        if validate_openai_embedding_key "$EMBEDDING_KEY"; then
          echo -e "   ${GREEN}✓${NC} Ключ валидный, embedding-доступ есть"
          EMBEDDING_ENABLED=true
          record_telemetry "R1_5_validated" "ok"
        else
          warn "Не смог валидировать ключ (сеть / неверный ключ / нет доступа к embedding-моделям)."
          echo -e "   ${BOLD}${WHITE}Что делать?${NC}"
          echo -e "   ${CYAN}1)${NC} Сохранить и продолжить ${DIM}(вдруг временный сбой сети)${NC}"
          echo -e "   ${CYAN}2)${NC} Пропустить embedding"
          echo ""
          echo -e "   ${BOLD}${WHITE}Выбор [1/2, Enter = 2]:${NC}"
          read -r FALLBACK
          case "${FALLBACK:-2}" in
            1)
              EMBEDDING_ENABLED=true
              record_telemetry "R1_5_skipped_validation" "ok"
              ;;
            *)
              EMBEDDING_ENABLED=false
              record_telemetry "R1_5_validation_failed" "ok"
              ;;
          esac
        fi
      fi
      ;;
    2)
      echo -e "   ${DIM}Без embedding — память будет читаться целиком (как раньше).${NC}"
      record_telemetry "R1_5_disabled" "ok"
      ;;
    *)
      warn "Не распознал выбор. Без embedding."
      record_telemetry "R1_5_invalid_choice" "ok"
      ;;
  esac
fi

# ═══════════════════════════════════════════════════════════════
#  R2. Сбор Telegram tokens
# ═══════════════════════════════════════════════════════════════
step_header "R2" "TELEGRAM BOT TOKENS"

explain "Создай по боту для каждого агента через ${BOLD}@BotFather${NC} в Telegram (${BOLD}/newbot${NC})."

# ─── Предупреждение про flood-блок @BotFather ───────────────────
# На Pro нужно много ботов (до 8). Если штамповать /newbot подряд,
# Telegram может временно заблокировать создание ботов (~сутки).
# Советуем создавать партиями по 2-3 с паузой. Установщик запрашивает
# токены по очереди (read блокирует) — клиент может делать паузы сам.
_bots_needed=${#AGENTS_TO_INSTALL[@]}
echo ""
echo -e "   ${BOLD}${YELLOW}⚠ Важно про создание ботов (нужно ${_bots_needed} шт.):${NC}"
echo -e "   ${YELLOW}   Не создавай всех ботов подряд за минуту!${NC} Если быстро штамповать"
echo -e "   ${YELLOW}   ботов через /newbot, Telegram может заблокировать создание новых${NC}"
echo -e "   ${YELLOW}   ботов примерно на сутки.${NC}"
echo -e "   ${DIM}   Безопасно: создай 2-3 бота → подожди 10-15 минут → ещё 2-3, и так далее.${NC}"
echo -e "   ${DIM}   Вставляй токены сюда по мере создания — установщик ждёт каждый ввод.${NC}"
echo ""

# NB: не используем `declare -A` (ассоциативные массивы) — они появились
# в bash 4.0, а macOS поставляет с /bin/bash 3.2 (Apple не обновляет
# из-за GPLv3). Клиент мог запустить через старый системный bash →
# установщик упадёт с "declare: -A: invalid option" (bug-репорт 2026-04-19).
#
# Вместо ассоциативных массивов используем динамически-именованные
# переменные: BOT_TOKEN_tech / BOT_TOKEN_marketer / BOT_TOKEN_producer.
# Запись: printf -v "BOT_TOKEN_$agent" '%s' "$token"
# Чтение: var="BOT_TOKEN_$agent"; value="${!var}"
# Работает в bash 3.2+.

# Саппорт 2026-06-10: интерактивный вопрос openclaw («Disable N unavailable
# skills?» → No → Setup cancelled, exit=1) ронял установку агентов. Превентивно
# чиним конфиг сами, отвечая Yes на всё. Безопасно и идемпотентно.
echo -e "   ${DIM}Профилактика конфига: openclaw doctor --fix (авто-Yes)...${NC}"
openclaw doctor --fix --yes &>/dev/null || true

# R3-аудит (live): probe отдаёт «- Telegram <agent>: … bot:@<username>» —
# собираем юзернеймы ботов УЖЕ установленных агентов, чтобы поймать повторное
# использование занятого бота (раньше ловили только дубли в рамках сессии).
# Best-effort: если gateway не отвечает — карта пустая, проверка пропускается.
_existing_bot_map="$(openclaw channels status --probe 2>/dev/null \
    | sed -nE 's/^- Telegram ([A-Za-z0-9_-]+):.*bot:@([A-Za-z0-9_]+).*/\2 \1/p')"

for agent in "${AGENTS_TO_INSTALL[@]}"; do
  emoji=""; label=""
  case "$agent" in
    tech)        emoji="🔧"; label="Технарь" ;;
    marketer)    emoji="📈"; label="Маркетолог" ;;
    producer)    emoji="🎬"; label="Продюсер" ;;
    designer)    emoji="🎨"; label="Дизайнер" ;;
    coordinator) emoji="🧭"; label="Координатор" ;;
    copywriter)  emoji="✍️"; label="Копирайтер" ;;
    leadcloser)  emoji="💰"; label="Лидоруб" ;;
    content)     emoji="🎥"; label="Контент-агент" ;;
  esac

  # Если токен передан через --config — берём оттуда как «preset»,
  # который попробуем один раз; если он невалидный, в следующей итерации
  # переходим к интерактивному вводу.
  env_var="BOT_TOKEN_$(echo "$agent" | tr '[:lower:]' '[:upper:]')"
  preset_token="${!env_var:-}"

  # Единый цикл ввод+валидация+проверка дубликатов.
  # Повтор делается через `continue`, а не `exit` (bug-репорт 2026-04-19 —
  # прошлая версия просто выходила после неудачной проверки).
  while true; do
    if [[ -n "$preset_token" ]]; then
      token="$preset_token"
      preset_token=""  # single-shot: в следующей итерации вернёмся к read
      echo -e "   ${DIM}Токен для ${label} взят из --config: ${env_var}${NC}"
    else
      echo ""
      echo -e "   ${BOLD}${WHITE}${emoji} Токен бота для ${label}:${NC}"
      echo -e "   ${DIM}(вставьте токен и нажмите Enter; символы не отображаются — это нормально)${NC}"

      # Читаем именно из управляющего терминала. В объединённом factory→agents
      # потоке stdin иногда уже не тот fd, откуда пользователь реально вводит
      # текст; `read` тогда тихо получает пустую строку и клиент видит ложное
      # «Токен пустой». /dev/tty убирает зависимость от stdin/pipe/eval.
      if [[ -r /dev/tty ]]; then
        IFS= read -r -s token </dev/tty || token=""
      else
        IFS= read -r -s token || token=""
      fi
      echo ""
      token="$(normalize_telegram_bot_token "$token")"

      # Если скрытый ввод всё равно получил 0 символов — даём безопасный
      # fallback с видимым вводом. Это не печатает токен в логи, но позволяет
      # человеку убедиться, что вставка реально попала в терминал.
      if [[ -z "$token" && -r /dev/tty ]]; then
        warn "Скрытый ввод получил 0 символов — похоже, вставка не попала в терминал."
        echo -e "   ${DIM}Вставьте токен ещё раз. Сейчас символы будут видны на экране; это нормально.${NC}"
        IFS= read -r token </dev/tty || token=""
        echo ""
        token="$(normalize_telegram_bot_token "$token")"
      fi
    fi

    # Нормализуем именно введённое значение: BotFather/Telegram Desktop иногда
    # кладут в буфер невидимый CR/пробел, из-за чего ручной `getMe` после `tr`
    # проходит, а установщик ложно ругается на токен.
    token="$(normalize_telegram_bot_token "$token")"

    # Считаем "пустой" в т.ч. строку из пробелов — клиент в config мог
    # написать BOT_TOKEN_TECH=" " что технически не пусто но бесполезно.
    if [[ -z "$(echo "$token" | tr -d '[:space:]')" ]]; then
      warn "Токен для ${label} пустой."
      if [[ -n "$CONFIG_FILE" ]]; then
        echo -e "   ${DIM}В --config режиме: проверь что ${BOLD}${env_var}${NC}${DIM} в config-файле${NC}"
        echo -e "   ${DIM}не пустой и не содержит только пробелы. Останавливаю установку.${NC}"
        exit 1
      fi
      continue
    fi

    # 1. Валидация через Telegram getMe
    echo -e "   ${DIM}Проверяю токен через Telegram API...${NC}"
    username=$(validate_telegram_token "$token" || echo "")
    if [[ -z "$username" ]]; then
      warn "Токен не прошёл проверку getMe. Возможные причины:"
      echo -e "   ${DIM}   • вы случайно скопировали не весь токен (обрезан)${NC}"
      echo -e "   ${DIM}   • токен недействителен — проверьте в @BotFather → /mybots${NC}"
      echo -e "   ${DIM}   • нет интернета / корпоративный firewall${NC}"
      [[ -n "$CONFIG_FILE" ]] && exit 1
      echo ""
      echo -e "   ${BOLD}${WHITE}Попробовать ввести другой токен? [Y/n]:${NC}"
      read -r retry
      if [[ "$retry" == "n" || "$retry" == "N" ]]; then
        echo -e "   ${DIM}Прервано. Создайте рабочего бота через @BotFather и запустите установщик снова.${NC}"
        exit 1
      fi
      continue  # ← правильный retry через continue, не exit
    fi

    # 2. Проверка что этот бот ещё не использован для другого агента.
    # Защита от типичной ошибки: клиент создал одного бота и вставил
    # его токен всем трём — тогда один и тот же бот оказывается
    # привязан ко всем агентам, роутинг ломается.
    already_used_for=""
    for prev_agent in "${AGENTS_TO_INSTALL[@]}"; do
      [[ "$prev_agent" == "$agent" ]] && break  # дошли до текущего — дальше не проверяем
      prev_var="BOT_USERNAME_$prev_agent"
      if [[ "${!prev_var:-}" == "$username" ]]; then
        already_used_for="$prev_agent"
        break
      fi
    done
    if [[ -n "$already_used_for" ]]; then
      warn "Бот @${username} уже указан для агента '${already_used_for}'."
      echo -e "   ${DIM}Нужны РАЗНЫЕ боты — по одному на каждого агента (всего ${#AGENTS_TO_INSTALL[@]}).${NC}"
      echo -e "   ${DIM}Откройте @BotFather в Telegram → /newbot → создайте ещё одного.${NC}"
      echo -e "   ${DIM}Если вы думали что ввели правильный — возможно, скопировали токен не того бота.${NC}"
      [[ -n "$CONFIG_FILE" ]] && exit 1
      echo ""
      echo -e "   ${BOLD}${WHITE}Попробовать другой токен? [Y/n]:${NC}"
      read -r retry
      if [[ "$retry" == "n" || "$retry" == "N" ]]; then
        echo -e "   ${DIM}Прервано. Создайте отдельного бота для ${label} и запустите снова.${NC}"
        exit 1
      fi
      continue
    fi

    # 2b. R3-аудит: …и против ботов УЖЕ установленных агентов (не только
    # введённых в этой сессии). Повторный ввод того же бота для ТОГО ЖЕ
    # агента (переустановка) — разрешён.
    if [[ -n "${_existing_bot_map:-}" ]]; then
      _ex_owner=$(printf '%s\n' "$_existing_bot_map" | awk -v u="$username" '$1==u{print $2; exit}')
      if [[ -n "$_ex_owner" && "$_ex_owner" != "$agent" ]]; then
        warn "Бот @${username} уже привязан к установленному агенту '${_ex_owner}'."
        echo -e "   ${DIM}Каждому агенту — свой бот. Создайте нового: @BotFather → /newbot.${NC}"
        [[ -n "$CONFIG_FILE" ]] && exit 1
        echo ""
        echo -e "   ${BOLD}${WHITE}Попробовать другой токен? [Y/n]:${NC}"
        read -r retry
        if [[ "$retry" == "n" || "$retry" == "N" ]]; then
          echo -e "   ${DIM}Прервано. Создайте отдельного бота для ${label} и запустите снова.${NC}"
          exit 1
        fi
        continue
      fi
      unset _ex_owner
    fi

    # Всё ок — сохраняем и выходим из цикла к следующему агенту
    printf -v "BOT_TOKEN_$agent" '%s' "$token"
    printf -v "BOT_USERNAME_$agent" '%s' "$username"
    echo -e "   ${GREEN}✓${NC} ${label}: @${username}"
    unset token  # не оставляем в переменной после save
    break
  done
done

echo ""
ok "Все токены проверены"

# Опциональный Telegram user ID для DM allowlist
OWNER_TG_ID="${OWNER_TG_ID:-}"
if [[ -z "$OWNER_TG_ID" && -z "$CONFIG_FILE" ]]; then
  echo ""
  echo -e "   ${BOLD}${WHITE}Ваш Telegram user ID (для allowlist):${NC}"
  echo -e "   ${DIM}Узнать: напишите @userinfobot в Telegram — он пришлёт число.${NC}"
  echo -e "   ${DIM}Можно пропустить (Enter) — но тогда бот запросит pairing-код при первой переписке.${NC}"
  read -r OWNER_TG_ID
fi
[[ "$OWNER_TG_ID" =~ ^[0-9]+$ ]] || OWNER_TG_ID=""  # только цифры, иначе обнуляем
record_telemetry "R2_tokens_collected" "ok"

# ═══════════════════════════════════════════════════════════════
#  R3. Cleanup существующих (если был выбран overwrite в R0)
# ═══════════════════════════════════════════════════════════════
#
# Если в R0 клиент выбрал «перезаписать начисто» — сносим всё старое.
# Если upgrade-сценарий («дополнить») — этот блок пропускается, и в R4
# ставятся только недостающие агенты, существующих не трогаем.
if [[ "$CLEANUP_EXISTING" == true && ${#EXISTING_AGENTS[@]} -gt 0 ]]; then
  step_header "R3" "ОЧИСТКА СТАРЫХ АГЕНТОВ"
  echo -e "   ${DIM}Сношу существующих, чтобы поставить начисто...${NC}"
  for aid in "${EXISTING_AGENTS[@]}"; do
    cleanup_agent_completely "$aid"
  done
  record_telemetry "R3_cleanup" "ok"
fi

# ═══════════════════════════════════════════════════════════════
#  R4. Установка агентов (основной цикл)
# ═══════════════════════════════════════════════════════════════
step_header "R4" "УСТАНОВКА АГЕНТОВ"

for agent in "${AGENTS_TO_INSTALL[@]}"; do
  [[ -z "$agent" ]] && continue  # пропущенные из-за коллизий
  target_id="${agent}${SUFFIX:+-$SUFFIX}"
  workspace_dir="$HOME/.openclaw/workspace-${target_id}"

  echo ""
  divider
  echo -e "${BOLD}${MAGENTA}→ Устанавливаю: ${target_id}${NC}"

  # 4.1 Скачиваем templates (IDENTITY/AGENTS/MEMORY/USER) в workspace
  echo -e "   ${DIM}Скачиваю шаблоны из репы...${NC}"
  if ! prepare_workspace_from_templates "$agent" "$workspace_dir"; then
    # wave 11 P1: при сбое сети (curl упал) останавливаем установку
    # текущего агента вместо тихого продолжения. Иначе workspace
    # будет частично заполнен и агент будет работать криво.
    warn "Не получилось загрузить шаблоны для ${agent}."
    echo -e "   ${DIM}Возможно raw.githubusercontent.com временно недоступен.${NC}"
    echo -e "   ${DIM}Пропущенные файлы можно дозалить вручную через --refresh-templates.${NC}"
    record_telemetry "R4_template_fetch_failed" "${target_id}"
    # Не делаем `exit 1` — даём установщику попытаться продолжить
    # с этим агентом (возможно у него уже есть workspace от прошлого
    # запуска). А если нет — agent'у не дадут стартовать.
  fi

  # 4.2 Добавляем Telegram-канал с правильным accountId
  # indirect expansion чтения токена (см. bash 3.2 комментарий выше)
  _tok_var="BOT_TOKEN_$agent"
  add_telegram_channel "$target_id" "${!_tok_var}"

  # 4.3 Настраиваем DM allowlist если есть OWNER_TG_ID
  if [[ -n "$OWNER_TG_ID" ]]; then
    configure_dm_allowlist "$target_id" "$OWNER_TG_ID"
  fi

  # 4.4 Создаём агента с биндингом telegram:<target_id>
  create_agent_with_bind "$target_id" "$workspace_dir" "$AGENT_MODEL" "$target_id"

  # 4.5 Копируем auth-profile из main
  copy_auth_profile_from_main "$target_id"

  # 4.6 Embedding-память (если клиент согласился в R1.5)
  if [[ "${EMBEDDING_ENABLED:-false}" == true ]]; then
    # Глобальный env-key пишем один раз на запуск
    if [[ "${EMBEDDING_ENV_WRITTEN:-false}" != true && -n "${EMBEDDING_KEY:-}" ]]; then
      write_embedding_env_key "$EMBEDDING_KEY"
      EMBEDDING_ENV_WRITTEN=true
    fi
    enable_embedding_for_agent "$target_id" \
      || warn "Embedding для ${target_id} не включился — продолжаю (включишь позже: --enable-embedding)"
    index_agent_memory "$target_id" \
      || warn "Индексация памяти ${target_id} не удалась — не критично"
  fi

  # 4.7 Забываем токен
  unset "BOT_TOKEN_$agent" _tok_var

  record_telemetry "R4_installed" "${target_id}"
done

# ═══════════════════════════════════════════════════════════════
#  R4.5. База знаний (вики) — только Pro, общая для всех агентов
# ═══════════════════════════════════════════════════════════════
# Разворачиваем мини-базу знаний (выжимки: продажи/прогрев/воронки/
# оффер/кастдев/линейка) в ~/.openclaw/knowledge и подключаем её к
# memory_search всех агентов. Идёт вместе с полной командой (Pro).
if [[ "$VIP_MODE" == true ]]; then
  step_header "R4.5" "БАЗА ЗНАНИЙ (ВИКИ ДЛЯ АГЕНТОВ)"
  setup_knowledge_base
  record_telemetry "R4_5_knowledge_base" "ok"
fi

# ═══════════════════════════════════════════════════════════════
#  R5. Рестарт gateway и финальная проверка
# ═══════════════════════════════════════════════════════════════
# ─── Сводка по реально установленным агентам ─────────────────
# Формируем INSTALLED_LIST раньше R5 — нужно для Telegram self-test
# (wave 9 BUG-03) и для опционального R5b (общая TG-группа).
INSTALLED_COUNT=0
INSTALLED_LIST=()
for agent in "${AGENTS_TO_INSTALL[@]}"; do
  [[ -z "$agent" ]] && continue
  target_id="${agent}${SUFFIX:+-$SUFFIX}"
  if agent_exists "$target_id"; then
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
    INSTALLED_LIST+=("$target_id")
  fi
done

step_header "R5" "РЕСТАРТ GATEWAY"

openclaw gateway restart 2>&1 | tail -3 | while IFS= read -r line; do
  echo -e "   ${DIM}${line}${NC}"
done
sleep 2

if openclaw gateway status 2>&1 | grep -qE "running"; then
  ok "Gateway: running"
else
  warn "Gateway не поднялся после рестарта. Попробуйте: openclaw gateway restart"
fi
record_telemetry "R5_gateway_restart" "ok"

# ─── wave 9 BUG-03: Telegram-канал self-test после gateway restart ─
#
# Из техотчёта: «бот молчит в личке/группе» — пользователь крутит токены/
# модели, хотя проблема в Telegram access layer. Локализуем заранее.
#
# `gateway running` ≠ «Telegram-канал работает». После рестарта
# для каждого установленного агента дёргаем getMe через сохранённый
# в конфиге токен. При провале — warn с конкретными причинами,
# чтобы клиент не валил всё подряд reinstall'ом.
if [[ ${#INSTALLED_LIST[@]} -gt 0 ]]; then
  echo ""
  echo -e "   ${DIM}Проверяю что каждый бот отвечает в Telegram (5-10 сек)...${NC}"
  TG_FAILED=()
  # wave 11 P1: small delay между getMe-вызовами против rate-limit
  # api.telegram.org. 6 быстрых getMe могут ловить 429 и давать
  # ложные fail'ы. 0.5 сек между запросами достаточно.
  for _aid in "${INSTALLED_LIST[@]}"; do
    if telegram_channel_self_test "$_aid"; then
      echo -e "   ${GREEN}✓${NC} ${_aid}: бот отвечает"
    else
      echo -e "   ${YELLOW}○${NC} ${_aid}: бот НЕ отвечает (gateway running, но Telegram-канал лежит)"
      TG_FAILED+=("$_aid")
    fi
    sleep 0.5  # rate-limit protection
  done
  unset _aid
  if [[ ${#TG_FAILED[@]} -gt 0 ]]; then
    echo ""
    warn "Telegram-каналы не работают для: ${TG_FAILED[*]}"
    echo -e "   ${DIM}Это означает: gateway запущен, но Telegram-токен/привязка не работает.${NC}"
    echo -e "   ${DIM}Не запускай reinstall — проблема в Telegram access layer. Что проверить:${NC}"
    echo -e "   ${DIM}  1. Токен бота в @BotFather (мог быть сброшен через /revoke)${NC}"
    echo -e "   ${DIM}  2. Бот не заблокирован тобой в Telegram${NC}"
    echo -e "   ${DIM}  3. api.telegram.org не блокируется фаерволом / VPN${NC}"
    echo -e "   ${DIM}  4. Запусти: ${GREEN}openclaw channels status --probe${NC}"
    echo -e "   ${DIM}  5. Диагностика для саппорта: ${GREEN}bash <(curl ...) --collect-debug${NC}"
    echo -e "   ${DIM}  6. Если в логах видишь ${BOLD}CIAO PROBING CANCELLED${NC}${DIM} (mDNS) или${NC}"
    echo -e "   ${DIM}     gateway циклически рестартится — выключи bonjour:${NC}"
    echo -e "   ${DIM}     ${GREEN}openclaw config set plugins.entries.bonjour.enabled false${NC}"
    record_telemetry "R5_tg_self_test_failed" "${#TG_FAILED[@]}"
  else
    record_telemetry "R5_tg_self_test_ok" "${#INSTALLED_LIST[@]}"
  fi
fi

# ═══════════════════════════════════════════════════════════════
#  R5b. ОБЩАЯ TG-ГРУППА (опционально)
# ═══════════════════════════════════════════════════════════════
#
# Показывается только если установлено ≥2 агентов и установка
# интерактивная (не --config). Default — N (не пугаем клиента).
#
# Если клиент соглашается — пошагово ведём через настройку.
# Можно отложить — клиент получит точную команду для запуска позже.

if [[ $INSTALLED_COUNT -ge 2 && -z "$CONFIG_FILE" && "$VPS_MODE" != true ]]; then
  step_header "R5b" "ОБЩАЯ TG-ГРУППА (опционально)"
  explain "Хочешь чтобы агенты могли работать ${BOLD}как команда${NC} в общей TG-группе?" \
    "Они смогут тегать друг друга — Координатор спрашивает Маркетолога," \
    "Маркетолог пишет смыслы, передаёт Копирайтеру, тот пишет текст и т.д." \
    "" \
    "Если интересно — нужно будет несколько ручных шагов с @BotFather"

  echo -e "   ${BOLD}${WHITE}Настроить общую группу? [y/N]:${NC}"
  read -r GROUP_CHOICE

  if [[ "${GROUP_CHOICE:-N}" == "y" || "${GROUP_CHOICE:-N}" == "Y" ]]; then
    echo ""
    echo -e "   ${BOLD}${YELLOW}Сделай ВРУЧНУЮ:${NC}"
    echo -e "   1. У ${BOLD}@BotFather${NC} → ${BOLD}/setprivacy${NC} → выбери КАЖДОГО бота → ${BOLD}Disable${NC}"
    echo -e "      ${DIM}(чтобы бот видел все сообщения в группе, а не только адресованные ему)${NC}"
    echo -e "   2. Создай TG-группу, добавь ${BOLD}всех ${INSTALLED_COUNT} ботов${NC} как ${BOLD}админов${NC}"
    echo -e "   3. Получи chat_id группы:"
    echo -e "      • Открой ${BOLD}@username_to_id_bot${NC}, напиши /start, перешли любое сообщение из группы"
    echo -e "      • Или для супергруппы: посмотри URL t.me/c/${BOLD}<число>${NC} → chat_id = -100<число>"
    echo ""
    echo -e "   ${BOLD}${WHITE}Введи chat_id (число с минусом, например -100123456789).${NC}"
    echo -e "   ${DIM}Или нажми Enter — настрою позже одной командой.${NC}"
    echo ""
    read -r GROUP_CHAT_ID

    if [[ -z "$GROUP_CHAT_ID" ]]; then
      echo ""
      echo -e "   ${YELLOW}Отложено.${NC} Когда будешь готов — выполни:"
      echo -e "   ${DIM}запусти команду из @AITeamVIPBot, добавив в конце:${NC} ${BOLD}${CYAN}--enable-group-mode <chat_id>${NC}"
      record_telemetry "R5b_postponed" "ok"
    elif [[ ! "$GROUP_CHAT_ID" =~ ^-?[0-9]+$ ]]; then
      warn "Не похоже на chat_id (должно быть число, может быть отрицательным). Пропускаю."
      record_telemetry "R5b_invalid_id" "ok"
    else
      echo ""
      echo -e "   ${DIM}Настраиваю group-mode для ${INSTALLED_COUNT} агентов с chat_id ${GROUP_CHAT_ID}...${NC}"
      echo ""
      for aid in "${INSTALLED_LIST[@]}"; do
        configure_group_membership "$aid" "$GROUP_CHAT_ID"
      done
      record_telemetry "R5b_configured" "ok"
      echo ""
      echo -e "   ${GREEN}${BOLD}✓ Group-mode настроен.${NC}"
      echo -e "   ${DIM}В группе агенты отвечают только когда их тегают (@<bot_username>).${NC}"
    fi
  else
    record_telemetry "R5b_declined" "ok"
  fi
fi

# ═══════════════════════════════════════════════════════════════
#  Финальный экран
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${GREEN}"
cat << 'FINISH'
   ╔════════════════════════════════════════════════════════════════╗
   ║                                                                ║
   ║   🎉  АГЕНТЫ УСТАНОВЛЕНЫ!                                       ║
   ║                                                                ║
   ║   Готовые боты могут отвечать в Telegram.                      ║
   ║                                                                ║
   ╚════════════════════════════════════════════════════════════════╝
FINISH
echo -e "${NC}"

echo -e "   ${BOLD}${WHITE}Ваши боты:${NC}"
for agent in "${AGENTS_TO_INSTALL[@]}"; do
  [[ -z "$agent" ]] && continue
  target_id="${agent}${SUFFIX:+-$SUFFIX}"
  emoji=""; label=""
  case "$agent" in
    tech)        emoji="🔧"; label="Технарь" ;;
    marketer)    emoji="📈"; label="Маркетолог" ;;
    producer)    emoji="🎬"; label="Продюсер" ;;
    designer)    emoji="🎨"; label="Дизайнер" ;;
    coordinator) emoji="🧭"; label="Координатор" ;;
    copywriter)  emoji="✍️"; label="Копирайтер" ;;
    leadcloser)  emoji="💰"; label="Лидоруб" ;;
    content)     emoji="🎥"; label="Контент-агент" ;;
  esac
  _usr_var="BOT_USERNAME_$agent"
  username="${!_usr_var:-неизвестно}"
  echo -e "   ${emoji} ${label}: ${GREEN}@${username}${NC} ${DIM}(agent id: ${target_id})${NC}"
done
echo ""

echo -e "   ${BOLD}${WHITE}Что дальше:${NC}"
echo -e "   ${CYAN}1.${NC} Откройте Telegram, напишите каждому боту ${BOLD}/start${NC} или ${BOLD}привет${NC}"
echo -e "   ${CYAN}2.${NC} Заполните ${BOLD}USER.md${NC} у каждого агента:"
for agent in "${AGENTS_TO_INSTALL[@]}"; do
  [[ -z "$agent" ]] && continue
  target_id="${agent}${SUFFIX:+-$SUFFIX}"
  echo -e "      ${DIM}~/.openclaw/workspace-${target_id}/USER.md${NC}"
done
echo -e "   ${CYAN}3.${NC} Сменить модель у всех: ${GREEN}openclaw-switch-model${NC}"
echo -e "   ${CYAN}4.${NC} Проверить здоровье: ${GREEN}bash <(curl ...) --diagnose-only${NC}"
echo ""

# ─── Оффер: мозги ChatGPT для всех агентов (решение Антона 2026-06-11) ───
# Интерактив и не VPS: предлагаем перевести всех агентов на GPT-5.5 через
# вход в обычный ChatGPT-аккаунт (браузер). Enter = да.
if [[ "${VPS_MODE:-false}" != true && -t 0 ]]; then
  _ADDCODEX="$(command -v openclaw-add-codex 2>/dev/null || echo "$HOME/.openclaw/bin/openclaw-add-codex")"
  if [[ "${OC_NO_AUTH_YET:-false}" == true ]]; then
    echo -e "   ${BOLD}${YELLOW}🧠 Остался один шаг — выбрать модель (мозги).${NC}"
    echo -e "   ${DIM}Боты уже в Telegram, отвечать начнут после подключения модели.${NC}"
  fi
  echo -e "   ${BOLD}${WHITE}Перевести всех агентов на ChatGPT (GPT-5.5)?${NC}"
  echo -e "   ${DIM}Понадобится вход в твой аккаунт ChatGPT в браузере (1 минута).${NC}"
  echo -e "   ${DIM}Совет: тариф ChatGPT Pro — Plus быстро упирается в лимиты GPT-5.5.${NC}"
  echo -e "   ${BOLD}${WHITE}[Y/n, Enter = да]:${NC}"
  read -r _gpt_offer || _gpt_offer="n"
  if [[ "${_gpt_offer:-y}" =~ ^[YyДд]?$ ]]; then
    if [[ -x "$_ADDCODEX" ]]; then
      "$_ADDCODEX" || warn "Переход на ChatGPT не завершился — можно повторить позже: openclaw-add-codex"
    else
      warn "Хелпер openclaw-add-codex не найден на этой машине."
      echo -e "   ${DIM}Запусти позже в новом терминале: ${BOLD}openclaw-add-codex${NC}"
    fi
  else
    echo -e "   ${DIM}Ок. Позже: ${BOLD}openclaw-add-codex${NC}${DIM} (ChatGPT) · ${BOLD}openclaw models auth login --provider <имя>${NC}${DIM} (другой провайдер) · ${BOLD}openclaw-switch-model <id>${NC}${DIM} (модель у всех).${NC}"
  fi
  echo ""
fi

# ─── wave 15: Bot-to-Bot Communication hint для VIP ──────────────
# Telegram (май 2026) добавил Bot-to-Bot Communication Mode —
# боты могут отвечать другим ботам напрямую без общей группы.
# Для VIP-команды (8 агентов) это полезно: Координатор может
# делегировать Маркетологу без посредника-группы.
#
# Настройка только ручная (через @BotFather), мы не можем
# автоматизировать. Просто упоминаем тем у кого VIP-набор.
if [[ "$VIP_MODE" == true && ${#INSTALLED_LIST[@]} -ge 4 ]]; then
  echo -e "   ${BOLD}${YELLOW}🤖↔🤖 Опционально: Bot-to-Bot Communication${NC}"
  echo -e "   ${DIM}Telegram (май 2026) добавил режим прямой связи между ботами.${NC}"
  echo -e "   ${DIM}Это даёт Координатору возможность делегировать задачи${NC}"
  echo -e "   ${DIM}Маркетологу/Копирайтеру без общей группы — цепочки идут${NC}"
  echo -e "   ${DIM}«за кулисами», тебе приходит только финальный результат.${NC}"
  echo -e "   ${DIM}Включи в @BotFather → /mybots → Bot Settings → Bot-to-Bot Mode${NC}"
  echo -e "   ${DIM}для каждого из ${#INSTALLED_LIST[@]} ботов. Полный гайд:${NC}"
  echo -e "   ${CYAN}docs/bot-to-bot-setup.md${NC}"
  echo ""
fi

if [[ "$VPS_MODE" == true ]]; then
  echo -e "   ${BOLD}${WHITE}Dashboard на VPS через SSH-tunnel:${NC}"
  _vps_host="<ip-вашего-vps>"
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    _vps_host=$(echo "$SSH_CONNECTION" | awk '{print $3}')
  fi
  echo -e "      ${GREEN}ssh -L 18789:127.0.0.1:18789 root@${_vps_host}${NC}"
  echo -e "   ${DIM}Затем откройте http://127.0.0.1:18789 в браузере на своей машине.${NC}"
  echo ""
else
  echo -e "   ${BOLD}${WHITE}Dashboard:${NC} ${CYAN}http://127.0.0.1:18789${NC}"
  if command -v open &>/dev/null; then
    echo -e "   ${BOLD}${WHITE}Открыть сейчас? [Y/n]:${NC}"
    read -r _open_dash
    if [[ "${_open_dash:-y}" == "y" || "${_open_dash:-y}" == "Y" ]]; then
      open "http://127.0.0.1:18789" &>/dev/null &
    fi
  fi
fi

record_telemetry "agents_pack_complete" "ok"
echo ""

# ─── wave 19: платформо-специфичная ссылка в финале ──────────────
# Авто-детект окружения + ОДНА целевая ссылка вместо списка из 4.
# Принцип wave 18 — «тупо не показываем то что неприменимо». Клиент
# на macOS видит только Mac-гайд, на Windows — Windows-гайд, и т.д.
# VPS-подсказка уже показана выше в VPS_MODE-блоке — здесь не дублируем.
_env_name=$(detect_environment 2>/dev/null || echo "unknown")
case "$_env_name" in
  macos)
    echo -e "   ${DIM}🍎 На Mac есть DMG-установщик (двойной клик):${NC}"
    echo -e "   ${DIM}   ${CYAN}docs/mac-install-guide.md${NC}"
    echo ""
    ;;
  windows-bash|wsl)
    _label="Git Bash / MSYS"
    [[ "$_env_name" == "wsl" ]] && _label="WSL"
    echo -e "   ${DIM}🪟 Гайд для ${_label}: ${CYAN}docs/windows-install-guide.md${NC}"
    echo ""
    # ─── Windows-интерфейс (Companion GUI) — официальное приложение OpenClaw ───
    # Спрашиваем только в интерактивном терминале (в headless/CI пропускаем).
    if [[ -t 0 ]]; then
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
      echo ""
    fi
    ;;
esac

echo -e "   ${DIM}📖 Подробнее: https://github.com/tonytrue92-beep/openclaw-agents-pack${NC}"
echo ""
