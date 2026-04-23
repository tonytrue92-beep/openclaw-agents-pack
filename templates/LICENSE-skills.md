# Imported Skills — Attributions

Все скиллы в `templates/<agent>/skills/` импортированы в формате
**wrapper** из каталога [openclaw/skills](https://github.com/openclaw/skills)
(и его витрины https://clawskills.sh). Это **сокращённые адаптации**
оригиналов:

- Attribution-блок в начале каждого `SKILL.md` (поле `author_original`
  указывает автора оригинала).
- Ссылка `source` ведёт на полный SKILL.md в upstream-репо.
- Краткое описание «когда использовать / когда не использовать»,
  основные параметры и flow.
- Полные API-примеры, код-скрипты, расширенные конфигурации — НЕ
  копируются, а даётся ссылка на оригинал и команда установки
  через ClawHub.

Это minimum-viable-attribution — mention authorship, license
preserved, no code re-distribution. Клиент в любой момент может
установить оригинал через `clawhub install <skill-slug>` и получить
полный функционал.

## Импортированные скиллы (2026-04-22)

| Slug | Author | Role | Source |
|---|---|---|---|
| `eachlabs-image-generation` | [@eftalyurtseven](https://github.com/eftalyurtseven) | Designer | [GitHub](https://github.com/openclaw/skills/tree/main/skills/eftalyurtseven/eachlabs-image-generation) |
| `color-palette` | [@qrost](https://github.com/qrost) | Designer | [GitHub](https://github.com/openclaw/skills/tree/main/skills/qrost/color-palette) |
| `agent-collaboration-network` | [@neiljo-gy](https://github.com/neiljo-gy) | Coordinator | [GitHub](https://github.com/openclaw/skills/tree/main/skills/neiljo-gy/agent-collaboration-network) |
| `close-loop` | [@clarezoe](https://github.com/clarezoe) | Coordinator | [GitHub](https://github.com/openclaw/skills/tree/main/skills/clarezoe/close-loop) |
| `reef-copywriting` | [@staybased](https://github.com/staybased) | Copywriter | [GitHub](https://github.com/openclaw/skills/tree/main/skills/staybased/reef-copywriting) |
| `brand-voice-profile` | [@dimitripantzos](https://github.com/dimitripantzos) | Copywriter | [GitHub](https://github.com/openclaw/skills/tree/main/skills/dimitripantzos/brand-voice-profile) |

## Лицензия оригиналов

Все скиллы — **MIT**. Ниже стандартный текст MIT для полноты; конкретные
права авторов указаны в их upstream-репозиториях (см. ссылки выше).

```
MIT License

Copyright (c) respective authors (see table above)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

## Политика обновления

- Wrappers фиксируются на дату импорта. Оригиналы могут меняться.
- Если автор оригинала снял MIT / удалил скилл — убираем wrapper
  следующей wave, не ждём.
- Раз в квартал — ревью: какие скиллы всё ещё актуальны, какие
  заменить, какие добавить.

## Как клиенту получить полную версию

```bash
clawhub install <author>/<slug>
# например:
clawhub install staybased/reef-copywriting
```

После установки полный SKILL.md заменит наш wrapper в workspace агента.
