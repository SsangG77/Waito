CREATE TABLE IF NOT EXISTS devices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  device_token TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS trackings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  device_id INTEGER NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  carrier_id TEXT NOT NULL,
  tracking_number TEXT NOT NULL,
  item_name TEXT NOT NULL DEFAULT '',
  current_status TEXT NOT NULL DEFAULT 'registered',
  current_t_value REAL NOT NULL DEFAULT 0.05,
  carrier_name TEXT NOT NULL DEFAULT '',
  estimated_delivery TEXT,
  live_activity_push_token TEXT,
  webhook_id TEXT,
  webhook_expires_at TEXT,
  last_polled_at TEXT,
  last_event_time TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  delivered_at TEXT,
  UNIQUE(device_id, carrier_id, tracking_number)
);

CREATE TABLE IF NOT EXISTS tracking_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tracking_id INTEGER NOT NULL REFERENCES trackings(id) ON DELETE CASCADE,
  tracker_status TEXT NOT NULL,
  mapped_status TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  event_time TEXT NOT NULL,
  location TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 국내 허브명 → 좌표 대응표. 배송 이력의 location 문자열을 카카오 장소검색으로 한 번만 변환해 재사용한다.
-- status='failed' 는 변환 실패(재시도 안 함, 관리자가 수동 입력할 대상).
CREATE TABLE IF NOT EXISTS hub_locations (
  name TEXT PRIMARY KEY,
  lat REAL,
  lon REAL,
  status TEXT NOT NULL DEFAULT 'ok',
  source TEXT NOT NULL DEFAULT 'kakao',
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_trackings_device_id ON trackings(device_id);
CREATE INDEX IF NOT EXISTS idx_trackings_status ON trackings(current_status);
CREATE INDEX IF NOT EXISTS idx_trackings_webhook ON trackings(webhook_id);
CREATE INDEX IF NOT EXISTS idx_tracking_events_tracking_id ON tracking_events(tracking_id);
