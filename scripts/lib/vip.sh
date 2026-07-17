#!/usr/bin/env bash
# vip.sh — локальная проверка VIP-токена для установщика.
# Без сетевых запросов при валидации: бот может лежать, а уже выданные
# токены продолжат работать.
#
# wave 11 P1: umask 077 для temp-файлов с PEM-ключом и сигнатурой
# во время Ed25519-проверки. На shared-VPS это защита от чтения
# чужими user'ами /tmp/vipverify.* пока проверка идёт.
umask 077

#
# ─── Единственный поддерживаемый формат: OC5 ────────────────────
#
#   OC5-<TIER>-<email_hash16>-<tg_user_id>-<nonce24>-<signature_b64url>
#
# TIER ∈ {VIP, STD, SUB, HRM}; подпись Ed25519 покрывает строку
# "OC5|<TIER>|<email_hash16>|<tg_user_id>|<nonce24>". Prefix version, exact
# Telegram owner and fresh nonce are cryptographically bound. Online status is
# mandatory: it enforces revocation and the seven-day credential lifetime.

# Публичный ключ бота (Ed25519). Приватный ключ — у @AITeamVIPBot на VPS.
VIP_PUBLIC_KEY_PEM=$(cat <<'EOF'
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAPbs+nSBSaxOGpTk+WrP71ufLO8PvZmBuIbWTzmbfO1g=
-----END PUBLIC KEY-----
EOF
)

# Endpoint аналитики установок (/activation на сервере технаря — Cloudflare
# не используем, решение 2026-06-10). ПУСТО = пинг выключен. Когда технарь
# поднимет эндпоинт (handoff/analytics-endpoint-reference/) — вписать сюда
# его URL вида https://<его-сервер>/activation
VIP_ACTIVATION_ENDPOINT="${VIP_ACTIVATION_ENDPOINT:-}"
VIP_TOKEN_STATUS_URL="https://api.tonytrue.pro/ip/verify"

# ─── Проверить форму единственной принятой версии ───────────────
# stdout: "oc5" | "unknown"
vip_token_version() {
  local token="$1"
  if [[ "$token" =~ ^OC5-(VIP|STD|SUB|HRM)-[A-F0-9]{16}-[0-9]{5,15}-[A-F0-9]{24}-[A-Za-z0-9_-]{80,100}$ ]]; then
    printf 'oc5'
  else
    printf 'unknown'
  fi
}

# ─── Извлечь подписанный tg_user_id из OC5-токена ───────────────
vip_token_get_expected_tg() {
  local token="$1"
  if [[ "$token" =~ ^OC5-(VIP|STD|SUB|HRM)-[A-F0-9]{16}-([0-9]{5,15})-[A-F0-9]{24}-[A-Za-z0-9_-]{80,100}$ ]]; then
    printf '%s' "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

# ─── Извлечь email_hash16 (для fire-and-forget логирования) ─────
vip_token_get_hash() {
  local token="$1"
  if [[ "$token" =~ ^OC5-(VIP|STD|SUB|HRM)-([A-F0-9]{16})-[0-9]{5,15}-[A-F0-9]{24}-[A-Za-z0-9_-]{80,100}$ ]]; then
    printf '%s' "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

# ─── Извлечь tier из токена ─────────────────────────────────────
# stdout: "VIP" | "STD" | "SUB" | "HRM" | ""
# Используется установщиком чтобы понять что у клиента:
#   • VIP — Pro: 6 агентов
#   • STD — Base: 3 агента
#   • SUB — OpenClaw: подписка, только base через первый установщик
#   • HRM — Hermes: super-agent (отдельный SKU), wave 25
course_token_get_tier() {
  local token="$1"
  if [[ "$token" =~ ^OC5-(VIP|STD|SUB|HRM)- ]]; then
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
#   2  — формат токена не распознан или токен отозванной версии
#   3  — tg_user_id в токене не совпадает с tg_id машины (шаринг)
#   4  — ошибка декодирования base64 signature
#   5  — подпись недействительна (токен повреждён или подделан)
#   6  — онлайн-проверка не пройдена (отзыв, истечение, недоступен сервис)
verify_vip_token() {
  local token="$1"
  local machine_tg_id="$2"

  local version
  version=$(vip_token_version "$token")

  case "$version" in
    oc5)
      _verify_oc5 "$token" "$machine_tg_id" || return $?
      vip_verify_token_online "$token"
      return $?
      ;;
    *)
      return 2
      ;;
  esac
}

# ─── Внутренняя проверка Ed25519 подписи ───────────────────────
# Сначала через Node crypto (стабильнее на разных системах), потом fallback на openssl.
_verify_ed25519_signature() {
  local payload="$1"
  local sig_part="$2"

  if command -v node >/dev/null 2>&1; then
    if VIP_PUBLIC_KEY_PEM="$VIP_PUBLIC_KEY_PEM" VIP_PAYLOAD="$payload" VIP_SIG_B64="$sig_part" node - <<'JS' >/dev/null 2>&1
const crypto = require('crypto');
try {
  const publicKey = crypto.createPublicKey(process.env.VIP_PUBLIC_KEY_PEM);
  const payload = Buffer.from(process.env.VIP_PAYLOAD || '', 'utf8');
  const signature = Buffer.from(process.env.VIP_SIG_B64 || '', 'base64url');
  const ok = crypto.verify(null, payload, publicKey, signature);
  process.exit(ok ? 0 : 1);
} catch {
  process.exit(1);
}
JS
    then
      return 0
    fi
  fi

  local tmpdir
  tmpdir=$(mktemp -d -t vipverify.XXXXXX)
  printf '%s' "$payload" > "$tmpdir/payload.txt"
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

# ─── OC5 verification ───────────────────────────────────────────
_verify_oc5() {
  local token="$1"
  local machine_tg_id="$2"

  local prefix hash_part tg_part nonce_part sig_part
  prefix=$(printf '%s' "$token" | cut -d'-' -f2)
  hash_part=$(printf '%s' "$token" | cut -d'-' -f3)
  tg_part=$(printf '%s' "$token" | cut -d'-' -f4)
  nonce_part=$(printf '%s' "$token" | cut -d'-' -f5)
  sig_part=$(printf '%s' "$token" | cut -d'-' -f6-)

  if [[ -n "$machine_tg_id" && "$tg_part" != "$machine_tg_id" ]]; then
    return 3
  fi

  _verify_ed25519_signature "OC5|${prefix}|${hash_part}|${tg_part}|${nonce_part}" "$sig_part"
  local rc=$?
  [[ $rc -eq 4 ]] && return 4
  [[ $rc -eq 0 ]] && return 0
  return 5
}

vip_verify_token_online() {
  local token="$1" response
  response=$(mktemp -t vip-token-status.XXXXXX) || return 6
  chmod 600 "$response" 2>/dev/null || true
  if curl -fsS --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 20 \
       -H "Authorization: Bearer ${token}" "$VIP_TOKEN_STATUS_URL" -o "$response" 2>/dev/null \
     && grep -qE '"ok"[[:space:]]*:[[:space:]]*true' "$response"; then
    rm -f "$response"
    return 0
  fi
  rm -f "$response"
  return 6
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

# ─── Fire-and-forget логирование активации в Worker аналитики ──
# Канон token_hash = sha256(ПОЛНОГО токена) — совпадает с тем, что бот шлёт в
# /issue (иначе склейка в D1 не сойдётся). Если endpoint не задан — no-op.
_oc_token_sha256() {
  if command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 256 | awk '{print $1}';
  elif command -v sha256sum >/dev/null 2>&1; then printf '%s' "$1" | sha256sum | awk '{print $1}'; fi
}
# Аргументы: <ПОЛНЫЙ_токен> <tg_id> [tier]
vip_log_activation() {
  local token="$1" tg_id="$2" tier="${3:-}"
  [[ -z "$VIP_ACTIVATION_ENDPOINT" ]] && return 0   # endpoint не настроен → пропуск
  local th os_info
  th=$(_oc_token_sha256 "$token"); [[ -z "$th" ]] && return 0
  os_info=$(uname -sm 2>/dev/null | tr ' ' '-' | tr '[:upper:]' '[:lower:]' || echo "unknown")
  (
    curl -fsSL --max-time 3 \
      -X POST "$VIP_ACTIVATION_ENDPOINT" \
      -H 'Content-Type: application/json' \
      -d "{\"token_hash\":\"${th}\",\"tg_id\":\"${tg_id:-}\",\"installer_version\":\"${INSTALLER_VERSION:-unknown}\",\"client_os\":\"${os_info}\",\"tier\":\"${tier}\",\"track\":\"paid\"}" \
      >/dev/null 2>&1
  ) &
}
