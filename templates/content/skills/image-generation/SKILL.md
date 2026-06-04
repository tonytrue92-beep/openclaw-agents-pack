---
skill: image-generation
version: wrapper-1.0
author_original: eftalyurtseven
source: https://github.com/openclaw/skills/tree/main/skills/eftalyurtseven/eachlabs-image-generation
license: MIT
imported_at: 2026-04-22
imported_by: openclaw-agents-pack (see templates/LICENSE-skills.md)
wrapper_note: Сжатая версия — полный SKILL.md с API-примерами по ссылке source.
---

# Image Generation (EachLabs) — генерация картинок через множество моделей

Скилл от `@eftalyurtseven` даёт доступ к 20+ text-to-image моделям через
один API: Flux (разные версии), GPT Image, Gemini, Imagen, Seedream и др.
Использую для кадров, обложек и картинок под контент.

## Когда использую

- Нужна картинка под пост / обложку / превью видео / кадр ролика
- Хочется сравнить генераторы под одну задачу (Flux vs GPT Image vs Imagen)
- Есть чёткий промпт (иначе сначала уточняю бриф)

## Когда НЕ использую

- Нужна точная копия референса 1:1 — генераторы не копируют, это руками
- Нужен face swap / photo editing — другие инструменты
- Нужен вектор (SVG) — генераторы дают растр

## Какие модели когда

| Модель | Сильная сторона |
|---|---|
| **Flux Pro / 2 Turbo** | Фотореализм, детали, высокое качество |
| **GPT Image v1.5** | Следует длинным многокомпонентным промптам |
| **Gemini 2.5 Flash Image** | Быстрая, дешёвая, средне-качественная |
| **Imagen 4** | Google-style «чистый красивый» визуал |
| **Seedream** | Художественные стили, иллюстрации |

## Как подключить

Скилл требует **API-ключ EachLabs**. Получить на `eachlabs.ai` →
Settings → API Keys. Храним через openclaw-config, не в коде:

```bash
openclaw config set eachlabs.apiKey "<ваш-ключ>"
```

## OpenClaw ограничения

Картинки отправляются через media tool OpenClaw. Разрешённые пути:
`~/.openclaw/media/`, `~/.openclaw/agents/`, `/tmp`. Иначе Telegram не отправит файл.

## Как включить полную версию

```bash
clawhub install eftalyurtseven/eachlabs-image-generation
# Или: https://raw.githubusercontent.com/openclaw/skills/main/skills/eftalyurtseven/eachlabs-image-generation/SKILL.md
```

## Главное

**Безопасность:** не подключаю чужие API-ключи в промпт, не качаю по
произвольным URL — только модели по документации EachLabs.
