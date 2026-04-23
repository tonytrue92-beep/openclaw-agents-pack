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
возвращает HEX / RGB значения + опциональный swatch-файл с превью.

## Когда использую

- Нужно повторить цветовую гамму существующего визуала
- Клиент прислал референс, хочу выделить его палитру для брендбука
- Делаю mood board — собираю цвета из 5-10 изображений в один файл
- Проверяю совместимость цветов между разными визуалами проекта

## Когда НЕ использую

- Нужно **создать** палитру с нуля (это к Маркетологу — он знает ЦА
  и какие эмоции нужно вызвать)
- Нужно подобрать дополнительные / контрастные цвета к существующему
  (для этого другой скилл — color-theory)

## Что получаешь на выходе

Текстом:
```
#2A4B7C  RGB(42, 75, 124)
#E8B04B  RGB(232, 176, 75)
#F5F5F5  RGB(245, 245, 245)
```

Плюс опционально — PNG-картинка со swatch'ом всех цветов (для
быстрого визуального сравнения).

## Параметры

- **image** — путь до файла (JPEG, PNG, и т.п.)
- **-n / --num-colors** — сколько цветов вытащить (по умолчанию 5,
  максимум 20)
- **--output** — путь куда сохранить swatch-картинку (опционально)

## Зависимости

Скилл на Python, нужны пакеты:
- `Pillow` — обязательно (обработка изображений)
- `colorgram.py` — опционально, лучше выделяет доминирующие цвета
- `matplotlib` — опционально, только если нужен swatch

Устанавливаются один раз после установки скилла:
```bash
pip install -r ~/.openclaw/agents/designer/skills/color-palette/requirements.txt
```

## Мой flow

1. Ты присылаешь картинку в Telegram
2. Я сохраняю её в `/tmp/<name>.jpg`
3. Запускаю:
   ```
   python3 scripts/extract_palette.py /tmp/<name>.jpg -n 5 \
     --output /tmp/palette.png
   ```
4. Отдаю тебе HEX-коды + swatch PNG

## OpenClaw ограничения

Swatch-картинка должна сохраняться в одну из разрешённых папок:
- `~/.openclaw/media/`
- `~/.openclaw/agents/`
- `/tmp`

Иначе Telegram не сможет отправить файл.

## Как включить полную версию

```bash
clawhub install qrost/color-palette

# Или прочитать оригинал:
# https://raw.githubusercontent.com/openclaw/skills/main/skills/qrost/color-palette/SKILL.md
```

В полной версии есть Python-скрипт `extract_palette.py`, примеры
использования для разных форматов.

## Главное

Сам по себе выделяет цвета — **не даёт интерпретацию**. Если нужно
«какие цвета ассоциируются с премиум-брендом?» — это отдельная
задача для Маркетолога.
