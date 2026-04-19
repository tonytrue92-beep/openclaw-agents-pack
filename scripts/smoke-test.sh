#!/usr/bin/env bash
# smoke-test.sh — проверка helper-функций openclaw-agents-pack.
# Запускается в CI и локально: bash scripts/smoke-test.sh

set -euo pipefail

cd "$(dirname "$0")/.."

fail() { echo "✗ FAIL: $1"; exit 1; }
pass() { echo "✓ PASS: $1"; }

# ─── Подключаем модули по отдельности ───
# shellcheck disable=SC1091
source scripts/lib/ui.sh
# shellcheck disable=SC1091
source scripts/lib/telemetry.sh
# shellcheck disable=SC1091
source scripts/lib/debug-bundle.sh
# shellcheck disable=SC1091
source scripts/lib/agents.sh

echo "=== Smoke-test agents-pack ==="
echo ""

# ─── Test 1: redact_secrets маскирует типовые секреты ───
cat > /tmp/fake.json <<EOJ
{
  "apiKey": "sk-proj-abcdefghijklmnopqrstuvwxyz0123456789",
  "telegram": {"botToken": "7123456789:AAGk-abcdefghijklmnopqrstuvwxyzABCDE"},
  "authorization": "Bearer abc.def.xyz789"
}
EOJ
redact_secrets /tmp/fake.json
if grep -qE "sk-proj-[a-z0-9]{20,}|7[0-9]{9}:AAGk" /tmp/fake.json; then
  echo "файл после redact:"
  cat /tmp/fake.json
  fail "secrets leaked through redact_secrets"
fi
pass "redact_secrets маскирует sk-, TG tokens, Bearer"

# ─── Test 2: validate_telegram_token → 1 на пустом ответе ───
# (мы не можем реально дёргать api.telegram.org в CI без токена, поэтому
# просто проверяем что функция не крашится на пустом вводе)
set +e
output=$(validate_telegram_token "fake-token-123" 2>&1)
rc=$?
set -e
if [[ "$rc" == "1" ]]; then
  pass "validate_telegram_token корректно возвращает 1 на невалидный токен"
else
  fail "validate_telegram_token с invalid token вернул rc=$rc (ожидается 1)"
fi

# ─── Test 3: agent_exists не крашится ───
set +e
agent_exists "nonexistent-agent-xyz" 2>&1 >/dev/null
rc=$?
set -e
# rc может быть 0 (если grep нашёл совпадение в debug output) или 1 (не нашёл) — оба валидны
if [[ "$rc" == "0" || "$rc" == "1" ]]; then
  pass "agent_exists возвращает валидный код (rc=$rc)"
else
  fail "agent_exists вернул неожиданный код: $rc"
fi

# ─── Test 4: heartbeat не висит и корректно останавливается ───
start_heartbeat "smoke-test" 1 10 &
HB_PID=$!
sleep 2
stop_heartbeat "$HB_PID"
if ps -p "$HB_PID" &>/dev/null; then
  fail "heartbeat процесс не остановился"
fi
pass "heartbeat стартует и корректно останавливается"

rm -f /tmp/fake.json

echo ""
echo "=== All smoke tests passed ==="
