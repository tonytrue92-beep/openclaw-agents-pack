---
skill: color-palette
version: wrapper-1.0
author_original: qrost
source: https://github.com/openclaw/skills/tree/main/skills/qrost/color-palette
license: MIT
imported_at: 2026-04-22
imported_by: openclaw-agents-pack (see templates/LICENSE-skills.md)
wrapper_note: Сжатая версия — полный SKILL.md с Python-скриптом по ссылке source.
---

# Color Palette — вытягиваю цвета из картинки

Скилл от `@qrost` извлекает доминирующие цвета из изображения и
возвращает HEX / RGB + опциональный swatch-файл. Использую, чтобы
держать единую палитру в роликах и обложках.

## Когда использую

- Нужно повторить цветовую гамму существующего визуала/референса
- Собираю mood board — цвета из 5-10 изображений в один файл
- Проверяю совместимость цветов между кадрами/обложками проекта

## Когда НЕ использую

- Нужно **создать** палитру с нуля под ЦА — это к Маркетологу
- Нужно подобрать контрастные/дополнительные цвета — другой скилл (color-theory)

## Что получаешь на выходе

```
#2A4B7C  RGB(42, 75, 124)
#E8B04B  RGB(232, 176, 75)
#F5F5F5  RGB(245, 245, 245)
```
Плюс опционально — PNG со swatch'ом всех цветов.

## Параметры

- **image** — путь до файла (JPEG, PNG)
- **-n / --num-colors** — сколько цветов (по умолчанию 5, максимум 20)
- **--output** — путь для swatch-картинки (опционально)

## Зависимости

Python: `Pillow` (обязательно), `colorgram.py` и `matplotlib` (опционально).
Устанавливаются один раз после установки скилла:
```bash
pip install -r ~/.openclaw/agents/content/skills/color-palette/requirements.txt
```

## OpenClaw ограничения

Swatch-картинка — в одну из разрешённых папок: `~/.openclaw/media/`,
`~/.openclaw/agents/`, `/tmp`. Иначе Telegram не отправит файл.

## Как включить полную версию

```bash
clawhub install qrost/color-palette
# Или: https://raw.githubusercontent.com/openclaw/skills/main/skills/qrost/color-palette/SKILL.md
```

## Главное

Выделяет цвета — **не даёт интерпретацию**. «Какие цвета у премиум-бренда?»
— это к Маркетологу.
