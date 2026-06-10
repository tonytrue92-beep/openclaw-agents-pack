-- Install-analytics — таблица D1 для аналитики установок AI TEAM.
-- Применить: wrangler d1 execute aiteam-installs --remote --file=schema.sql
CREATE TABLE IF NOT EXISTS installs (
  token_hash        TEXT PRIMARY KEY,  -- sha256(полный токен) hex
  tg_id             TEXT,
  email             TEXT,              -- только от бота (/issue), установщик не знает
  tier              TEXT,              -- VIP / STD / SUB / TRY
  track             TEXT,              -- paid / trial
  issued_at         TEXT,             -- когда бот выдал токен
  activated_at      TEXT,             -- первая установка
  last_activated_at TEXT,
  activation_count  INTEGER DEFAULT 0,
  installer_version TEXT,
  client_os         TEXT
);
