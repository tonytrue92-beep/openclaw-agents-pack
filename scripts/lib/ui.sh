#!/usr/bin/env bash
# ui.sh — цвета, баннеры, примитивы вывода.
# Vendored из openclaw-factory/scripts/demo-install.sh (решение #17 в handoff
# первого установщика — мы копируем helpers, а не подключаем через curl|source,
# чтобы избежать рантайм-зависимости и drift'а между репами).

# Цвета (интерпретируем escape через ANSI-C quoting, чтобы работало в heredoc'ах)
# shellcheck disable=SC2034
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
# shellcheck disable=SC2034
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
MAGENTA=$'\033[0;35m'
WHITE=$'\033[1;37m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
# shellcheck disable=SC2034
ITALIC=$'\033[3m'
NC=$'\033[0m'

# ─── Заголовки ──────────────────────────────────────────────────
step_header() {
  local num="$1"
  local title="$2"
  echo ""
  echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${MAGENTA}  STEP ${num}: ${title}${NC}"
  echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

# Подробное объяснение на русском (главный блок)
explain() {
  echo ""
  echo -e "   ${CYAN}☕${NC} ${BOLD}$1${NC}"
  shift
  for line in "$@"; do
    echo -e "   ${DIM}${line}${NC}"
  done
  echo ""
}

# Команда для копирования
show_cmd() {
  local cmd="$1"
  echo -e "   ${DIM}┌─ 📋 скопируйте эту команду (без \$) ─────────────────────┐${NC}"
  echo -e "   ${DIM}│${NC} ${YELLOW}\$${NC} ${GREEN}${BOLD}${cmd}${NC}"
  echo -e "   ${DIM}└──────────────────────────────────────────────────────────┘${NC}"
}

ru() { echo -e "   ${CYAN}↳${NC} $1"; }
ok() { echo ""; echo -e "   ${GREEN}✅ $1${NC}"; echo ""; }
warn() { echo -e "   ${YELLOW}⚠️  $1${NC}"; }
divider() {
  echo ""
  echo -e "${DIM}   ─────────────────────────────────────────────────────────────${NC}"
  echo ""
}
pause() {
  echo ""
  echo -e "   ${DIM}Нажмите Enter чтобы продолжить...${NC}"
  read -r
}
