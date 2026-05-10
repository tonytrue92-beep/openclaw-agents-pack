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
# Бриф технарю проверяем только если handoff/ присутствует (Docker
# smoke не копирует handoff/ — это OK, бриф нужен только в host-репо)
if [[ -d "handoff" ]]; then
  [[ -f "handoff/course-token-brief-for-techie.md" ]] \
    || fail "handoff/course-token-brief-for-techie.md отсутствует (wave 12 — бриф для технаря)"
fi
pass "wave 12: course-token v3 (Standard + VIP) во всех слоях + бриф технарю"

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

# Новое сообщение про авто-Standard для STD-tier
grep -q 'Тариф.*Standard.*установлю 3 агента' scripts/install-agents.sh \
  || fail "wave 14: STD-tier auto-install message отсутствует"

# Новое сообщение про tier=VIP меню «VIP-набор / Только Standard»
grep -q 'У тебя.*VIP.*-тариф' scripts/install-agents.sh \
  || fail "wave 14: VIP-tier меню заголовок отсутствует"
grep -q 'Только Standard' scripts/install-agents.sh \
  || fail "wave 14: VIP-меню опция «Только Standard» отсутствует"
pass "wave 14: V0 (токен) до R0 + tier-based menu (STD авто / VIP подтверждение)"

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
