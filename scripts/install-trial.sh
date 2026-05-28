#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════
#  AI TEAM 2.0 — TRIAL / ДЕМО установщик
#
#  ⚠️  ЭТО ОТДЕЛЬНЫЙ УСТАНОВЩИК. Не связан с install-agents.sh.
#      Ставит OpenClaw движок + ОДНОГО агента-ассистента (демо).
#      БЕЗ курс-токена — бесплатная тестовая установка для лидогенерации.
#
#  Агент-ассистент каждые 2-3 сообщения мягко предлагает полную версию
#  курса со ссылкой https://serditov.tonytrue.pro/ (логика в шаблоне
#  templates/assistant/AGENTS.md + SOUL.md).
#
#  Цель: дать людям попробовать систему бесплатно → конвертировать
#  в полную версию (6 агентов + Hermes).
#
#  Работает на macOS / Linux / VPS / Windows (WSL/Git Bash).
# ═══════════════════════════════════════════════════════════════════════

# ─── Bash 4+ self-upgrade (как в основном установщике) ──────────
if (( BASH_VERSINFO[0] < 4 )); then
  for _newer_bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [[ -x "$_newer_bash" && "$_newer_bash" != "$BASH" ]]; then
      exec "$_newer_bash" "$0" "$@"
    fi
  done
  if command -v brew &>/dev/null; then
    echo "⚙ Обновляю bash через Homebrew..." >&2
    brew install bash >&2 2>&1 || true
    for _newer_bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
      if [[ -x "$_newer_bash" && "$_newer_bash" != "$BASH" ]]; then
        exec "$_newer_bash" "$0" "$@"
      fi
    done
  fi
  echo "✗ Нужен bash 4+. Поставь Homebrew (https://brew.sh) → brew install bash → запусти снова." >&2
  exit 1
fi

TRIAL_VERSION="2026.05.26"
TRIAL_COMMIT="__COMMIT_PLACEHOLDER__"
COURSE_URL="https://serditov.tonytrue.pro/"
REPO_RAW="https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main"

# ─── Цвета ──────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
  CYAN=$'\033[36m'; WHITE=$'\033[37m'; MAGENTA=$'\033[35m'
else
  BOLD=''; DIM=''; NC=''; RED=''; GREEN=''; YELLOW=''; CYAN=''; WHITE=''; MAGENTA=''
fi

ok()   { echo -e "   ${GREEN}✓${NC} $*"; }
warn() { echo -e "   ${YELLOW}⚠${NC} $*" >&2; }
err()  { echo -e "   ${RED}✗${NC} $*" >&2; }
divider() { echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ─── Парсинг флагов ─────────────────────────────────────────────
VPS_MODE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vps|--headless) VPS_MODE=true; shift ;;
    --version)
      echo "AI TEAM 2.0 Trial v${TRIAL_VERSION} (${TRIAL_COMMIT})"
      exit 0
      ;;
    --help)
      cat <<HELP
AI TEAM 2.0 — TRIAL / ДЕМО установщик v${TRIAL_VERSION}

Бесплатная тестовая установка: OpenClaw + один агент-ассистент.
Без курс-токена. Для полной версии (6 агентов) — ${COURSE_URL}

Usage:
  bash <(curl -fsSL .../install-trial-bundled.sh) [флаги]

Options:
  --vps, --headless   Режим VPS/сервера (без GUI, dashboard через SSH)
  --version           Показать версию
  --help              Эта справка
HELP
      exit 0
      ;;
    *) shift ;;
  esac
done

# ─── detect ОС ──────────────────────────────────────────────────
detect_os() {
  case "${OSTYPE:-}" in
    cygwin|msys|mingw*) printf 'windows-bash'; return ;;
    darwin*)            printf 'macos'; return ;;
  esac
  if [[ "$(uname -s 2>/dev/null)" == "Linux" ]]; then
    uname -r 2>/dev/null | grep -qiE 'microsoft|wsl' && printf 'wsl' || printf 'linux'
    return
  fi
  printf 'unknown'
}
OS_NAME=$(detect_os)

# ─── Banner ─────────────────────────────────────────────────────
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
echo -e "${NC}"
echo -e "${BOLD}${YELLOW}              Д Е М О   —   Б Е С П Л А Т Н А Я   В Е Р С И Я${NC}"
echo ""
echo -e "${BOLD}${WHITE}   Попробуй личного AI-ассистента бесплатно.${NC}"
echo -e "${DIM}   Это демо одного агента. Полная версия — команда из 6 агентов${NC}"
echo -e "${DIM}   которые работают на тебя 24/7: ${CYAN}${COURSE_URL}${NC}"
echo ""
echo -e "${DIM}   trial v${TRIAL_VERSION}${NC}"
if [[ "$VPS_MODE" == true ]]; then
  echo -e "${BOLD}${MAGENTA}   🌐 VPS-режим${NC}"
else
  case "$OS_NAME" in
    macos)        _os_label="macOS" ;;
    linux)        _os_label="Linux" ;;
    wsl)          _os_label="Windows (WSL)" ;;
    windows-bash) _os_label="Windows (Git Bash)" ;;
    *)            _os_label="неизвестная ОС" ;;
  esac
  echo -e "${DIM}   🖥  Система: ${BOLD}${_os_label}${NC}${DIM} (на VPS — запусти с --vps)${NC}"
fi
echo ""
divider
echo ""

# ═══════════════════════════════════════════════════════════════
#  T1. Preflight — Homebrew + OpenClaw движок
# ═══════════════════════════════════════════════════════════════
echo -e "${BOLD}${WHITE}Шаг 1/4 — Проверяю систему и ставлю OpenClaw...${NC}"
echo ""

# Homebrew (нужен для установки OpenClaw на macOS/Linux)
if ! command -v brew &>/dev/null; then
  if [[ "$OS_NAME" == "windows-bash" ]]; then
    err "На Windows OpenClaw ставится официальным installer'ом, не через bash."
    echo -e "   ${DIM}Гайд: ${CYAN}https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/docs/windows-install-guide.md${NC}"
    exit 1
  fi
  echo -e "   ${DIM}Homebrew не найден — ставлю (это займёт 2-5 минут, попросит пароль)...${NC}"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
    err "Не удалось поставить Homebrew. Поставь вручную с https://brew.sh и запусти снова."
    exit 1
  }
  # Подхватываем brew в PATH (Apple Silicon vs Intel)
  for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [[ -x "$_brew" ]] && eval "$("$_brew" shellenv)"
  done
fi
ok "Homebrew на месте"

# OpenClaw движок
if ! command -v openclaw &>/dev/null; then
  echo -e "   ${DIM}Ставлю OpenClaw движок через Homebrew...${NC}"
  brew install --cask openclaw 2>&1 | tail -5 | while IFS= read -r line; do
    echo -e "   ${DIM}${line}${NC}"
  done || {
    err "Не удалось поставить OpenClaw. Попробуй: brew install --cask openclaw"
    exit 1
  }
fi
if command -v openclaw &>/dev/null; then
  ok "OpenClaw установлен: $(openclaw --version 2>/dev/null | head -1 || echo 'готов')"
else
  err "OpenClaw не доступен после установки. Перезапусти терминал и попробуй снова."
  exit 1
fi
echo ""

# ═══════════════════════════════════════════════════════════════
#  T2. Онбординг OpenClaw (gateway + модель)
# ═══════════════════════════════════════════════════════════════
echo -e "${BOLD}${WHITE}Шаг 2/4 — Базовая настройка OpenClaw...${NC}"
echo ""
echo -e "${DIM}   Если OpenClaw ещё не настроен — открою интерактивный онбординг.${NC}"
echo -e "${DIM}   Для демо выбирай бесплатную модель (minimax) когда спросит.${NC}"
echo ""

# Если gateway ещё не настроен — запускаем онбординг.
if ! openclaw gateway status &>/dev/null; then
  openclaw onboard || warn "Онбординг прерван — можно донастроить позже через 'openclaw configure'"
fi
ok "OpenClaw настроен"
echo ""

# ═══════════════════════════════════════════════════════════════
#  T3. Telegram-бот для ассистента
# ═══════════════════════════════════════════════════════════════
echo -e "${BOLD}${WHITE}Шаг 3/4 — Telegram-бот для ассистента...${NC}"
echo ""
echo -e "   ${DIM}Создай бота через ${BOLD}@BotFather${NC}${DIM} в Telegram (/newbot) и вставь токен.${NC}"
echo ""

BOT_TOKEN=""
attempts=0
while [[ $attempts -lt 3 ]]; do
  attempts=$((attempts + 1))
  echo -e "   ${BOLD}${WHITE}🤖 Токен бота для Ассистента:${NC}"
  echo -e "   ${DIM}(символы не отображаются при вводе — это нормально)${NC}"
  read -rs BOT_TOKEN
  echo ""
  BOT_TOKEN=$(printf '%s' "$BOT_TOKEN" | tr -d '[:space:]')
  if [[ -z "$BOT_TOKEN" ]]; then
    warn "Пустой токен."
    continue
  fi
  # Валидация через Telegram getMe
  username=$(curl -fsSL --max-time 10 "https://api.telegram.org/bot${BOT_TOKEN}/getMe" 2>/dev/null \
    | grep -o '"username":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
  if [[ -n "$username" ]]; then
    ok "Токен валиден: @${username}"
    break
  fi
  warn "Токен не прошёл проверку. Проверь в @BotFather → /mybots."
  BOT_TOKEN=""
done

if [[ -z "$BOT_TOKEN" ]]; then
  err "Не удалось получить рабочий токен бота. Создай бота в @BotFather и запусти снова."
  exit 1
fi

# Прописываем telegram-аккаунт для ассистента
openclaw config set "channels.telegram.accounts.assistant.token" "$BOT_TOKEN" &>/dev/null || \
  warn "Не смог записать токен в конфиг — проверь 'openclaw configure'"
echo ""

# ═══════════════════════════════════════════════════════════════
#  T4. Установка агента-ассистента
# ═══════════════════════════════════════════════════════════════
echo -e "${BOLD}${WHITE}Шаг 4/4 — Ставлю агента-ассистента...${NC}"
echo ""

WORKSPACE="$HOME/.openclaw/workspace-assistant"
mkdir -p "$WORKSPACE"

# Скачиваем шаблон ассистента (с offer-логикой)
for f in IDENTITY AGENTS SOUL USER MEMORY; do
  if curl -fsSL --max-time 15 "${REPO_RAW}/templates/assistant/${f}.md" -o "${WORKSPACE}/${f}.md" 2>/dev/null; then
    ok "${f}.md"
  else
    warn "Не скачал ${f}.md — ассистент будет работать в базовом режиме"
  fi
done

# Модель для демо — бесплатная minimax
TRIAL_MODEL="opencode/minimax-m2.5-free"

# Регистрируем агента (реальная команда OpenClaw)
echo -e "   ${DIM}Регистрирую ассистента в OpenClaw...${NC}"
{ openclaw agents add assistant \
    --non-interactive \
    --workspace "$WORKSPACE" \
    --model "$TRIAL_MODEL" \
    --bind "telegram:assistant" 2>&1 || true; } | while IFS= read -r line; do
  echo -e "   ${DIM}${line}${NC}"
done
openclaw agents bind --agent assistant --bind "telegram:assistant" &>/dev/null || true

# Рестарт gateway чтобы агент поднялся
echo -e "   ${DIM}Перезапускаю gateway...${NC}"
openclaw gateway restart &>/dev/null || openclaw gateway start &>/dev/null || true
ok "Ассистент готов"
echo ""

# ═══════════════════════════════════════════════════════════════
#  Финал
# ═══════════════════════════════════════════════════════════════
divider
echo ""
echo -e "${BOLD}${GREEN}🎉 Демо готово! Твой AI-ассистент работает.${NC}"
echo ""
echo -e "   ${BOLD}${WHITE}Что дальше:${NC}"
echo -e "   ${CYAN}1.${NC} Открой Telegram, найди своего бота, напиши ${BOLD}/start${NC} или ${BOLD}привет${NC}"
echo -e "   ${CYAN}2.${NC} Попробуй: «придумай 3 идеи для поста» / «помоги составить план»"
echo -e "   ${CYAN}3.${NC} Ассистент покажет на что способна AI-команда"
echo ""
if [[ "$VPS_MODE" == true ]]; then
  echo -e "   ${BOLD}${WHITE}Dashboard (VPS):${NC} ssh -L 18789:127.0.0.1:18789 root@<ip>, затем http://127.0.0.1:18789"
else
  echo -e "   ${BOLD}${WHITE}Dashboard:${NC} ${CYAN}http://127.0.0.1:18789${NC}"
fi
echo ""
echo -e "${BOLD}${YELLOW}   ⭐ Понравилось? Полная версия — команда из 6 агентов + супер-агент:${NC}"
echo -e "${BOLD}${CYAN}      ${COURSE_URL}${NC}"
echo ""
divider
