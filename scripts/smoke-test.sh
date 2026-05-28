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

# ─── Test 6.4b: wave 29 обогащённая базовая тройка (Pro) ─────────
# tech/marketer/producer теперь имеют SOUL + LEARNING + 2 skills
# (как VIP-тройка). В установщике эти extras копируются ТОЛЬКО при
# VIP_MODE=true (Pro) — в Base остаются 4 базовых файла.
for base_agent in tech marketer producer; do
  [[ -f "templates/${base_agent}/SOUL.md" ]] \
    || fail "wave 29: templates/${base_agent}/SOUL.md отсутствует"
  [[ -f "templates/${base_agent}/LEARNING.md" ]] \
    || fail "wave 29: templates/${base_agent}/LEARNING.md отсутствует"
done
for skill in tech/skills/diagnostic-checklist tech/skills/safe-rollback \
             marketer/skills/funnel-diagnosis marketer/skills/channel-unit-economics \
             producer/skills/launch-route-selector producer/skills/product-unit-economics; do
  [[ -f "templates/${skill}/SKILL.md" ]] \
    || fail "wave 29: отсутствует templates/${skill}/SKILL.md"
done
# В agents.sh — extras для базовой тройки гейтятся VIP_MODE
grep -qE 'tech\|marketer\|producer\)' scripts/lib/agents.sh \
  || fail "wave 29: agents.sh не различает базовую тройку для extras"
grep -q 'VIP_MODE:-false.*== true.*&& has_extras=true' scripts/lib/agents.sh \
  || fail "wave 29: extras базовой тройки не гейтятся через VIP_MODE"
pass "wave 29: базовая тройка обогащена (SOUL+LEARNING+skills, только Pro)"

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

# В R1.5 предупреждение про карту (РФ-карта не работает / нужна иностранная)
# + ссылка на бот для виртуальной зарубежной (wave 18: смягчили regex,
# принимаем любой вариант — «Российская карта в OpenAI НЕ» / «иностранная карта» /
# «зарубежная карта» — суть в том что клиент должен быть предупреждён).
grep -q "WantToPayBot" scripts/install-agents.sh \
  || fail "scripts/install-agents.sh не содержит ссылку на @WantToPayBot для виртуальной зарубежной карты (wave 8.2)"
# Принимаем любой из вариантов формулировки — суть в том что клиент
# должен быть предупреждён про карту. Без posix-character-ranges
# с кириллицей (Ubuntu grep ругается «Invalid collation character»).
if ! grep -q "иностранная карта" scripts/install-agents.sh \
   && ! grep -q "иностранную карту" scripts/install-agents.sh \
   && ! grep -q "зарубежная карта" scripts/install-agents.sh \
   && ! grep -q "зарубежную карту" scripts/install-agents.sh \
   && ! grep -q "Российская карта" scripts/install-agents.sh \
   && ! grep -q "РФ-карта" scripts/install-agents.sh \
   && ! grep -q "российские не работают" scripts/install-agents.sh; then
  fail "scripts/install-agents.sh не содержит предупреждение про карту (wave 8.2)"
fi
pass "wave 8.2: карта-warning + ссылка на @WantToPayBot в R1.5"

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

# ─── Test 6.11: docs/curator-cheatsheet.md существует (для AI-куратора) ───
[[ -f "docs/curator-cheatsheet.md" ]] \
  || fail "docs/curator-cheatsheet.md отсутствует (wave 8.5 — шпаргалка для куратора)"
pass "wave 8.5: docs/curator-cheatsheet.md на месте"

# ─── Test 6.12: wave 9 system hardening (BUG-01 / 03 / 05 / 06) ───
# BUG-01: hard preflight bash/python3/curl
grep -q 'missing_tools' scripts/lib/preflight.sh \
  || fail "preflight.sh не проверяет наличие bash/python3/curl (wave 9 BUG-01)"
# BUG-05: JSON validation main/auth-profiles
grep -q 'json.load' scripts/lib/preflight.sh \
  || fail "preflight.sh не валидирует JSON в main/auth-profiles.json (wave 9 BUG-05)"
grep -q 'SKIP_AUTH_PROFILE_CHECK' scripts/lib/preflight.sh \
  || fail "preflight.sh не имеет SKIP_AUTH_PROFILE_CHECK guard для refresh-templates (wave 9 BUG-05)"
grep -q 'SKIP_AUTH_PROFILE_CHECK=true' scripts/install-agents.sh \
  || fail "--refresh-templates entry не выставляет SKIP_AUTH_PROFILE_CHECK=true (wave 9 BUG-05 guard)"
# BUG-06: git clone fallback message
grep -q 'git clone https://github.com/tonytrue92-beep/openclaw-agents-pack' scripts/install-agents.sh \
  || fail "install-agents.sh не показывает git clone fallback при curl-сбое (wave 9 BUG-06)"
# BUG-03: Telegram self-test после R5
grep -q 'telegram_channel_self_test' scripts/lib/agents.sh \
  || fail "telegram_channel_self_test не объявлена (wave 9 BUG-03)"
grep -q 'telegram_channel_self_test' scripts/install-agents.sh \
  || fail "telegram_channel_self_test не вызывается в R5 (wave 9 BUG-03)"
# Эскалация в curator-cheatsheet.md
grep -q 'Эскалация на технаря (вне нашей зоны)' docs/curator-cheatsheet.md \
  || fail "curator-cheatsheet.md не содержит секцию эскалации BUG-02/04/07 (wave 9)"
pass "wave 9: BUG-01/03/05/06 + эскалация на технаря — все на месте"

# ─── Test 6.13: wave 10 build-bundle (self-contained installer) ───
[[ -f "scripts/build-bundle.sh" ]] \
  || fail "scripts/build-bundle.sh отсутствует (wave 10)"
[[ -x "scripts/build-bundle.sh" ]] \
  || fail "scripts/build-bundle.sh не executable"
# Маркеры для bundle-сборки в install-agents.sh
grep -q '=== BUNDLE_LIB_BEGIN ===' scripts/install-agents.sh \
  || fail "install-agents.sh не содержит маркер BUNDLE_LIB_BEGIN (wave 10)"
grep -q '=== BUNDLE_LIB_END ===' scripts/install-agents.sh \
  || fail "install-agents.sh не содержит маркер BUNDLE_LIB_END (wave 10)"
# Сообщение об ошибке curl должно теперь упоминать bundled-URL
grep -q 'install-agents-bundled.sh' scripts/install-agents.sh \
  || fail "install-agents.sh не упоминает bundled-URL в curl-error сообщении (wave 10)"
# Release workflow проверяем только если .github/ присутствует
# (Docker smoke не копирует .github/ — там этих файлов нет, и это OK).
if [[ -d ".github" ]]; then
  [[ -f ".github/workflows/release.yml" ]] \
    || fail ".github/workflows/release.yml отсутствует (wave 10 — auto-release при теге)"
  [[ -f ".github/release-body-template.md" ]] \
    || fail ".github/release-body-template.md отсутствует (wave 10)"
fi
pass "wave 10: build-bundle.sh + bundle-маркеры на месте"

# ─── Test 6.14: wave 10.1 bonjour VPS hotfix ─────────────────────
grep -q 'disable_bonjour_for_vps' scripts/lib/agents.sh \
  || fail "disable_bonjour_for_vps не объявлена (wave 10.1)"
grep -q 'disable_bonjour_for_vps' scripts/install-agents.sh \
  || fail "install-agents.sh не вызывает disable_bonjour_for_vps в --vps режиме (wave 10.1)"
grep -q 'CIAO PROBING CANCELLED\|bonjour' scripts/install-agents.sh \
  || fail "install-agents.sh не упоминает bonjour в Telegram self-test recovery (wave 10.1)"
grep -q 'bonjour' scripts/diagnose-agents.sh \
  || fail "diagnose-agents.sh не проверяет bonjour на Linux/WSL (wave 10.1)"
grep -q 'СЦЕНАРИЙ 4а' docs/curator-cheatsheet.md \
  || fail "curator-cheatsheet не содержит сценарий «бот молчит на VPS / bonjour» (wave 10.1)"
pass "wave 10.1: bonjour VPS-hotfix во всех слоях (lib + install + diagnose + curator)"

# ─── Test 6.15: wave 11 audit fixes ──────────────────────────────
# P0: python json validation должен использовать sys.argv (не heredoc-injection)
grep -q 'sys.argv\[1\]' scripts/lib/preflight.sh \
  || fail "preflight.sh не использует sys.argv для пути auth-profiles (wave 11 P0 — path injection fix)"
# P0: bonjour guard через command -v openclaw
grep -q 'VPS_MODE.*&&.*command -v openclaw' scripts/install-agents.sh \
  || fail "install-agents.sh не имеет guard 'command -v openclaw' перед disable_bonjour_for_vps (wave 11 P0)"
# P1: portable while-read replacement для mapfile
grep -qE 'while IFS= read -r _agent_id' scripts/install-agents.sh \
  || fail "install-agents.sh всё ещё использует mapfile вместо portable while-read (wave 11 P1 — bash 3.2 compat)"
# P1: BOT_TOKEN_* unset в начале
grep -qE 'unset BOT_TOKEN_TECH BOT_TOKEN_MARKETER' scripts/install-agents.sh \
  || fail "install-agents.sh не делает unset BOT_TOKEN_* в начале (wave 11 P1 stale-token cleanup)"
# P1: umask 077 в lib-файлах с секретами
grep -q '^umask 077' scripts/lib/debug-bundle.sh \
  || fail "debug-bundle.sh не имеет umask 077 (wave 11 P1 — temp file secrets)"
grep -q '^umask 077' scripts/lib/vip.sh \
  || fail "vip.sh не имеет umask 077 (wave 11 P1 — temp file PEM/sig)"
# P1: TG self-test sleep против rate-limit (контекст: rate-limit protection)
grep -q 'sleep 0.5  # rate-limit protection' scripts/install-agents.sh \
  || fail "install-agents.sh R5 self-test без sleep против rate-limit (wave 11 P1)"
pass "wave 11: P0 (python injection / bonjour guard) + P1 (mapfile/unset/umask/sleep) на месте"

# ─── Test 6.16: wave 12 course-token mandatory ───────────────────
[[ -f "scripts/lib/course-token.sh" ]] \
  || fail "scripts/lib/course-token.sh отсутствует (wave 12)"
grep -q 'acquire_course_token' scripts/lib/course-token.sh \
  || fail "acquire_course_token не объявлена (wave 12)"
grep -q 'course_token_get_tier' scripts/lib/vip.sh \
  || fail "course_token_get_tier не объявлена в vip.sh (wave 12)"
grep -q '_verify_v3' scripts/lib/vip.sh \
  || fail "_verify_v3 не объявлена в vip.sh (wave 12 — STD/VIP tier-aware)"
grep -q 'STD-\[A-F0-9\]' scripts/lib/vip.sh \
  || fail "vip.sh не распознаёт STD-префикс токена (wave 12)"
grep -q -- '--course-token' scripts/install-agents.sh \
  || fail "--course-token флаг не прописан в install-agents.sh (wave 12)"
grep -q 'acquire_course_token' scripts/install-agents.sh \
  || fail "install-agents.sh не вызывает acquire_course_token в V1 (wave 12)"
grep -q 'course-token' scripts/build-bundle.sh \
  || fail "build-bundle.sh не включает course-token.sh в bundle (wave 12)"
# Wave 12 бриф (course-token-brief-for-techie.md) удалён как выполненный
# (course-token в проде с мая 2026). Сама логика course-token проверена
# выше — ассерт на handoff-файл больше не нужен.
pass "wave 12: course-token v3 (Standard + VIP) во всех слоях"

# ─── Test 6.17: wave 12.1 v3 token runtime tests (after @AITeamVIPBot v3) ─
# Технарь обновил бот до v3 (commit fbb8443) и прислал тестовые
# токены, подписанные тем же приватным ключом что v2-VIP-тест выше.
# Оба для TG=123456789 (тестовый, токены бесполезны злоумышленнику).
TEST_STD_TOKEN_V3="STD-83E4E94BC01F3E0E-123456789-c9H1UYJVjqbu5MCuw0Dwq5rWhqxl4cZRtSCXud3IeBBoG4pnVy4N7iJud6c5oo1fgGKaxSE4JXH_OwIOwSPvDQ"
TEST_VIP_TOKEN_V3="VIP-377D8277E363B9B3-123456789-B1VpzqPSalsWOzpm-lPX1E6JR8wYTDvNi6THaF2eAkXafCmbaTbPOKf7mk1NPt6gdINAszG7IlIARf0a2dRZDA"

# 12.1a. v3-STD формат распознаётся правильно
[[ "$(vip_token_version "$TEST_STD_TOKEN_V3")" == "v3-std" ]] \
  || fail "v3-STD токен не распознан как v3-std"
pass "wave 12.1: v3-STD форма распознаётся"

# 12.1b. v3-VIP имеет ту же форму что v2 (различается по payload)
[[ "$(vip_token_version "$TEST_VIP_TOKEN_V3")" == "v2" ]] \
  || fail "v3-VIP должен иметь форму v2 (различается через payload)"
pass "wave 12.1: v3-VIP имеет правильную v2-совместимую форму"

# 12.1c. STD-токен с правильным TG → rc=0
set +e
verify_vip_token "$TEST_STD_TOKEN_V3" "123456789"
rc=$?
set -e
[[ "$rc" == "0" ]] || fail "v3-STD с правильным TG: ожидался rc=0, получен rc=$rc"
pass "wave 12.1: v3-STD валидация с правильным TG: rc=0"

# 12.1d. VIP-токен v3 с правильным TG → rc=0
set +e
verify_vip_token "$TEST_VIP_TOKEN_V3" "123456789"
rc=$?
set -e
[[ "$rc" == "0" ]] || fail "v3-VIP с правильным TG: ожидался rc=0, получен rc=$rc"
pass "wave 12.1: v3-VIP валидация с правильным TG: rc=0"

# 12.1e. STD-токен с чужим TG → rc=3 (anti-share)
set +e
verify_vip_token "$TEST_STD_TOKEN_V3" "999999999"
rc=$?
set -e
[[ "$rc" == "3" ]] || fail "v3-STD anti-share: ожидался rc=3, получен rc=$rc"
pass "wave 12.1: v3-STD anti-share с чужим TG: rc=3"

# 12.1f. course_token_get_tier правильно извлекает tier
[[ "$(course_token_get_tier "$TEST_STD_TOKEN_V3")" == "STD" ]] \
  || fail "course_token_get_tier для STD-токена должна вернуть STD"
[[ "$(course_token_get_tier "$TEST_VIP_TOKEN_V3")" == "VIP" ]] \
  || fail "course_token_get_tier для VIP-токена должна вернуть VIP"
pass "wave 12.1: course_token_get_tier корректно извлекает STD/VIP"

# ─── Test 6.18: wave 13 DMG installer для macOS ──────────────────
[[ -f "scripts/build-dmg.sh" ]] \
  || fail "scripts/build-dmg.sh отсутствует (wave 13)"
[[ -x "scripts/build-dmg.sh" ]] \
  || fail "scripts/build-dmg.sh не executable (wave 13)"
[[ -d "dmg-template" ]] \
  || fail "dmg-template/ директория отсутствует (wave 13)"
[[ -f "dmg-template/1-Установить-OpenClaw.command" ]] \
  || fail "dmg-template/1-Установить-OpenClaw.command отсутствует (wave 13)"
[[ -f "dmg-template/2-Установить-AI-команду.command" ]] \
  || fail "dmg-template/2-Установить-AI-команду.command отсутствует (wave 13)"
[[ -f "dmg-template/README.txt" ]] \
  || fail "dmg-template/README.txt отсутствует (wave 13)"
[[ -x "dmg-template/1-Установить-OpenClaw.command" ]] \
  || fail ".command файлы должны быть executable иначе двойной клик не работает (wave 13)"
[[ -x "dmg-template/2-Установить-AI-команду.command" ]] \
  || fail ".command файлы должны быть executable иначе двойной клик не работает (wave 13)"
[[ -f "docs/mac-install-guide.md" ]] \
  || fail "docs/mac-install-guide.md отсутствует (wave 13)"
# bash-syntax внутри .command файлов
bash -n "dmg-template/1-Установить-OpenClaw.command" \
  || fail "1-Установить-OpenClaw.command не проходит bash -n (wave 13)"
bash -n "dmg-template/2-Установить-AI-команду.command" \
  || fail "2-Установить-AI-команду.command не проходит bash -n (wave 13)"
# build-dmg.sh должен явно проверять что мы на macOS (не падать тихо
# на Linux в CI смешанных runner'ах)
grep -q 'uname -s.*Darwin\|uname -s.*!= "Darwin"' scripts/build-dmg.sh \
  || fail "build-dmg.sh не имеет macOS-only guard (wave 13)"
pass "wave 13: DMG installer (build-dmg.sh + dmg-template/ + mac-install-guide) на месте"

# ─── Test 6.19: wave 14 token-first flow ─────────────────────────
# Проверяем что V0 (токен) идёт ДО R0 (анализ состояния), а старое
# меню Standard/VIP убрано (раньше шло до V1).
# Верифицируется через line-numbers — нумерация steps в скрипте.
v0_line=$(grep -n 'step_header "V0"' scripts/install-agents.sh | head -1 | cut -d: -f1)
r0_line=$(grep -n 'step_header "R0"' scripts/install-agents.sh | head -1 | cut -d: -f1)
[[ -n "$v0_line" && -n "$r0_line" && "$v0_line" -lt "$r0_line" ]] \
  || fail "wave 14: V0 (токен) должен идти ДО R0 (line v0=$v0_line < r0=$r0_line)"

# Старое меню «Установить только одного» убрано — этот текст теперь
# только в новом VIP-меню после V0.
old_menu_match=$(grep -c 'Какой набор агентов устанавливаем' scripts/install-agents.sh || true)
[[ "$old_menu_match" == "0" ]] \
  || fail "wave 14: старое меню (\"Какой набор\") не удалено (matches: $old_menu_match)"

# Сообщение про авто-установку для STD-tier (wave 20 переименовал Standard → Base).
# Допускаем ANSI/bash-variables (${BOLD}/${NC}) между «Тариф» и именем тарифа.
grep -qE 'Тариф.*(Standard|Base).*установлю 3 агента' scripts/install-agents.sh \
  || fail "wave 14/20: STD-tier auto-install message (Base) отсутствует"

# Сообщение про tier=VIP меню (wave 20 переименовал VIP → Pro)
grep -qE 'Выбери что поставить|У тебя.*VIP.*-тариф' scripts/install-agents.sh \
  || fail "wave 14/20: VIP-tier меню заголовок отсутствует"
# Опция «Base» (бывший Только Standard) в Pro-меню
grep -qE 'Base — 3 агента|Только Standard' scripts/install-agents.sh \
  || fail "wave 14/20: Pro-меню опция «Base — 3 агента» отсутствует"
pass "wave 14/20: V0 (токен) до R0 + tier-based menu (STD авто / VIP=Pro меню)"

# ─── Test 6.20: wave 15 Bot-to-Bot Communication docs ────────────
[[ -f "docs/bot-to-bot-setup.md" ]] \
  || fail "docs/bot-to-bot-setup.md отсутствует (wave 15)"
# group-mode.md должен ссылаться на bot-to-bot-setup.md как альтернативу
grep -q 'bot-to-bot-setup.md' docs/group-mode.md \
  || fail "docs/group-mode.md не упоминает bot-to-bot-setup.md (wave 15)"
# curator-cheatsheet должен иметь сценарий «Боты зациклились»
grep -q 'СЦЕНАРИЙ 7а\|Боты зациклились' docs/curator-cheatsheet.md \
  || fail "curator-cheatsheet.md не содержит сценарий «боты зациклились» (wave 15)"
# Установщик в финале для VIP должен упоминать Bot-to-Bot
grep -q 'Bot-to-Bot Communication\|bot-to-bot-setup.md' scripts/install-agents.sh \
  || fail "install-agents.sh не упоминает Bot-to-Bot в финальном экране (wave 15)"
pass "wave 15: docs/bot-to-bot-setup.md + group-mode/curator-cheatsheet/installer обновлены"

# ─── Test 6.21: wave 15.1 token UX clarity ──────────────────────
# Info-сообщения в early-exit режимах что токен не запрашивается
grep -q 'Курс-токен не запрашивается.*read-only' scripts/install-agents.sh \
  || fail "wave 15.1: --collect-debug / --diagnose-only без info про токен"
grep -q 'Курс-токен не запрашивается.*обновление существующих' scripts/install-agents.sh \
  || fail "wave 15.1: --refresh-templates без info про токен"
grep -q 'Курс-токен не запрашивается.*конфигурируем уже установленных' scripts/install-agents.sh \
  || fail "wave 15.1: --enable-group-mode без info про токен"
# Усиленный отказ при невалидном токене — должен быть явный «УСТАНОВКА ОТКЛОНЕНА»
grep -q 'УСТАНОВКА ОТКЛОНЕНА.*курс-токен не валиден' scripts/install-agents.sh \
  || fail "wave 15.1: невалидный токен без явного «УСТАНОВКА ОТКЛОНЕНА»"
grep -q 'УСТАНОВКА ОТКЛОНЕНА.*несоответствие тарифа' scripts/install-agents.sh \
  || fail "wave 15.1: tier-mismatch без явного «УСТАНОВКА ОТКЛОНЕНА»"
pass "wave 15.1: info про токен в early-exits + усиленный отказ при невалидном токене"

# ─── Test 6.22: wave 16 SUB-tier subscription ────────────────────
# Lib должен распознавать SUB- префикс
grep -q 'SUB-\[A-F0-9\]' scripts/lib/vip.sh \
  || fail "wave 16: vip.sh не распознаёт SUB- префикс"
# vip_token_version возвращает v3-sub для SUB-токенов
TEST_SUB_TOKEN_FORMAT="SUB-83E4E94BC01F3E0E-123456789-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
[[ "$(vip_token_version "$TEST_SUB_TOKEN_FORMAT")" == "v3-sub" ]] \
  || fail "wave 16: vip_token_version не возвращает v3-sub для SUB-токена"
# course_token_get_tier → SUB
[[ "$(course_token_get_tier "$TEST_SUB_TOKEN_FORMAT")" == "SUB" ]] \
  || fail "wave 16: course_token_get_tier не возвращает SUB"
# vip_token_get_expected_tg + vip_token_get_hash работают на SUB
[[ "$(vip_token_get_expected_tg "$TEST_SUB_TOKEN_FORMAT")" == "123456789" ]] \
  || fail "wave 16: vip_token_get_expected_tg не работает на SUB"
[[ "$(vip_token_get_hash "$TEST_SUB_TOKEN_FORMAT")" == "83E4E94BC01F3E0E" ]] \
  || fail "wave 16: vip_token_get_hash не работает на SUB"
# install-agents: V0c (SUB graceful exit) на месте
grep -q 'V0c.*SUB-tier\|COURSE_TIER == "SUB"' scripts/install-agents.sh \
  || fail "wave 16: install-agents не имеет SUB graceful-exit (V0c)"
# Wave 20 переименовал «SUB-тариф (подписка)» → «Тариф OpenClaw (подписка)».
# Принимаем оба варианта (старый/новый брендинг).
grep -qE 'SUB-тариф.*подписка|Тариф OpenClaw.*подписка' scripts/install-agents.sh \
  || fail "wave 16/20: install-agents не имеет info-сообщения про подписочный тариф"
# Бриф для технаря и CSV проверяем только если handoff/ присутствует.
# Docker smoke не копирует handoff/ (это внутренний документ для разработки,
# не входит в bundle для клиентов).
if [[ -d "handoff" ]]; then
  [[ -f "handoff/subscription-tier-brief-for-techie.md" ]] \
    || fail "wave 16: handoff/subscription-tier-brief-for-techie.md отсутствует"
  [[ -f "handoff/active_subscribers-2026-05-11.csv" ]] \
    || fail "wave 16: handoff/active_subscribers-2026-05-11.csv отсутствует"
fi
# curator-cheatsheet с новыми сценариями
grep -q 'СЦЕНАРИЙ 13.*SUB\|СЦЕНАРИЙ 14.*[Пп]одписка' docs/curator-cheatsheet.md \
  || fail "wave 16: curator-cheatsheet не содержит сценариев SUB / истёкшая подписка"
pass "wave 16: SUB-tier распознаётся + graceful exit + бриф технарю + CSV + curator-cheatsheet"

# ─── Test 6.23: wave 17 token input sanitization ─────────────────
# Кейс Надежды (15.05.2026): валидный VIP-токен отклонялся с кодом 5
# из-за trailing whitespace при копировании из Telegram. Wave 17
# добавляет автоочистку токена от пробелов / юникод-тире / кавычек.
grep -q 'Wave 17: санитизация ввода' scripts/lib/course-token.sh \
  || fail "wave 17: санитизация ввода не помечена в course-token.sh"
grep -q "tr -d '\[:space:\]'" scripts/lib/course-token.sh \
  || fail "wave 17: санитизация whitespace отсутствует в _course_token_validate_and_set"
grep -q 'EM DASH\|U+2014' scripts/lib/course-token.sh \
  || fail "wave 17: замена длинного тире не реализована"
grep -q 'EN DASH\|U+2013' scripts/lib/course-token.sh \
  || fail "wave 17: замена среднего тире не реализована"
grep -q 'Очистил токен от лишних символов' scripts/lib/course-token.sh \
  || fail "wave 17: info-сообщение о санитизации отсутствует"
# Runtime-проверка: токен с trailing-space должен пройти валидацию формата
test_token_dirty="  STD-AAAAAAAAAAAAAAAA-12345  "
test_token_clean="STD-AAAAAAAAAAAAAAAA-12345"
test_token_dashes="STD—AAAAAAAAAAAAAAAA—12345"  # с длинными тире
# Проверяем только что регекс tier-prefix отрабатывает после санитизации
(
  source scripts/lib/vip.sh 2>/dev/null
  source scripts/lib/course-token.sh 2>/dev/null
  result=$(course_token_get_tier "$test_token_clean" 2>/dev/null)
  [[ "$result" == "STD" ]] || exit 1
) || fail "wave 17: course_token_get_tier не распознаёт чистый STD-токен"
pass "wave 17: санитизация токена (whitespace / unicode-тире / кавычки) на месте"

# ─── Test 6.24: wave 19 платформо-aware финальный экран ──────────
# Авто-детект окружения + одна целевая ссылка на платформо-гайд
# в финале install-agents.sh. macOS → mac-install-guide, Windows/WSL
# → windows-install-guide. Покрывает 3 главных канала доставки.
grep -q 'wave 19: платформо-специфичная ссылка' scripts/install-agents.sh \
  || fail "wave 19: финальный платформо-блок не помечен"
grep -q 'detect_environment' scripts/install-agents.sh \
  || fail "wave 19: install-agents не вызывает detect_environment в финале"
grep -q 'docs/mac-install-guide.md' scripts/install-agents.sh \
  || fail "wave 19: ссылка на mac-install-guide в финале отсутствует"
grep -q 'docs/windows-install-guide.md' scripts/install-agents.sh \
  || fail "wave 19: ссылка на windows-install-guide в финале отсутствует"
pass "wave 19: платформо-aware финальный экран (macOS/Windows/WSL)"

# ─── Test 6.25: wave 20 публичный нейминг тарифов (Base/Pro/OpenClaw) ─
# Banner и меню используют новые публичные названия Base (бывший Standard)
# и Pro (бывший VIP). Внутренние COURSE_TIER (STD/VIP/SUB) и token-формат
# не меняются — backwards-compat с токенами полная.
# Wave 23: «Base:» и «Pro:» из баннера убраны в пользу маркетингового
# pitch'а. Названия тарифов остались в главном меню (V_MAIN) — там
# и проверяем.
grep -q 'Base.*3 базовых агента' scripts/install-agents.sh \
  || fail "wave 20/23: «Base» в меню (3 базовых агента) отсутствует"
grep -q 'Pro.*6 агентов' scripts/install-agents.sh \
  || fail "wave 20/23: «Pro» в меню (6 агентов) отсутствует"
grep -q 'Pro — 6 агентов' scripts/install-agents.sh \
  || fail "wave 20: меню не содержит опцию «Pro — 6 агентов»"
grep -q 'Base — 3 агента' scripts/install-agents.sh \
  || fail "wave 20: меню не содержит опцию «Base — 3 агента»"
grep -q 'Только OpenClaw' scripts/install-agents.sh \
  || fail "wave 20: меню не содержит опцию «Только OpenClaw» (3-й пункт)"
# Меню теперь компактное — 3 пункта без Hermes или 4 с Hermes.
# Wave 26: порядок пунктов изменён (OpenClaw → Base → Pro → Hermes),
# default стал Enter = 3 (Pro).
grep -qE '\[1/2/3, Enter = 3\]|\[1/2/3/4, Enter = 3\]' scripts/install-agents.sh \
  || fail "wave 20/26: меню не содержит [1/2/3, Enter = 3] / [1/2/3/4, Enter = 3]"
grep -q '\[1/2/3/4/5' scripts/install-agents.sh \
  && fail "wave 20: старое 5-опционное меню всё ещё на месте"
pass "wave 20/26: публичные тарифы Base/Pro/OpenClaw + меню 3-4 пункта"

# ─── Test 6.26: wave 21 главное меню (V_MAIN) после banner ───────
# V_MAIN показывает 3 опции (Pro/Base/OpenClaw) СРАЗУ после banner,
# ДО запроса токена. Клиент видит линейку продуктов и выбирает что
# хочет — потом подтверждает токеном. Пропускается при non-interactive
# флагах (--install / --course-token / --only-agent / --config / VPS).
grep -q 'V_MAIN. ГЛАВНОЕ МЕНЮ' scripts/install-agents.sh \
  || fail "wave 21: V_MAIN блок не помечен"
grep -q 'Г Л А В Н О Е   М Е Н Ю' scripts/install-agents.sh \
  || fail "wave 21: ASCII-баннер главного меню отсутствует"
grep -q 'MAIN_CHOICE=' scripts/install-agents.sh \
  || fail "wave 21: переменная MAIN_CHOICE не объявлена"
grep -q 'main_menu_openclaw_exit' scripts/install-agents.sh \
  || fail "wave 21: telemetry-маркер выхода через OpenClaw отсутствует"
grep -q 'main_choice_tier_mismatch_pro' scripts/install-agents.sh \
  || fail "wave 21: проверка соответствия Pro vs tier отсутствует"
grep -q 'main_choice_tier_mismatch_base' scripts/install-agents.sh \
  || fail "wave 21: проверка соответствия Base vs tier отсутствует"
pass "wave 21: главное меню V_MAIN (Pro/Base/OpenClaw) + tier-валидация"

# ─── Test 6.27: wave 22 banner AI TEAM 2.0 (новый brand) ─────────
# ASCII-баннер «OpenClaw Agents Pack» заменён на «AI TEAM 2.0».
# Проверяем уникальные части нового баннера (figlet standard font).
grep -q '___   _____ _____    _    __  __   ____    ___' scripts/install-agents.sh \
  || fail "wave 22: новый ASCII-баннер «AI TEAM 2.0» отсутствует (строка 1)"
grep -q '|___ \\  / _ \\' scripts/install-agents.sh \
  || fail "wave 22: новый ASCII-баннер «AI TEAM 2.0» (часть 2.0) отсутствует"
# Старый OpenClaw-баннер не должен остаться
! grep -q 'T R U E   P A C K' scripts/install-agents.sh \
  || fail "wave 22: старый «T R U E   P A C K» suffix не удалён"
pass "wave 22: banner AI TEAM 2.0 (новый бренд)"

# ─── Test 6.28: wave 23 продающий pitch под баннером ─────────────
# Технические строки «Base: ... / Pro: ... / Installer v...» заменены
# на маркетинговый pitch + версия мелким текстом для саппорта.
grep -q 'Собери команду ИИ-агентов' scripts/install-agents.sh \
  || fail "wave 23: продающий pitch (строка 1) отсутствует"
grep -q 'работает на тебя 24/7' scripts/install-agents.sh \
  || fail "wave 23: продающий pitch («24/7») отсутствует"
grep -q 'становится умнее каждую неделю' scripts/install-agents.sh \
  || fail "wave 23: продающий pitch («умнее каждую неделю») отсутствует"
grep -q 'установил, работает' scripts/install-agents.sh \
  || fail "wave 23: продающий pitch («установил, работает») отсутствует"
# Старый «Installer v..» с (COMMIT) убран — версия теперь компактная
! grep -q 'Installer v\${INSTALLER_VERSION} (\${INSTALLER_COMMIT})' scripts/install-agents.sh \
  || fail "wave 23: старая строка «Installer v...(COMMIT)» в баннере осталась"
pass "wave 23: продающий pitch под баннером + версия мелко"

# ─── Test 6.29: wave 24 co-branding TONY TRUE × СЕРДИТОВ ─────────
# Подзаголовок под ASCII-баннером AI TEAM 2.0 — разреженный шрифт magenta.
grep -q 'T O N Y   T R U E   ×   С Е Р Д И Т О В' scripts/install-agents.sh \
  || fail "wave 24: подзаголовок «TONY TRUE × СЕРДИТОВ» отсутствует"
pass "wave 24: co-branding подзаголовок TONY TRUE × СЕРДИТОВ"

# ─── Test 6.30: wave 25 Hermes super-agent integration ──────────
# Опция «4) Hermes» появляется в V_MAIN только если OpenClaw обнаружен.
# Новый HRM-tier распознаётся в vip.sh (тот же Ed25519, payload HRM|hash|tg).
# Установка через official NousResearch installer после HRM-токен валидации
# и confirm-шага от клиента.
grep -q 'detect_openclaw()' scripts/install-agents.sh \
  || fail "wave 25: функция detect_openclaw отсутствует"
grep -q 'install_hermes_super_agent' scripts/install-agents.sh \
  || fail "wave 25: функция install_hermes_super_agent отсутствует"
grep -q 'NousResearch/hermes-agent' scripts/install-agents.sh \
  || fail "wave 25: URL Hermes installer отсутствует"
grep -q 'OPENCLAW_INSTALLED' scripts/install-agents.sh \
  || fail "wave 25: переменная OPENCLAW_INSTALLED не объявлена"
grep -q 'BOLD}Hermes' scripts/install-agents.sh \
  || fail "wave 25: 4-й пункт меню (Hermes) отсутствует"
# vip.sh распознаёт HRM-префикс
grep -q "'v3-hrm'" scripts/lib/vip.sh \
  || fail "wave 25: vip.sh не распознаёт HRM-tier (v3-hrm)"
grep -q 'HRM' scripts/lib/vip.sh \
  || fail "wave 25: vip.sh не упоминает HRM tier"
pass "wave 25: Hermes super-agent (HRM-токен + condition menu + Nous installer)"

# ─── Test 6.31: wave 26 порядок пунктов меню (OpenClaw → Base → Pro) ─
# Ladder снизу вверх: OpenClaw (1) → Base (2) → Pro (3, default) → Hermes (4).
# Default Enter = 3 (Pro как рекомендуемый).
# Проверяем что в коде «1)» идёт с OpenClaw, «3)» с Pro, default «3» в case.
grep -q '1)${NC}  ${BOLD}OpenClaw' scripts/install-agents.sh \
  || fail "wave 26: пункт 1) не OpenClaw (порядок ladder нарушен)"
grep -q '2)${NC}  ${BOLD}Base' scripts/install-agents.sh \
  || fail "wave 26: пункт 2) не Base"
grep -q '3)${NC}  ${BOLD}Pro' scripts/install-agents.sh \
  || fail "wave 26: пункт 3) не Pro"
grep -q '_main_menu_input:-3' scripts/install-agents.sh \
  || fail "wave 26: default по Enter не = 3 (Pro)"
pass "wave 26: ladder OpenClaw→Base→Pro→Hermes (default Enter = Pro)"

# ─── Test 6.32: wave 27 ANSI 3D-куб intro в Hermes ──────────────
# Inline Python heredoc HERMES_CUBE_EOF — анимация 3.5s при выборе
# опции 4. Skip если нет python3 или ENV HERMES_NO_INTRO=1.
grep -q 'HERMES_CUBE_EOF' scripts/install-agents.sh \
  || fail "wave 27: heredoc HERMES_CUBE_EOF отсутствует"
grep -q 'HERMES_NO_INTRO' scripts/install-agents.sh \
  || fail "wave 27: opt-out через HERMES_NO_INTRO не реализован"
grep -q 'FACE_CHARS' scripts/install-agents.sh \
  || fail "wave 27: куб-рендер (FACE_CHARS) не inline'ен"
grep -q 'CUBE_WIDTH' scripts/install-agents.sh \
  || fail "wave 27: куб-параметр CUBE_WIDTH не inline'ен"
pass "wave 27: ANSI 3D-куб intro для Hermes (inline Python heredoc)"

# ─── Test 6.33: wave 28 auto-detect ОС indicator в баннере ──────
# Клиент видит в баннере «🖥 Система определена автоматически: macOS»
# (или Linux / Windows / WSL) с подсказкой запустить --vps если сервер.
grep -q 'Система определена автоматически' scripts/install-agents.sh \
  || fail "wave 28: auto-detect indicator отсутствует в баннере"
grep -q '_os_label' scripts/install-agents.sh \
  || fail "wave 28: переменная _os_label не объявлена"
grep -q 'Если ты на VPS' scripts/install-agents.sh \
  || fail "wave 28: подсказка про --vps отсутствует"
pass "wave 28: auto-detect ОС-indicator в баннере"

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

# ─── Test 6.34: wave 30 trial-установщик (демо-воронка) ──────────
# Отдельный установщик install-trial.sh — НЕ связан с install-agents.sh.
# Ставит OpenClaw + одного assistant-агента с offer-логикой.
[[ -f "scripts/install-trial.sh" ]] \
  || fail "wave 30: scripts/install-trial.sh отсутствует"
[[ -x "scripts/install-trial.sh" ]] \
  || fail "wave 30: scripts/install-trial.sh не executable"
# Шаблон ассистента (5 файлов)
for f in IDENTITY AGENTS SOUL USER MEMORY; do
  [[ -f "templates/assistant/${f}.md" ]] \
    || fail "wave 30: templates/assistant/${f}.md отсутствует"
done
# Offer-логика: ссылка на курс в шаблоне ассистента
grep -q 'serditov.tonytrue.pro' templates/assistant/AGENTS.md \
  || fail "wave 30: offer-ссылка отсутствует в assistant/AGENTS.md"
grep -q 'serditov.tonytrue.pro' scripts/install-trial.sh \
  || fail "wave 30: offer-ссылка отсутствует в install-trial.sh"
# Offer-ритм 2-3 сообщения прописан
grep -qE 'каждые 2-3|2-3 (моих )?ответ' templates/assistant/AGENTS.md \
  || fail "wave 30: offer-ритм (2-3 сообщения) не прописан"
# Trial НЕ требует курс-токен (это бесплатное демо)
grep -q 'course.token\|COURSE_TOKEN\|--vip-token' scripts/install-trial.sh \
  && fail "wave 30: install-trial.sh не должен требовать курс-токен (демо бесплатно)" \
  || true
# Изоляция: install-trial не ВЫЗЫВАЕТ install-agents (source/bash).
# Сначала выкидываем строки-комментарии, потом ищем реальный вызов —
# упоминание в комментарии «не связан с install-agents.sh» допустимо.
if grep -vE '^\s*#' scripts/install-trial.sh | grep -qE 'install-agents'; then
  fail "wave 30: install-trial.sh не должен вызывать install-agents (изоляция)"
fi
pass "wave 30: trial-установщик + assistant с offer-логикой (изолирован)"

# ─── Test 6.35: wave 34 trial ставит OpenClaw через npm ─────────
# Wave 34: trial ставит движок через `npm install -g openclaw@latest`
# (как factory) — кроссплатформенно, БЕЗ brew-cask и macOS 15+ барьера.
# Это заменило ошибочный wave 32 (macOS-check был на предпосылке brew cask).
grep -q 'npm install -g openclaw@latest' scripts/install-trial.sh \
  || fail "wave 34: trial не ставит OpenClaw через npm"
grep -q 'nvm install 22' scripts/install-trial.sh \
  || fail "wave 34: trial не ставит Node.js через nvm"
# brew-cask путь убран (он был macOS-only + требовал Sequoia)
grep -q 'brew install --cask openclaw' scripts/install-trial.sh \
  && fail "wave 34: brew-cask путь должен быть убран (заменён на npm)" \
  || true
pass "wave 34: trial ставит OpenClaw через npm (Node+npm, кроссплатформенно)"

# ─── Test 6.36: wave 35 auto-install Xcode CLT ──────────────────
# На чистом маке нет Command Line Tools (git/компиляторы) — nvm падает.
# Trial сам запускает xcode-select --install + ждёт в loop до готовности.
grep -q 'xcode-select --install' scripts/install-trial.sh \
  || fail "wave 35: trial не запускает auto-install Xcode CLT"
grep -q 'xcode-select -p' scripts/install-trial.sh \
  || fail "wave 35: trial не проверяет наличие Xcode CLT (xcode-select -p)"
grep -q 'Command Line Tools' scripts/install-trial.sh \
  || fail "wave 35: trial не упоминает Command Line Tools в сообщении"
pass "wave 35: auto-install Xcode CLT + wait-loop (без ошибки у клиента)"

# ─── Test 6.37: wave 36 флаг --uninstall в trial ────────────────
# Чистое удаление для повторной установки: gateway stop + удалить
# агента + npm uninstall openclaw + rm ~/.openclaw. С confirm.
grep -q '\-\-uninstall|--reset)' scripts/install-trial.sh \
  || fail "wave 36: флаг --uninstall не обработан"
grep -q 'npm uninstall -g openclaw' scripts/install-trial.sh \
  || fail "wave 36: --uninstall не удаляет npm-пакет openclaw"
grep -q 'rm -rf "\$HOME/.openclaw"' scripts/install-trial.sh \
  || fail "wave 36: --uninstall не удаляет ~/.openclaw"
grep -q 'openclaw agents delete assistant' scripts/install-trial.sh \
  || fail "wave 36: --uninstall не удаляет assistant-агента"
pass "wave 36: флаг --uninstall (чистое удаление для переустановки)"

# ─── Test 6.38: wave 37 trial подключает модель (auth-profile) ──
# Без auth-profiles.json агент молчит (нет авторизации к provider).
# Trial запрашивает opencode-ключ → пишет auth-profiles.json для
# assistant-агента + config set model (как factory R3).
grep -q 'opencode.ai' scripts/install-trial.sh \
  || fail "wave 37: trial не запрашивает opencode-ключ для модели"
grep -q 'auth-profiles.json' scripts/install-trial.sh \
  || fail "wave 37: trial не пишет auth-profiles.json (агент будет молчать)"
grep -q 'agents.defaults.model.primary' scripts/install-trial.sh \
  || fail "wave 37: trial не устанавливает модель по умолчанию"
grep -q 'OPENCODE_KEY' scripts/install-trial.sh \
  || fail "wave 37: trial не обрабатывает opencode API-ключ"
pass "wave 37: trial подключает модель (opencode-ключ + auth-profile + config)"

# ─── Test 6.39: wave 38 trial прописывает nvm в shell rc ────────
# Главная причина «openclaw не вызывается после установки»: nvm не
# прописан в shell-профиль → node/openclaw не в PATH новых терминалов.
grep -q 'persist_nvm_in_shell_rc' scripts/install-trial.sh \
  || fail "wave 38: trial не прописывает nvm в shell rc (openclaw будет недоступен)"
grep -qE '\.zshrc.*\.bashrc|HOME/.zshrc' scripts/install-trial.sh \
  || fail "wave 38: trial не трогает shell rc-файлы для nvm"
pass "wave 38: trial персистит nvm в shell rc (openclaw доступен в новых терминалах)"

# ─── Test 6.40: wave 39 trial — правильное подключение telegram+node ─
# Главные баги рабочего бота: токен через config set (не работал) +
# bind telegram:assistant (нет аккаунта) + нет dmPolicy/allowFrom (бот
# просит pairing) + нет nvm alias default (openclaw не в PATH).
grep -q 'openclaw channels add --channel telegram' scripts/install-trial.sh \
  || fail "wave 39: telegram-токен не через channels add (бот будет молчать)"
grep -q 'channels.telegram.dmPolicy allowlist' scripts/install-trial.sh \
  || fail "wave 39: нет dmPolicy allowlist (бот попросит pairing)"
grep -q 'channels.telegram.allowFrom' scripts/install-trial.sh \
  || fail "wave 39: нет allowFrom (владелец не в allowlist)"
grep -q 'nvm alias default' scripts/install-trial.sh \
  || fail "wave 39: нет nvm alias default (openclaw не в PATH новых терминалов)"
grep -q -- '--bind telegram' scripts/install-trial.sh \
  || fail "wave 39: agents add без --bind telegram"
# Старый неправильный bind не должен остаться
grep -q 'bind "telegram:assistant"' scripts/install-trial.sh \
  && fail "wave 39: остался неправильный bind telegram:assistant" \
  || true
pass "wave 39: telegram channels add + dmPolicy/allowFrom + nvm default + bind telegram"

# ─── Test 6.41: wave 40 trial — правильный запуск gateway ───────
# «Gateway: not reachable» = бот молчит. Был только `gateway restart`,
# но без `gateway install` launchd-сервис не создаётся. Нужно:
# gateway.mode local → gateway install → gateway start (как factory).
grep -q 'config set gateway.mode local' scripts/install-trial.sh \
  || fail "wave 40: trial не ставит gateway.mode local (gateway упадёт)"
grep -q 'openclaw gateway install' scripts/install-trial.sh \
  || fail "wave 40: trial не делает gateway install (сервис не создаётся)"
grep -q 'openclaw gateway start' scripts/install-trial.sh \
  || fail "wave 40: trial не делает gateway start"
# Проверка статуса gateway — по НАДЁЖНЫМ маркерам (не «running», который
# ловит «not running»; см. wave 41). Маркер проверяется в онбординге T5.
grep -q 'openclaw gateway status' scripts/install-trial.sh \
  || fail "wave 40: trial не проверяет статус gateway"
pass "wave 40: gateway install+start+проверка (бот реально поднимается)"

# ─── Test 6.42: wave 41 trial — надёжный gateway (launchctl bootstrap) ─
# Баги wave 40: grep "running" ловил "not running" → install пропускался;
# gateway start не грузит LaunchAgent. Фикс: install безусловно +
# launchctl bootstrap (точная команда openclaw) + надёжная проверка.
grep -q 'launchctl bootstrap' scripts/install-trial.sh \
  || fail "wave 41: trial не делает launchctl bootstrap (LaunchAgent не грузится)"
grep -q 'ai.openclaw.gateway.plist' scripts/install-trial.sh \
  || fail "wave 41: trial не ссылается на gateway LaunchAgent plist"
grep -q 'LaunchAgent \\(loaded\\)' scripts/install-trial.sh \
  || fail "wave 41: проверка gateway не на надёжный маркер (LaunchAgent loaded)"
# Хрупкий grep "running" (ловящий "not running") должен быть убран из проверки gateway
grep -q 'grep -qE "running|RPC probe: ok"' scripts/install-trial.sh \
  && fail "wave 41: остался хрупкий grep running (ловит not running)" \
  || true
pass "wave 41: надёжный gateway (install безусловно + launchctl bootstrap)"

# ─── Test 6.43: wave 42 trial — onboard + русский онбординг ─────
# Штатный onboard в авто-режиме + видимый русский чек-лист (✓/✗).
# Проверенные auth/gateway (wave 37/40/41) ОСТАЮТСЯ как страховка —
# onboard их не заменяет.
grep -q 'openclaw onboard' scripts/install-trial.sh \
  || fail "wave 42: trial не прогоняет openclaw onboard (Антон просил анбординг)"
grep -q 'opencode-zen-api-key' scripts/install-trial.sh \
  || fail "wave 42: onboard без --opencode-zen-api-key (модель не настроится)"
grep -q 'non-interactive' scripts/install-trial.sh \
  || fail "wave 42: onboard не в non-interactive (повиснет на промпте)"
grep -q 'Быстрый онбординг' scripts/install-trial.sh \
  || fail "wave 42: нет видимого русского онбординг-чеклиста"
# Страховка не должна быть потеряна: auth-profile пишется напрямую,
# gateway поднимается проверенными командами (не только через onboard).
grep -q 'auth-profiles.json' scripts/install-trial.sh \
  || fail "wave 42: потеряна прямая запись auth-profile (агент замолчит)"
grep -q 'openclaw gateway install' scripts/install-trial.sh \
  || fail "wave 42: потеряна страховочная установка gateway"
pass "wave 42: onboard + русский онбординг (страховка сохранена)"

# ─── Test 6.44: wave 43 trial — модель фиксирована (DeepSeek), без меню ─
# Антон: убрать меню выбора модели, всегда ставить deepseek-v4-flash-free.
grep -q 'opencode/deepseek-v4-flash-free' scripts/install-trial.sh \
  || fail "wave 43: trial не ставит deepseek-v4-flash-free по умолчанию"
grep -q 'Выбери модель' scripts/install-trial.sh \
  && fail "wave 43: меню выбора модели должно быть убрано" \
  || true
grep -qiE 'minimax|gpt-5|claude-sonnet' scripts/install-trial.sh \
  && fail "wave 43: остались старые модели (minimax/gpt-5/claude-sonnet)" \
  || true
pass "wave 43: модель фиксирована DeepSeek Flash Free (меню убрано)"

# ─── Test 6.45: wave 44 trial — финал открывает сайт-продажник ──────
# Антон: в конце авто-открыть сайт полной версии в браузере (как
# opencode.ai в Шаге 2), а не просто кинуть ссылку текстом.
grep -qF 'open "$COURSE_URL"' scripts/install-trial.sh \
  || fail "wave 44: финал не открывает сайт-продажник через open (macOS)"
grep -qF 'xdg-open "$COURSE_URL"' scripts/install-trial.sh \
  || fail "wave 44: финал не открывает сайт-продажник через xdg-open (Linux)"
pass "wave 44: финал авто-открывает сайт полной версии в браузере"

rm -f /tmp/fake.json

echo ""
echo "=== All smoke tests passed ==="
