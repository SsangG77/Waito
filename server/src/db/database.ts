import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

// ESM 에는 __dirname 이 없으므로 import.meta.url 로 대체
const __dirname = path.dirname(fileURLToPath(import.meta.url));

let db: Database.Database | null = null;

export function getDb(): Database.Database {
  if (!db) {
    db = new Database(path.join(process.cwd(), 'waito.db'));
    db.pragma('journal_mode = WAL');
    db.pragma('foreign_keys = ON');
  }
  return db;
}

export function initDb(): void {
  const database = getDb();
  const migrationPath = path.join(__dirname, 'migrations', '001_initial.sql');
  const migration = fs.readFileSync(migrationPath, 'utf-8');
  database.exec(migration);
  runColumnMigrations(database);
}

/**
 * 기존 DB에도 안전하게 적용되는 멱등 컬럼 추가.
 * (별도 마이그레이션 러너가 없으므로 PRAGMA로 컬럼 존재를 확인하고 ADD COLUMN)
 */
function runColumnMigrations(database: Database.Database): void {
  addColumnIfMissing(database, 'devices', 'push_to_start_token', 'TEXT');
  addColumnIfMissing(database, 'devices', 'truck_config', 'TEXT');
  addColumnIfMissing(database, 'trackings', 'live_activity_started_at', 'TEXT');
  addColumnIfMissing(database, 'trackings', 'memo', 'TEXT');
  // 디바이스별 배송완료 누적 카운트 (트럭 부품 해제 보상용). 토큰은 클라 Keychain 에 영속.
  addColumnIfMissing(database, 'devices', 'delivered_count', 'INTEGER DEFAULT 0');
  // 포인트로 해제한 부품 목록(JSON 배열). 잔여 포인트 = delivered_count - 해제수 * 비용
  addColumnIfMissing(database, 'devices', 'unlocked_parts', 'TEXT');
  // 표준 원격알림(일반 배너)용 APNs device token. Live Activity 토큰과 별개.
  addColumnIfMissing(database, 'devices', 'apns_token', 'TEXT');
}

function addColumnIfMissing(
  database: Database.Database,
  table: string,
  column: string,
  type: string,
): void {
  const cols = database.prepare(`PRAGMA table_info(${table})`).all() as Array<{ name: string }>;
  if (!cols.some(c => c.name === column)) {
    database.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${type}`);
  }
}

export function closeDb(): void {
  if (db) {
    db.close();
    db = null;
  }
}
