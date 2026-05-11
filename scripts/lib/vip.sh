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
# stdout: "v3-vip" | "v3-std" | "v2" | "v1" | "unknown"
#
# wave 12: добавлен v3 формат с явным tier-префиксом для course-token.
# v3 синтаксис: <TIER>-<email_hash16>-<tg_user_id>-<signature>
#   где TIER ∈ {VIP, STD, SUB}
# Payload подписывается: "<TIER>|<email_hash16>|<tg_user_id>"
#
# v2 (легаси VIP-токены) продолжают работать как раньше.
#
# wave 16: добавлен SUB-tier для подписчиков (только базовая установка
# OpenClaw + main-агент). SUB-токены имеют ту же форму что VIP/STD v3.
vip_token_version() {
  local token="$1"
  if [[ "$token" =~ ^VIP-[A-F0-9]{16}-[0-9]{5,15}-[A-Za-z0-9_-]{80,100}$ ]]; then
    # v2 и v3-vip имеют одинаковую форму. Различаем по payload (см. _verify_v3).
    # Чтобы не ломать backward-compat, считаем форму v2 — _verify_v2 fallback'ом
    # попробует v3-vip если v2 не пройдёт.
    printf 'v2'
  elif [[ "$token" =~ ^STD-[A-F0-9]{16}-[0-9]{5,15}-[A-Za-z0-9_-]{80,100}$ ]]; then
    printf 'v3-std'
  elif [[ "$token" =~ ^SUB-[A-F0-9]{16}-[0-9]{5,15}-[A-Za-z0-9_-]{80,100}$ ]]; then
    printf 'v3-sub'
  elif [[ "$token" =~ ^VIP-[A-F0-9]{16}-[A-Za-z0-9_-]{80,100}$ ]]; then
    printf 'v1'
  else
    printf 'unknown'
  fi
}

# ─── Извлечь ожидаемый tg_user_id из v2/v3-токена ──────────────
# Возвращает пусто для v1-токена (там нет TG).
vip_token_get_expected_tg() {
  local token="$1"
  if [[ "$token" =~ ^(VIP|STD|SUB)-[A-F0-9]{16}-([0-9]{5,15})-[A-Za-z0-9_-]{80,100}$ ]]; then
    printf '%s' "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

# ─── Извлечь email_hash16 (для fire-and-forget логирования) ─────
vip_token_get_hash() {
  local token="$1"
  # v2 / v3: <TIER>-<hash>-<tg>-<sig>
  if [[ "$token" =~ ^(VIP|STD|SUB)-([A-F0-9]{16})-[0-9]{5,15}-[A-Za-z0-9_-]{80,100}$ ]]; then
    printf '%s' "${BASH_REMATCH[2]}"
    return 0
  fi
  # v1: VIP-<hash>-<sig>
  if [[ "$token" =~ ^VIP-([A-F0-9]{16})-[A-Za-z0-9_-]{80,100}$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# ─── Извлечь tier из токена ─────────────────────────────────────
# stdout: "VIP" | "STD" | "SUB" | "" (пусто для v1)
# Используется установщиком чтобы понять что у клиента:
#   • VIP — 6 агентов
#   • STD — Standard 3 агента
#   • SUB — подписка, только base OpenClaw+main (через первый установщик)
course_token_get_tier() {
  local token="$1"
  if [[ "$token" =~ ^(VIP|STD|SUB)- ]]; then
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
      # wave 12: v2-форма используется и для legacy VIP-токенов (payload "<hash>|<tg>"),
      # и для v3-VIP (payload "VIP|<hash>|<tg>"). Сначала пробуем v3-VIP, если
      # подпись не сходится — fallback на legacy v2. Это backward-compat.
      _verify_v3 "$token" "$machine_tg_id" "VIP"
      local rc=$?
      if [[ $rc -eq 0 ]]; then
        return 0
      fi
      # Если v3 fail — возможно это старый v2-токен; пробуем legacy
      _verify_v2 "$token" "$machine_tg_id"
      return $?
      ;;
    v3-std)
      _verify_v3 "$token" "$machine_tg_id" "STD"
      return $?
      ;;
    v3-sub)
      # wave 16: SUB-tier (subscription). Та же подпись и тот же payload-
      # формат "<TIER>|<hash>|<tg>", только TIER=SUB. Установщик распознаёт
      # tier=SUB и завершается с info «дополнительные агенты только для
      # Standard/VIP» — без агентов не ставит (это работа первого
      # установщика factory).
      _verify_v3 "$token" "$machine_tg_id" "SUB"
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

# ─── v2 проверка (legacy VIP) ──────────────────────────────────
_verify_v2() {
  local token="$1"
  local machine_tg_id="$2"

  local hash_part tg_part sig_part
  hash_part=$(printf '%s' "$token" | cut -d'-' -f2)
  tg_part=$(printf '%s' "$token" | cut -d'-' -f3)
  sig_part=$(printf '%s' "$token" | cut -d'-' -f4-)

  if [[ -n "$machine_tg_id" && "$tg_part" != "$machine_tg_id" ]]; then
    return 3
  fi

  _verify_ed25519_signature "${hash_part}|${tg_part}" "$sig_part"
  local rc=$?
  [[ $rc -eq 4 ]] && return 4
  [[ $rc -eq 0 ]] && return 0
  return 5
}

# ─── v3 проверка (course-token, wave 12) ───────────────────────
#
# v3-payload формат: "<TIER>|<email_hash16>|<tg_user_id>"
# Где TIER явно подписан в payload — нельзя «переделать» STD-токен в VIP
# подменой префикса в строке.
#
# Args:
#   $1 = token (VIP-... или STD-...)
#   $2 = machine_tg_id (для anti-share проверки)
#   $3 = expected_tier ("VIP" или "STD") — caller знает какой prefix он видел
_verify_v3() {
  local token="$1"
  local machine_tg_id="$2"
  local expected_tier="$3"

  local prefix hash_part tg_part sig_part
  prefix=$(printf '%s' "$token" | cut -d'-' -f1)
  hash_part=$(printf '%s' "$token" | cut -d'-' -f2)
  tg_part=$(printf '%s' "$token" | cut -d'-' -f3)
  sig_part=$(printf '%s' "$token" | cut -d'-' -f4-)

  # Префикс должен совпасть с expected (защита от чтения payload c
  # подменой prefix в строке)
  if [[ "$prefix" != "$expected_tier" ]]; then
    return 5
  fi

  if [[ -n "$machine_tg_id" && "$tg_part" != "$machine_tg_id" ]]; then
    return 3
  fi

  # v3 payload включает tier явно
  _verify_ed25519_signature "${expected_tier}|${hash_part}|${tg_part}" "$sig_part"
  local rc=$?
  [[ $rc -eq 4 ]] && return 4
  [[ $rc -eq 0 ]] && return 0
  return 5
}

# ─── v1 проверка (легаси) ──────────────────────────────────────
# Возвращает 0 если подпись валидна, 1 — не валидна.
_verify_v1() {
  local token="$1"

  local hash_part sig_part
  hash_part=$(printf '%s' "$token" | cut -d'-' -f2)
  sig_part=$(printf '%s' "$token" | cut -d'-' -f3-)

  _verify_ed25519_signature "$hash_part" "$sig_part" >/dev/null 2>&1
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
