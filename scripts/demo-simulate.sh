#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  OpenClaw Agents TRUE PACK — Симуляция установки для видеоурока
#
#  Этот скрипт НИЧЕГО не устанавливает и НЕ требует:
#    • установленного OpenClaw
#    • реальных Telegram-токенов
#    • интернета
#    • API-ключей opencode.ai
#
#  Он просто визуально проигрывает весь флоу установки агент-пака
#  для демонстрации в видеоуроке или GIF.
#
#  Запуск:
#    bash <(curl -fsSL <raw-url>/demo-simulate.sh)            # с паузами Enter
#    bash <(curl -fsSL <raw-url>/demo-simulate.sh) --auto      # без пауз (~2 мин)
#    bash <(curl -fsSL <raw-url>/demo-simulate.sh) --fast      # ускоренный (30 сек)
# ═══════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─── Параметры режимов ──────────────────────────────────────────
AUTO_MODE=false   # --auto: без пауз Enter между этапами
FAST_MODE=false   # --fast: короткие sleep'ы (для GIF)

for arg in "$@"; do
  case "$arg" in
    --auto)    AUTO_MODE=true ;;
    --fast)    FAST_MODE=true; AUTO_MODE=true ;;
    --help|-h)
      cat <<EOF
OpenClaw Agents TRUE PACK — Симуляция установки

Без аргументов: с паузами Enter между блоками (удобно объяснять в видео)
--auto:  без пауз, автоматический прогон (~2 мин, для записи GIF)
--fast:  --auto + ускоренные таймеры (~30 сек, быстрый превью)
EOF
      exit 0
      ;;
  esac
done

# ─── Цвета (копия из scripts/lib/ui.sh для автономности скрипта) ─
# shellcheck disable=SC2034
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
MAGENTA=$'\033[0;35m'
WHITE=$'\033[1;37m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
NC=$'\033[0m'

# ─── Таймеры ────────────────────────────────────────────────────
# В fast-режиме все sleep делим на 3 — для GIF-записи оптимально.
_sleep() {
  local t="$1"
  if [[ "$FAST_MODE" == true ]]; then
    # bc не везде; используем awk для деления на 3
    t=$(awk "BEGIN {printf \"%.2f\", $t/3}")
  fi
  sleep "$t"
}

# Пауза для видео — в интерактивном режиме ждёт Enter, в --auto пропускает.
# В видеоуроке Антон объясняет тему, потом жмёт Enter → следующий блок.
_beat() {
  if [[ "$AUTO_MODE" == true ]]; then
    _sleep 1.2
  else
    echo ""
    echo -e "   ${DIM}(Enter — следующий шаг)${NC}"
    read -r _ || true
  fi
}

# ─── UI-примитивы ───────────────────────────────────────────────
step_header() {
  echo ""
  echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${MAGENTA}  STEP $1: $2${NC}"
  echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}
explain() {
  echo ""
  echo -e "   ${CYAN}☕${NC} ${BOLD}$1${NC}"
  shift
  for line in "$@"; do echo -e "   ${DIM}${line}${NC}"; done
  echo ""
}
ru() { echo -e "   ${CYAN}↳${NC} $1"; }
ok() { echo ""; echo -e "   ${GREEN}✅ $1${NC}"; echo ""; }
note() { echo -e "   ${DIM}$1${NC}"; }

# Симуляция «печатающейся» строки — для красивого видео
typewrite() {
  local text="$1"
  local delay=0.015
  [[ "$FAST_MODE" == true ]] && delay=0.005
  [[ "$AUTO_MODE" == false ]] && delay=0.02
  for ((i=0; i<${#text}; i++)); do
    printf '%s' "${text:$i:1}"
    sleep "$delay"
  done
  echo ""
}

# ═══════════════════════════════════════════════════════════════
#  СТАРТОВЫЙ ЭКРАН
# ═══════════════════════════════════════════════════════════════
# clear может вернуть non-zero если TERM не задан (например, в curl|bash
# или в CI). Обёртка в `|| true` защищает от срабатывания set -e.
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
echo -e "${BOLD}   🎬 РЕЖИМ СИМУЛЯЦИИ — для видеоурока${NC}"
echo -e "${DIM}   Ничего не устанавливается, файлы не создаются, интернет не нужен.${NC}"
echo -e "${DIM}   Все токены и usernames — демонстрационные заглушки.${NC}"
echo ""
echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

explain "Что увидит студент после запуска реальной команды" \
  "" \
  "Установщик поставит трёх готовых AI-агентов поверх OpenClaw:" \
  "" \
  "  🔧 Технарь    — отвечает в одном Telegram-боте" \
  "  📈 Маркетолог — отвечает в другом Telegram-боте" \
  "  🎬 Продюсер   — отвечает в третьем Telegram-боте" \
  "" \
  "Каждому — свой workspace, своя личность, свои правила работы." \
  "" \
  "Ниже — полная симуляция процесса от начала до конца."

_beat

# ═══════════════════════════════════════════════════════════════
#  R0. PRECHECK — версия и baseline
# ═══════════════════════════════════════════════════════════════
step_header "R0" "ПРОВЕРКА ОКРУЖЕНИЯ"

echo -e "${DIM}   OpenClaw Factory Agents Pack v2026.04.23 (demo-commit)${NC}"
echo -e "${DIM}   Если что-то не так — пришлите в поддержку debug-bundle${NC}"
echo ""
note "Проверяю сеть (5 сек)..."
_sleep 0.6
echo -e "   ${GREEN}✓${NC} npm registry (HTTP 200)"
_sleep 0.3
echo -e "   ${GREEN}✓${NC} GitHub raw (HTTP 301)"
_sleep 0.3
echo -e "   ${GREEN}✓${NC} opencode.ai (HTTP 200)"
_sleep 0.3
echo -e "   ${GREEN}✓${NC} Telegram API (HTTP 302)"
echo ""
echo -e "   ${GREEN}Сеть OK — все критичные сервисы доступны.${NC}"

_beat

# ═══════════════════════════════════════════════════════════════
#  R1. OPENCLAW PRESENCE CHECK
# ═══════════════════════════════════════════════════════════════
step_header "R1" "ПРОВЕРКА OPENCLAW"

explain "Агент-пак ставится поверх уже рабочего OpenClaw." \
  "Если вы ещё не устанавливали — сначала нужен первый установщик:" \
  "  ${GREEN}bash <(curl -fsSL .../openclaw-factory/.../demo-install.sh)${NC}"

note "Проверяю что OpenClaw установлен и отвечает..."
_sleep 0.5
echo -e "   ${GREEN}✓${NC} openclaw --version: ${DIM}OpenClaw 2026.4.15 (041266a)${NC}"
_sleep 0.3
echo -e "   ${GREEN}✓${NC} gateway.mode=local"
_sleep 0.3
echo -e "   ${GREEN}✓${NC} Gateway: running"
_sleep 0.3
echo -e "   ${GREEN}✓${NC} Основной агент 'main' найден"

ok "OpenClaw готов — ставим пак поверх"

_beat

# ═══════════════════════════════════════════════════════════════
#  R2. TELEGRAM BOT TOKENS
# ═══════════════════════════════════════════════════════════════
step_header "R2" "TELEGRAM BOT TOKENS"

explain "Нужны три разных бота — по одному на каждого агента." \
  "" \
  "Создайте их через ${BOLD}@BotFather${NC} в Telegram (для каждого — ${BOLD}/newbot${NC})." \
  "Названия на ваш вкус, например: 'Мой Технарь', 'Мой Маркетолог', 'Мой Продюсер'." \
  "" \
  "Подробный гайд: ${CYAN}https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/docs/telegram-setup.md${NC}"

_sleep 0.8

# ─── Ввод токенов (симуляция) ───
for agent_tuple in "tech|🔧|Технарь|demo_tech_bot" \
                   "marketer|📈|Маркетолог|demo_marketer_bot" \
                   "producer|🎬|Продюсер|demo_producer_bot"; do
  agent="${agent_tuple%%|*}"
  rest="${agent_tuple#*|}"
  emoji="${rest%%|*}"
  rest="${rest#*|}"
  label="${rest%%|*}"
  fake_username="${rest##*|}"

  echo ""
  echo -e "   ${BOLD}${WHITE}${emoji} Токен бота для ${label}:${NC}"
  echo -e "   ${DIM}(символы не отображаются при вводе — это нормально)${NC}"
  _sleep 0.9
  echo -e "   ${DIM}[студент вставляет токен — символы скрыты]${NC}"
  _sleep 0.4
  note "Проверяю токен через Telegram API..."
  _sleep 0.6
  echo -e "   ${GREEN}✓${NC} ${label}: @${fake_username}"
done

echo ""
ok "Все токены проверены"

_beat

# ═══════════════════════════════════════════════════════════════
#  R2.5. OWNER TG ID (опциональный)
# ═══════════════════════════════════════════════════════════════

explain "Ваш Telegram user ID (чтобы бот отвечал только вам)" \
  "Узнать можно через @userinfobot в Telegram — пришлите ему любое сообщение."

_sleep 0.6
echo -e "   ${DIM}[студент вводит свой TG ID]${NC}"
_sleep 0.4
echo -e "   ${GREEN}✓${NC} Allowlist: ваш ID 123456789 разрешён для всех трёх ботов"

_beat

# ═══════════════════════════════════════════════════════════════
#  R3. COLLISION CHECK
# ═══════════════════════════════════════════════════════════════
step_header "R3" "ПРОВЕРКА СУЩЕСТВУЮЩИХ АГЕНТОВ"

_sleep 0.5
echo -e "   ${GREEN}✓${NC} Свежая установка — конфликтов нет"
note "(если агенты уже были, здесь предложили бы перезаписать начисто)"

_beat

# ═══════════════════════════════════════════════════════════════
#  R4. AGENT INSTALLATION — главное шоу
# ═══════════════════════════════════════════════════════════════
step_header "R4" "УСТАНОВКА АГЕНТОВ"

for agent_tuple in "tech|🔧|Технарь|demo_tech_bot" \
                   "marketer|📈|Маркетолог|demo_marketer_bot" \
                   "producer|🎬|Продюсер|demo_producer_bot"; do
  agent="${agent_tuple%%|*}"
  rest="${agent_tuple#*|}"
  emoji="${rest%%|*}"
  rest="${rest#*|}"
  label="${rest%%|*}"
  fake_username="${rest##*|}"

  echo ""
  echo -e "   ${BOLD}${MAGENTA}━━━ ${emoji} ${label} ━━━${NC}"
  echo ""

  note "Создаю агента '${agent}'..."
  _sleep 0.6
  echo -e "   ${GREEN}✓${NC} openclaw agents add ${agent}"

  note "Готовлю workspace ~/.openclaw/workspace-${agent}/..."
  _sleep 0.4
  echo -e "   ${GREEN}✓${NC} ${agent}/IDENTITY.md"
  _sleep 0.2
  echo -e "   ${GREEN}✓${NC} ${agent}/AGENTS.md"
  _sleep 0.2
  echo -e "   ${GREEN}✓${NC} ${agent}/MEMORY.md"
  _sleep 0.2
  echo -e "   ${GREEN}✓${NC} ${agent}/USER.md"

  note "Копирую auth-profile от main-агента..."
  _sleep 0.4
  echo -e "   ${GREEN}✓${NC} Auth-profile скопирован: ${agent}"

  note "Подключаю Telegram канал (account=${agent})..."
  _sleep 0.7
  echo -e "   ${GREEN}✓${NC} Telegram канал подключён: @${fake_username}"

  note "Привязываю агента '${agent}' к каналу..."
  _sleep 0.4
  echo -e "   ${GREEN}✓${NC} agents bind → ${agent} ↔ telegram:${agent}"

  note "Настраиваю DM allowlist..."
  _sleep 0.3
  echo -e "   ${GREEN}✓${NC} Бот ${emoji} отвечает только на ID 123456789"
done

echo ""
ok "Все три агента установлены"

_beat

# ═══════════════════════════════════════════════════════════════
#  R5. FINAL CHECK
# ═══════════════════════════════════════════════════════════════
step_header "R5" "ФИНАЛЬНАЯ ПРОВЕРКА"

note "Перезапускаю gateway, чтобы подхватились все 3 канала..."
_sleep 0.7
echo -e "   ${GREEN}✓${NC} Gateway: running (pid 12345)"
_sleep 0.3
echo ""
note "Проверяю каналы через Telegram API (probe)..."
_sleep 0.5
echo -e "   ${GREEN}✓${NC} telegram/tech:      connected  (audit: ok)"
_sleep 0.2
echo -e "   ${GREEN}✓${NC} telegram/marketer:  connected  (audit: ok)"
_sleep 0.2
echo -e "   ${GREEN}✓${NC} telegram/producer:  connected  (audit: ok)"

_beat

# ═══════════════════════════════════════════════════════════════
#  ФИНАЛЬНЫЙ ЭКРАН
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${GREEN}"
cat << 'FINISH'
   ╔════════════════════════════════════════════════════════════════╗
   ║                                                                ║
   ║   🚀  УСТАНОВКА АГЕНТОВ ЗАВЕРШЕНА!                            ║
   ║                                                                ║
   ║   Три AI-ассистента подключены и готовы к работе.             ║
   ║                                                                ║
   ╚════════════════════════════════════════════════════════════════╝
FINISH
echo -e "${NC}"

echo -e "   ${BOLD}${WHITE}Ваши агенты в Telegram:${NC}"
echo -e "      ${GREEN}🔧${NC} Технарь:    ${BOLD}@demo_tech_bot${NC}"
echo -e "      ${GREEN}📈${NC} Маркетолог: ${BOLD}@demo_marketer_bot${NC}"
echo -e "      ${GREEN}🎬${NC} Продюсер:   ${BOLD}@demo_producer_bot${NC}"
echo ""
echo -e "   ${BOLD}${WHITE}Как проверить что всё работает:${NC}"
echo -e "      1. Откройте Telegram"
echo -e "      2. Найдите одного из ботов (по username'у выше)"
echo -e "      3. Напишите ему: ${BOLD}/status${NC}"
echo -e "      4. Подождите 5-10 секунд — бот должен ответить"
echo ""
echo -e "   ${BOLD}${WHITE}Что делать дальше:${NC}"
echo -e "      ${CYAN}•${NC} Пишите любому боту — он AI, отвечает на всё"
echo -e "      ${CYAN}•${NC} Персонализировать: ${DIM}~/.openclaw/workspace-<агент>/IDENTITY.md${NC}"
echo -e "      ${CYAN}•${NC} Сменить модель: ${GREEN}openclaw-switch-model${NC}"
echo -e "      ${CYAN}•${NC} Диагностика: ${GREEN}bash <(curl ...) --diagnose-only${NC}"
echo ""

divider() { echo -e "${DIM}   ─────────────────────────────────────────────────────────────${NC}"; }
divider
echo ""
echo -e "${BOLD}${MAGENTA}   🎬 Это была симуляция. У реального студента — то же самое,${NC}"
echo -e "${BOLD}${MAGENTA}   но с его токенами и его AI-агентами.${NC}"
echo ""
echo -e "   ${DIM}Для реальной установки студент запускает:${NC}"
echo -e "      ${GREEN}bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/\\${NC}"
echo -e "      ${GREEN}openclaw-agents-pack/main/scripts/install-agents.sh)${NC}"
echo ""
