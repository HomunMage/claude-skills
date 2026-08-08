# JSONB: Indexing & Query Patterns

## GIN index, never btree

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

## Query patterns that use GIN

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

## JSONB operators

| Operator | Meaning | GIN? |
|----------|---------|------|
| `@>` | Contains (left contains right) | Yes |
| `<@` | Contained by | Yes |
| `?` | Key exists | Yes |
| `?\|` | Any key exists | Yes |
| `?&` | All keys exist | Yes |
| `->` | Get value by key (returns jsonb) | No |
| `->>` | Get value by key (returns text) | No |
| `#>` | Get value by path (returns jsonb) | No |
| `#>>` | Get value by path (returns text) | No |

## JSONB mutation

```sql
-- Set a key
UPDATE t SET data = jsonb_set(data, '{key}', '"value"');

-- Merge (||) — overwrites matching keys, keeps others
UPDATE t SET data = data || '{"status": "done"}'::jsonb;

-- Remove a key
UPDATE t SET data = data - 'key';

-- Remove nested key
UPDATE t SET data = data #- '{nested,key}';
```

## Per-column index on JSONB (LatticeCast pattern)

LatticeCast stores row data in `rows.row_data` JSONB. Each column gets an auto-managed index:

```sql
-- B-tree for number/date columns (range queries)
CREATE INDEX IF NOT EXISTS idx_rows_{col_id}_btree
  ON rows ((row_data ->> '{col_id}'));

-- GIN for select/tags/text columns (containment)
CREATE INDEX IF NOT EXISTS idx_rows_{col_id}_gin
  ON rows USING GIN ((row_data -> '{col_id}'));
```

Indexes are created on column add, dropped on column delete.
