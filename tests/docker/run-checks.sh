#!/usr/bin/env bash
# Docker smoke: что проверяем в чистом контейнере без OpenClaw.
# Ожидаемое время: 15-30 секунд.

set -euo pipefail

cd /opt/openclaw-agents-pack

pass() { echo "✓ $1"; }
fail() { echo "✗ $1"; exit 1; }

echo "=== Docker smoke: $(uname -s) — $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"' || echo 'unknown') ==="
echo "    Node: $(node -v), bash: $(bash --version | head -1)"
echo ""

# 1. bash -n всех скриптов
for f in scripts/*.sh scripts/lib/*.sh; do
  bash -n "$f" || fail "bash -n failed on $f"
done
pass "bash -n across all scripts"

# 2. --version
ver=$(bash scripts/install-agents.sh --version 2>&1)
echo "$ver" | grep -qE "OpenClaw Agents Pack v[0-9]{4}\.[0-9]{2}\.[0-9]{2}" || fail "--version output unexpected: $ver"
pass "--version: $ver"

# 3. --help
bash scripts/install-agents.sh --help >/dev/null 2>&1 || fail "--help crashed"
pass "--help runs cleanly"

# 4. smoke-test helper-функций
bash scripts/smoke-test.sh > /tmp/smoke.log 2>&1 || {
  echo "--- smoke-test output ---"
  cat /tmp/smoke.log
  fail "smoke-test.sh failed"
}
pass "smoke-test.sh passed"

# 5. security-audit
bash scripts/security-audit.sh > /tmp/sec.log 2>&1 || {
  echo "--- security-audit output ---"
  cat /tmp/sec.log
  fail "security-audit.sh failed (possibly personal data leaked into templates)"
}
pass "security-audit.sh passed (templates clean)"

# 6. --diagnose-only должен корректно сказать «OpenClaw не установлен»
#    и НЕ упасть с синтаксической ошибкой.
diag_output=$(bash scripts/install-agents.sh --diagnose-only 2>&1 || true)
if echo "$diag_output" | grep -q "LIVE ДИАГНОСТИКА"; then
  pass "--diagnose-only runs и правильно детектит отсутствие openclaw"
else
  echo "--- diagnose output ---"
  echo "$diag_output" | head -30
  fail "--diagnose-only не напечатал ожидаемый заголовок"
fi

# 7. Шаблоны на месте.
#
#    Раскладка после wave 6:
#      • 6 агентов × 4 базовых md (IDENTITY/AGENTS/MEMORY/USER) = 24
#      • 3 VIP-агента × 2 расширения (SOUL/LEARNING)            =  6
#      • 3 VIP-агента × 2 скилла (SKILL.md каждый)              =  6
#      • 1 manifest LICENSE-skills.md                            =  1
#      • ИТОГО                                                   = 37
#
#    Исторические значения (12 = pre-wave5, 24 = pre-wave6) оставляем
#    валидными чтобы CI не падал на старых релизных ветках.
template_count=$(find templates -name "*.md" | wc -l | tr -d ' ')
case "$template_count" in
  12) pass "templates/ содержит 12 md-файлов (Standard pre-wave5)" ;;
  24) pass "templates/ содержит 24 md-файла (VIP pre-wave6)" ;;
  37) pass "templates/ содержит 37 md-файлов (VIP + SOUL/LEARNING/skills — wave 6)" ;;
  *)  fail "templates/ содержит $template_count файлов (ожидается 12/24/37 — проверь что ничего не забыл/не потерялось)" ;;
esac

echo ""
echo "=== Docker smoke — всё зелёное ==="
