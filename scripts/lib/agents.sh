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
# Два режима:
#
#   • full (default) — свежая установка / полная перезапись. Скачивает
#     все md (IDENTITY/AGENTS/MEMORY/USER + SOUL/LEARNING/skills для VIP),
#     генерит новый anti-sharing watermark из VIP_TOKEN.
#
#   • refresh — обновление существующей установки (wave 7). Скачивает
#     только «системные» md (IDENTITY/AGENTS + SOUL/LEARNING/skills), НЕ
#     трогает MEMORY.md и USER.md (это пользовательские данные — контекст
#     сессий и ответы онбординга). Старые файлы бэкапятся в
#     <workspace>/.backups/<timestamp>/. Watermark из старой IDENTITY.md
#     переносится в новую как есть (не перевыпускаем — для refresh нам
#     не нужен VIP_TOKEN).
#
# Args:
#   $1 = agent_id (tech / marketer / producer / designer / coordinator / copywriter)
#   $2 = workspace dir
#   $3 = mode: "full" (default) | "refresh"
prepare_workspace_from_templates() {
  local agent_id="$1"
  local workspace_dir="$2"
  local mode="${3:-full}"

  mkdir -p "$workspace_dir"

  # ─── Refresh mode: бэкап + вытащить старый watermark ──────────
  local backup_dir=""
  local old_watermark=""
  if [[ "$mode" == "refresh" ]]; then
    local ts
    ts=$(date +%Y%m%d-%H%M%S)
    backup_dir="${workspace_dir}/.backups/${ts}"
    mkdir -p "$backup_dir"
    # Сохраняем anti-sharing watermark из старой IDENTITY.md
    # (строка `<!-- issued-to: ... -->` из wave 3 / 6)
    if [[ -f "${workspace_dir}/IDENTITY.md" ]]; then
      old_watermark=$(grep -E '^<!-- issued-to:' "${workspace_dir}/IDENTITY.md" 2>/dev/null | head -1)
    fi
  fi

  # Commit-pin: если __COMMIT_PLACEHOLDER__ или dev — берём main
  local commit_ref="${INSTALLER_COMMIT:-main}"
  if [[ "$commit_ref" == "__COMMIT_PLACEHOLDER__" || "$commit_ref" == *dev* ]]; then
    commit_ref="main"
  fi
  local base="https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/${commit_ref}/templates/${agent_id}"

  # ─── Базовые md-файлы ────────────────────────────────────────
  # full: скачиваем все 4 (IDENTITY/AGENTS/MEMORY/USER)
  # refresh: только IDENTITY/AGENTS — MEMORY и USER это пользовательские
  # данные (контекст + ответы онбординга), трогать нельзя.
  local md_list="IDENTITY AGENTS MEMORY USER"
  if [[ "$mode" == "refresh" ]]; then
    md_list="IDENTITY AGENTS"
  fi

  local md
  for md in $md_list; do
    local dst="${workspace_dir}/${md}.md"
    # В refresh mode — бэкап старого перед перезаписью
    if [[ "$mode" == "refresh" && -f "$dst" ]]; then
      cp "$dst" "${backup_dir}/${md}.md" 2>/dev/null || true
    fi
    if curl -fsSL --max-time 10 "${base}/${md}.md" -o "$dst" 2>/dev/null; then
      echo -e "   ${GREEN}✓${NC} ${agent_id}/${md}.md"
    else
      warn "Не смог скачать ${agent_id}/${md}.md — проверьте сеть"
      return 1
    fi
  done

  # ─── VIP-агенты: расширенный набор (SOUL + LEARNING + skills) ──
  #
  # 3 VIP-специфичных агента (designer/coordinator/copywriter) получают
  # дополнительные файлы:
  #   • SOUL.md   — personality / границы / autonomy / онбординг-протокол
  #   • LEARNING.md — предзаполненные anti-patterns + место для новых
  #   • skills/<name>/SKILL.md × 2 — готовые фреймворки под роль
  #
  # Остальные 3 (tech/marketer/producer) используют старый минимальный
  # формат (4 базовых md-файла). Если VIP-extras не докачались — warn,
  # но установку не прерываем (без них агент работает хуже, но работает).
  local has_extras=false
  case "$agent_id" in
    designer|coordinator|copywriter) has_extras=true ;;
  esac

  if [[ "$has_extras" == true ]]; then
    # SOUL и LEARNING — в refresh mode тоже обновляем (это «системная»
    # часть, не содержит пользовательских ответов). Бэкап по-прежнему
    # сохраняем.
    local extra
    for extra in SOUL LEARNING; do
      local extra_dst="${workspace_dir}/${extra}.md"
      if [[ "$mode" == "refresh" && -f "$extra_dst" ]]; then
        cp "$extra_dst" "${backup_dir}/${extra}.md" 2>/dev/null || true
      fi
      if curl -fsSL --max-time 10 "${base}/${extra}.md" -o "$extra_dst" 2>/dev/null; then
        echo -e "   ${GREEN}✓${NC} ${agent_id}/${extra}.md"
      else
        warn "Не скачал ${agent_id}/${extra}.md — агент будет работать в базовом режиме"
      fi
    done

    # skills/*/SKILL.md — список зашит по ролям
    local skills_list=""
    case "$agent_id" in
      designer)    skills_list="eachlabs-image-generation color-palette" ;;
      coordinator) skills_list="agent-collaboration-network close-loop" ;;
      copywriter)  skills_list="reef-copywriting brand-voice-profile" ;;
    esac

    # В refresh mode — целиком бэкапим skills/ перед перезаписью
    if [[ "$mode" == "refresh" && -d "${workspace_dir}/skills" ]]; then
      cp -R "${workspace_dir}/skills" "${backup_dir}/skills" 2>/dev/null || true
    fi

    mkdir -p "${workspace_dir}/skills"
    local skill
    for skill in $skills_list; do
      local skill_dir="${workspace_dir}/skills/${skill}"
      mkdir -p "$skill_dir"
      if curl -fsSL --max-time 10 \
           "${base}/skills/${skill}/SKILL.md" \
           -o "${skill_dir}/SKILL.md" 2>/dev/null; then
        echo -e "   ${GREEN}✓${NC} ${agent_id}/skills/${skill}/SKILL.md"
      else
        warn "Не скачал skill ${skill} для ${agent_id} — не критично"
      fi
    done
  fi

  # ─── Anti-sharing watermark ───────────────────────────────────
  # Для VIP-установок вставляем в IDENTITY.md скрытый markdown-комментарий
  # с хэшем email и TG ID клиента. Markdown-комментарии не рендерятся,
  # агент их не видит, но если клиент «поделится» файлами — по watermark
  # видно чей это инстанс. Психологический сдерживающий фактор.
  #
  # Формат: <!-- issued-to: <email_hash16> | tg:<tg_id> | <agent_id> | YYYY-MM-DD -->
  # email_hash16 = первая секция VIP-токена (не сам email — так не палим PII).
  #
  # В refresh mode — не перевыпускаем, а переносим старый watermark из
  # сохранённой строки (у нас нет VIP_TOKEN в refresh).
  if [[ "$mode" == "refresh" && -n "$old_watermark" ]]; then
    local identity_md="${workspace_dir}/IDENTITY.md"
    if [[ -f "$identity_md" ]]; then
      {
        echo ""
        echo "$old_watermark"
      } >> "$identity_md"
    fi
  elif [[ "$mode" != "refresh" && "${VIP_MODE:-false}" == true \
          && -n "${VIP_TOKEN:-}" && -n "${MACHINE_TG_ID:-}" ]]; then
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

  # ─── Refresh summary ─────────────────────────────────────────
  if [[ "$mode" == "refresh" ]]; then
    echo -e "   ${DIM}Бэкап старых шаблонов: ${backup_dir}${NC}"
    echo -e "   ${DIM}MEMORY.md и USER.md не тронуты${NC}"
  fi
}

# ─── Найти все установленные агенты (для --refresh-templates) ────
#
# Итерируется по известным ID, проверяет agent_exists и возвращает
# список существующих (через stdout, по одному на строку). Используется
# неинтерактивным режимом --refresh-templates чтобы не спрашивать
# клиента какие агенты у него стоят.
find_installed_agents() {
  local candidate
  for candidate in tech marketer producer designer coordinator copywriter; do
    if agent_exists "$candidate"; then
      echo "$candidate"
    fi
  done
}

# ─── Валидация OpenAI API-ключа через embeddings endpoint ───────
#
# Делает 1-токен POST на /v1/embeddings — самый дешёвый способ
# убедиться что ключ работает + имеет доступ к embedding-моделям
# (некоторые ключи органзаций могут быть ограничены только chat-моделями).
#
# Args:
#   $1 = api key
# Returns:
#   0 — ключ валидный
#   1 — ошибка (сеть / 401 / 403 / нет доступа к модели)
validate_openai_embedding_key() {
  local key="$1"
  local response
  response=$(curl --max-time 5 -s -w '\n%{http_code}' \
    -X POST 'https://api.openai.com/v1/embeddings' \
    -H "Authorization: Bearer ${key}" \
    -H 'Content-Type: application/json' \
    -d '{"model":"text-embedding-3-large","input":"ping"}' 2>/dev/null)

  local http_code
  http_code=$(echo "$response" | tail -1)
  local body
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" == "200" ]]; then
    # Проверим что в ответе есть массив embedding'ов
    if echo "$body" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('data') and len(d['data'])>0 else 1)" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

# ─── Включить embedding-память для агента ───────────────────────
#
# Прописывает в ~/.openclaw/openclaw.json:
#   • agents.<id>.memorySearch.enabled = true
#   • agents.<id>.memorySearch.provider = openai
#   • agents.<id>.memorySearch.model = text-embedding-3-large
#
# OPENAI_EMBEDDING_API_KEY пишется отдельно один раз глобально через
# guard-флаг EMBEDDING_ENV_WRITTEN (см. caller в install-agents.sh).
#
# Per-agent а не agents.defaults — чтобы --only-установка одного
# агента не флипала switch у уже стоящих.
#
# Все вызовы openclaw config set идут через redaction-pipe чтобы
# случайно не утёк ключ если openclaw напечатает его в stdout.
#
# Args:
#   $1 = agent_id
enable_embedding_for_agent() {
  local agent_id="$1"

  echo -e "   ${DIM}Включаю embedding-память для ${BOLD}${agent_id}${NC}${DIM}...${NC}"

  { openclaw config set "agents.${agent_id}.memorySearch.enabled" true 2>&1 || true; } \
    | sed -E -e 's/sk-[A-Za-z0-9_-]{20,}/sk-[REDACTED]/g' \
    | while IFS= read -r line; do echo -e "   ${DIM}${line}${NC}"; done

  { openclaw config set "agents.${agent_id}.memorySearch.provider" openai 2>&1 || true; } \
    | sed -E -e 's/sk-[A-Za-z0-9_-]{20,}/sk-[REDACTED]/g' \
    | while IFS= read -r line; do echo -e "   ${DIM}${line}${NC}"; done

  { openclaw config set "agents.${agent_id}.memorySearch.model" text-embedding-3-large 2>&1 || true; } \
    | sed -E -e 's/sk-[A-Za-z0-9_-]{20,}/sk-[REDACTED]/g' \
    | while IFS= read -r line; do echo -e "   ${DIM}${line}${NC}"; done
}

# ─── Записать OpenAI ключ в env.vars ─────────────────────────────
#
# Пишется глобально один раз на запуск установщика. Caller должен
# guard'ить через EMBEDDING_ENV_WRITTEN чтобы не дублировать вызов.
#
# Args:
#   $1 = api key
write_embedding_env_key() {
  local key="$1"
  { openclaw config set 'env.vars.OPENAI_EMBEDDING_API_KEY' "$key" 2>&1 || true; } \
    | sed -E -e 's/sk-[A-Za-z0-9_-]{20,}/sk-[REDACTED]/g' \
    | while IFS= read -r line; do echo -e "   ${DIM}${line}${NC}"; done
}

# ─── Запустить индексацию памяти агента (embedding) ──────────────
#
# Wrapper над `openclaw memory index --agent <id>` с heartbeat
# (на больших MEMORY.md может занять 10-30 сек — клиент должен
# видеть что мы живы).
#
# На неудаче — warn (не убивает установку): без индекса embedding
# просто не работает, но MEMORY.md по-прежнему доступна агенту
# через классический path-режим.
#
# Args:
#   $1 = agent_id
index_agent_memory() {
  local agent_id="$1"

  echo -e "   ${DIM}Индексирую память: ${BOLD}${agent_id}${NC}${DIM}...${NC}"
  start_heartbeat "memory-index-${agent_id}" 5 60 &
  local hb_pid=$!

  if ! openclaw memory index --agent "$agent_id" >/dev/null 2>&1; then
    stop_heartbeat "$hb_pid" 2>/dev/null || true
    warn "Не удалось проиндексировать память ${agent_id}. Можно позже: openclaw memory index --agent ${agent_id}"
    return 0  # не критично
  fi

  stop_heartbeat "$hb_pid" 2>/dev/null || true
  echo -e "   ${GREEN}✓${NC} ${agent_id}: память проиндексирована"
}

# ─── Получить статус embedding для агента (для diagnose) ─────────
#
# stdout: одна из строк:
#   on:<doc_count>:<last_indexed_iso>
#   off
#   error
#
# Используется в diagnose-agents.sh.
embedding_status_for_agent() {
  local agent_id="$1"
  local out
  out=$(openclaw memory status --agent "$agent_id" --json 2>/dev/null || echo '{}')

  python3 -c "
import json,sys
try:
    d = json.loads('''${out}''')
    enabled = d.get('enabled', False)
    if not enabled:
        print('off')
        sys.exit(0)
    docs = d.get('index', {}).get('docs', 0)
    last = d.get('index', {}).get('lastIndexedAt', '?')
    print(f'on:{docs}:{last}')
except Exception:
    print('error')
" 2>/dev/null || echo "error"
}

# ─── Конфигурация TG-группового режима для агента ────────────────
#
# Прописывает per-agent TG-канал:
#   • channels.telegram.accounts.<id>.groupPolicy = allowlist
#   • channels.telegram.accounts.<id>.groupAllowFrom — добавляет chat_id (дедуп)
#   • channels.telegram.accounts.<id>.groups.<chat_id>.requireMention = true
#
# Идемпотентно: повторный запуск с тем же chat_id не создаёт дубли.
# Читает существующий groupAllowFrom через --json, добавляет уникально.
#
# Args:
#   $1 = agent_id (= account_id в нашей схеме)
#   $2 = chat_id (signed integer, может быть -100… для supergroup или -… для basic)
configure_group_membership() {
  local agent_id="$1"
  local chat_id="$2"

  echo -e "   ${DIM}Настраиваю group-mode: ${BOLD}${agent_id}${NC}${DIM} ↔ chat ${chat_id}${NC}"

  # 1. groupPolicy = allowlist
  openclaw config set "channels.telegram.accounts.${agent_id}.groupPolicy" allowlist &>/dev/null || true

  # 2. groupAllowFrom — читаем массив, добавляем chat_id если нет
  local existing_json
  existing_json=$(openclaw config get "channels.telegram.accounts.${agent_id}.groupAllowFrom" --json 2>/dev/null || echo '[]')

  local new_json
  new_json=$(python3 -c "
import json,sys
try:
    arr = json.loads('''${existing_json}''')
    if not isinstance(arr, list):
        arr = []
except Exception:
    arr = []
chat_id = '${chat_id}'
if chat_id not in [str(x) for x in arr]:
    arr.append(chat_id)
print(json.dumps(arr))
" 2>/dev/null)

  if [[ -n "$new_json" ]]; then
    openclaw config set "channels.telegram.accounts.${agent_id}.groupAllowFrom" "$new_json" --strict-json &>/dev/null || true
  fi

  # 3. requireMention = true для этой группы
  openclaw config set "channels.telegram.accounts.${agent_id}.groups.${chat_id}.requireMention" true --strict-json &>/dev/null || true

  echo -e "   ${GREEN}✓${NC} ${agent_id}: group-mode настроен (chat ${chat_id})"
}

# ─── Получить статус group-mode для агента (для diagnose) ────────
#
# stdout: одна из строк:
#   on:<chat_id1>,<chat_id2>,…
#   off
#   error
group_mode_status_for_agent() {
  local agent_id="$1"
  local out
  out=$(openclaw config get "channels.telegram.accounts.${agent_id}.groupAllowFrom" --json 2>/dev/null || echo '[]')

  python3 -c "
import json,sys
try:
    arr = json.loads('''${out}''')
    if isinstance(arr, list) and len(arr) > 0:
        print('on:' + ','.join(str(x) for x in arr))
    else:
        print('off')
except Exception:
    print('error')
" 2>/dev/null || echo "error"
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
