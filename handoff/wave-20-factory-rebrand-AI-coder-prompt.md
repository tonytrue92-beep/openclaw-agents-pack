# Промпт для AI-coder — Wave 20 rebrand в factory

**Кому**: технарю Антона, у которого открыт `openclaw-factory` репозиторий
**Что делать**: скопируй промпт ниже целиком и вставь в Cursor /
Claude Code / Aider. Агент закроет за 5 минут.

**Примечание**: этот промпт **только для factory**. Для бота
`@AITeamVIPBot` AI-coder не подойдёт — там нужно понимать структуру
кода бота. См. полный бриф: `wave-20-rebrand-brief.md`.

---

## ⤵️ Скопируй всё что между `BEGIN` и `END` и вставь в AI-coder

```
BEGIN PROMPT ─────────────────────────────────────────────────────

Ты работаешь в репозитории openclaw-factory. Задача: переименовать
тарифы на ПУБЛИЧНЫЕ названия в UI-выводе scripts/demo-install.sh.

═══ КОНТЕКСТ ═══

Антон зафиксировал публичный нейминг продуктовой линейки:

  Внутри (token-payload) → Публично (на экране клиента):
    SUB  →  OpenClaw
    STD  →  Base
    VIP  →  Pro

ВАЖНО: внутренний tier в payload-формате токена НЕ меняется
(SUB/STD/VIP). Backwards-compat 100% — старые токены продолжают
работать. Меняется ТОЛЬКО что клиент видит на экране.

В соседнем репо openclaw-agents-pack это уже сделано:
https://github.com/tonytrue92-beep/openclaw-agents-pack/pull/30/files

═══ ЧТО ДЕЛАТЬ ═══

1. Открой scripts/demo-install.sh.

2. Найди ВСЕ упоминания публичных названий тарифов в UI-выводе:

   grep -nE 'Standard|VIP|подписка|Subscription' scripts/demo-install.sh

3. Применяй замены ТОЛЬКО в строках которые попадают в вывод
   клиенту (echo / explain / printf / cat heredoc). НЕ трогай:

   - Комментарии в коде (#)
   - Внутренние переменные ($COURSE_TIER, $VIP_MODE, $SUB_MODE)
   - Параметры функций (verify_vip_token, _verify_v3_vip)
   - Имя бота @AITeamVIPBot (это бренд)
   - Префиксы токенов в технических примерах (формат VIP-XXX-...,
     STD-XXX-..., SUB-XXX-...)

4. Замены (в порядке убывания специфичности):

   "SUB-тариф (подписка)"   → "Тариф OpenClaw (подписка)"
   "Subscription"           → "OpenClaw" (если упоминается как тариф)
   "VIP-набор"              → "Pro-набор"
   "VIP-тариф"              → "Pro-тариф"
   "VIP" (в UI-контексте)   → "Pro"
   "Standard-набор"         → "Base-набор"
   "Standard-тариф"         → "Base-тариф"
   "Standard" (UI-контекст) → "Base"

   ОСТОРОЖНО с "VIP" — в строках типа "Получи VIP-токен в
   @AITeamVIPBot" замена "VIP-токен" → "Pro-токен" уместна,
   а "@AITeamVIPBot" — НЕ меняем.

5. Если есть упоминания старого 5-пунктового меню («Только Standard»,
   «Установить только одного», «Диагностика», «Debug-bundle») —
   проверь нужно ли тоже урезать до 3 пунктов. См. пример в
   agents-pack/install-agents.sh строки ~742-810.

6. Подними INSTALLER_VERSION в начале файла. Поставь "2026.05.25"
   (или текущая дата если позже).

7. Сделай `bash -n scripts/demo-install.sh` — должно пройти.

8. Если в репо есть smoke-test или CI — прогони локально.

9. Закоммить:

   Wave 20: публичные тарифы Base/Pro/OpenClaw в demo-install.sh

   В UI-выводе:
     • Standard → Base
     • VIP → Pro
     • SUB-тариф (подписка) → Тариф OpenClaw (подписка)

   Внутренние COURSE_TIER (STD/VIP/SUB) и token-payload НЕ меняются —
   backwards-compat 100%. Старые токены работают.

   Аналогично openclaw-agents-pack v2026.05.24 (wave 20).

10. Создай PR на main.

═══ ЧТО НЕ ДЕЛАТЬ ═══

- НЕ меняй внутренние переменные ($COURSE_TIER, $VIP_MODE и т.п.)
- НЕ меняй имя бота @AITeamVIPBot
- НЕ меняй формат токена / Ed25519-ключи / payload
- НЕ меняй параметры функций verify_vip_token и подобных
- НЕ меняй технические примеры в комментариях с префиксами VIP-/STD-/SUB-

═══ КАК ПРОВЕРИТЬ ЧТО РАБОТАЕТ ═══

После применения:

  # 1. Все UI-упоминания старых названий найдены и заменены:
  grep -nE 'Standard|"VIP|подписка|Subscription' scripts/demo-install.sh | \
    grep -v '^[[:space:]]*#'    # без комментариев

  # Должны остаться только: технические примеры в строках формата
  # токена (VIP-XXXXX-...), упоминания @AITeamVIPBot, и комментарии.

  # 2. bash -n проходит:
  bash -n scripts/demo-install.sh

  # 3. Help содержит новые названия:
  bash scripts/demo-install.sh --help | grep -iE 'Base|Pro|OpenClaw'

═══ REFERENCE ═══

Готовый паттерн в agents-pack (1-в-1):
https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/v2026.05.24/scripts/install-agents.sh

CHANGELOG wave 20:
https://github.com/tonytrue92-beep/openclaw-agents-pack/blob/main/CHANGELOG.md

Поиск в файле install-agents.sh: «wave 20» — это вся затронутая зона.

END PROMPT ───────────────────────────────────────────────────────
```

---

## После применения

1. AI-coder создаёт PR → ты ревьюишь → мержишь
2. Пишешь Антону: «Wave 20 factory готов, версия 2026.MM.DD»
3. Параллельно — работа над **@AITeamVIPBot** (для AI-coder
   это уже не подойдёт, см. полный бриф `wave-20-rebrand-brief.md`)

## Fallback — если AI-coder не справился

Открой полный бриф: `wave-20-rebrand-brief.md` — там пошаговая
инструкция с конкретными заменами. Это займёт ~30 минут вручную
для factory + 1-2 часа для бота.
