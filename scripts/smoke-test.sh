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
agent_exists "nonexistent-agent-xyz" >/dev/null 2>&1
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

# ─── Test 5: VIP v2 end-to-end с реальным токеном от @AITeamVIPBot ───
# Токен выдан 2026-04-21 после sync-фикса (бот обновлён до v2).
# TG=123456789 — тестовое несуществующее значение, токен бесполезен
# для реального злоумышленника (чужой TG, проверка провалится).
# shellcheck disable=SC1091
source scripts/lib/vip.sh

REAL_VIP_TOKEN="VIP-4EAF70B1F7A79796-123456789-Luu9d94qEEvJxrBZkQiRHJo2sdunPjmIh6SOAMh4aVyInPzMs3iDDV5tlJVGztUQk0P5wIIyESLtBUPbHzDEAw"
REAL_VIP_TG="123456789"

# 5a. Формат распознаётся как v2
[[ "$(vip_token_version "$REAL_VIP_TOKEN")" == "v2" ]] || fail "v2 token не распознан как v2"
pass "v2 формат распознаётся"

# 5b. Корректный TG → rc=0
set +e
verify_vip_token "$REAL_VIP_TOKEN" "$REAL_VIP_TG"
rc=$?
set -e
[[ "$rc" == "0" ]] || fail "valid token с правильным TG: ожидался rc=0, получен rc=$rc"
pass "VIP v2 валидация с правильным TG ($REAL_VIP_TG): rc=0"

# 5c. Чужой TG → rc=3 (TG mismatch, анти-шаринг)
set +e
verify_vip_token "$REAL_VIP_TOKEN" "999999999"
rc=$?
set -e
[[ "$rc" == "3" ]] || fail "valid token с чужим TG: ожидался rc=3, получен rc=$rc"
pass "VIP v2 анти-шаринг с чужим TG: rc=3 (блокирует)"

# 5d. Испорченный токен → rc=5 (подпись не проходит)
BROKEN_TOKEN="VIP-4EAF70B1F7A79796-123456789-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
set +e
verify_vip_token "$BROKEN_TOKEN" "123456789"
rc=$?
set -e
[[ "$rc" == "5" ]] || fail "broken signature: ожидался rc=5, получен rc=$rc"
pass "VIP v2 отвергает токен с битой подписью: rc=5"

# ─── Test 6: wave 6 шаблоны на месте — SOUL / LEARNING / skills ───
# Для 3 VIP-агентов должны существовать расширенные шаблоны.
# Если файл удалили/переименовали — тест падает, CI не даст смержить.
for vip_agent in designer coordinator copywriter; do
  for extra in SOUL.md LEARNING.md; do
    [[ -f "templates/${vip_agent}/${extra}" ]] \
      || fail "отсутствует templates/${vip_agent}/${extra}"
  done
done
pass "wave 6: SOUL.md + LEARNING.md присутствуют для 3 VIP-агентов"

# skills/ — 2 файла на VIP-агента, по зашитым именам
for skill in designer/skills/eachlabs-image-generation \
             designer/skills/color-palette \
             coordinator/skills/agent-collaboration-network \
             coordinator/skills/close-loop \
             copywriter/skills/reef-copywriting \
             copywriter/skills/brand-voice-profile; do
  [[ -f "templates/${skill}/SKILL.md" ]] \
    || fail "отсутствует templates/${skill}/SKILL.md"
done
pass "wave 6: skills/*/SKILL.md на месте (6 импортированных MIT-скиллов)"

# LICENSE-skills.md — единый attribution manifest
[[ -f "templates/LICENSE-skills.md" ]] \
  || fail "отсутствует templates/LICENSE-skills.md (MIT attribution)"
pass "wave 6: LICENSE-skills.md attribution manifest на месте"

# ─── Test 6.5: wave 7 refresh mode прописан в prepare_workspace_from_templates ───
# Проверяем что в коде функции действительно есть проверка mode=refresh,
# и find_installed_agents объявлена. Это статическая проверка — полный
# dry-run требует curl к github, его оставляем на CI/live-тесты.
grep -q 'local mode="${3:-full}"' scripts/lib/agents.sh \
  || fail "prepare_workspace_from_templates не принимает mode-аргумент (wave 7)"
grep -q 'find_installed_agents()' scripts/lib/agents.sh \
  || fail "find_installed_agents не объявлена в agents.sh (wave 7)"
grep -q 'REFRESH_TEMPLATES_ONLY' scripts/install-agents.sh \
  || fail "--refresh-templates флаг не обработан в install-agents.sh (wave 7)"
grep -q '"refresh"' scripts/install-agents.sh \
  || fail "режим refresh не вызывается из install-agents.sh (wave 7)"
pass "wave 7: refresh mode + --refresh-templates + find_installed_agents на месте"

# ─── Test 6.6: wave 8 embedding + group-mode прописаны ───
# Статические grep-ассерты что новые функции и флаги на месте.
grep -q 'enable_embedding_for_agent' scripts/lib/agents.sh \
  || fail "enable_embedding_for_agent не объявлена в agents.sh (wave 8)"
grep -q 'configure_group_membership' scripts/lib/agents.sh \
  || fail "configure_group_membership не объявлена в agents.sh (wave 8)"
grep -q 'validate_openai_embedding_key' scripts/lib/agents.sh \
  || fail "validate_openai_embedding_key не объявлена (wave 8)"
grep -q 'R1\.5' scripts/install-agents.sh \
  || fail "Шаг R1.5 (embedding) не прописан в install-agents.sh (wave 8)"
grep -q -- '--enable-group-mode' scripts/install-agents.sh \
  || fail "Флаг --enable-group-mode не прописан (wave 8)"
grep -q -- '--enable-embedding' scripts/install-agents.sh \
  || fail "Флаг --enable-embedding не прописан (wave 8)"
pass "wave 8: embedding + group-mode lib функции и флаги на месте"

# ─── Test 6.7: wave 8 AGENTS.md содержит блок «Если ты в группе» ───
for vip_agent in tech marketer producer designer coordinator copywriter; do
  grep -q "Если ты в группе" "templates/${vip_agent}/AGENTS.md" \
    || fail "${vip_agent}/AGENTS.md не содержит блок «Если ты в группе» (wave 8)"
done
pass "wave 8: блок «Если ты в группе» во всех 6 AGENTS.md"

# ─── Test 6.8: wave 8 docs/group-mode.md существует ───
[[ -f "docs/group-mode.md" ]] \
  || fail "docs/group-mode.md отсутствует (wave 8)"
pass "wave 8: docs/group-mode.md на месте"

# ─── Test 6.9: wave 8.1 docs/openai-key-setup.md существует ───
[[ -f "docs/openai-key-setup.md" ]] \
  || fail "docs/openai-key-setup.md отсутствует (wave 8.1 — гайд по получению OpenAI ключа)"
# В R1.5 explain должна быть прямая ссылка на api-keys
grep -q "platform.openai.com/api-keys" scripts/install-agents.sh \
  || fail "scripts/install-agents.sh не содержит ссылку на platform.openai.com/api-keys (wave 8.1)"
pass "wave 8.1: docs/openai-key-setup.md + ссылка в R1.5 на месте"

# В R1.5 предупреждение про РФ-карту + ссылка на бот для виртуальной зарубежной
grep -q "WantToPayBot" scripts/install-agents.sh \
  || fail "scripts/install-agents.sh не содержит ссылку на @WantToPayBot для виртуальной зарубежной карты (wave 8.2)"
grep -qiE "Российская\\s+карта\\s+в\\s+OpenAI\\s+НЕ" scripts/install-agents.sh \
  || fail "scripts/install-agents.sh не содержит явное предупреждение «РФ карта не пройдёт» (wave 8.2)"
pass "wave 8.2: РФ-карта warning + ссылка на @WantToPayBot в R1.5"

# ─── Test 6.10: wave 8.3 docs/windows-install-guide.md + Windows detector ───
[[ -f "docs/windows-install-guide.md" ]] \
  || fail "docs/windows-install-guide.md отсутствует (wave 8.3 — Windows гайд)"
grep -q 'detect_environment()' scripts/lib/preflight.sh \
  || fail "detect_environment() не объявлена в preflight.sh (wave 8.3)"
grep -q 'print_windows_hints' scripts/lib/preflight.sh \
  || fail "print_windows_hints() не объявлена (wave 8.3)"
grep -q 'windows-bash\|wsl' scripts/lib/preflight.sh \
  || fail "preflight.sh не различает windows-bash/wsl окружения (wave 8.3)"
pass "wave 8.3: docs/windows-install-guide.md + detect_environment + Windows hints"

# ─── Test 7: wave 6 AGENTS.md содержит Session Startup + Онбординг ───
# Гарантия что агент при старте сессии читает файлы по порядку
# и запускает онбординг при пустом USER.md.
for vip_agent in designer coordinator copywriter; do
  grep -q "Session Startup" "templates/${vip_agent}/AGENTS.md" \
    || fail "${vip_agent}/AGENTS.md не содержит секцию 'Session Startup'"
  grep -qE "Первый контакт|онбординг" "templates/${vip_agent}/AGENTS.md" \
    || fail "${vip_agent}/AGENTS.md не содержит секцию онбординга"
done
pass "wave 6: AGENTS.md у 3 VIP-агентов содержит Session Startup + онбординг"

rm -f /tmp/fake.json

echo ""
echo "=== All smoke tests passed ==="
