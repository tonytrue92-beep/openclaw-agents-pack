#!/usr/bin/env bash
# vip.sh — локальная проверка VIP-токена для установщика.
# Без сетевых запросов: бот может лежать, а уже выданные токены продолжат работать.

VIP_PUBLIC_KEY_PEM=$(cat <<'EOF'
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsb1HPv/Pw4U+c1MOr8Ci
Z6+PIdUmRdJLn0fpl53TWgagAh2ibJqLsAIxKHjPlUnU/FLXF0ylzYKqq4ZObw7a
xbK6nTbbnphHueiWr15/URUyUbKBfz/nryyp3q90a6y/wBXg9FWJWZo/F/n+5YM3
j9KTMFS/JGSZfY4vzFuJuA6rrFt4ZwFyR8/tP8DUtg3cVJVQhtC4zE2JkULONVJx
Gu4y+PXNrnaOIwOoIIYemEO1ksHs8QuOYUs/DakC0kqXtpTR1SEKdIPY+hN47e64
itpd+46P0Gg+bUJA+lEz8lo+o/nhVdDzgnxtC/uRB0/7tiJu1FiAzePmPpZThIno
pQIDAQAB
-----END PUBLIC KEY-----
EOF
)

verify_vip_token() {
  local token="$1"
  [[ "$token" =~ ^VIP-[A-F0-9]{16}-[A-Za-z0-9_-]{80,}$ ]] || return 1

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

  if openssl dgst -sha256 -verify "$tmpdir/public.pem" -signature "$tmpdir/signature.bin" "$tmpdir/payload.txt" >/dev/null 2>&1; then
    rm -rf "$tmpdir"
    return 0
  fi

  rm -rf "$tmpdir"
  return 1
}
