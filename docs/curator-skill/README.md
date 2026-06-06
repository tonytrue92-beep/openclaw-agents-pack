# Скилл куратора — `installer-support`

Готовый OpenClaw-скилл для **агента-нейрокуратора**, который ведёт клиентов
через установку. Активируется по триггерам («установка», «ошибка», «бот
молчит», «command not found», «токен», «мозги/модель» и т.д.), даёт каркас
реакции + быстрые фиксы, а за полным контекстом отсылает к
[`../curator-guide.md`](../curator-guide.md).

## Как поставить куратору

1. Скопировать папку скилла в рабочую папку куратор-агента:
   ```bash
   cp -r installer-support ~/.openclaw/workspace-<имя-куратора>/skills/
   ```
   (или туда, где у твоего куратора лежат `skills/`).

2. Положить полный гайд в базу знаний и переиндексировать, чтобы скилл
   мог из него доставать детали:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-agents-pack/main/docs/curator-guide.md \
     -o ~/.openclaw/knowledge/curator-guide.md
   openclaw memory index --force
   ```

3. Перезапустить gateway: `openclaw gateway restart`.

## Обновление

Скилл — это каркас, он меняется редко. Актуальные команды/ошибки живут в
`curator-guide.md` — обновляй его (шаг 2), скилл трогать не нужно.
