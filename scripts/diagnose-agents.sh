#!/usr/bin/env bash
# diagnose-agents.sh — проверка всех трёх агентов без изменений.
# Вызывается напрямую или через `install-agents.sh --diagnose-only`.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/ui.sh"
# agents.sh даёт agent_exists, embedding_status_for_agent, group_mode_status_for_agent
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/agents.sh" 2>/dev/null || true

echo ""
echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${MAGENTA}  🩺  OpenClaw Agents Pack — LIVE ДИАГНОСТИКА${NC}"
echo -e "${BOLD}${MAGENTA}  (ничего не меняется, только проверяем)${NC}"
echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

issues=()

# ─── 1. OpenClaw CLI ───
echo -e "${BOLD}1. OpenClaw CLI${NC}"
if command -v openclaw &>/dev/null; then
  echo -e "   ${GREEN}✓${NC} openclaw: $(openclaw --version 2>&1 | head -1)"
else
  echo -e "   ${RED}✗${NC} openclaw не найден в PATH"
  issues+=("openclaw не установлен — запустите первый установщик openclaw-factory")
fi

# ─── 2. Gateway ───
echo ""
echo -e "${BOLD}2. Gateway${NC}"
if command -v openclaw &>/dev/null; then
  gw_status=$(openclaw gateway status 2>&1 || true)
  if echo "$gw_status" | grep -qE "running"; then
    echo -e "   ${GREEN}✓${NC} Gateway: running"
  else
    echo -e "   ${RED}✗${NC} Gateway не отвечает"
    issues+=("gateway не работает — попробуйте: openclaw gateway restart")
  fi
fi

# ─── 3. Каждый из установленных агентов ───
echo ""
echo -e "${BOLD}3. Агенты${NC}"

# Берём агентов которые реально установлены (а не жёсткий список — wave 5+
# может иметь 3 (Standard) или 6 (VIP), не статично).
AGENTS_TO_CHECK=()
for candidate in tech marketer producer designer coordinator copywriter; do
  if command -v openclaw &>/dev/null && openclaw agents list 2>&1 | grep -qiE "\b${candidate}\b"; then
    AGENTS_TO_CHECK+=("$candidate")
  fi
done

if [[ ${#AGENTS_TO_CHECK[@]} -eq 0 ]]; then
  echo -e "   ${YELLOW}○${NC} Не нашёл установленных агентов в openclaw agents list"
  AGENTS_TO_CHECK=(tech marketer producer)  # fallback на старое поведение
fi

for agent in "${AGENTS_TO_CHECK[@]}"; do
  echo ""
  echo -e "${BOLD}   Agent: ${agent}${NC}"
  ws="$HOME/.openclaw/workspace-${agent}"
  auth="$HOME/.openclaw/agents/${agent}/agent/auth-profiles.json"

  # 3a. Workspace папка
  if [[ -d "$ws" ]]; then
    echo -e "   ${GREEN}✓${NC} workspace: ${ws}"
    for md in IDENTITY AGENTS MEMORY USER; do
      if [[ -f "${ws}/${md}.md" ]]; then
        echo -e "      ${GREEN}•${NC} ${md}.md (${BOLD}$(wc -l < "${ws}/${md}.md")${NC} строк)"
      else
        echo -e "      ${YELLOW}○${NC} ${md}.md отсутствует"
      fi
    done
  else
    echo -e "   ${RED}✗${NC} workspace-папка не создана (${ws})"
    issues+=("agent ${agent}: workspace отсутствует")
    continue
  fi

  # 3b. Агент в OpenClaw CLI
  if command -v openclaw &>/dev/null; then
    if openclaw agents list 2>&1 | grep -qiE "\b${agent}\b"; then
      echo -e "   ${GREEN}✓${NC} зарегистрирован в OpenClaw"
    else
      echo -e "   ${RED}✗${NC} не зарегистрирован в OpenClaw"
      issues+=("agent ${agent}: нет в openclaw agents list")
    fi

    # 3c. Binding
    if openclaw agents bindings 2>&1 | grep -qE "^-\s*${agent}\b"; then
      echo -e "   ${GREEN}✓${NC} binding telegram:${agent} на месте"
    else
      echo -e "   ${YELLOW}○${NC} binding не найден (бот не маршрутизируется к агенту)"
      issues+=("agent ${agent}: bind telegram:${agent} отсутствует")
    fi
  fi

  # 3d. Auth-profile
  if [[ -f "$auth" ]]; then
    perms=$(stat -f '%A' "$auth" 2>/dev/null || stat -c '%a' "$auth" 2>/dev/null || echo "?")
    if [[ "$perms" == "600" ]]; then
      echo -e "   ${GREEN}✓${NC} auth-profile: ${perms}"
    else
      echo -e "   ${YELLOW}○${NC} auth-profile: права ${perms} (ожидается 600)"
    fi
  else
    echo -e "   ${YELLOW}○${NC} auth-profile отсутствует — бот может получить 401"
    issues+=("agent ${agent}: auth-profile не скопирован из main")
  fi

  # 3e. Embedding-память (wave 8) — по желанию клиента, не критично
  if command -v openclaw &>/dev/null && declare -F embedding_status_for_agent >/dev/null 2>&1; then
    emb_status=$(embedding_status_for_agent "$agent" 2>/dev/null || echo "error")
    case "$emb_status" in
      on:*)
        emb_data=${emb_status#on:}
        emb_docs=${emb_data%:*}
        emb_last=${emb_data#*:}
        # Считаем «свежий» если индексировано за последние 7 дней
        # Простой способ: ищем сегодняшнюю дату или вчерашнюю в строке
        echo -e "   ${GREEN}✓${NC} embedding: вкл (${emb_docs} docs, last ${emb_last:0:10})"
        ;;
      off)
        echo -e "   ${DIM}○${NC} embedding: выкл (опция R1.5 — не выбрана)"
        ;;
      *)
        echo -e "   ${YELLOW}○${NC} embedding: статус unknown (проверьте openclaw memory status --agent ${agent})"
        ;;
    esac
  fi

  # 3f. Group-mode (wave 8)
  if command -v openclaw &>/dev/null && declare -F group_mode_status_for_agent >/dev/null 2>&1; then
    grp_status=$(group_mode_status_for_agent "$agent" 2>/dev/null || echo "error")
    case "$grp_status" in
      on:*)
        echo -e "   ${GREEN}✓${NC} group-mode: ${grp_status#on:}"
        ;;
      off)
        echo -e "   ${DIM}○${NC} group-mode: выкл (агент только в DM)"
        ;;
      *) ;;  # error / неизвестно — молчим, не критично
    esac
  fi
done

# ─── Вердикт ───
echo ""
echo -e "${BOLD}${MAGENTA}━━━ ИТОГ ━━━${NC}"
if [[ ${#issues[@]} -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}✓ Все три агента в порядке.${NC}"
  echo -e "${DIM}Напишите любому из ботов — должен ответить.${NC}"
else
  echo -e "${YELLOW}Найдено проблем: ${#issues[@]}${NC}"
  for issue in "${issues[@]}"; do
    echo -e "   ${RED}•${NC} ${issue}"
  done
  echo ""
  echo -e "${BOLD}${WHITE}Варианты действий:${NC}"
  echo -e "   ${CYAN}→${NC} Переустановить с нуля: ${GREEN}bash <(curl ...) --install${NC}"
  echo -e "   ${CYAN}→${NC} Собрать debug-bundle: ${GREEN}bash <(curl ...) --collect-debug${NC}"
fi
echo ""
