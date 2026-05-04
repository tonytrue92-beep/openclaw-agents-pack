#!/usr/bin/env bash
# build-dmg.sh — собирает macOS DMG-установщик из dmg-template/.
#
# Wave 13: новый канал доставки для не-технических macOS-клиентов.
# Двойной клик по .command файлу внутри DMG → запускает Terminal с
# уже вставленной командой установки. Без копи-паста, без страшного
# bash <(curl ...).
#
# Это локальный сборщик. CI вызывает его в release.yml на macos-latest
# при push тега v2026.*. Output: `dist/OpenClaw-Setup.dmg` + .sha256.
#
# Зависимости: hdiutil (стандартная macOS-утилита, входит в /usr/bin).
# Не работает на Linux/Windows — там используй scripts/build-bundle.sh
# для Linux и нативный Windows installer для Windows.
#
# Usage:
#   bash scripts/build-dmg.sh

set -euo pipefail

cd "$(dirname "$0")/.."

OUT_DIR="dist"
DMG_NAME="OpenClaw-Setup.dmg"
VOLUME_NAME="OpenClaw Setup"

# ─── Sanity-check: только macOS ─────────────────────────────────
# hdiutil существует только на macOS. На Linux/CI запускай этот
# скрипт через runs-on: macos-latest.
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: build-dmg.sh работает только на macOS (нужен hdiutil)." >&2
  echo "       Текущая ОС: $(uname -s)" >&2
  echo "       На Linux/CI запускай через runs-on: macos-latest." >&2
  exit 1
fi

# ─── Sanity-check: dmg-template/ существует ─────────────────────
if [[ ! -d dmg-template ]]; then
  echo "ERROR: dmg-template/ не найдена. Запусти из корня репо:" >&2
  echo "       cd /path/to/openclaw-agents-pack && bash scripts/build-dmg.sh" >&2
  exit 1
fi

REQUIRED_FILES=(
  "dmg-template/1-Установить-OpenClaw.command"
  "dmg-template/2-Установить-AI-команду.command"
  "dmg-template/README.txt"
)
for f in "${REQUIRED_FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: $f отсутствует в dmg-template/" >&2
    exit 1
  fi
done

# ─── Создаём временную папку для сборки ─────────────────────────
TEMP_BUILD=$(mktemp -d -t openclaw-dmg-build.XXXXXX)
trap 'rm -rf "$TEMP_BUILD"' EXIT

# ─── Копируем шаблон + ставим chmod +x ──────────────────────────
cp -R dmg-template/* "$TEMP_BUILD/"

# .command файлы должны быть executable, иначе двойной клик не работает.
chmod +x "$TEMP_BUILD"/*.command

# ─── Собираем DMG через hdiutil ─────────────────────────────────
mkdir -p "$OUT_DIR"

# UDZO = compressed read-only (стандартный формат для distribution).
# -ov = overwrite если файл уже существует.
# -volname = имя тома в Finder когда смонтирован.
echo "Создаю DMG через hdiutil..."
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$TEMP_BUILD" \
  -ov \
  -format UDZO \
  "$OUT_DIR/$DMG_NAME" >/dev/null

# ─── Verify: DMG валидный + монтируется ─────────────────────────
echo "Проверяю целостность DMG..."
hdiutil verify "$OUT_DIR/$DMG_NAME" >/dev/null

# Тестовый mount + detach — убедиться что DMG реально монтируется
# и Finder увидит правильное содержимое.
echo "Тестирую mount/detach..."
mount_info=$(hdiutil attach -nobrowse -noverify -readonly "$OUT_DIR/$DMG_NAME" 2>&1)
mount_point=$(echo "$mount_info" | tail -1 | awk '{$1=$2=""; sub(/^[ \t]+/, ""); print}')
if [[ -z "$mount_point" || ! -d "$mount_point" ]]; then
  echo "ERROR: DMG не смонтировался корректно" >&2
  echo "$mount_info" >&2
  exit 1
fi

# Проверяем что внутри DMG лежат ожидаемые файлы
EXPECTED_IN_DMG=(
  "1-Установить-OpenClaw.command"
  "2-Установить-AI-команду.command"
  "README.txt"
)
for f in "${EXPECTED_IN_DMG[@]}"; do
  if [[ ! -f "${mount_point}/${f}" ]]; then
    hdiutil detach "$mount_point" >/dev/null 2>&1 || true
    echo "ERROR: файл '$f' не найден в смонтированном DMG" >&2
    exit 1
  fi
done

# Проверяем что .command файлы executable внутри DMG
for f in "${mount_point}/"*.command; do
  if [[ ! -x "$f" ]]; then
    hdiutil detach "$mount_point" >/dev/null 2>&1 || true
    echo "ERROR: $f не executable внутри DMG" >&2
    exit 1
  fi
done

# Размонтируем тестово
hdiutil detach "$mount_point" >/dev/null

# ─── SHA256 для целостности при скачивании ──────────────────────
cd "$OUT_DIR"
shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
cd ..

# ─── Финальный отчёт ────────────────────────────────────────────
DMG_SIZE=$(du -sh "$OUT_DIR/$DMG_NAME" | cut -f1)
DMG_SHA=$(awk '{print $1}' "$OUT_DIR/$DMG_NAME.sha256")

echo ""
echo "✓ DMG собран и проверен:"
echo "   Файл:    $OUT_DIR/$DMG_NAME"
echo "   Размер:  $DMG_SIZE"
echo "   SHA256:  $DMG_SHA"
echo ""
echo "Локальный тест:"
echo "   open $OUT_DIR/$DMG_NAME"
echo ""
echo "После публикации в GitHub Releases клиенты будут скачивать через:"
echo "   https://github.com/tonytrue92-beep/openclaw-agents-pack/releases/latest/download/OpenClaw-Setup.dmg"
