---
name: developing-db-sql
description: SQL writing — INSERT, UPSERT, indexing, JSONB. Use when writing or reviewing SQL statements, migrations, or schema changes.
user-invocable: false
---

# Safe SQL Rules

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
