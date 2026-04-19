#!/usr/bin/env bash
# telemetry.sh — opt-in локальная телеметрия + heartbeat + educational tips.
# Vendored из первого установщика (и адаптирован: tips о том что делают агенты).
#
# Consent read/write из `~/.openclaw/.telemetry-consent` (тот же файл что
# использует openclaw-factory — чтобы не спрашивать дважды).

TELEMETRY_CONSENT_FILE="$HOME/.openclaw/.telemetry-consent"
TELEMETRY_LOG="$HOME/.openclaw/.telemetry-events.jsonl"

# Educational tips — что ученик может сделать с тремя агентами
# shellcheck disable=SC2034
_HEARTBEAT_TIPS=(
  "💡 Три бота работают независимо. Технарь не видит переписку Маркетолога и наоборот."
  "💡 Память агента живёт в ~/.openclaw/workspace-<агент>/MEMORY.md — можете редактировать руками."
  "💡 USER.md — ваш профиль. Заполните за 5 минут — агенты будут отвечать точнее с первого раза."
  "💡 Сменить модель у всех агентов сразу: openclaw-switch-model (из первого установщика)."
  "💡 Если агент отвечает не так как надо — правьте IDENTITY.md и AGENTS.md в его workspace."
  "💡 Если нужно передать задачу коллеге — агенты подскажут, к кому обратиться."
  "💡 Dashboard с перепиской всех агентов — на http://127.0.0.1:18789 (или SSH-туннель с VPS)."
)

_show_random_tip() {
  (( RANDOM % 10 < 3 )) || return 0
  local count=${#_HEARTBEAT_TIPS[@]}
  (( count == 0 )) && return 0
  local idx=$((RANDOM % count))
  echo -e "   ${CYAN}${_HEARTBEAT_TIPS[$idx]}${NC}"
}

start_heartbeat() {
  local label="${1:-работаю}"
  local interval="${2:-30}"
  local hint_at="${3:-300}"
  local started
  started=$(date +%s)
  while true; do
    sleep "$interval"
    local now
    now=$(date +%s)
    local elapsed=$((now - started))
    if [[ $elapsed -ge $hint_at ]]; then
      echo -e "   ${DIM}⏳ ${label} (${elapsed} сек)... если больше 10 минут молчит — Ctrl+C и проверьте сеть${NC}"
    else
      echo -e "   ${DIM}⏳ ${label} (${elapsed} сек)... я жив, просто процесс небыстрый${NC}"
      _show_random_tip
    fi
  done
}

stop_heartbeat() {
  local hb_pid="$1"
  [[ -z "$hb_pid" ]] && return 0
  kill "$hb_pid" 2>/dev/null || true
  wait "$hb_pid" 2>/dev/null || true
}

# ─── Opt-in telemetry ────────────────────────────────────────────
#
# Если первый установщик уже спросил согласие — читаем его как есть.
# Иначе спрашиваем. Новые запуски второго установщика НЕ перезадают вопрос.
ensure_telemetry_consent() {
  [[ "${DRY_RUN:-false}" == true ]] && return 0

  if [[ -f "$TELEMETRY_CONSENT_FILE" ]]; then
    TELEMETRY_CONSENT=$(cat "$TELEMETRY_CONSENT_FILE" 2>/dev/null | tr -d '\n ')
    return 0
  fi

  echo ""
  echo -e "   ${BOLD}${WHITE}Разрешить анонимную телеметрию установки?${NC}"
  echo -e "   ${DIM}Помогает улучшать установщик. Имена, ключи, IP — не собираем.${NC}"
  echo -e "   ${DIM}Пока Worker не задеплоен — пишется ТОЛЬКО локально в:${NC}"
  echo -e "   ${DIM}   ${TELEMETRY_LOG}${NC}"
  echo ""
  echo -e "   ${BOLD}${WHITE}Разрешить? [y/N]:${NC}"
  read -r tel_consent
  mkdir -p "$(dirname "$TELEMETRY_CONSENT_FILE")"
  if [[ "$tel_consent" == "y" || "$tel_consent" == "Y" ]]; then
    echo "yes" > "$TELEMETRY_CONSENT_FILE"
    TELEMETRY_CONSENT="yes"
    echo -e "   ${GREEN}✓${NC} Телеметрия разрешена (логируется только локально)"
  else
    echo "no" > "$TELEMETRY_CONSENT_FILE"
    TELEMETRY_CONSENT="no"
    echo -e "   ${DIM}Окей, не собираем.${NC}"
  fi
  echo ""
}

record_telemetry() {
  [[ "${DRY_RUN:-false}" == true ]] && return 0
  [[ "${TELEMETRY_CONSENT:-no}" == "yes" ]] || return 0

  local step="${1:-unknown}"
  local status="${2:-unknown}"
  local duration="${3:-0}"
  local os_info
  os_info=$(uname -sm 2>/dev/null | tr ' ' '-' | tr '[:upper:]' '[:lower:]' || echo "unknown")
  local ts
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  mkdir -p "$(dirname "$TELEMETRY_LOG")"
  printf '{"ts":"%s","installer":"agents-pack","step":"%s","status":"%s","duration_s":%s,"os":"%s","installer_version":"%s","commit":"%s"}\n' \
    "$ts" "$step" "$status" "$duration" "$os_info" "${INSTALLER_VERSION:-dev}" "${INSTALLER_COMMIT:-dev}" \
    >> "$TELEMETRY_LOG" 2>/dev/null || true
}
