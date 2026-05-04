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
#     TRUE AI AGENCY)
#   • Пути файловой системы автора (/Users/<name>)
#   • Прошитые API-ключи с префиксами конкретных платформ (ntn_ / cpk_ / pat_FL)
#   • IG handle автора (instapol2136) — был в полных версиях TOOLS.md
#
# ПРИМЕЧАНИЕ: сознательно НЕ включаем в regex слова "сработало" и "связки"
# — это обычные русские слова (работает / комбинации), а -i даёт
# case-insensitive match и ловит легитимный контент в шаблонах.
# Брендовое название курса вычищается ревью на стадии коммита вручную.
forbidden=$(grep -rniE \
  'antonpolakov|@tonytruee|tonytrue92|975494053|1167075209|vip-factory\b|openclaw-factory\b|/Users/[a-z]+|Антон\s+Поляков|Tonytrue|serditov|instapol2136|TRUE AI AGENCY|ntn_[A-Za-z0-9]{20,}|cpk_[A-Za-z0-9]{20,}|pat_FL[A-Za-z0-9]{20,}' \
  templates/ 2>/dev/null || true)
if [[ -n "$forbidden" ]]; then
  fail "templates/ содержат личные маркеры автора:"
  echo "$forbidden" | head -10
else
  pass "templates/ чистые от личных данных автора"
fi
echo ""

# ─── Check 6b (wave 13): dmg-template/ без секретов и личных данных ──
# DMG-шаблоны — публичные .command файлы которые попадут к клиентам.
# В отличие от templates/ они **легитимно содержат**:
#   • Публичные GitHub URL'ы (tonytrue92-beep/openclaw-factory,
#     openclaw-agents-pack) — это путь к нашим репо, не утечка
#   • Ссылки на @AITeamVIPBot, @BotFather, @userinfobot — публичные боты
#
# Поэтому Check 6b строже только на:
#   • Реальные секреты (sk-, Telegram bot tokens)
#   • Личные данные автора (TG ID 975494053, email, имя)
#   • Прошитые API-prefix-ы (ntn_/cpk_/pat_FL)
#
# Если папки нет (репо клонирован без wave 13) — пропускаем.
echo "─── Check 6b (wave 13): dmg-template/ чистый от секретов ───"
if [[ -d dmg-template ]]; then
  # Real secrets + личные TG IDs (НЕ публичные GitHub URL'ы)
  forbidden_dmg=$(grep -rniE \
    'antonpolakov|@tonytruee\b|975494053|/Users/[a-z]+|Антон\s+Поляков|serditov|instapol2136|TRUE AI AGENCY|ntn_[A-Za-z0-9]{20,}|cpk_[A-Za-z0-9]{20,}|pat_FL[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{30,}' \
    dmg-template/ 2>/dev/null || true)
  # Telegram tokens (формат цифры:AA…) — никогда не в DMG-шаблонах
  forbidden_tg=$(grep -rnE '[0-9]{8,12}:AA[A-Za-z0-9_-]{30,}' \
    dmg-template/ 2>/dev/null \
    | grep -vE '7123456789' || true)

  combined="$forbidden_dmg"
  [[ -n "$forbidden_tg" ]] && combined="${combined}${combined:+$'\n'}${forbidden_tg}"

  if [[ -n "$combined" ]]; then
    fail "dmg-template/ содержит секреты или личные данные:"
    echo "$combined" | head -10
  else
    pass "dmg-template/ чистый от секретов и личных маркеров"
  fi
else
  pass "dmg-template/ отсутствует — проверка пропущена"
fi
echo ""

# ─── Check 7 (wave 12): docs/ не содержат личных TG ID / email ──
# Эта проверка отделена от check #6 чтобы не падать на легитимных
# упоминаниях имён в docs (например, "Антон Поляков" в README — это
# нормально). Тут точечно ловим:
#   • TG user ID Антона (975494053) — должен быть placeholder 123456789
#   • Чужие TG chat_id (1167075209) — должны быть в Markdown URL
#     рефералки, не как голое число
#   • API-ключи с конкретными префиксами (ntn_ / cpk_ / pat_FL) — никогда
#     не должны быть в docs
echo "─── Check 7 (wave 12): docs/ не содержат личных TG ID и API-ключей ───"
if [[ -d docs ]]; then
  # 975494053 — реальный TG ID Антона. В docs должен быть только 123456789
  # (стандартный placeholder).
  forbidden_docs=$(grep -rnE '\b975494053\b' docs/ 2>/dev/null || true)
  # API prefix ключи — никогда не должны попадать в публичные docs
  forbidden_keys=$(grep -rnE 'ntn_[A-Za-z0-9]{20,}|cpk_[A-Za-z0-9]{20,}|pat_FL[A-Za-z0-9]{20,}' docs/ 2>/dev/null || true)
  # 1167075209 разрешён ТОЛЬКО в URL вида ?start=ref_1167075209 (это
  # рефералка). Все остальные упоминания — fail.
  forbidden_chat=$(grep -rnE '\b1167075209\b' docs/ 2>/dev/null \
    | grep -vE 'WantToPayBot|WhisperSummaryAI|start=ref_1167075209' || true)

  combined="$forbidden_docs"
  [[ -n "$forbidden_keys" ]] && combined="${combined}${combined:+$'\n'}${forbidden_keys}"
  [[ -n "$forbidden_chat" ]] && combined="${combined}${combined:+$'\n'}${forbidden_chat}"

  if [[ -n "$combined" ]]; then
    fail "docs/ содержат личные данные:"
    echo "$combined" | head -10
  else
    pass "docs/ чистые от личных TG ID и API-ключей"
  fi
else
  pass "docs/ отсутствует — проверка пропущена"
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
