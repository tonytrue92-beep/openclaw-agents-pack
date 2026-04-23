---
skill: eachlabs-image-generation
version: wrapper-1.0
author_original: eftalyurtseven
source: https://github.com/openclaw/skills/tree/main/skills/eftalyurtseven/eachlabs-image-generation
license: MIT
imported_at: 2026-04-22
imported_by: openclaw-agents-pack (see templates/LICENSE-skills.md)
wrapper_note: Сжатая версия — полный SKILL.md с API-примерами по ссылке source.
---

# EachLabs — генерация картинок через множество моделей

Скилл от `@eftalyurtseven` даёт мне доступ к 20+ text-to-image моделям
через один API: Flux (разные версии), GPT Image, Gemini, Imagen,
Seedream и др.

## Когда использую

- Нужна картинка под пост / обложку / баннер
- Хочется попробовать разные генераторы под одну задачу (сравнить
  результат Flux vs GPT Image vs Imagen)
- Есть чёткий текстовый промпт (иначе сначала уточняю бриф у тебя)

## Когда НЕ использую

- Нужна точная копия референса — LLM-генераторы не копируют 1:1,
  для этого лучше руками в Figma / Photoshop
- Нужен face swap / photo editing — это другие инструменты
- Нужен векторный файл (SVG) — генераторы дают растр

## Какие модели когда

| Модель | Сильная сторона |
|---|---|
| **Flux Pro / 2 Turbo** | Фотореализм, детали, высокое качество |
| **GPT Image v1.5** | Следует длинным многокомпонентным промптам |
| **Gemini 2.5 Flash Image** | Быстрая, дёшёвая, средне-качественная |
| **Imagen 4** | Google-style «чистый красивый» визуал |
| **Seedream** | Художественные стили, иллюстрации |

## Мой flow

1. Читаю бриф из `USER.md` (какой стиль, какая аудитория)
2. Если промпт размытый — пишу 3 версии на разных уровнях детализации,
   спрашиваю тебя какая ближе
3. Выбираю модель под задачу (см. таблицу выше)
4. Генерирую → показываю → итерация
5. Финальный файл сохраняю в разрешённую папку (см. ниже)

## Как подключить

Скилл требует **API-ключ EachLabs**. Получить на `eachlabs.ai` →
Settings → API Keys. Сохраняется в переменной окружения:

```bash
export EACHLABS_API_KEY="..."
```

Храним через openclaw-config, не в коде:

```bash
openclaw config set eachlabs.apiKey "<ваш-ключ>"
```

## OpenClaw ограничения

Картинки отправляются через встроенный media tool OpenClaw. Разрешённые
пути для сохранения:

- `~/.openclaw/media/`
- `~/.openclaw/agents/`
- `/tmp`

Если сохранить в другое место — Telegram не отправит файл.

## Как включить полную версию

```bash
# В скилле — примеры curl для каждой модели, детали API,
# обработка ошибок, optimization tips
clawhub install eftalyurtseven/eachlabs-image-generation

# Или прочитать:
# https://raw.githubusercontent.com/openclaw/skills/main/skills/eftalyurtseven/eachlabs-image-generation/SKILL.md
```

## Главное

**Безопасность:** никогда не подключаю чужие API-ключи в промпт
к генератору, не скачиваю по произвольным URL — только указанные
модели по документации EachLabs.
