#!/usr/bin/env bash
# build-bundle.sh — собирает self-contained `install-agents-bundled.sh`
# из `scripts/install-agents.sh` + всех `scripts/lib/*.sh`.
#
# Зачем: при `bash <(curl raw.githubusercontent…)` установщик второй
# раз дёргает curl чтобы скачать 6 lib-файлов. На корпоративных сетях
# / VPS / медленном интернете это ломается (BUG-06 из техотчёта 2026-04-26).
# Bundled-вариант — один файл, никаких nested curl.
#
# Workflow использования:
#   1. Локально: `bash scripts/build-bundle.sh` → `dist/install-agents-bundled.sh`
#   2. CI на тег v2026.*.* запускает этот скрипт и публикует
#      bundled-файл как GitHub Release asset.
#   3. Клиент вызывает:
#      bash <(curl -fsSL https://github.com/…/releases/latest/download/install-agents-bundled.sh)
#
# Маркеры `=== BUNDLE_LIB_BEGIN ===` и `=== BUNDLE_LIB_END ===` в
# `install-agents.sh` ограничивают блок source/curl для lib/*. Build
# заменяет всё между ними на inline-контент 6 lib-файлов.

set -euo pipefail

cd "$(dirname "$0")/.."

OUT_DIR="dist"
OUT_FILE="${OUT_DIR}/install-agents-bundled.sh"
SRC="scripts/install-agents.sh"
LIB_DIR="scripts/lib"

# Порядок lib/*.sh важен — он повторяет порядок source-вызовов в install-agents.sh
LIB_ORDER=(ui preflight telemetry debug-bundle agents vip)

# ─── Sanity-checks ─────────────────────────────────────────────
if [[ ! -f "$SRC" ]]; then
  echo "ERROR: $SRC не найден. Запусти из корня репо: bash scripts/build-bundle.sh" >&2
  exit 1
fi

for mod in "${LIB_ORDER[@]}"; do
  if [[ ! -f "${LIB_DIR}/${mod}.sh" ]]; then
    echo "ERROR: ${LIB_DIR}/${mod}.sh не найден" >&2
    exit 1
  fi
done

if ! grep -q '=== BUNDLE_LIB_BEGIN ===' "$SRC"; then
  echo "ERROR: маркер === BUNDLE_LIB_BEGIN === не найден в $SRC" >&2
  echo "       Возможно блок lib-source был переписан без сохранения маркеров." >&2
  exit 1
fi

if ! grep -q '=== BUNDLE_LIB_END ===' "$SRC"; then
  echo "ERROR: маркер === BUNDLE_LIB_END === не найден в $SRC" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

# ─── Собираем bundle через временный файл ─────────────────────
TMP_BUNDLE=$(mktemp)
trap 'rm -f "$TMP_BUNDLE"' EXIT

# 1. Часть до маркера BUNDLE_LIB_BEGIN — печатаем всё включая строку маркера
awk '
  /=== BUNDLE_LIB_BEGIN ===/ { print; exit }
  { print }
' "$SRC" > "$TMP_BUNDLE"

# 2. Inline-контент lib/* — каждый файл с заголовком, без shebang
{
  echo ""
  echo "# ─── BUNDLED lib/* (wave 10 self-contained) ──────────────────────"
  echo "# Этот блок автогенерирован scripts/build-bundle.sh."
  echo "# Не редактируй вручную — изменения теряются при пересборке."
  echo "# Чтобы поменять lib-функции: правь scripts/lib/<mod>.sh, потом"
  echo "# запусти 'bash scripts/build-bundle.sh' из корня репо."
  echo ""

  for mod in "${LIB_ORDER[@]}"; do
    echo "# ─── inline: scripts/lib/${mod}.sh ──────────────────────────────"
    # Удаляем shebang (один на bundled-файл — в install-agents.sh).
    # Удаляем повторные `set -euo pipefail` (один на bundled-файл).
    # Сохраняем всё остальное как есть.
    sed -e '/^#!\/usr\/bin\/env bash[[:space:]]*$/d' \
        -e '/^set -euo pipefail[[:space:]]*$/d' \
        "${LIB_DIR}/${mod}.sh"
    echo ""
  done
} >> "$TMP_BUNDLE"

# 3. Часть после маркера BUNDLE_LIB_END — печатаем начиная со строки маркера
awk '
  found { print; next }
  /=== BUNDLE_LIB_END ===/ { print; found=1; next }
' "$SRC" >> "$TMP_BUNDLE"

# ─── Выходной файл с warning-headerom ──────────────────────────
{
  # Sanity: первая строка должна быть shebang из install-agents.sh
  head -1 "$TMP_BUNDLE"
  echo ""
  echo "# ═══════════════════════════════════════════════════════════════════════════"
  echo "# OpenClaw Agents Pack — SELF-CONTAINED BUNDLE"
  echo "#"
  echo "# Сгенерирован: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "# Source commit: $(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
  echo "#"
  echo "# Этот файл = scripts/install-agents.sh + scripts/lib/*.sh inline."
  echo "# Не зависит от raw.githubusercontent.com при выполнении."
  echo "# Используй когда корпоративная сеть / VPS режет HTTPS к GitHub raw."
  echo "#"
  echo "# Источник: https://github.com/tonytrue92-beep/openclaw-agents-pack"
  echo "# Не редактируй — все правки делай в исходниках, потом пересобери:"
  echo "#   bash scripts/build-bundle.sh"
  echo "# ═══════════════════════════════════════════════════════════════════════════"
  # Всё остальное содержимое (со 2-й строки)
  tail -n +2 "$TMP_BUNDLE"
} > "$OUT_FILE"

chmod +x "$OUT_FILE"

# ─── Sanity check: bundled-файл должен сам пройти bash -n ─────
if ! bash -n "$OUT_FILE" 2>/dev/null; then
  echo "ERROR: bundled-файл $OUT_FILE не проходит bash -n" >&2
  echo "       Возможно повреждён один из lib-файлов или нарушены маркеры." >&2
  exit 1
fi

# ─── Финальный отчёт ─────────────────────────────────────────────
SRC_LINES=$(wc -l < "$SRC" | tr -d ' ')
OUT_LINES=$(wc -l < "$OUT_FILE" | tr -d ' ')
OUT_SIZE_KB=$(( $(wc -c < "$OUT_FILE") / 1024 ))

echo "✓ Bundle собран: $OUT_FILE"
echo "  Размер: ${OUT_SIZE_KB} KB"
echo "  install-agents.sh:        ${SRC_LINES} строк"
echo "  install-agents-bundled.sh: ${OUT_LINES} строк"
echo ""
echo "Тестовый запуск (без побочных эффектов):"
echo "  bash $OUT_FILE --version"
echo "  bash $OUT_FILE --help"
echo ""
echo "Команда для клиента (после публикации в GitHub Releases):"
echo "  bash <(curl -fsSL https://github.com/tonytrue92-beep/openclaw-agents-pack/releases/latest/download/install-agents-bundled.sh)"
