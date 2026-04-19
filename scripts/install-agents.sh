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
#  OpenClaw Agents Pack — установщик трёх предустановленных агентов
#
#  Ставится поверх уже работающего OpenClaw (который поставлен первым
#  установщиком из openclaw-factory). Создаёт:
#
#    🔧 Технарь    → свой Telegram-бот, accountId=tech
#    📈 Маркетолог  → свой Telegram-бот, accountId=marketer
#    🎬 Продюсер   → свой Telegram-бот, accountId=producer
#
#  Каждому агенту — свой workspace в ~/.openclaw/workspace-<agent>/
#  с IDENTITY.md / AGENTS.md / MEMORY.md / USER.md из templates/ репо.
# ═══════════════════════════════════════════════════════════════════════

# ─── Версия установщика ─────────────────────────────────────────
# Обновляется при каждом значимом коммите. INSTALLER_COMMIT подставляется
# через sed в release-workflow; если скрипт запущен из рабочей копии —
# runtime-fallback на git rev-parse.
INSTALLER_VERSION="2026.04.19"
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

Установщик трёх предустановленных агентов (Технарь / Маркетолог / Продюсер)
поверх уже работающего OpenClaw.

Usage: bash install-agents.sh [OPTIONS]

Options:
  --install              Пропустить меню, поставить всех трёх агентов
  --vps, --headless      VPS-режим (skip GUI, SSH-tunnel-инструкция для dashboard)
  --only <agent>         Поставить только одного: tech | marketer | producer
  --suffix <str>         Суффикс к id при коллизии (tech-2, marketer-2, …)
  --config <file>        env-файл для неинтерактивной установки:
                           BOT_TOKEN_TECH=...
                           BOT_TOKEN_MARKETER=...
                           BOT_TOKEN_PRODUCER=...
                           AGENT_MODEL=openai-codex/gpt-5.4
                           OWNER_TG_ID=12345678
  --diagnose-only        Проверить что агенты живы (ничего не меняет)
  --collect-debug        Собрать debug-bundle для саппорта (не нужен TTY)
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
ONLY_AGENT=""
SUFFIX=""
CONFIG_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) SKIP_MENU=true; shift ;;
    --vps|--headless) VPS_MODE=true; SKIP_MENU=true; shift ;;
    --collect-debug) COLLECT_DEBUG_ONLY=true; shift ;;
    --diagnose-only) DIAGNOSE_ONLY=true; shift ;;
    --only)
      ONLY_AGENT="${2:-}"
      [[ -z "$ONLY_AGENT" ]] && { echo "ERROR: --only требует значение (tech|marketer|producer)"; exit 1; }
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
else
  # Скачиваем lib/ во временную папку
  _LIB_TMP=$(mktemp -d -t openclaw-agents-lib.XXXXXX)
  _LIB_COMMIT="${INSTALLER_COMMIT:-main}"
  if [[ "$_LIB_COMMIT" == "__COMMIT_PLACEHOLDER__" || "$_LIB_COMMIT" == *dev* ]]; then
    _LIB_COMMIT="main"
  fi
  _LIB_BASE="https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/${_LIB_COMMIT}/scripts/lib"
  for _mod in ui preflight telemetry debug-bundle agents; do
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
echo -e "${BOLD}   Три агента поверх OpenClaw: Технарь 🔧  Маркетолог 📈  Продюсер 🎬${NC}"
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

# ─── Загружаем --config если указан ─────────────────────────────
if [[ -n "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
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
  explain "Что хотите сделать?"
  echo -e "   ${BOLD}${GREEN}  1)${NC}  ${BOLD}Установить всех трёх агентов${NC} (рекомендуется)"
  echo -e "       ${DIM}Технарь 🔧 + Маркетолог 📈 + Продюсер 🎬, каждый в своём Telegram-боте.${NC}"
  echo ""
  echo -e "   ${BOLD}${YELLOW}  2)${NC}  ${BOLD}Установить только одного${NC}"
  echo -e "       ${DIM}Выберите: tech, marketer или producer.${NC}"
  echo ""
  echo -e "   ${BOLD}${CYAN}  3)${NC}  ${BOLD}Диагностика${NC} — проверить уже установленных"
  echo -e "       ${DIM}Ничего не меняет, только показывает состояние.${NC}"
  echo ""
  echo -e "   ${BOLD}${MAGENTA}  4)${NC}  ${BOLD}Debug-bundle${NC} для саппорта"
  echo ""
  divider
  echo -e "   ${BOLD}${WHITE}Выбор [1/2/3/4]:${NC}"
  echo ""
  read -r MENU_CHOICE
  case "$MENU_CHOICE" in
    2)
      echo -e "   ${BOLD}${WHITE}Какого агента поставить? [tech/marketer/producer]:${NC}"
      read -r ONLY_AGENT
      ;;
    3) exec bash "$0" --diagnose-only ;;
    4) collect_debug_bundle "manual from menu"; exit 0 ;;
    1|"") : ;;
    *) echo "Не распознал выбор. Выход."; exit 0 ;;
  esac
fi

# ─── Определяем список агентов для установки ────────────────────
AGENTS_TO_INSTALL=()
if [[ -n "$ONLY_AGENT" ]]; then
  case "$ONLY_AGENT" in
    tech|marketer|producer) AGENTS_TO_INSTALL=("$ONLY_AGENT") ;;
    *) echo "ERROR: --only должен быть tech/marketer/producer, получено: $ONLY_AGENT"; exit 1 ;;
  esac
else
  AGENTS_TO_INSTALL=(tech marketer producer)
fi

# ─── Активируем trap для auto debug-bundle на ERR ───────────────
trap 'on_installer_error $LINENO' ERR

# ═══════════════════════════════════════════════════════════════
#  R1. Выбор модели
# ═══════════════════════════════════════════════════════════════
step_header "R1" "ВЫБОР МОДЕЛИ"

DEFAULT_MODEL="openai-codex/gpt-5.4"
AGENT_MODEL="${AGENT_MODEL:-}"  # из --config если задан

if [[ -z "$AGENT_MODEL" ]]; then
  explain "Какую модель использовать для всех трёх агентов?" \
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

explain "Нужны три разных бота — по одному на каждого агента." \
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
    tech)     emoji="🔧"; label="Технарь" ;;
    marketer) emoji="📈"; label="Маркетолог" ;;
    producer) emoji="🎬"; label="Продюсер" ;;
  esac

  # Если из --config — не спрашиваем
  env_var="BOT_TOKEN_$(echo "$agent" | tr '[:lower:]' '[:upper:]')"
  token="${!env_var:-}"

  if [[ -n "$token" ]]; then
    echo -e "   ${DIM}Токен для ${label} взят из config: ${env_var}${NC}"
  else
    while true; do
      echo ""
      echo -e "   ${BOLD}${WHITE}${emoji} Токен бота для ${label}:${NC}"
      echo -e "   ${DIM}(символы не отображаются при вводе)${NC}"
      read -rs token
      echo ""
      [[ -z "$token" ]] && { warn "Токен пустой."; continue; }
      break
    done
  fi

  # Валидируем через getMe
  echo -e "   ${DIM}Проверяю токен через Telegram API...${NC}"
  username=$(validate_telegram_token "$token" || echo "")
  if [[ -z "$username" ]]; then
    warn "Токен не прошёл проверку getMe. Проверьте его через @BotFather."
    if [[ -n "$CONFIG_FILE" ]]; then
      exit 1  # в non-interactive — сразу падаем
    fi
    echo -e "   ${BOLD}${WHITE}Попробовать другой? [Y/n]:${NC}"
    read -r retry
    if [[ "$retry" != "n" && "$retry" != "N" ]]; then
      # повтор: откат счётчика цикла невозможен, поэтому делаем повтор через exec
      echo -e "   ${DIM}Перезапускаю сбор токенов — используйте тот же процесс${NC}"
      exit 1
    fi
    exit 1
  fi

  # Динамическое имя переменной (см. комментарий выше про bash 3.2 + declare -A)
  printf -v "BOT_TOKEN_$agent" '%s' "$token"
  printf -v "BOT_USERNAME_$agent" '%s' "$username"
  echo -e "   ${GREEN}✓${NC} ${label}: @${username}"
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
#  R3. Проверка коллизий
# ═══════════════════════════════════════════════════════════════
step_header "R3" "ПРОВЕРКА СУЩЕСТВУЮЩИХ АГЕНТОВ"

for agent in "${AGENTS_TO_INSTALL[@]}"; do
  target_id="${agent}${SUFFIX:+-$SUFFIX}"
  if agent_exists "$target_id"; then
    warn "Агент '${target_id}' уже существует."
    if [[ -n "$CONFIG_FILE" ]]; then
      echo -e "   ${DIM}--config режим: пропускаю (используйте --suffix для пересоздания).${NC}"
      record_telemetry "R3_collision" "skip_${agent}"
      continue
    fi
    echo -e "   ${BOLD}${WHITE}Что делать?${NC}"
    echo -e "   ${CYAN}1)${NC} Пропустить (оставить как есть)"
    echo -e "   ${CYAN}2)${NC} Пересоздать (удалить старого и поставить заново)"
    echo -e "   ${CYAN}3)${NC} Прервать установку"
    echo -e "   ${BOLD}Выбор [1/2/3, Enter = 1]:${NC}"
    read -r COLLIDE_CHOICE
    case "${COLLIDE_CHOICE:-1}" in
      2)
        echo -e "   ${DIM}Удаляю старого ${target_id}...${NC}"
        openclaw agents delete "$target_id" --yes &>/dev/null || true
        ;;
      3) exit 0 ;;
      *) AGENTS_TO_INSTALL=("${AGENTS_TO_INSTALL[@]/$agent}") ;;
    esac
  fi
done
record_telemetry "R3_collision_checked" "ok"

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
   ║   Три бота готовы отвечать в Telegram.                         ║
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
    tech)     emoji="🔧"; label="Технарь" ;;
    marketer) emoji="📈"; label="Маркетолог" ;;
    producer) emoji="🎬"; label="Продюсер" ;;
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
