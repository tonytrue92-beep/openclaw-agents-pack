#!/usr/bin/env bash
# debug-bundle.sh — redact_secrets + collect_debug_bundle + on_installer_error.
# Vendored из openclaw-factory. Дополнительно собирает templates-папки агентов
# для диагностики (IDENTITY/AGENTS/MEMORY/USER у всех трёх).

# ─── redact_secrets ──────────────────────────────────────────────
#
# Маскирует в файле типовые секреты: sk-ключи, TG tokens (цифры:буквы),
# Bearer, password-подобные поля JSON. Работает in-place.
redact_secrets() {
  local file="$1"
  [[ ! -f "$file" ]] && return 0
  grep -Iq . "$file" 2>/dev/null || return 0  # skip binary

  local tmp
  tmp=$(mktemp -t openclaw-redact.XXXXXX)

  sed -E \
    -e 's/sk-[A-Za-z0-9_-]{20,}/sk-[REDACTED]/g' \
    -e 's/[0-9]{8,12}:[A-Za-z0-9_-]{30,}/[TG_TOKEN_REDACTED]/g' \
    -e 's/([Bb]earer )[A-Za-z0-9._-]+/\1[REDACTED]/g' \
    -e 's/("(key|token|password|secret|apiKey|api_key|botToken)"[[:space:]]*:[[:space:]]*")[^"]*(")/\1[REDACTED]\3/g' \
    "$file" > "$tmp"

  mv "$tmp" "$file"
}

# ─── collect_debug_bundle ───────────────────────────────────────
collect_debug_bundle() {
  local reason="${1:-manual}"
  local ts
  ts=$(date +%Y%m%d-%H%M%S)
  local bundle_dir
  bundle_dir=$(mktemp -d -t openclaw-debug.XXXXXX)
  local bundle_name="openclaw-agents-pack-debug-${ts}"
  local bundle_path="${bundle_dir}/${bundle_name}"
  mkdir -p "$bundle_path"

  # ─── Manifest ───
  cat > "${bundle_path}/MANIFEST.txt" <<MANIFEST
OpenClaw Agents Pack — Debug Bundle
====================================
Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Reason: ${reason}
Installer: v${INSTALLER_VERSION:-dev} (${INSTALLER_COMMIT:-dev})

System:
  $(uname -a 2>&1 || echo 'uname failed')

Versions:
  node: $(command -v node >/dev/null && node -v 2>&1 || echo 'not installed')
  npm:  $(command -v npm >/dev/null && npm -v 2>&1 || echo 'not installed')
  openclaw: $(command -v openclaw >/dev/null && openclaw --version 2>&1 | head -1 || echo 'not installed')

Contents:
  - MANIFEST.txt               — этот файл
  - system-info.txt            — uname, disk space, admin check, xcode-select
  - openclaw-config.json       — ~/.openclaw/openclaw.json (секреты замаскированы)
  - openclaw-status.txt        — openclaw status --all
  - openclaw-agents.txt        — openclaw agents list
  - openclaw-bindings.txt      — openclaw agents bindings
  - openclaw-channels.txt      — openclaw channels list
  - workspace-tech/*.md        — содержимое workspace технаря (секреты замаскированы)
  - workspace-marketer/*.md    — содержимое workspace маркетолога
  - workspace-producer/*.md    — содержимое workspace продюсера
  - gateway.log                — последние 200 строк gateway log (секреты замаскированы)

IMPORTANT: все секреты (API keys, Telegram tokens) автоматически заменены на
[REDACTED]. Всё же просмотрите файлы перед отправкой в саппорт.
MANIFEST

  # ─── Система ───
  {
    echo "=== uname -a ==="
    uname -a 2>&1 || true
    echo ""
    echo "=== sw_vers (macOS) ==="
    sw_vers 2>&1 || true
    echo ""
    echo "=== Disk (\$HOME) ==="
    df -h "$HOME" 2>&1 || true
    echo ""
    echo "=== PATH ==="
    echo "$PATH"
    echo ""
    echo "=== xcode-select -p ==="
    xcode-select -p 2>&1 || echo 'not found'
  } > "${bundle_path}/system-info.txt" 2>&1

  # ─── OpenClaw конфиг и состояние ───
  if [[ -f "$HOME/.openclaw/openclaw.json" ]]; then
    cp "$HOME/.openclaw/openclaw.json" "${bundle_path}/openclaw-config.json"
    redact_secrets "${bundle_path}/openclaw-config.json"
  else
    echo "(no ~/.openclaw/openclaw.json)" > "${bundle_path}/openclaw-config.json"
  fi

  if command -v openclaw &>/dev/null; then
    openclaw status --all > "${bundle_path}/openclaw-status.txt" 2>&1 || true
    openclaw agents list > "${bundle_path}/openclaw-agents.txt" 2>&1 || true
    openclaw agents bindings > "${bundle_path}/openclaw-bindings.txt" 2>&1 || true
    openclaw channels list > "${bundle_path}/openclaw-channels.txt" 2>&1 || true
  fi

  # ─── Workspace-папки трёх агентов ───
  for agent in tech marketer producer; do
    local ws="$HOME/.openclaw/workspace-${agent}"
    if [[ -d "$ws" ]]; then
      mkdir -p "${bundle_path}/workspace-${agent}"
      # Копируем только .md файлы (без бинарников, без media)
      for md in "$ws"/*.md; do
        [[ -f "$md" ]] || continue
        cp "$md" "${bundle_path}/workspace-${agent}/"
      done
    fi
  done

  # ─── Gateway logs ───
  if [[ -d "$HOME/.openclaw/logs" ]]; then
    local latest_log
    latest_log=$(ls -t "$HOME/.openclaw/logs/"*.log 2>/dev/null | head -1)
    if [[ -n "$latest_log" && -f "$latest_log" ]]; then
      tail -200 "$latest_log" > "${bundle_path}/gateway.log"
    fi
  fi

  # ─── Маскируем всё что копировалось ───
  # (страховка — хотя в шаблонах и так секретов нет)
  find "${bundle_path}" -type f \( -name "*.txt" -o -name "*.json" -o -name "*.log" -o -name "*.md" \) | while read -r f; do
    redact_secrets "$f"
  done

  # ─── Архив ───
  local archive_path="$HOME/${bundle_name}.zip"
  if command -v zip &>/dev/null; then
    (cd "$bundle_dir" && zip -qr "$archive_path" "$bundle_name" 2>/dev/null) || {
      archive_path="$HOME/${bundle_name}.tar.gz"
      tar -czf "$archive_path" -C "$bundle_dir" "$bundle_name" 2>/dev/null || true
    }
  else
    archive_path="$HOME/${bundle_name}.tar.gz"
    tar -czf "$archive_path" -C "$bundle_dir" "$bundle_name" 2>/dev/null || true
  fi

  rm -rf "$bundle_dir" 2>/dev/null

  if [[ -f "$archive_path" ]]; then
    echo ""
    echo -e "   ${BOLD}${CYAN}📦 Debug-bundle agents-pack собран:${NC}"
    echo -e "   ${GREEN}${archive_path}${NC}"
    echo -e "   ${DIM}Размер: $(du -h "$archive_path" | cut -f1)${NC}"
    echo ""
    echo -e "   ${BOLD}${WHITE}Что дальше:${NC}"
    echo -e "   ${CYAN}1.${NC} Пришлите файл в саппорт курса"
    echo -e "   ${CYAN}2.${NC} Секреты замаскированы — но если волнуетесь, просмотрите сами"
    echo ""
  fi
}

# Error handler
on_installer_error() {
  local exit_code=$?
  local line_no="${1:-?}"

  if [[ "${DRY_RUN:-false}" == true ]]; then return $exit_code; fi
  if [[ $exit_code -eq 130 ]]; then return $exit_code; fi

  echo ""
  echo -e "   ${BOLD}${RED}━━━ agents-pack остановился (exit=${exit_code}, line=${line_no}) ━━━${NC}"
  echo ""
  echo -e "   ${DIM}Собираю debug-bundle для саппорта...${NC}"
  collect_debug_bundle "error exit=${exit_code} at line ${line_no}" || true
  return $exit_code
}
