-- safe_example.sql — Idempotent PG patterns using IF EXISTS / IF NOT EXISTS
-- All statements safe to run multiple times without error.

-- ═══════════════════════════════════════════════════════════════════
-- SCHEMA
-- ═══════════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS private;

-- ═══════════════════════════════════════════════════════════════════
-- ROLE (no IF NOT EXISTS — use DO block)
-- ═══════════════════════════════════════════════════════════════════

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app') THEN
    CREATE ROLE app;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'dba') THEN
    CREATE ROLE dba;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'login_mgr') THEN
    CREATE ROLE login_mgr;
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════════
-- USER (no IF NOT EXISTS — use DO block)
-- ═══════════════════════════════════════════════════════════════════

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_user') THEN
    CREATE USER app_user WITH PASSWORD 'changeme' IN ROLE app;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'dba_user') THEN
    CREATE USER dba_user WITH PASSWORD 'changeme' IN ROLE dba;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'login_user') THEN
    CREATE USER login_user WITH PASSWORD 'changeme' IN ROLE login_mgr;
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════════
-- TABLE
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS auth.users (
  user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS auth.user_info (
  user_id UUID PRIMARY KEY REFERENCES auth.users(user_id),
  user_name VARCHAR UNIQUE,
  email VARCHAR
);

-- ═══════════════════════════════════════════════════════════════════
-- COLUMN (no IF NOT EXISTS — use DO block)
-- ═══════════════════════════════════════════════════════════════════

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'auth' AND table_name = 'user_info' AND column_name = 'avatar_url'
  ) THEN
    ALTER TABLE auth.user_info ADD COLUMN avatar_url TEXT;
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════════
-- INDEX
-- ═══════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_user_info_email ON auth.user_info (email);
CREATE INDEX IF NOT EXISTS idx_user_info_name ON auth.user_info (user_name);

-- ═══════════════════════════════════════════════════════════════════
-- DROP (safe — no error if missing)
-- ═══════════════════════════════════════════════════════════════════

DROP TABLE IF EXISTS temp_migration_state;
DROP INDEX IF EXISTS idx_old_unused;
DROP SCHEMA IF EXISTS deprecated CASCADE;

-- ═══════════════════════════════════════════════════════════════════
-- GRANT (idempotent by nature — re-granting is a no-op)
-- ═══════════════════════════════════════════════════════════════════

GRANT USAGE ON SCHEMA public TO app;
GRANT USAGE ON SCHEMA auth TO app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app;
GRANT SELECT ON ALL TABLES IN SCHEMA auth TO app;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO app;

-- DEFAULT PRIVILEGES (for future tables created by dba)
ALTER DEFAULT PRIVILEGES FOR ROLE dba IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app;
ALTER DEFAULT PRIVILEGES FOR ROLE dba IN SCHEMA public
  GRANT USAGE ON SEQUENCES TO app;
ALTER DEFAULT PRIVILEGES FOR ROLE dba IN SCHEMA auth
  GRANT SELECT ON TABLES TO app;

GRANT USAGE ON SCHEMA auth TO login_mgr;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA auth TO login_mgr;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA auth TO login_mgr;

ALTER DEFAULT PRIVILEGES FOR ROLE dba IN SCHEMA auth
  GRANT SELECT, INSERT, UPDATE ON TABLES TO login_mgr;
ALTER DEFAULT PRIVILEGES FOR ROLE dba IN SCHEMA auth
  GRANT USAGE ON SEQUENCES TO login_mgr;

-- ═══════════════════════════════════════════════════════════════════
-- FUNCTION / TRIGGER
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION auth.updated_at_trigger()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- DROP trigger first (no IF NOT EXISTS for triggers)
DROP TRIGGER IF EXISTS trg_updated_at ON auth.user_info;
CREATE TRIGGER trg_updated_at
  BEFORE UPDATE ON auth.user_info
  FOR EACH ROW EXECUTE FUNCTION auth.updated_at_trigger();

-- ═══════════════════════════════════════════════════════════════════
-- MOVE TABLE TO SCHEMA (idempotent check)
-- ═══════════════════════════════════════════════════════════════════

DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'users'
  ) THEN
    ALTER TABLE public.users SET SCHEMA auth;
  END IF;
END $$;
