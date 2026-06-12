import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';

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
