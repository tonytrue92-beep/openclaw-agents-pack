#!/usr/bin/env bash
# vip.sh — локальная проверка VIP-токена для установщика.
# Без сетевых запросов при валидации: бот может лежать, а уже выданные
# токены продолжат работать.
#
# ─── Поддерживаем ДВА формата токена (backward-compat) ──────────
#
# v2 (новый, с TG-binding — анти-шаринг):
#   VIP-<email_hash16>-<tg_user_id>-<signature_b64url>
#   Подписывается: "<email_hash16>|<tg_user_id>"
#   Клиент не может отдать токен другу — у друга свой TG ID, проверка упадёт.
#
# v1 (легаси, пока бот технаря не обновлён):
#   VIP-<email_hash16>-<signature_b64url>
#   Подписывается: "<email_hash16>"
#   TG-binding отсутствует. Будет работать, но клиент получит warning
#   «защита от шаринга недоступна, обновитесь до v2».
#
# Когда бот технаря переключится на v2 — новые токены автоматически
# начнут работать с полной защитой. Старые v1-токены никогда не
# выпустятся, а уже выданные перестанут быть актуальны по другим
# причинам (клиент переставит = получит свежий v2).

# Публичный ключ бота (Ed25519). Приватный ключ — у @AITeamVIPBot на VPS.
VIP_PUBLIC_KEY_PEM=$(cat <<'EOF'
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAQIjPPB5LB1R3outrY1HMaVRVUB2tkDhHtpC8LLJ+8rA=
-----END PUBLIC KEY-----
EOF
)

# Endpoint для fire-and-forget логирования активации (анти-шаринг алерт)
VIP_ACTIVATION_ENDPOINT="${VIP_ACTIVATION_ENDPOINT:-https://aiteam-vip.openclaw.ai/log/activation}"

# ─── Определить версию токена по его форме ─────────────────────
# stdout: "v2" | "v1" | "unknown"
vip_token_version() {
  local token="$1"
  if [[ "$token" =~ ^VIP-[A-F0-9]{16}-[0-9]{5,15}-[A-Za-z0-9_-]{80,100}$ ]]; then
    printf 'v2'
  elif [[ "$token" =~ ^VIP-[A-F0-9]{16}-[A-Za-z0-9_-]{80,100}$ ]]; then
    printf 'v1'
  else
    printf 'unknown'
  fi
}

# ─── Извлечь ожидаемый tg_user_id из v2-токена ──────────────────
# Возвращает пусто для v1-токена (там нет TG).
vip_token_get_expected_tg() {
  local token="$1"
  if [[ "$token" =~ ^VIP-[A-F0-9]{16}-([0-9]{5,15})-[A-Za-z0-9_-]{80,100}$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# ─── Извлечь email_hash16 (для fire-and-forget логирования) ─────
vip_token_get_hash() {
  local token="$1"
  # v2: VIP-<hash>-<tg>-<sig>
  if [[ "$token" =~ ^VIP-([A-F0-9]{16})-[0-9]{5,15}-[A-Za-z0-9_-]{80,100}$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  # v1: VIP-<hash>-<sig>
  if [[ "$token" =~ ^VIP-([A-F0-9]{16})-[A-Za-z0-9_-]{80,100}$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# ─── Главная функция валидации ─────────────────────────────────
#
# verify_vip_token <token> <machine_tg_id>
#
# Exit codes (разные — чтобы установщик мог показать точное сообщение):
#   0  — OK
#   2  — формат токена не распознан (ни v1, ни v2)
#   3  — v2: tg_user_id в токене не совпадает с tg_id машины (шаринг)
#   4  — ошибка декодирования base64 signature
#   5  — подпись недействительна (токен повреждён или подделан)
#   6  — v1-токен: подпись валидна, но он без TG-binding
#        (установщик может показать warning и продолжить)
verify_vip_token() {
  local token="$1"
  local machine_tg_id="$2"

  local version
  version=$(vip_token_version "$token")

  case "$version" in
    v2)
      _verify_v2 "$token" "$machine_tg_id"
      return $?
      ;;
    v1)
      # Проверяем подпись, но возвращаем специальный код — установщик
      # должен показать warning «нет TG-binding, рекомендуем обновить».
      if _verify_v1 "$token"; then
        return 6
      else
        return 5
      fi
      ;;
    *)
      return 2
      ;;
  esac
}

# ─── v2 проверка ───────────────────────────────────────────────
_verify_v2() {
  local token="$1"
  local machine_tg_id="$2"

  local hash_part tg_part sig_part
  hash_part=$(printf '%s' "$token" | cut -d'-' -f2)
  tg_part=$(printf '%s' "$token" | cut -d'-' -f3)
  sig_part=$(printf '%s' "$token" | cut -d'-' -f4-)

  # TG-binding проверка (быстро, без openssl)
  if [[ -n "$machine_tg_id" && "$tg_part" != "$machine_tg_id" ]]; then
    return 3
  fi

  local tmpdir
  tmpdir=$(mktemp -d -t vipverify.XXXXXX)

  printf '%s|%s' "$hash_part" "$tg_part" > "$tmpdir/payload.txt"
  printf '%s\n' "$VIP_PUBLIC_KEY_PEM" > "$tmpdir/public.pem"

  if ! _decode_b64url "$sig_part" "$tmpdir/signature.bin"; then
    rm -rf "$tmpdir"
    return 4
  fi

  if openssl pkeyutl -verify -pubin -inkey "$tmpdir/public.pem" \
       -rawin -in "$tmpdir/payload.txt" -sigfile "$tmpdir/signature.bin" \
       >/dev/null 2>&1; then
    rm -rf "$tmpdir"
    return 0
  fi

  rm -rf "$tmpdir"
  return 5
}

# ─── v1 проверка (легаси) ──────────────────────────────────────
# Возвращает 0 если подпись валидна, 1 — не валидна.
_verify_v1() {
  local token="$1"

  local hash_part sig_part
  hash_part=$(printf '%s' "$token" | cut -d'-' -f2)
  sig_part=$(printf '%s' "$token" | cut -d'-' -f3-)

  local tmpdir
  tmpdir=$(mktemp -d -t vipverify.XXXXXX)

  # v1 подпись от чистого hash_part
  printf '%s' "$hash_part" > "$tmpdir/payload.txt"
  printf '%s\n' "$VIP_PUBLIC_KEY_PEM" > "$tmpdir/public.pem"

  if ! _decode_b64url "$sig_part" "$tmpdir/signature.bin"; then
    rm -rf "$tmpdir"
    return 1
  fi

  if openssl pkeyutl -verify -pubin -inkey "$tmpdir/public.pem" \
       -rawin -in "$tmpdir/payload.txt" -sigfile "$tmpdir/signature.bin" \
       >/dev/null 2>&1; then
    rm -rf "$tmpdir"
    return 0
  fi

  rm -rf "$tmpdir"
  return 1
}

# ─── Утилита: декодирование base64url в бинарный файл ──────────
_decode_b64url() {
  local sig="$1"
  local out="$2"
  python3 - "$sig" "$out" <<'PY' 2>/dev/null
import base64, sys
sig, out = sys.argv[1], sys.argv[2]
padded = sig + '=' * (-len(sig) % 4)
with open(out, 'wb') as fh:
    fh.write(base64.urlsafe_b64decode(padded.encode()))
PY
}

# ─── Автодетект TG ID клиента из первого установщика ───────────
vip_detect_owner_tg_id() {
  local cfg="$HOME/.openclaw/openclaw.json"
  [[ ! -f "$cfg" ]] && return 0

  local tg_id
  tg_id=$(grep -oE '"allowFrom"[[:space:]]*:[[:space:]]*\[[[:space:]]*"[0-9]+"' "$cfg" \
            | grep -oE '"[0-9]+"' | head -1 | tr -d '"')

  if [[ -z "$tg_id" ]]; then
    tg_id=$(grep -oE '"allowlistAllowFrom"[[:space:]]*:[[:space:]]*\[[[:space:]]*"[0-9]+"' "$cfg" \
              | grep -oE '"[0-9]+"' | head -1 | tr -d '"')
  fi

  printf '%s' "${tg_id:-}"
}

# ─── Fire-and-forget логирование активации боту ───────────────
vip_log_activation() {
  local token_hash="$1"
  local tg_id="$2"
  local os_info
  os_info=$(uname -sm 2>/dev/null | tr ' ' '-' | tr '[:upper:]' '[:lower:]' || echo "unknown")

  (
    curl -fsSL --max-time 3 \
      -X POST "$VIP_ACTIVATION_ENDPOINT" \
      -H 'Content-Type: application/json' \
      -d "{\"token_hash\":\"${token_hash}\",\"tg_id\":${tg_id:-0},\"installer_version\":\"${INSTALLER_VERSION:-unknown}\",\"client_os\":\"${os_info}\"}" \
      >/dev/null 2>&1
  ) &
}
