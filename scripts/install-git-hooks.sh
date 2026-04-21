#!/usr/bin/env bash
# Активирует version-controlled git hooks из папки .githooks/.
#
# Запускается ОДИН раз после клонирования репо:
#   bash scripts/install-git-hooks.sh
#
# Что делает: git config core.hooksPath .githooks
# Результат: git при каждом commit начинает использовать .githooks/pre-commit,
# который блокирует случайный коммит sk-* / Telegram-токенов / Bearer-токенов.

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -d .githooks ]]; then
  echo "✗ .githooks/ не найдена в $(pwd)"
  echo "  Убедитесь что запускаете из корня репо (или из scripts/)."
  exit 1
fi

# Активируем hooks из версионируемой директории
git config core.hooksPath .githooks

# Делаем hook исполняемым (на случай если git не сохранил executable bit)
chmod +x .githooks/*

echo "✓ Git hooks активированы: core.hooksPath = .githooks"
echo ""
echo "Теперь при каждом 'git commit' автоматически запускается"
echo "  .githooks/pre-commit — сканирует staged-файлы на утечку секретов"
echo "  (sk-* API keys, Telegram bot tokens, Bearer tokens)."
echo ""
echo "Обойти hook (только в крайнем случае):"
echo "  git commit --no-verify"
