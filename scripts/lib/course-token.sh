#!/usr/bin/env bash
# course-token.sh — wave 12: единая система токенов для Standard и VIP.
#
# До wave 12: токен требовался ТОЛЬКО для VIP-установки. Standard-клиенты
# просто запускали `bash <(curl)` без авторизации → команду могли просто
# скопировать из чата и поставить себе бесплатно.
#
# После wave 12: ЛЮБАЯ свежая установка / переустановка требует
# course-token. Токены выдаёт @AITeamVIPBot:
#   - VIP-клиентам: OC5-VIP-... (payload OC5|VIP|hash|tg_id|nonce)
#   - Standard-клиентам: OC5-STD-... (payload OC5|STD|hash|tg_id|nonce)
#
# Backward-compat:
#   - --refresh-templates: токен НЕ требуется (уже-установленные не страдают)
#   - --diagnose-only / --collect-debug / --enable-group-mode: токен НЕ нужен
#   - Поддерживаются только OC5 токены с обязательной online-проверкой; v1/v2/v3/OC4
#     отозваны и требуют перевыпуска в @AITeamVIPBot.
#
# Кэширование: после успешной валидации токен сохраняется в
# ~/.openclaw/course-token (chmod 600). На следующих запусках читается
# автоматически — клиент не вводит каждый раз.
#
# Ожидает что vip.sh уже подключён (verify_vip_token, course_token_get_tier).

# Путь к кэшу токена
COURSE_TOKEN_CACHE="$HOME/.openclaw/course-token"

# ─── Прочитать кэшированный токен ──────────────────────────────
# stdout: токен или пусто
_course_token_load_cache() {
  if [[ -f "$COURSE_TOKEN_CACHE" ]]; then
    # umask 077 не помогает на уже существующем файле — проверяем права
    local perms
    perms=$(stat -f '%A' "$COURSE_TOKEN_CACHE" 2>/dev/null \
              || stat -c '%a' "$COURSE_TOKEN_CACHE" 2>/dev/null \
              || echo "?")
    if [[ "$perms" == "?" ]]; then
      # R2-аудит: stat недоступен — раньше fail-open; теперь чиним права
      # сами и продолжаем только если chmod удался (fail-closed).
      chmod 600 "$COURSE_TOKEN_CACHE" 2>/dev/null || return 1
    elif [[ "$perms" != "600" ]]; then
      # Кэш не защищён — игнорируем, чтобы не использовать скомпрометированный токен
      return 1
    fi
    cat "$COURSE_TOKEN_CACHE" 2>/dev/null | tr -d '[:space:]'
  fi
}

# ─── Сохранить токен в кэш ────────────────────────────────────
# Args: $1 = токен
_course_token_save_cache() {
  local token="$1"
  local dir
  dir=$(dirname "$COURSE_TOKEN_CACHE")
  mkdir -p "$dir" 2>/dev/null || true
  # umask 077 + явный chmod 600 — двойная защита
  ( umask 077; printf '%s\n' "$token" > "$COURSE_TOKEN_CACHE" )
  chmod 600 "$COURSE_TOKEN_CACHE" 2>/dev/null || true
}

# ─── Удалить кэш (например, при отзыве токена) ────────────────
course_token_clear_cache() {
  rm -f "$COURSE_TOKEN_CACHE" 2>/dev/null || true
}

# ─── Главная функция: получить и провалидировать токен ────────
#
# Алгоритм:
#   1. Если caller передал токен (через --course-token / --vip-token / --config)
#      → валидируем его
#   2. Иначе пробуем кэш
#   3. Иначе prompt пользователю
#   4. После успешной валидации — сохраняем кэш
#
# Args:
#   $1 = preset_token (или пусто — попробуем кэш / prompt)
#   $2 = machine_tg_id (для anti-share проверки)
#   $3 = mode: "interactive" | "non-interactive" (--config)
#
# stdout: ничего
# Returns:
#   0 — токен получен и валиден; экспортирует COURSE_TOKEN, COURSE_TIER
#   1 — токен невалиден / отказ пользователя
#
# После успеха caller может читать:
#   $COURSE_TOKEN  — сам токен
#   $COURSE_TIER   — "VIP" или "STD"
acquire_course_token() {
  local preset_token="$1"
  local machine_tg_id="$2"
  local mode="${3:-interactive}"

  COURSE_TOKEN=""
  COURSE_TIER=""

  # Шаг 1: preset (явно переданный)
  if [[ -n "$preset_token" ]]; then
    if _course_token_validate_and_set "$preset_token" "$machine_tg_id"; then
      _course_token_save_cache "$COURSE_TOKEN"
      return 0
    fi
    # Preset невалиден — в non-interactive это fatal
    if [[ "$mode" == "non-interactive" ]]; then
      return 1
    fi
    # В interactive падаем на prompt
  fi

  # Шаг 2: кэш
  local cached
  cached=$(_course_token_load_cache)
  if [[ -n "$cached" ]]; then
    if _course_token_validate_and_set "$cached" "$machine_tg_id"; then
      echo -e "   ${GREEN}✓${NC} Использую кэшированный course-token (${COURSE_TIER}-тариф)"
      return 0
    else
      # Кэшированный токен не прошёл — возможно был отозван или TG ID
      # машины поменялся. Удаляем кэш и просим заново.
      warn "Кэшированный токен больше не валиден (возможно отозван). Запрашиваю новый."
      course_token_clear_cache
    fi
  fi

  # Шаг 3: prompt (только в interactive)
  if [[ "$mode" == "non-interactive" ]]; then
    echo "" >&2
    echo "ERROR: course-token обязателен для свежей установки." >&2
    echo "В non-interactive режиме передайте флагом:" >&2
    echo "  bash scripts/install-agents.sh --install --course-token OC5-STD-..." >&2
    echo "Или строкой COURSE_TOKEN=OC5-STD-... в файле для --config." >&2
    return 1
  fi

  _course_token_prompt_loop "$machine_tg_id"
}

# ─── Prompt-цикл для интерактивного режима ────────────────────
_course_token_prompt_loop() {
  local machine_tg_id="$1"
  local attempts=0
  local max_attempts=3

  while [[ $attempts -lt $max_attempts ]]; do
    attempts=$((attempts + 1))

    if [[ $attempts -eq 1 ]]; then
      explain "Для установки нужен course-token." \
        "" \
        "Получи его в Telegram-боте курса:" \
        "  ${BOLD}@AITeamVIPBot${NC} → /start → email/phone оплаты" \
        "" \
        "Бот выдаст токен формата:" \
        "  ${DIM}OC5-STD-XXXXXXXXXXXXXXXX-<TG_ID>-<nonce>-<подпись>  (Standard)${NC}" \
        "  ${DIM}OC5-VIP-XXXXXXXXXXXXXXXX-<TG_ID>-<nonce>-<подпись>  (VIP)${NC}" \
        "" \
        "Токен привязан к твоему Telegram — расшарить нельзя." \
        "" \
        "${YELLOW}💡 Если ты уже устанавливал агентов раньше${NC}" \
        "${YELLOW}   и просто хочешь обновить — нажми ${BOLD}Ctrl+C${NC}${YELLOW} и запусти:${NC}" \
        "${YELLOW}   ${BOLD}bash <(curl ...) --refresh-templates${NC}" \
        "${YELLOW}   (это обновит шаблоны БЕЗ потери MEMORY и БЕЗ токена)${NC}"
    fi

    echo -e "   ${BOLD}${WHITE}Вставь course-token (попытка ${attempts}/${max_attempts}):${NC}"
    local token
    read -r token

    if [[ -z "$token" ]]; then
      warn "Пустой ввод."
      continue
    fi

    if _course_token_validate_and_set "$token" "$machine_tg_id"; then
      _course_token_save_cache "$COURSE_TOKEN"
      echo -e "   ${GREEN}✓${NC} Токен подтверждён (${COURSE_TIER}-тариф). Сохранил для следующих запусков."
      return 0
    fi
  done

  warn "Превышено количество попыток. Получи свежий токен в @AITeamVIPBot и попробуй снова."
  return 1
}

# ─── Валидация + установка глобальных переменных ──────────────
# Args: $1 = token, $2 = machine_tg_id
# Returns: 0 если всё ОК (COURSE_TOKEN, COURSE_TIER установлены)
_course_token_validate_and_set() {
  local token="$1"
  local machine_tg_id="$2"

  # Wave 17: санитизация ввода — типичные ошибки копипасты.
  # Реальный кейс (Надежда Sagitova, 15.05.2026): валидный VIP-токен
  # отклонялся с кодом 5 из-за trailing-whitespace при копировании
  # из Telegram-десктопа. На мобильных встречается замена дефиса (-)
  # на длинное тире (—) — Apple-автокоррекция.
  local original_token="$token"
  token=$(printf '%s' "$token" | tr -d '[:space:]')
  token="${token//—/-}"   # U+2014 EM DASH (длинное тире)
  token="${token//–/-}"   # U+2013 EN DASH (среднее тире)
  token="${token//‐/-}"   # U+2010 HYPHEN (юникод-дефис)
  token="${token//‑/-}"   # U+2011 NON-BREAKING HYPHEN (неразрывный дефис)
  token="${token//\"/}"   # обрамляющие кавычки если клиент скопировал "TOKEN"
  token="${token//\'/}"   # обрамляющие одинарные кавычки

  if [[ "$token" != "$original_token" ]]; then
    echo -e "   ${DIM}ℹ️  Очистил токен от лишних символов (пробелы / тире-юникод / кавычки).${NC}" >&2
  fi

  # Префикс должен быть OC5-VIP- / OC5-STD- / OC5-SUB-
  local tier
  tier=$(course_token_get_tier "$token" 2>/dev/null)
  if [[ -z "$tier" ]]; then
    warn "Токен устарел или имеет неверный формат. Получи новый OC5-токен в @AITeamVIPBot."
    return 1
  fi

  # Криптографическая и обязательная онлайн-проверка через verify_vip_token.
  verify_vip_token "$token" "$machine_tg_id"
  local rc=$?

  case $rc in
    0)
      COURSE_TOKEN="$token"
      COURSE_TIER="$tier"
      return 0
      ;;
    3)
      local expected_tg
      expected_tg=$(vip_token_get_expected_tg "$token" 2>/dev/null || echo "?")
      warn "Токен выдан для TG ID ${expected_tg}, а у тебя ${machine_tg_id}."
      echo -e "   ${DIM}Это анти-шаринг защита: получи свой токен в @AITeamVIPBot${NC}"
      echo -e "   ${DIM}с ТОГО ЖЕ Telegram-аккаунта где будут жить агенты.${NC}"
      return 1
      ;;
    6)
      warn "Онлайн-проверка токена не пройдена: он отозван, истёк (7 дней) или сервис недоступен."
      echo -e "   ${DIM}Получи свежий токен в @AITeamVIPBot и проверь подключение к интернету.${NC}"
      return 1
      ;;
    *)
      warn "Подпись токена не прошла проверку (код $rc)."
      echo -e "   ${DIM}Возможно: токен повреждён при копировании / отозван / устарел.${NC}"
      echo -e "   ${DIM}Получи свежий в @AITeamVIPBot.${NC}"
      return 1
      ;;
  esac
}

# ─── Проверить что для текущего режима требуется токен ────────
#
# Args: $1 = mode_name ("install" | "refresh" | "diagnose" | "debug-bundle" | "group-mode")
# Returns: 0 если токен нужен, 1 если нет
course_token_required_for_mode() {
  local mode="$1"
  case "$mode" in
    install|reinstall|fresh) return 0 ;;
    refresh|diagnose|debug-bundle|group-mode) return 1 ;;
    *) return 0 ;;  # неизвестный режим — на всякий случай требуем
  esac
}
