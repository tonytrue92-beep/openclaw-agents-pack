#!/usr/bin/env bash
# Регенерация SHA256SUMS для всех публичных скриптов.
#
# Запускается: bash scripts/update-checksums.sh
# Результат: файл SHA256SUMS в корне репо.
# CI проверяет свежесть и падает, если расходится — запусти скрипт и закоммить.

set -euo pipefail

cd "$(dirname "$0")/.."

OUT="SHA256SUMS"
TMP=$(mktemp)

echo "# SHA-256 checksums for OpenClaw Agents Pack" > "$TMP"
echo "# Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> "$TMP"
echo "# Commit: $(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')" >> "$TMP"
echo "#" >> "$TMP"
echo "# Verify a downloaded script matches the committed version:" >> "$TMP"
echo "#   curl -fsSL <raw-url> | shasum -a 256" >> "$TMP"
echo "#   (or on Linux: sha256sum <file>)" >> "$TMP"
echo "#" >> "$TMP"
echo "" >> "$TMP"

if command -v sha256sum &>/dev/null; then
  HASHER="sha256sum"
elif command -v shasum &>/dev/null; then
  HASHER="shasum -a 256"
else
  echo "ERROR: не найден ни sha256sum, ни shasum" >&2
  exit 1
fi

# Хэшируем все скрипты + все шаблоны
for f in scripts/*.sh scripts/lib/*.sh templates/*/*.md; do
  $HASHER "$f" >> "$TMP"
done

mv "$TMP" "$OUT"

echo "✓ Обновлён: $OUT"
cat "$OUT"
