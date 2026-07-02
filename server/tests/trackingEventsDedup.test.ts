import { describe, it, expect } from 'vitest';
import Database from 'better-sqlite3';
import {
  TRACKING_EVENTS_DEDUP_SQL,
  TRACKING_EVENTS_UNIQUE_INDEX_SQL,
} from '../src/db/database.js';
import {
  testStepIndex,
  TEST_STEPS,
  TEST_STEP_INTERVAL_MS,
} from '../src/services/trackerApi.js';

// 001_initial.sql 의 tracking_events 스키마와 동일(메모리 DB)
function makeDb(): Database.Database {
  const db = new Database(':memory:');
  db.exec(`CREATE TABLE tracking_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tracking_id INTEGER NOT NULL,
    tracker_status TEXT NOT NULL,
    mapped_status TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    event_time TEXT NOT NULL,
    location TEXT
  )`);
  return db;
}

const insertOrIgnore = (db: Database.Database) =>
  db.prepare(`INSERT OR IGNORE INTO tracking_events
    (tracking_id, tracker_status, mapped_status, description, event_time, location)
    VALUES (?, ?, ?, ?, ?, ?)`);

const count = (db: Database.Database) =>
  (db.prepare('SELECT COUNT(*) c FROM tracking_events').get() as { c: number }).c;

describe('tracking_events 중복 누적 버그', () => {
  it('UNIQUE 인덱스가 없으면 같은 이벤트가 누적된다 (버그 재현)', () => {
    const db = makeDb();
    const stmt = insertOrIgnore(db);
    for (let i = 0; i < 5; i++) {
      stmt.run(1, 'DELIVERED', 'delivered', '배송완료', '2026-01-01T00:00:00.000Z', '부산');
    }
    expect(count(db)).toBe(5); // 중복 누적 = 버그
    db.close();
  });

  it('UNIQUE 인덱스가 있으면 INSERT OR IGNORE 가 실제로 중복을 막는다 (수정)', () => {
    const db = makeDb();
    db.exec(TRACKING_EVENTS_UNIQUE_INDEX_SQL);
    const stmt = insertOrIgnore(db);
    for (let i = 0; i < 5; i++) {
      stmt.run(1, 'DELIVERED', 'delivered', '배송완료', '2026-01-01T00:00:00.000Z', '부산');
    }
    expect(count(db)).toBe(1);
    db.close();
  });

  it('DEDUP_SQL 이 기존 중복을 그룹당 1개로 정리한다', () => {
    const db = makeDb();
    const stmt = db.prepare(`INSERT INTO tracking_events
      (tracking_id, tracker_status, mapped_status, description, event_time, location)
      VALUES (?, ?, ?, ?, ?, ?)`);
    for (let i = 0; i < 4; i++) {
      stmt.run(1, 'DELIVERED', 'delivered', '배송완료', '2026-01-01T00:00:00.000Z', '부산');
    }
    stmt.run(1, 'OUT_FOR_DELIVERY', 'delivering', '배송중', '2026-01-01T02:00:00.000Z', '부산'); // 구별되는 이벤트
    db.exec(TRACKING_EVENTS_DEDUP_SQL);
    expect(count(db)).toBe(2);
    // 정리 후 유니크 인덱스 생성도 성공해야 함(중복이 남아있으면 실패)
    expect(() => db.exec(TRACKING_EVENTS_UNIQUE_INDEX_SQL)).not.toThrow();
    db.close();
  });
});

describe('test970719 사이클 리셋', () => {
  it('배송완료(step 6) 다음 사이클에서 step 0(접수)으로 초기화된다', () => {
    const created = 0;
    const n = TEST_STEPS.length; // 5 (택배사 코드)
    expect(testStepIndex(created, (n - 1) * TEST_STEP_INTERVAL_MS)).toBe(n - 1); // 마지막(배송완료)
    expect(testStepIndex(created, n * TEST_STEP_INTERVAL_MS)).toBe(0);           // 순환 → 접수
    expect(TEST_STEPS[0].description).toBe('접수');
    expect(TEST_STEPS[n - 1].description).toBe('배송완료');
  });

  it('pollTestTracking 의 재구성 로직: 매 폴링마다 이벤트 수 = step+1 (누적 없음)', () => {
    const db = makeDb();
    const created = 0;
    // 폴링을 시뮬레이션: 삭제 후 0..step 재삽입
    const poll = (nowMs: number) => {
      const step = testStepIndex(created, nowMs);
      db.prepare('DELETE FROM tracking_events WHERE tracking_id = ?').run(1);
      const ins = insertOrIgnore(db);
      for (let i = 0; i <= step; i++) {
        ins.run(1, TEST_STEPS[i].code, 'x', TEST_STEPS[i].description,
          new Date(created + i * TEST_STEP_INTERVAL_MS).toISOString(), TEST_STEPS[i].location);
      }
      return step;
    };
    const n = TEST_STEPS.length; // 5
    poll((n - 1) * TEST_STEP_INTERVAL_MS); // 마지막 단계 → n개
    expect(count(db)).toBe(n);
    poll(n * TEST_STEP_INTERVAL_MS); // 다음 사이클 접수 → 1개로 리셋(누적 X)
    expect(count(db)).toBe(1);
    poll(20 * TEST_STEP_INTERVAL_MS); // 한참 뒤에도 누적 없이 현재 사이클만
    expect(count(db)).toBe(testStepIndex(created, 20 * TEST_STEP_INTERVAL_MS) + 1);
    db.close();
  });
});
