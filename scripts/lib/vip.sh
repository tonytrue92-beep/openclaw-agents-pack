#!/usr/bin/env bash
# vip.sh — локальная проверка VIP-токена для установщика.
# Без сетевых запросов при валидации: бот может лежать, а уже выданные
# токены продолжат работать.
#
# v2 формат токена: VIP-<email_hash16>-<tg_user_id>-<signature_b64url>
#   • email_hash16    — 16 hex chars, reverse-lookup в БД бота
#   • tg_user_id      — 5-15 цифр, plain Telegram user_id клиента
#   • signature_b64url — Ed25519 подпись от "<email_hash>|<tg_user_id>"
#
# Привязка к tg_user_id защищает от расшаривания: чтобы другом воспользоваться
# чужим токеном, ему нужно подменить свой TG user_id. Это невозможно —
# TG user_id это аккаунт Telegram, его не подделать.

# Публичный ключ бота (Ed25519). Приватный ключ только у @AITeamVIPBot.
# Этот публичный можно видеть всем — это часть дизайна. Подписывать им
# нельзя, только проверять подпись.
VIP_PUBLIC_KEY_PEM=$(cat <<'EOF'
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAQIjPPB5LB1R3outrY1HMaVRVUB2tkDhHtpC8LLJ+8rA=
-----END PUBLIC KEY-----
EOF
)

# Endpoint для fire-and-forget логирования активации (анти-шаринг алерт).
# Перекрывается через env, чтобы не ломать локальные тесты.
VIP_ACTIVATION_ENDPOINT="${VIP_ACTIVATION_ENDPOINT:-https://aiteam-vip.openclaw.ai/log/activation}"

# ─── Извлечь ожидаемый tg_user_id из токена (без проверки подписи) ──
# Нужно чтобы установщик мог показать пользователю «этот токен выдан
# для TG ID X» до того как спросит фактический ID.
vip_token_get_expected_tg() {
  local token="$1"
  if [[ "$token" =~ ^VIP-[A-F0-9]{16}-([0-9]{5,15})-[A-Za-z0-9_-]{80,100}$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# ─── Извлечь email_hash16 из токена (для fire-and-forget логирования) ─
vip_token_get_hash() {
  local token="$1"
  if [[ "$token" =~ ^VIP-([A-F0-9]{16})-[0-9]{5,15}-[A-Za-z0-9_-]{80,100}$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# ─── Главная функция валидации ─────────────────────────────────
#
# verify_vip_token <token> <expected_tg_id>
#
# Exit codes (разные — чтобы установщик мог показать точное сообщение):
#   0  — OK
#   2  — формат токена неверный (не v2-структура)
#   3  — tg_user_id в токене не совпадает с тем что у машины (!!! шаринг !!!)
#   4  — ошибка декодирования base64 signature
#   5  — подпись недействительна (токен подделан или порчен)
verify_vip_token() {
  local token="$1"
  local machine_tg_id="$2"

  # Формат
  if [[ ! "$token" =~ ^VIP-[A-F0-9]{16}-[0-9]{5,15}-[A-Za-z0-9_-]{80,100}$ ]]; then
    return 2
  fi

  local hash_part tg_part sig_part
  hash_part=$(printf '%s' "$token" | cut -d'-' -f2)
  tg_part=$(printf '%s' "$token" | cut -d'-' -f3)
  sig_part=$(printf '%s' "$token" | cut -d'-' -f4-)

  # TG-binding: tg_id в токене должен совпасть с TG ID фактической машины
  # ВАЖНО: это проверяется ДО подписи — чтобы быстро отсечь шаринг без
  # затрат на openssl. Подделать plain tg_part невозможно: если кто-то его
  # поменяет руками, подпись станет невалидной (проверится ниже).
  if [[ -n "$machine_tg_id" && "$tg_part" != "$machine_tg_id" ]]; then
    return 3
  fi

  local tmpdir
  tmpdir=$(mktemp -d -t vipverify.XXXXXX)

  # payload для проверки подписи — ровно то, что подписывал бот
  printf '%s|%s' "$hash_part" "$tg_part" > "$tmpdir/payload.txt"
  printf '%s\n' "$VIP_PUBLIC_KEY_PEM" > "$tmpdir/public.pem"

  # Декодирование base64url подписи
  if ! python3 - "$sig_part" "$tmpdir/signature.bin" <<'PY'
import base64, sys
sig, out = sys.argv[1], sys.argv[2]
padded = sig + '=' * (-len(sig) % 4)
with open(out, 'wb') as fh:
    fh.write(base64.urlsafe_b64decode(padded.encode()))
PY
  then
    rm -rf "$tmpdir"
    return 4
  fi

  # Ed25519 verify через openssl
  if openssl pkeyutl -verify -pubin -inkey "$tmpdir/public.pem" \
       -rawin -in "$tmpdir/payload.txt" -sigfile "$tmpdir/signature.bin" \
       >/dev/null 2>&1; then
    rm -rf "$tmpdir"
    return 0
  fi

  rm -rf "$tmpdir"
  return 5
}

# ─── Автодетект TG ID клиента из первого установщика ───────────
#
# Первый установщик (openclaw-factory → demo-install.sh) при настройке
# Telegram-канала в R4 спрашивает у клиента TG user_id и записывает в
# allowFrom внутри ~/.openclaw/openclaw.json. Читаем оттуда — клиенту
# не нужно вводить ID заново.
#
# Возвращает: TG ID в stdout, либо пусто если не нашли.
vip_detect_owner_tg_id() {
  local cfg="$HOME/.openclaw/openclaw.json"
  [[ ! -f "$cfg" ]] && return 0

  # Вариант 1: "allowFrom": ["975494053"]
  local tg_id
  tg_id=$(grep -oE '"allowFrom"[[:space:]]*:[[:space:]]*\[[[:space:]]*"[0-9]+"' "$cfg" \
            | grep -oE '"[0-9]+"' | head -1 | tr -d '"')

  # Вариант 2: "allowlistAllowFrom": ["975494053"] (старое имя поля)
  if [[ -z "$tg_id" ]]; then
    tg_id=$(grep -oE '"allowlistAllowFrom"[[:space:]]*:[[:space:]]*\[[[:space:]]*"[0-9]+"' "$cfg" \
              | grep -oE '"[0-9]+"' | head -1 | tr -d '"')
  fi

  printf '%s' "${tg_id:-}"
}

# ─── Fire-and-forget логирование активации боту ───────────────
#
# Вызывается после успешной верификации, в фоне с таймаутом 3 сек.
# Если бот лежит / интернета нет — молча пропускаем, установка продолжается.
# Бот при получении проверяет: >3 уникальных IP за 7 дней = аномалия,
# шлёт админу алерт.
vip_log_activation() {
  local token_hash="$1"
  local tg_id="$2"
  local os_info
  os_info=$(uname -sm 2>/dev/null | tr ' ' '-' | tr '[:upper:]' '[:lower:]' || echo "unknown")

  # В фоне, со своим таймаутом — не тормозит основной флоу
  (
    curl -fsSL --max-time 3 \
      -X POST "$VIP_ACTIVATION_ENDPOINT" \
      -H 'Content-Type: application/json' \
      -d "{\"token_hash\":\"${token_hash}\",\"tg_id\":${tg_id},\"installer_version\":\"${INSTALLER_VERSION:-unknown}\",\"client_os\":\"${os_info}\"}" \
      >/dev/null 2>&1
  ) &
}
