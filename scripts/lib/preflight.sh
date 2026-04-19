#!/usr/bin/env bash
# preflight.sh — проверки перед запуском установщика:
# 1. OpenClaw установлен и gateway живой (специфично для agent-pack)
# 2. Есть auth-profile основного агента — копировать его в новых
# 3. Сеть к critical endpoints работает
#
# Ожидает что ui.sh уже подключён (цвета + ok/warn/ru).

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

  if ! command -v openclaw &>/dev/null; then
    echo ""
    warn "OpenClaw не найден в PATH."
    echo ""
    echo -e "   ${BOLD}${WHITE}Этот установщик — вторая ступень.${NC}"
    echo -e "   ${DIM}Он только ДОБАВЛЯЕТ агентов к уже работающему OpenClaw.${NC}"
    echo ""
    echo -e "   ${BOLD}Сначала нужно установить сам OpenClaw:${NC}"
    echo ""
    echo -e "      ${GREEN}bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh)${NC}"
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

  # auth-profiles главного агента — нужен чтобы копировать в новых
  local main_auth="$HOME/.openclaw/agents/main/agent/auth-profiles.json"
  if [[ ! -f "$main_auth" ]]; then
    warn "Не найден auth-profile основного агента (${main_auth})"
    echo -e "   ${DIM}Это значит, у вас ещё нет настроенного opencode.ai ключа.${NC}"
    echo -e "   ${DIM}Сначала пройдите реальную установку в первом установщике.${NC}"
    return 1
  fi
  echo -e "   ${GREEN}✓${NC} auth-profile основного агента найден"

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
