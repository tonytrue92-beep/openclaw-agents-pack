#!/usr/bin/env bash
# vip.sh — локальная проверка VIP-токена для установщика.
# Без сетевых запросов: бот может лежать, а уже выданные токены продолжат работать.

VIP_PUBLIC_KEY_PEM=$(cat <<'EOF'
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAQIjPPB5LB1R3outrY1HMaVRVUB2tkDhHtpC8LLJ+8rA=
-----END PUBLIC KEY-----
EOF
)

verify_vip_token() {
  local token="$1"
  [[ "$token" =~ ^VIP-[A-F0-9]{16}-[A-Za-z0-9_-]{80,100}$ ]] || return 1

  local payload signature tmpdir
  payload=$(printf '%s' "$token" | cut -d'-' -f2)
  signature=$(printf '%s' "$token" | cut -d'-' -f3-)
  tmpdir=$(mktemp -d -t vipverify.XXXXXX)

  printf '%s' "$payload" > "$tmpdir/payload.txt"
  printf '%s
' "$VIP_PUBLIC_KEY_PEM" > "$tmpdir/public.pem"

  if ! python3 - "$signature" "$tmpdir/signature.bin" <<'PY'
import base64
import sys

sig = sys.argv[1]
out = sys.argv[2]
padded = sig + '=' * (-len(sig) % 4)
with open(out, 'wb') as fh:
    fh.write(base64.urlsafe_b64decode(padded.encode()))
PY
  then
    rm -rf "$tmpdir"
    return 1
  fi

  if openssl pkeyutl -verify -pubin -inkey "$tmpdir/public.pem" -rawin -in "$tmpdir/payload.txt" -sigfile "$tmpdir/signature.bin" >/dev/null 2>&1; then
    rm -rf "$tmpdir"
    return 0
  fi

  rm -rf "$tmpdir"
  return 1
}
