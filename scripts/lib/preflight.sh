#!/usr/bin/env bash
# preflight.sh — проверки перед запуском установщика:
# 1. OpenClaw установлен и gateway живой (специфично для agent-pack)
# 2. Есть auth-profile основного агента — копировать его в новых
# 3. Сеть к critical endpoints работает
#
# Ожидает что ui.sh уже подключён (цвета + ok/warn/ru).

# ─── Detect окружение (Windows / WSL / native bash) ─────────────
#
# stdout: одно из значений
#   "windows-bash"  — Git Bash / MSYS2 / Cygwin (натуральный Windows)
#   "wsl"           — Windows Subsystem for Linux
#   "linux"         — Linux (Ubuntu / Debian / Alpine / ...)
#   "macos"         — macOS Darwin
#   "unknown"       — что-то ещё
#
# Используется чтобы давать Windows-специфичные подсказки (нативный
# OpenClaw installer вместо bash-скрипта factory, Git Bash вместо
# PowerShell, и т.д.).
detect_environment() {
  case "${OSTYPE:-}" in
    cygwin|msys|mingw*) printf 'windows-bash'; return 0 ;;
    darwin*)            printf 'macos';        return 0 ;;
  esac
  # Linux + WSL отличаются по uname -r — WSL содержит "microsoft" или "WSL"
  if [[ "$(uname -s 2>/dev/null)" == "Linux" ]]; then
    if uname -r 2>/dev/null | grep -qiE 'microsoft|wsl'; then
      printf 'wsl'
    else
      printf 'linux'
    fi
    return 0
  fi
  printf 'unknown'
}

# ─── Подсказка по правилам Windows-установки ─────────────────────
#
# Печатается ОДИН РАЗ при первом preflight'е если детектировали
# windows-bash или wsl. Доносит главные правила из success kit:
#   1. Не бить bash <(curl ...) в PowerShell — это Git Bash / WSL
#   2. OpenClaw на Windows ставится официальным installer'ом, не bash-скриптом
#   3. Не смешивать среды (всё в одной — либо везде Git Bash, либо везде WSL)
#   4. Если raw.githubusercontent тупит — git clone репозитория
#
# Полный гайд: docs/windows-install-guide.md
WINDOWS_HINTS_PRINTED=false
print_windows_hints() {
  [[ "$WINDOWS_HINTS_PRINTED" == true ]] && return 0
  WINDOWS_HINTS_PRINTED=true

  local env_name="$1"
  local label="Git Bash / MSYS"
  [[ "$env_name" == "wsl" ]] && label="WSL (Linux подсистема)"

  echo ""
  echo -e "   ${BOLD}${YELLOW}🪟 Обнаружено окружение: ${label}${NC}"
  echo -e "   ${DIM}Несколько правил чтобы не получить -ой:${NC}"
  echo -e "   ${DIM}  1. Не запускайте этот скрипт в PowerShell/cmd — нужен bash.${NC}"
  echo -e "   ${DIM}  2. OpenClaw на Windows ставится официальным installer'ом${NC}"
  echo -e "   ${DIM}     (НЕ bash-скриптом factory). После установки команды${NC}"
  echo -e "   ${DIM}     запускаются как ${BOLD}openclaw.cmd${NC}${DIM}.${NC}"
  echo -e "   ${DIM}  3. Если raw.githubusercontent тупит — скачайте репо:${NC}"
  echo -e "   ${DIM}     ${BOLD}git clone https://github.com/tonytrue92-beep/openclaw-agents-pack${NC}"
  echo -e "   ${DIM}     ${BOLD}cd openclaw-agents-pack && bash scripts/install-agents.sh${NC}"
  echo -e "   ${DIM}  4. Не смешивайте среды: если запустили в Git Bash —${NC}"
  echo -e "   ${DIM}     все диагностические команды (которые установщик${NC}"
  echo -e "   ${DIM}     просит выполнить) тоже в Git Bash, не в PowerShell.${NC}"
  echo ""
  echo -e "   ${DIM}Полный гайд: ${CYAN}docs/windows-install-guide.md${NC} ${DIM}в репо.${NC}"
  echo ""
}

# ─── OpenClaw preflight ─────────────────────────────────────────
#
# Уникальная часть второго установщика: OpenClaw должен быть уже поставлен
# (через первый установщик openclaw-factory). Если нет — даём ссылку на
# первый и выходим.
#
# Возвращает:
#   0 — всё готово, можно ставить агентов
#   1 — OpenClaw не установлен (или сломан) — надо сначала первый установщик
#   2 — gateway не отвечает — советуем диагностику/рестарт
preflight_openclaw() {
  echo ""
  echo -e "   ${DIM}Проверяю, что OpenClaw уже установлен и живой...${NC}"

  # Окружение — для Windows-специфичных подсказок ниже
  local env_name
  env_name=$(detect_environment)

  # Печатаем правила Windows один раз (на первом вызове)
  if [[ "$env_name" == "windows-bash" || "$env_name" == "wsl" ]]; then
    print_windows_hints "$env_name"
  fi

  # ─── wave 9 BUG-01: hard preflight базовых утилит ────────────
  # Без bash/python3/curl установщик всё равно сломается дальше —
  # лучше упасть тут с понятным сообщением чем висеть в R0
  # с непонятной ошибкой.
  local missing_tools=()
  for _tool in bash python3 curl; do
    command -v "$_tool" >/dev/null 2>&1 || missing_tools+=("$_tool")
  done
  if [[ ${#missing_tools[@]} -gt 0 ]]; then
    warn "Не найдены базовые утилиты: ${missing_tools[*]}"
    echo -e "   ${DIM}Установщик использует их на каждом шаге — без них дальше нет смысла.${NC}"
    echo ""
    if [[ "$env_name" == "windows-bash" ]]; then
      echo -e "   ${BOLD}На Windows эти утилиты идут в Git Bash:${NC}"
      echo -e "      Скачай Git for Windows: ${CYAN}https://git-scm.com/download/win${NC}"
      echo -e "      Запусти заново через Git Bash (НЕ PowerShell)"
    elif [[ "$env_name" == "macos" ]]; then
      echo -e "   ${BOLD}На macOS:${NC}"
      echo -e "      ${GREEN}brew install ${missing_tools[*]}${NC}"
    elif [[ "$env_name" == "wsl" || "$env_name" == "linux" ]]; then
      echo -e "   ${BOLD}На Linux/WSL:${NC}"
      echo -e "      ${GREEN}apt-get install -y ${missing_tools[*]}${NC} ${DIM}(или dnf/apk в зависимости от дистрибутива)${NC}"
    fi
    echo ""
    return 1
  fi

  if ! command -v openclaw &>/dev/null; then
    echo ""
    warn "OpenClaw не найден в PATH."
    echo ""
    echo -e "   ${BOLD}${WHITE}Этот установщик — вторая ступень.${NC}"
    echo -e "   ${DIM}Он только ДОБАВЛЯЕТ агентов к уже работающему OpenClaw.${NC}"
    echo ""

    if [[ "$env_name" == "windows-bash" ]]; then
      echo -e "   ${BOLD}Сначала нужно установить OpenClaw нативным Windows-installer'ом:${NC}"
      echo ""
      echo -e "      1. Скачать: ${CYAN}https://openclaw.ai/download/windows${NC}"
      echo -e "      2. Запустить .msi / .exe — следовать мастеру"
      echo -e "      3. После установки в ${BOLD}PowerShell${NC}: ${GREEN}openclaw.cmd configure${NC}"
      echo -e "         → выбрать модель → вставить токен бота"
      echo -e "      4. ${GREEN}openclaw.cmd gateway start${NC}"
      echo -e "      5. Когда бот ответит в Telegram — возвращайтесь сюда (в Git Bash) и запускайте этот скрипт"
      echo ""
      echo -e "   ${DIM}Полный гайд по Windows: ${CYAN}docs/windows-install-guide.md${NC}"
    elif [[ "$env_name" == "wsl" ]]; then
      echo -e "   ${BOLD}В WSL можно использовать обычный bash-скрипт factory:${NC}"
      echo ""
      echo -e "      ${GREEN}bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh)${NC}"
      echo ""
      echo -e "   ${DIM}Альтернатива — поставить нативно на Windows и запускать наш скрипт${NC}"
      echo -e "   ${DIM}отсюда (WSL увидит openclaw.exe из Windows PATH).${NC}"
    else
      echo -e "   ${BOLD}Сначала нужно установить сам OpenClaw:${NC}"
      echo ""
      echo -e "      ${GREEN}bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh)${NC}"
    fi

    echo ""
    echo -e "   ${DIM}После того как бот из первого установщика напишет вам в Telegram — возвращайтесь сюда.${NC}"
    return 1
  fi

  local oc_ver
  oc_ver=$(openclaw --version 2>&1 | head -1)
  echo -e "   ${GREEN}✓${NC} OpenClaw: ${oc_ver}"

  # Gateway health
  local gw_status
  gw_status=$(openclaw gateway status 2>&1 || true)
  if echo "$gw_status" | grep -qE "running"; then
    echo -e "   ${GREEN}✓${NC} Gateway: running"
  else
    warn "Gateway не отвечает (status не вернул 'running')."
    echo -e "   ${DIM}Попробуйте: ${GREEN}openclaw gateway restart${NC}${DIM}, затем запустите этот установщик снова.${NC}"
    echo -e "   ${DIM}Или запустите диагностику:${NC}"
    echo -e "      ${GREEN}bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh) --diagnose-only${NC}"
    return 2
  fi

  # auth-profiles главного агента — нужен чтобы копировать в новых.
  #
  # ─── wave 9 BUG-05: hard JSON validation ─────────────────────
  # Из техотчёта 2026-04-26: частый кейс ложного фикса — клиент
  # сам создаёт пустой `{}` чтобы «обойти» отсутствие файла, потом
  # все новые агенты падают в HTTP 401. Теперь:
  #   1. файл должен существовать
  #   2. файл не должен быть пустым (0 байт или {})
  #   3. JSON должен быть валидным
  #   4. это должен быть непустой объект
  # При любом нарушении — hard-stop с прямой инструкцией перезапустить
  # первый установщик. Не лечим вручную.
  #
  # Skip в --refresh-templates режиме (этот режим обновляет только
  # шаблоны, не использует main/auth-profile для копирования).
  local main_auth="$HOME/.openclaw/agents/main/agent/auth-profiles.json"

  if [[ "${SKIP_AUTH_PROFILE_CHECK:-false}" == true ]]; then
    # --refresh-templates режим — пропускаем deep-check, делаем только
    # информативный warn если файл битый (но не падаем).
    if [[ -f "$main_auth" && -s "$main_auth" ]]; then
      echo -e "   ${GREEN}✓${NC} auth-profile основного агента найден (deep-check skipped в refresh-mode)"
    else
      warn "auth-profile основного агента отсутствует или пустой — refresh продолжится, но новые агенты могут падать в 401"
    fi
    return 0
  fi

  if [[ ! -f "$main_auth" ]]; then
    warn "Не найден auth-profile основного агента (${main_auth})"
    echo -e "   ${DIM}Это значит, у вас ещё нет настроенного API-ключа модели.${NC}"
    echo -e "   ${DIM}Сначала пройдите реальную установку в первом установщике:${NC}"
    echo -e "      ${GREEN}bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh)${NC}"
    return 1
  fi

  if [[ ! -s "$main_auth" ]]; then
    warn "auth-profile основного агента ПУСТОЙ (${main_auth})"
    echo -e "   ${DIM}Это значит первый установщик не довёл main до конца.${NC}"
    echo -e "   ${BOLD}${YELLOW}Не лечите файл вручную${NC} ${DIM}— это приведёт к 401 у новых агентов.${NC}"
    echo -e "   ${BOLD}Перезапустите первый установщик и доведите до момента когда main отвечает в Telegram:${NC}"
    echo -e "      ${GREEN}bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh)${NC}"
    return 1
  fi

  if ! python3 -c "
import json, sys
try:
    with open('$main_auth') as f:
        d = json.load(f)
    if not isinstance(d, dict) or len(d) == 0:
        sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
    warn "auth-profile невалидный (битый JSON или пустой объект {})"
    echo -e "   ${DIM}Кто-то редактировал файл вручную, или установщик упал на половине.${NC}"
    echo -e "   ${BOLD}${YELLOW}Не лечите вручную${NC} ${DIM}— перезапустите первый установщик начисто:${NC}"
    echo -e "      ${GREEN}bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh)${NC}"
    return 1
  fi

  echo -e "   ${GREEN}✓${NC} auth-profile основного агента валидный"
  return 0
}

# ─── Network preflight (copy из первого) ────────────────────────
preflight_network_check() {
  echo ""
  echo -e "   ${DIM}Проверяю доступность сети (5 сек)...${NC}"

  local endpoints=(
    "GitHub raw|https://raw.githubusercontent.com/|critical"
    "Telegram API|https://api.telegram.org/|critical"
    "opencode.ai|https://opencode.ai/|optional"
  )

  local failed_critical=()
  local all_ok=true

  for entry in "${endpoints[@]}"; do
    local name="${entry%%|*}"
    local rest="${entry#*|}"
    local url="${rest%%|*}"
    local level="${rest##*|}"

    local http_code
    http_code=$(curl --max-time 5 -sI -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo "000")

    if [[ "$http_code" =~ ^(2|3|401|403|404) ]]; then
      echo -e "   ${GREEN}✓${NC} ${name} (HTTP ${http_code})"
    else
      all_ok=false
      if [[ "$level" == "critical" ]]; then
        failed_critical+=("${name}|${url}")
        echo -e "   ${RED}✗${NC} ${name} недоступен (HTTP ${http_code:-timeout})"
      else
        echo -e "   ${YELLOW}○${NC} ${name} недоступен (необязательный)"
      fi
    fi
  done

  echo ""

  if [[ "$all_ok" == true ]]; then
    echo -e "   ${GREEN}Сеть OK — все критичные сервисы доступны.${NC}"
    return 0
  fi

  if [[ ${#failed_critical[@]} -gt 0 ]]; then
    warn "Критичные сервисы недоступны — установщик агентов не сможет продолжиться:"
    for entry in "${failed_critical[@]}"; do
      local name="${entry%%|*}"
      local url="${entry##*|}"
      echo -e "   ${RED}✗${NC} ${BOLD}${name}${NC}: ${url}"
    done
    echo ""
    echo -e "   ${BOLD}${WHITE}Вероятные причины:${NC} корпоративный прокси / VPN / DNS / регион."
    echo -e "   ${DIM}Проверьте вручную: ${GREEN}curl -I https://api.telegram.org/${NC}"
    echo ""
    echo -e "   ${BOLD}${WHITE}Продолжить несмотря на это? [y/N]:${NC}"
    read -r ignore_net
    if [[ "$ignore_net" != "y" && "$ignore_net" != "Y" ]]; then
      echo -e "   ${DIM}Остановлено. Почините сеть и запустите снова.${NC}"
      exit 1
    fi
  fi

  return 0
}
