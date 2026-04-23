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
if (( BASH_VERSINFO[0] < 4 )); then
  # Шаг 1: может уже лежит новый bash в brew-путях — переиспользуем.
  for _newer_bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [[ -x "$_newer_bash" && "$_newer_bash" != "$BASH" ]]; then
      exec "$_newer_bash" "$0" "$@"
    fi
  done
  # Шаг 2: если есть Homebrew — ставим bash автоматически.
  # Клиент уже согласился на `bash <(curl ...)` — доверие есть, не спрашиваем.
  if command -v brew &>/dev/null; then
    echo "⚙ Текущий bash устарел ($BASH_VERSION); ставлю свежий через Homebrew..." >&2
    if brew install bash >&2; then
      for _newer_bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [[ -x "$_newer_bash" && "$_newer_bash" != "$BASH" ]]; then
          echo "✓ Готово. Перезапускаю установщик через $_newer_bash..." >&2
          exec "$_newer_bash" "$0" "$@"
        fi
      done
    fi
  fi
  # Шаг 3: ни brew-bash, ни brew — даём инструкцию.
  cat >&2 <<BASHERR
✗ Этому установщику нужен bash 4+ (у вас $BASH_VERSION).

macOS по умолчанию поставляется с bash 3.2, Apple не обновляет его
из-за GPLv3. Поставьте свежий bash:

  1. Убедитесь, что Homebrew установлен (если нет — https://brew.sh)
  2. brew install bash
  3. Запустите установщик снова

Или поставьте OpenClaw через первый установщик — он сам ставит Homebrew:
  bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh)
BASHERR
  exit 1
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
INSTALLER_VERSION="2026.04.23"
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

Установщик Standard (3 агента) и VIP (6 агентов)
поверх уже работающего OpenClaw.

Usage: bash install-agents.sh [OPTIONS]

Options:
  --install              Пропустить меню, поставить Standard-набор (3 агента)
  --vip-token <token>    Включить VIP-режим (5 агентов) и валидировать токен локально
  --vps, --headless      VPS-режим (skip GUI, SSH-tunnel-инструкция для dashboard)
  --only <agent>         Поставить только одного: tech | marketer | producer | designer | coordinator | copywriter
  --suffix <str>         Суффикс к id при коллизии (tech-2, marketer-2, …)
  --config <file>        env-файл для неинтерактивной установки:
                           BOT_TOKEN_TECH=...
                           BOT_TOKEN_MARKETER=...
                           BOT_TOKEN_PRODUCER=...
                           BOT_TOKEN_DESIGNER=...      # для VIP
                           BOT_TOKEN_COORDINATOR=...   # для VIP
                           VIP_TOKEN=...               # для VIP
                           AGENT_MODEL=openai-codex/gpt-5.4
                           OWNER_TG_ID=12345678
  --diagnose-only        Проверить что агенты живы (ничего не меняет)
  --collect-debug        Собрать debug-bundle для саппорта (не нужен TTY)
  --refresh-templates    Обновить ТОЛЬКО шаблоны уже установленных агентов
                         (IDENTITY/AGENTS/SOUL/LEARNING/skills), сохранив
                         MEMORY.md + USER.md + настройки каналов. Безопасный
                         апдейт без потери данных. Не нужен VIP-токен.
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
done
if [[ "$NEEDS_TTY" == true && ! -t 0 ]]; then
  if [[ -e /dev/tty ]]; then
    exec < /dev/tty
  else
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
VIP_MODE=false
VIP_TOKEN=""
ONLY_AGENT=""
SUFFIX=""
CONFIG_FILE=""

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
    echo "  bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh) --collect-debug"
    echo ""
  fi
' EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) SKIP_MENU=true; shift ;;
    --vps|--headless) VPS_MODE=true; SKIP_MENU=true; shift ;;
    --collect-debug) COLLECT_DEBUG_ONLY=true; shift ;;
    --diagnose-only) DIAGNOSE_ONLY=true; shift ;;
    --refresh-templates) REFRESH_TEMPLATES_ONLY=true; shift ;;
    --vip-token)
      VIP_TOKEN="${2:-}"
      [[ -z "$VIP_TOKEN" ]] && { echo "ERROR: --vip-token требует значение"; exit 1; }
      VIP_MODE=true
      SKIP_MENU=true
      shift 2
      ;;
    --only)
      ONLY_AGENT="${2:-}"
      [[ -z "$ONLY_AGENT" ]] && { echo "ERROR: --only требует значение (tech|marketer|producer|designer|coordinator|copywriter)"; exit 1; }
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
else
  # Скачиваем lib/ во временную папку
  _LIB_TMP=$(mktemp -d -t openclaw-agents-lib.XXXXXX)
  _LIB_COMMIT="${INSTALLER_COMMIT:-main}"
  if [[ "$_LIB_COMMIT" == "__COMMIT_PLACEHOLDER__" || "$_LIB_COMMIT" == *dev* ]]; then
    _LIB_COMMIT="main"
  fi
  _LIB_BASE="https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/${_LIB_COMMIT}/scripts/lib"
  for _mod in ui preflight telemetry debug-bundle agents vip; do
    if ! curl -fsSL --max-time 10 "${_LIB_BASE}/${_mod}.sh" -o "${_LIB_TMP}/${_mod}.sh"; then
      echo "ERROR: не смог скачать scripts/lib/${_mod}.sh с GitHub"
      echo "Проверьте сеть и что commit ${_LIB_COMMIT} существует."
      exit 1
    fi
    # shellcheck disable=SC1090
    source "${_LIB_TMP}/${_mod}.sh"
  done
  # Оставляем _LIB_TMP до конца скрипта (source может подгрузить ещё что-то)
fi

# ─── --collect-debug: ничего не ставим, собираем bundle и выходим ─
if [[ "$COLLECT_DEBUG_ONLY" == true ]]; then
  echo ""
  echo -e "${BOLD}${CYAN}📦 Сбор debug-bundle для саппорта${NC}"
  echo -e "${DIM}   agents-pack v${INSTALLER_VERSION} (${INSTALLER_COMMIT})${NC}"
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
    ___                    ____ _                    _                    _
   / _ \ _ __   ___ _ __  / ___| | __ ___      __   / \   __ _  ___ _ __ | |_ ___
  | | | | '_ \ / _ \ '_ \| |   | |/ _` \ \ /\ / /  / _ \ / _` |/ _ \ '_ \| __/ __|
  | |_| | |_) |  __/ | | | |___| | (_| |\ V  V /  / ___ \ (_| |  __/ | | | |_\__ \
   \___/| .__/ \___|_| |_|\____|_|\__,_| \_/\_/  /_/   \_\__, |\___|_| |_|\__|___/
        |_|                                              |___/   T R U E   P A C K
LOGO
echo -e "${NC}"
echo -e "${BOLD}   Standard: Технарь 🔧  Маркетолог 📈  Продюсер 🎬${NC}"
echo -e "${BOLD}   VIP: + Дизайнер 🎨  Координатор 🧭${NC}"
echo -e "${DIM}   Installer v${INSTALLER_VERSION} (${INSTALLER_COMMIT})${NC}"
if [[ "$VPS_MODE" == true ]]; then
  echo -e "${BOLD}${MAGENTA}   🌐 VPS-режим: Linux-сервер, headless${NC}"
fi
echo ""
echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ─── --diagnose-only: быстрая проверка без изменений ────────────
if [[ "$DIAGNOSE_ONLY" == true ]]; then
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
  echo ""

  preflight_openclaw || exit 1

  # Ищем какие агенты уже стоят
  mapfile -t FOUND_AGENTS < <(find_installed_agents)

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
    prepare_workspace_from_templates "$agent" "$workspace_dir" "refresh" || {
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

# ─── Загружаем --config если указан ─────────────────────────────
if [[ -n "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  [[ -n "${VIP_TOKEN:-}" ]] && VIP_MODE=true
  SKIP_MENU=true
  ru "Конфиг загружен из: ${CONFIG_FILE}"
fi

# ─── Preflight: OpenClaw + сеть ─────────────────────────────────
preflight_openclaw || exit 1
preflight_network_check || true

# ─── Telemetry consent (читаем из первого установщика если уже есть) ─
ensure_telemetry_consent
record_telemetry "agents_pack_start" "ok"

# ─── Главное меню (если не SKIP_MENU) ──────────────────────────
if [[ "$SKIP_MENU" != true ]]; then
  explain "Какой набор агентов устанавливаем?"
  echo -e "   ${BOLD}${GREEN}  1)${NC}  ${BOLD}Стандарт — 3 агента${NC}  ${DIM}(тариф «Стандарт» курса)${NC}"
  echo -e "       🔧 Технарь   📈 Маркетолог   🎬 Продюсер"
  echo -e "       ${DIM}Токен НЕ нужен — просто выбирайте и ставьте.${NC}"
  echo ""
  echo -e "   ${BOLD}${YELLOW}  2)${NC}  ${BOLD}VIP — 6 агентов${NC}  ${DIM}(тариф «VIP» курса)${NC}"
  echo -e "       🔧 Технарь   📈 Маркетолог   🎬 Продюсер"
  echo -e "       🎨 Дизайнер  🧭 Координатор  ✍️  Копирайтер"
  echo -e "       ${DIM}Понадобится VIP-токен — получить в ${BOLD}@AITeamVIPBot${NC}${DIM} по вашему email или телефону.${NC}"
  echo ""
  echo -e "   ${BOLD}${CYAN}  3)${NC}  ${BOLD}Установить только одного${NC}"
  echo -e "       ${DIM}Выберите: tech, marketer, producer, designer, coordinator или copywriter.${NC}"
  echo ""
  echo -e "   ${BOLD}${MAGENTA}  4)${NC}  ${BOLD}Диагностика${NC} — проверить уже установленных"
  echo -e "       ${DIM}Ничего не меняет, только показывает состояние.${NC}"
  echo ""
  echo -e "   ${BOLD}${WHITE}  5)${NC}  ${BOLD}Debug-bundle${NC} для саппорта"
  echo ""
  divider
  echo -e "   ${BOLD}${WHITE}Выбор [1/2/3/4/5]:${NC}"
  echo ""
  read -r MENU_CHOICE
  case "$MENU_CHOICE" in
    2) VIP_MODE=true ;;
    3)
      echo -e "   ${BOLD}${WHITE}Какого агента поставить? [tech/marketer/producer/designer/coordinator/copywriter]:${NC}"
      read -r ONLY_AGENT
      ;;
    4)
      # ВАЖНО: НЕ делать `exec bash "$0" ...` — при запуске через
      # `bash <(curl -fsSL ...)` переменная $0 указывает на уже закрытый
      # file descriptor (/dev/fd/N), exec падает с ошибкой
      # «No such file or directory» и тихо выкидывает клиента в шелл
      # без объяснений. Вместо exec — качаем свежую копию через curl
      # и запускаем с флагом. Это работает и при curl-pipe, и при
      # локальном запуске из clone'а.
      echo ""
      echo -e "   ${DIM}Запускаю диагностику...${NC}"
      bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/scripts/install-agents.sh) --diagnose-only
      _last_exit_reason="manual_diagnose"
      exit 0
      ;;
    5)
      collect_debug_bundle "manual from menu"
      _last_exit_reason="manual_debug_bundle"
      exit 0
      ;;
    1|"") : ;;
    *)
      echo "Не распознал выбор «$MENU_CHOICE». Выход."
      _last_exit_reason="invalid_menu_choice"
      exit 0
      ;;
  esac
fi

if [[ "$ONLY_AGENT" == "designer" || "$ONLY_AGENT" == "coordinator" || "$ONLY_AGENT" == "copywriter" ]]; then
  VIP_MODE=true
fi

if [[ "$VIP_MODE" == true ]]; then
  step_header "V1" "ПРОВЕРКА VIP-ТОКЕНА"

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

  # Запрос токена (в цикле — если клиент ввёл не тот, не выходим по exit)
  while true; do
    if [[ -z "${VIP_TOKEN:-}" ]]; then
      explain "Нужен VIP-токен из @AITeamVIPBot." \
        "" \
        "Важно: получайте токен в боте с ТОГО ЖЕ Telegram-аккаунта," \
        "куда подключите агентов. Иначе проверка не пройдёт." \
        "" \
        "Токен привязан к вашему TG ID — шаринг с друзьями не работает."
      echo -e "   ${BOLD}${WHITE}Вставьте VIP-токен:${NC}"
      read -r VIP_TOKEN
    fi

    # Раздельная валидация для точного диагноза
    verify_vip_token "$VIP_TOKEN" "$MACHINE_TG_ID"
    rc=$?

    case $rc in
      0)
        ok "VIP-токен подтверждён для TG ID ${MACHINE_TG_ID}. Открываю установку 6 агентов."
        # Fire-and-forget сообщение боту — если бот увидит что этот токен
        # активируется с 4+ разных IP за неделю, пришлёт админу алерт.
        vip_log_activation "$(vip_token_get_hash "$VIP_TOKEN")" "$MACHINE_TG_ID" || true
        break
        ;;
      6)
        # v1-токен: подпись валидна, но без TG-binding. Это легаси-формат
        # от бота, который ещё не обновился до v2. Продолжаем установку,
        # но предупреждаем клиента что защита от шаринга не активна.
        warn "Ваш VIP-токен в старом формате (без TG-привязки)."
        echo -e "   ${DIM}Подпись валидна — токен настоящий.${NC}"
        echo -e "   ${DIM}Но защита от расшаривания пока не активна для этого токена.${NC}"
        echo -e "   ${DIM}Когда администратор обновит бота, вы сможете получить${NC}"
        echo -e "   ${DIM}свежий v2-токен в @AITeamVIPBot — он будет с защитой.${NC}"
        echo ""
        echo -e "   ${GREEN}Продолжаю установку 6 агентов...${NC}"
        vip_log_activation "$(vip_token_get_hash "$VIP_TOKEN")" "${MACHINE_TG_ID:-0}" || true
        break
        ;;
      2)
        warn "Формат токена не распознан."
        echo -e "   ${DIM}Ожидается одна из структур:${NC}"
        echo -e "   ${DIM}  • v2: VIP-XXXXXXXXXXXXXXXX-123456789-<длинная-подпись>${NC}"
        echo -e "   ${DIM}  • v1: VIP-XXXXXXXXXXXXXXXX-<длинная-подпись>${NC}"
        echo -e "   ${DIM}Скопируйте токен из @AITeamVIPBot целиком (без пробелов в конце).${NC}"
        ;;
      3)
        expected_tg=$(vip_token_get_expected_tg "$VIP_TOKEN" || echo "?")
        warn "Этот токен выдан для TG ID ${expected_tg}, а вы на ${MACHINE_TG_ID}."
        echo -e "   ${DIM}Это анти-шаринг защита: токен работает только на том TG-аккаунте,${NC}"
        echo -e "   ${DIM}с которого вы писали боту @AITeamVIPBot при получении.${NC}"
        echo -e "   ${DIM}Если это ваш токен — получите новый в боте, пишите с ТОГО ЖЕ TG.${NC}"
        echo -e "   ${DIM}Если не ваш — попросите владельца получить свой.${NC}"
        ;;
      4|5)
        warn "Криптографическая проверка подписи провалилась."
        echo -e "   ${DIM}Возможные причины:${NC}"
        echo -e "   ${DIM}  • токен повреждён при копировании (обрезан, лишние символы)${NC}"
        echo -e "   ${DIM}  • бот администратора обновил ключ подписи — нужен свежий токен${NC}"
        echo -e "   ${DIM}Получите свежий в @AITeamVIPBot (/start → email/phone).${NC}"
        ;;
    esac

    [[ -n "$CONFIG_FILE" ]] && exit 1  # в non-interactive не даём retry

    echo ""
    echo -e "   ${BOLD}${WHITE}Попробовать другой токен? [Y/n]:${NC}"
    read -r retry
    if [[ "$retry" == "n" || "$retry" == "N" ]]; then
      echo -e "   ${DIM}Прервано. Получите новый токен в @AITeamVIPBot с правильного TG-аккаунта.${NC}"
      exit 1
    fi
    VIP_TOKEN=""  # сбрасываем чтобы в следующей итерации снова запросить
  done
fi

# ─── Определяем список агентов для установки ────────────────────
AGENTS_TO_INSTALL=()
if [[ -n "$ONLY_AGENT" ]]; then
  case "$ONLY_AGENT" in
    tech|marketer|producer|designer|coordinator|copywriter) AGENTS_TO_INSTALL=("$ONLY_AGENT") ;;
    *) echo "ERROR: --only должен быть tech/marketer/producer/designer/coordinator/copywriter, получено: $ONLY_AGENT"; exit 1 ;;
  esac
elif [[ "$VIP_MODE" == true ]]; then
  AGENTS_TO_INSTALL=(tech marketer producer designer coordinator copywriter)
else
  AGENTS_TO_INSTALL=(tech marketer producer)
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
  # Сценарий FRESH
  echo -e "   ${GREEN}✓${NC} Свежая установка — агентов в системе ещё нет"
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
          prepare_workspace_from_templates "$aid" "$workspace_dir" "refresh" || {
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
  echo -e "   ${GREEN}Уже установлены${NC} ${DIM}(будут сохранены):${NC}"
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
step_header "R1" "ВЫБОР МОДЕЛИ"

DEFAULT_MODEL="openai-codex/gpt-5.4"
AGENT_MODEL="${AGENT_MODEL:-}"  # из --config если задан

if [[ -z "$AGENT_MODEL" ]]; then
  explain "Какую модель использовать для выбранных агентов?" \
    "" \
    "Модель можно сменить в любой момент через ${BOLD}openclaw-switch-model${NC}" \
    "или напрямую: ${BOLD}openclaw config set agents.defaults.model.primary <id>${NC}"
  echo ""
  echo -e "   ${BOLD}${GREEN}  1)${NC} ${GREEN}openai-codex/gpt-5.4${NC}        ${DIM}(рекомендуется: умная, нужен OpenCode auth)${NC}"
  echo -e "   ${BOLD}${GREEN}  2)${NC} ${GREEN}opencode/claude-sonnet-4-5${NC}  ${DIM}(премиум, платная)${NC}"
  echo -e "   ${BOLD}${GREEN}  3)${NC} ${GREEN}opencode/minimax-m2.5-free${NC}  ${DIM}(бесплатная, для старта)${NC}"
  echo -e "   ${BOLD}${GREEN}  4)${NC} ${GREEN}opencode/gpt-5-mini${NC}         ${DIM}(компромисс OpenAI)${NC}"
  echo -e "   ${BOLD}${GREEN}  5)${NC} ${DIM}Ввести свою (например: openrouter/...)${NC}"
  echo ""
  echo -e "   ${BOLD}${WHITE}Выбор [1-5, Enter = 1]:${NC}"
  read -r MODEL_CHOICE
  case "${MODEL_CHOICE:-1}" in
    1|"") AGENT_MODEL="openai-codex/gpt-5.4" ;;
    2)    AGENT_MODEL="opencode/claude-sonnet-4-5" ;;
    3)    AGENT_MODEL="opencode/minimax-m2.5-free" ;;
    4)    AGENT_MODEL="opencode/gpt-5-mini" ;;
    5)
      echo -e "   ${BOLD}${WHITE}Введите id модели:${NC}"
      read -r AGENT_MODEL
      [[ -z "$AGENT_MODEL" ]] && AGENT_MODEL="$DEFAULT_MODEL"
      ;;
    *) AGENT_MODEL="$DEFAULT_MODEL" ;;
  esac
fi
ok "Модель: ${AGENT_MODEL}"
record_telemetry "R1_model_chosen" "ok"

# ═══════════════════════════════════════════════════════════════
#  R2. Сбор Telegram tokens
# ═══════════════════════════════════════════════════════════════
step_header "R2" "TELEGRAM BOT TOKENS"

explain "Нужны отдельные Telegram-боты — по одному на каждого агента." \
  "" \
  "Создайте их через ${BOLD}@BotFather${NC} в Telegram (для каждого — ${BOLD}/newbot${NC})." \
  "Названия на ваш вкус, например: 'Мой Технарь', 'Мой Маркетолог', 'Мой Продюсер'." \
  "" \
  "Подробный гайд: ${CYAN}https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/docs/telegram-setup.md${NC}"

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

for agent in "${AGENTS_TO_INSTALL[@]}"; do
  emoji=""; label=""
  case "$agent" in
    tech)        emoji="🔧"; label="Технарь" ;;
    marketer)    emoji="📈"; label="Маркетолог" ;;
    producer)    emoji="🎬"; label="Продюсер" ;;
    designer)    emoji="🎨"; label="Дизайнер" ;;
    coordinator) emoji="🧭"; label="Координатор" ;;
    copywriter)  emoji="✍️"; label="Копирайтер" ;;
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
      echo -e "   ${DIM}(символы не отображаются при вводе — это нормально)${NC}"
      read -rs token
      echo ""
    fi

    if [[ -z "$token" ]]; then
      warn "Токен пустой."
      [[ -n "$CONFIG_FILE" ]] && exit 1
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
      echo -e "   ${DIM}Нужны ТРИ РАЗНЫХ бота — по одному на каждого агента.${NC}"
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
  prepare_workspace_from_templates "$agent" "$workspace_dir"

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

  # 4.6 Забываем токен
  unset "BOT_TOKEN_$agent" _tok_var

  record_telemetry "R4_installed" "${target_id}"
done

# ═══════════════════════════════════════════════════════════════
#  R5. Рестарт gateway и финальная проверка
# ═══════════════════════════════════════════════════════════════
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
echo -e "   ${DIM}📖 Подробнее: https://github.com/tonytrue92-beep/openclaw-agents-pack${NC}"
echo ""
