---
name: developing-db-sql
description: SQL writing — INSERT, UPSERT, indexing, JSONB. Use when writing or reviewing SQL statements, migrations, or schema changes.
user-invocable: false
version: 0.4.0
---

# Safe SQL Rules

## PG Roles & Schemas: Least Privilege

### Principle: roles start with ZERO privileges — add incrementally

A newly created role has NO access to anything. You must explicitly grant every capability.

### Schema-based permission model

```
public   — user-facing data (tables, rows, workspaces, workspace_members)
auth     — authentication (users, user_info)
private  — internal system data (migrations, config)
```

### Roles

| Role | Purpose | Schemas |
|------|---------|---------|
| `dba` | Migrations (DDL) | ALL schemas — CREATE/ALTER/DROP |
| `app` | General API | public: CRUD, auth: SELECT only |
| `login_mgr` | Login/auth | auth: SELECT/INSERT/UPDATE only |

### Creating roles (step by step)

```sql
-- 1. Create role (NO privileges by default)
CREATE ROLE app;

-- 2. Grant USAGE on schema (required to see objects in it)
GRANT USAGE ON SCHEMA public TO app;

-- 3. Grant table-level privileges
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app;

-- 4. Grant sequence usage (needed for SERIAL/BIGSERIAL columns)
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO app;

-- 5. Set DEFAULT privileges (for tables created in the future by dba)
ALTER DEFAULT PRIVILEGES FOR ROLE dba IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app;
ALTER DEFAULT PRIVILEGES FOR ROLE dba IN SCHEMA public
  GRANT USAGE ON SEQUENCES TO app;

-- 6. Create login user inheriting role
CREATE USER app_user WITH PASSWORD 'secret' IN ROLE app;
```

### Key rules

- **`GRANT USAGE ON SCHEMA`** — required first, otherwise role can't even see the schema
- **`GRANT ... ON ALL TABLES`** — covers existing tables only
- **`ALTER DEFAULT PRIVILEGES`** — covers future tables (must specify `FOR ROLE <owner>`)
- **`FOR ROLE dba`** is critical — default privileges apply to objects created BY that role
- **Never GRANT on `public` schema to `login_mgr`** — login should only touch auth tables
- **Never GRANT DDL (CREATE/ALTER/DROP) to `app` or `login_mgr`**
- **Test**: `psql -U app_user -c "DROP TABLE public.rows"` must fail

### Cross-schema SELECT

If `app` needs to read from `auth` schema (e.g. resolve user display names):

```sql
GRANT USAGE ON SCHEMA auth TO app;
GRANT SELECT ON ALL TABLES IN SCHEMA auth TO app;
ALTER DEFAULT PRIVILEGES FOR ROLE dba IN SCHEMA auth
  GRANT SELECT ON TABLES TO app;
```

### search_path per connection

Set `search_path` when creating the SQLAlchemy engine so models resolve unqualified table names correctly:

```python
# app engine: sees public + auth (read-only)
engine = create_async_engine(url, connect_args={"server_settings": {"search_path": "public,auth"}})

# login engine: sees auth only  
engine = create_async_engine(url, connect_args={"server_settings": {"search_path": "auth"}})

# dba engine: sees everything
engine = create_async_engine(url, connect_args={"server_settings": {"search_path": "public,auth,private"}})
```

### PG logging (docker-compose)

Enable native logging for debugging permission issues:

```yaml
command: >
  postgres
  -c logging_collector=on
  -c log_directory=/var/log/postgresql
  -c log_statement=all
  -c log_connections=on
  -c log_disconnections=on
```

## Idempotent SQL: Always use IF EXISTS / IF NOT EXISTS

All SQL must be safe to run multiple times. See [safe_example.sql](safe_example.sql) for complete patterns.

Key patterns:
- `CREATE TABLE IF NOT EXISTS` / `DROP TABLE IF EXISTS`
- `CREATE SCHEMA IF NOT EXISTS` / `DROP SCHEMA IF EXISTS`
- `CREATE INDEX IF NOT EXISTS` / `DROP INDEX IF EXISTS`
- Roles/Users/Columns have no `IF NOT EXISTS` — wrap in `DO $$ BEGIN IF NOT EXISTS (SELECT ...) THEN ... END IF; END $$;`
- Triggers: `DROP TRIGGER IF EXISTS` then `CREATE TRIGGER`
- Functions: `CREATE OR REPLACE FUNCTION`
- GRANTs are naturally idempotent (re-granting is a no-op)

## Migrations: NEVER modify existing files

**NEVER** edit an existing `migration/*.sql` file — it may have already been applied to production databases.

**ALWAYS** create a new migration file with the next sequence number.

**Why:** Migrations are applied once and recorded. Modifying an applied migration causes drift between environments. Always move forward.

## UPSERT: Always specify conflict target

**NEVER** bare `ON CONFLICT DO NOTHING` — it silently swallows constraint violations you didn't intend.

**ALWAYS** use `ON CONFLICT (column_name) DO NOTHING` or `DO UPDATE`.

```sql
-- BAD: which constraint? all of them? silent data loss
INSERT INTO users (email, name) VALUES ('a@b.com', 'A')
ON CONFLICT DO NOTHING;

-- GOOD: explicit — only skip on email duplicate
INSERT INTO users (email, name) VALUES ('a@b.com', 'A')
ON CONFLICT (email) DO NOTHING;

-- GOOD: upsert with explicit target
INSERT INTO users (email, name) VALUES ('a@b.com', 'A')
ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name;
```

**Why:** Bare `ON CONFLICT` catches ANY unique constraint — if a second unique column conflicts unexpectedly, the row silently disappears. Debugging this is painful.

## JSONB: Use GIN index, never btree

**NEVER** `CREATE INDEX ON t (jsonb_col)` — btree can't search inside JSONB.

**ALWAYS** use GIN for JSONB columns.

```sql
-- BAD: btree on jsonb — useless for key/value lookups
CREATE INDEX idx_data ON events (metadata);

-- GOOD: GIN index — supports @>, ?, ?&, ?| operators
CREATE INDEX idx_data ON events USING GIN (metadata);

-- GOOD: GIN on specific path (smaller, faster)
CREATE INDEX idx_data ON events USING GIN ((metadata -> 'type'));
```

**Why:** btree indexes on JSONB only support equality on the entire JSON blob. GIN indexes support `@>` containment, `?` key-exists, and path queries — the operations you actually use.

### Query patterns that use GIN

```sql
-- containment: uses GIN
SELECT * FROM events WHERE metadata @> '{"type": "click"}';

-- key exists: uses GIN
SELECT * FROM events WHERE metadata ? 'type';

-- AVOID: this does NOT use GIN index
SELECT * FROM events WHERE metadata->>'type' = 'click';
-- FIX: use containment instead
SELECT * FROM events WHERE metadata @> '{"type": "click"}';
```
