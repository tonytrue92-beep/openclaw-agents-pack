#!/usr/bin/env bash
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/openclaw-agents-token-rotation.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT

fail() {
  printf 'TOKEN ROTATION TEST FAILED: %s\n' "$*" >&2
  exit 1
}

# shellcheck disable=SC1091
source "$ROOT/scripts/lib/vip.sh"

private_key="$TEST_ROOT/private.pem"
public_key="$TEST_ROOT/public.pem"
openssl genpkey -algorithm ED25519 -out "$private_key" >/dev/null 2>&1 ||
  fail 'could not create an isolated Ed25519 keypair'
openssl pkey -in "$private_key" -pubout -out "$public_key" >/dev/null 2>&1 ||
  fail 'could not export the isolated public key'
VIP_PUBLIC_KEY_PEM=$(<"$public_key")

sign_b64url() {
  local payload=$1 signature_file
  signature_file="$TEST_ROOT/signature.bin"
  printf '%s' "$payload" > "$TEST_ROOT/payload.txt"
  openssl pkeyutl -sign -rawin -inkey "$private_key" \
    -in "$TEST_ROOT/payload.txt" -out "$signature_file" >/dev/null 2>&1 || return 1
  base64 < "$signature_file" | tr '+/' '-_' | tr -d '=\n'
}

HASH='0123456789ABCDEF'
OWNER='123456789'
NONCE="ABCDEF0123456789ABCDEF01"
signature=$(sign_b64url "OC5|STD|${HASH}|${OWNER}|${NONCE}") || fail 'could not sign OC5 fixture'
valid="OC5-STD-${HASH}-${OWNER}-${NONCE}-${signature}"

# Cryptographic behavior is tested here; gateway behavior is covered by the
# dedicated HTTP service tests and must not make this offline unit test networked.
vip_verify_token_online() { return 0; }

[[ "$(vip_token_version "$valid")" == oc5 ]] || fail 'OC5 token format was not recognized'
[[ "$(course_token_get_tier "$valid")" == STD ]] || fail 'OC5 tier was not extracted'
[[ "$(vip_token_get_expected_tg "$valid")" == "$OWNER" ]] || fail 'OC5 owner was not extracted'
[[ "$(vip_token_get_hash "$valid")" == "$HASH" ]] || fail 'OC5 token identifier was not extracted'

verify_vip_token "$valid" "$OWNER" || fail 'matching OC5 token was rejected'
if verify_vip_token "$valid" 987654321; then
  fail 'OC5 token was accepted for another Telegram owner'
else
  [[ $? -eq 3 ]] || fail 'owner mismatch did not return the anti-sharing status'
fi

legacy_signature=$(sign_b64url "STD|${HASH}|${OWNER}") || fail 'could not sign legacy fixture'
legacy="STD-${HASH}-${OWNER}-${legacy_signature}"
if verify_vip_token "$legacy" "$OWNER"; then
  fail 'legacy v3 token was accepted after the revocation cutover'
else
  [[ $? -eq 2 ]] || fail 'legacy v3 token did not report a revoked format'
fi

printf 'agents-pack token rotation cases passed\n'
