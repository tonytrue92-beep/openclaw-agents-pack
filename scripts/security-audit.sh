#!/usr/bin/env bash
# security-audit.sh — статические проверки безопасности для agent-pack.
#
# Запускается в CI на каждый push. Шесть проверок:
#   1. Нет прямого echo секретных переменных
#   2. collect_debug_bundle не дампит env
#   3. unset после использования секретов
#   4. Нет валидных токенов в исходниках
#   5. redact_secrets применяется к копируемым файлам debug-bundle
#   6. **templates/ не содержат личных данных автора курса** (ключевая проверка)

set -euo pipefail

INSTALLER=scripts/install-agents.sh
LIBS=(scripts/lib/*.sh)

fail_count=0

fail() { echo "✗ FAIL: $1"; fail_count=$((fail_count + 1)); }
pass() { echo "✓ PASS: $1"; }

echo "=== Security audit: openclaw-agents-pack ==="
echo ""

# ─── Check 1: no direct echo of secret vars ───
echo "─── Check 1: direct echo of secret variables ───"
if grep -nE '(echo|printf).*\$\{?(BOT_TOKEN|API_KEY|AGENT_TOKEN|INSTALLER_TOKEN)[_A-Z]*\}?' "$INSTALLER" "${LIBS[@]}" 2>/dev/null; then
  fail "found echo/printf of raw secret variable"
else
  pass "no direct echo/printf of secret variables"
fi
echo ""

# ─── Check 2: no $(env) in debug-bundle ───
echo "─── Check 2: no raw env dump in collect_debug_bundle ───"
bundle_body=$(awk '/^collect_debug_bundle\(\)/,/^\}$/' scripts/lib/debug-bundle.sh)
bundle_code=$(echo "$bundle_body" | sed 's/^[[:space:]]*#.*$//')
if echo "$bundle_code" | grep -qE '(\$\(env\)|`env`|[^a-zA-Z_]env( |$|\|))'; then
  fail "collect_debug_bundle contains a raw env dump"
else
  pass "collect_debug_bundle does not dump env"
fi
echo ""

# ─── Check 3: токен бота очищается после использования ───
echo "─── Check 3: BOT_TOKEN_* unset после add_telegram_channel ───"
# Мы используем динамически-именованные переменные BOT_TOKEN_<agent>
# (не ассоциативный массив — bash 3.2 на macOS не умеет), и делаем
# `unset "BOT_TOKEN_$agent"` сразу после add_telegram_channel.
if grep -qE 'unset\s+"?BOT_TOKEN_\$agent"?' "$INSTALLER"; then
  pass "BOT_TOKEN_<agent> unset after use"
else
  fail "BOT_TOKEN_<agent> is not unset — memory leak risk"
fi
echo ""

# ─── Check 4: no real tokens committed ───
echo "─── Check 4: no real tokens committed ───"
leaks=$(grep -rnE '"sk-[A-Za-z0-9]{30,}"|["\x27]7[0-9]{9}:AA[A-Za-z0-9_-]{30,}["\x27]' \
  scripts/ templates/ 2>/dev/null \
  | grep -vE 'sk-(xxx|•|test|REDACTED|proj-abc)' \
  | grep -vE '7123456789:AA(Hk-xx|Gk-abc)' || true)
if [[ -n "$leaks" ]]; then
  fail "possible real token in source:"
  echo "$leaks"
else
  pass "no real tokens in scripts/templates"
fi
echo ""

# ─── Check 5: redact applied to bundle files ───
echo "─── Check 5: redact_secrets applied to bundle contents ───"
# Проверяем что (а) redact вызывается для openclaw-config.json и (б) внутри
# блока find(…bundle_path) на соседних строках есть вызов redact_secrets.
config_redacted=$(echo "$bundle_body" | grep -cE 'redact_secrets.*openclaw-config\.json' || true)
find_then_redact=$(echo "$bundle_body" | awk '
  /find "\$\{bundle_path\}"/ { inblock=1; next }
  inblock && /redact_secrets "\$f"/ { print "YES"; exit }
  inblock && /^\s*done\s*$/ { inblock=0 }
')
if [[ "$config_redacted" -ge 1 && "$find_then_redact" == "YES" ]]; then
  pass "redact_secrets applied to config + все файлы bundle"
else
  fail "redact_secrets не применяется к всем файлам bundle (config=$config_redacted, find=$find_then_redact)"
fi
echo ""

# ─── Check 6: templates/ без личных данных автора ───
echo "─── Check 6: templates/ не содержат личных данных автора курса ───"
# Покрывает (wave 6 расширение):
#   • Имя / email / TG handle автора курса
#   • TG user ID автора (975494053) + чужие chat_id из полных версий (1167075209)
#   • Бренд-маркеры оригинального факторинга (vip-factory, openclaw-factory,
#     TRUE AI AGENCY, СРАБОТАЛО, СВЯЗКИ)
#   • Пути файловой системы автора (/Users/<name>)
#   • Прошитые API-ключи с префиксами конкретных платформ (ntn_ / cpk_ / pat_FL)
#   • IG handle автора (instapol2136) — был в полных версиях TOOLS.md
forbidden=$(grep -rniE \
  'antonpolakov|@tonytruee|tonytrue92|975494053|1167075209|vip-factory\b|openclaw-factory\b|/Users/[a-z]+|Антон\s+Поляков|Tonytrue|serditov|instapol2136|TRUE AI AGENCY|СРАБОТАЛО|СВЯЗКИ|ntn_[A-Za-z0-9]{20,}|cpk_[A-Za-z0-9]{20,}|pat_FL[A-Za-z0-9]{20,}' \
  templates/ 2>/dev/null || true)
if [[ -n "$forbidden" ]]; then
  fail "templates/ содержат личные маркеры автора:"
  echo "$forbidden" | head -10
else
  pass "templates/ чистые от личных данных автора"
fi
echo ""

# ─── Summary ───
if [[ $fail_count -eq 0 ]]; then
  echo "=== Security audit passed ==="
  exit 0
else
  echo "=== Security audit FAILED: $fail_count issue(s) ==="
  exit 1
fi
