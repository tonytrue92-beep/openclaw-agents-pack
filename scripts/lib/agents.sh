#!/usr/bin/env bash
# agents.sh — операции с агентами OpenClaw для второго установщика.
# Всё что специфично для pack'а: подключение каналов, создание агентов с bind,
# копирование auth-profile, проверка коллизий, валидация Telegram-токенов.
#
# Ожидает что ui.sh уже подключён.

# ─── Валидация Telegram bot token через getMe ───────────────────
#
# Возвращает:
#   0 + echo "<bot_username>" — токен рабочий
#   1 — токен невалидный / сеть не отвечает
validate_telegram_token() {
  local token="$1"
  local response
  response=$(curl --max-time 5 -s "https://api.telegram.org/bot${token}/getMe" 2>/dev/null)

  if [[ -z "$response" ]]; then
    return 1
  fi

  # Парсим JSON через python3 (гарантированно есть на macOS/Linux с Node 22)
  if ! echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('ok') else 1)" 2>/dev/null; then
    return 1
  fi

  local username
  username=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result']['username'])" 2>/dev/null)

  if [[ -z "$username" ]]; then
    return 1
  fi

  echo "$username"
  return 0
}

# ─── Проверка, существует ли агент с заданным id ────────────────
agent_exists() {
  local agent_id="$1"
  if ! command -v openclaw &>/dev/null; then
    return 1
  fi
  openclaw agents list 2>/dev/null | grep -qE "^[- *] ?${agent_id}\b|^\s*${agent_id}\s" || \
    openclaw agents list 2>/dev/null | grep -qiE "\b${agent_id}\b"
}

# ─── Добавить Telegram-канал с заданным accountId + token ───────
#
# Вывод фильтруется inline-sed, чтобы если openclaw случайно напечатает
# токен в stdout — клиент не увидел его в терминале.
#
# Args:
#   $1 = accountId (tech / marketer / producer)
#   $2 = bot token
add_telegram_channel() {
  local account_id="$1"
  local token="$2"

  echo -e "   ${DIM}Подключаю Telegram-канал: ${BOLD}${account_id}${NC}${DIM}...${NC}"

  # pipe-маска на случай утечки токена в stdout
  { openclaw channels add --channel telegram --account "$account_id" --token "$token" 2>&1 || true; } \
    | sed -E \
        -e 's/[0-9]{8,12}:[A-Za-z0-9_-]{30,}/[TG_TOKEN_REDACTED]/g' \
        -e 's/sk-[A-Za-z0-9_-]{20,}/sk-[REDACTED]/g' \
    | while IFS= read -r line; do
        echo -e "   ${DIM}${line}${NC}"
      done
}

# ─── Создать агента + workspace + bind на канал ─────────────────
#
# Args:
#   $1 = agent_id (tech / marketer / producer)
#   $2 = workspace dir (~/.openclaw/workspace-<id>)
#   $3 = model id (opencode/minimax-m2.5-free или выбранная)
#   $4 = telegram account_id (обычно == agent_id)
create_agent_with_bind() {
  local agent_id="$1"
  local workspace_dir="$2"
  local model="$3"
  local account_id="$4"

  echo -e "   ${DIM}Создаю агента: ${BOLD}${agent_id}${NC}${DIM} (model=${model}, bind=telegram:${account_id})...${NC}"

  { openclaw agents add "$agent_id" \
      --non-interactive \
      --workspace "$workspace_dir" \
      --model "$model" \
      --bind "telegram:${account_id}" 2>&1 || true; } | while IFS= read -r line; do
    echo -e "   ${DIM}${line}${NC}"
  done

  # Страховочный второй вызов bind — если первый не применился
  openclaw agents bind --agent "$agent_id" --bind "telegram:${account_id}" &>/dev/null || true
}

# ─── Скопировать auth-profile из main в нового агента ───────────
#
# Новые агенты без скопированного auth-profile получают 401 Invalid API key
# на первый запрос к opencode. Копируем из main (тот что был настроен
# в первом установщике).
copy_auth_profile_from_main() {
  local agent_id="$1"
  local src="$HOME/.openclaw/agents/main/agent/auth-profiles.json"
  local dst_dir="$HOME/.openclaw/agents/${agent_id}/agent"
  local dst="${dst_dir}/auth-profiles.json"

  if [[ ! -f "$src" ]]; then
    warn "Не найден auth-profile в main — агент ${agent_id} может не иметь доступа к opencode"
    return 1
  fi

  mkdir -p "$dst_dir"
  cp "$src" "$dst"
  chmod 600 "$dst"
  echo -e "   ${GREEN}✓${NC} Auth-profile скопирован: ${agent_id}"
}

# ─── Подготовка workspace'а: скачать шаблоны в нужное место ─────
#
# Шаблоны скачиваются с GitHub raw, пинованные к INSTALLER_COMMIT —
# контент и скрипт версионируются вместе.
#
# Args:
#   $1 = agent_id (tech / marketer / producer)
#   $2 = workspace dir
prepare_workspace_from_templates() {
  local agent_id="$1"
  local workspace_dir="$2"

  mkdir -p "$workspace_dir"

  # Commit-pin: если __COMMIT_PLACEHOLDER__ или dev — берём main
  local commit_ref="${INSTALLER_COMMIT:-main}"
  if [[ "$commit_ref" == "__COMMIT_PLACEHOLDER__" || "$commit_ref" == *dev* ]]; then
    commit_ref="main"
  fi
  local base="https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/${commit_ref}/templates/${agent_id}"

  for md in IDENTITY AGENTS MEMORY USER; do
    local dst="${workspace_dir}/${md}.md"
    if curl -fsSL --max-time 10 "${base}/${md}.md" -o "$dst" 2>/dev/null; then
      echo -e "   ${GREEN}✓${NC} ${agent_id}/${md}.md"
    else
      warn "Не смог скачать ${agent_id}/${md}.md — проверьте сеть"
      return 1
    fi
  done

  # ─── Anti-sharing watermark ───────────────────────────────────
  # Для VIP-установок вставляем в IDENTITY.md скрытый markdown-комментарий
  # с хэшем email и TG ID клиента. Markdown-комментарии не рендерятся,
  # агент их не видит, но если клиент «поделится» файлами — по watermark
  # видно чей это инстанс. Психологический сдерживающий фактор.
  #
  # Формат: <!-- issued-to: <email_hash16> | tg:<tg_id> | <agent_id> | YYYY-MM-DD -->
  # email_hash16 = первая секция VIP-токена (не сам email — так не палим PII).
  if [[ "${VIP_MODE:-false}" == true && -n "${VIP_TOKEN:-}" && -n "${MACHINE_TG_ID:-}" ]]; then
    local identity_md="${workspace_dir}/IDENTITY.md"
    if [[ -f "$identity_md" ]]; then
      local hash_part
      hash_part=$(vip_token_get_hash "$VIP_TOKEN" 2>/dev/null || echo "unknown")
      {
        echo ""
        echo "<!-- issued-to: ${hash_part} | tg:${MACHINE_TG_ID} | ${agent_id} | $(date -u +%Y-%m-%d) -->"
      } >> "$identity_md"
    fi
  fi
}

# ─── Полная очистка всего связанного с агентом ──────────────────
#
# Идемпотентный clean-reinstall. Вызывается когда повторно запускают
# установщик и клиент соглашается «перезаписать начисто». Убирает
# ВСЁ, что установщик когда-либо создавал для этого агента:
#
#   1. Сам агент (openclaw agents delete)
#   2. Telegram channel account с тем же id (openclaw channels remove)
#   3. Workspace-папка (~/.openclaw/workspace-<id>)
#   4. Agent state dir (~/.openclaw/agents/<id>) — включая auth-profile
#
# Все команды идут с `|| true` — если агента/канала/папки уже нет,
# это не ошибка.
#
# Args:
#   $1 = agent_id
cleanup_agent_completely() {
  local agent_id="$1"

  # 1. Agent из OpenClaw registry
  openclaw agents delete "$agent_id" --yes &>/dev/null || true

  # 2. Telegram channel account с тем же id (accountId у нас всегда == agent_id)
  openclaw channels remove --channel telegram --account "$agent_id" --yes &>/dev/null || true

  # 3. Workspace dir
  rm -rf "$HOME/.openclaw/workspace-${agent_id}" 2>/dev/null || true

  # 4. Agent state dir (с auth-profile)
  rm -rf "$HOME/.openclaw/agents/${agent_id}" 2>/dev/null || true

  echo -e "   ${GREEN}✓${NC} ${agent_id}: всё старое удалено"
}

# ─── Запрос Telegram user ID и настройка DM allowlist для аккаунта ──
#
# Без allowlist бот не будет отвечать в личке (по умолчанию
# dmPolicy: pairing — нужен pairing-код, что для курса лишнее).
#
# Args:
#   $1 = account_id
#   $2 = owner_tg_id (если пусто — спрашиваем интерактивно)
configure_dm_allowlist() {
  local account_id="$1"
  local owner_tg_id="$2"

  if [[ -z "$owner_tg_id" ]]; then
    return 0  # если ID не задан — не трогаем конфиг
  fi

  openclaw config set "channels.telegram.accounts.${account_id}.dmPolicy" allowlist &>/dev/null || true
  openclaw config set "channels.telegram.accounts.${account_id}.allowFrom" "[\"${owner_tg_id}\"]" --strict-json &>/dev/null || true
}
