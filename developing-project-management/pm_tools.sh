#!/bin/bash
# pm_tools.sh — Shared PM helpers for orchestrator, worker, and AI scripts
# Source this: source "$(dirname "$0")/pm_tools.sh"
#
# Required env vars: PM_URL, TABLE_ID, PROJECT_DIR
# Optional: ROW_NUMBER (for row-level ops)

PM_URL="${PM_URL:-http://localhost:13491}"
TABLE_ID="${TABLE_ID:?Set TABLE_ID}"
AUTH_HEADER="Authorization: Bearer claude"
COL_CACHE="${PROJECT_DIR:-.}/.tmp/claude-bot/_col_cache.json"

# ─── Column helpers ──────────────────────────────────────────────────────────

# Cache all column IDs (call once at startup)
pm_cache_cols() {
  mkdir -p "$(dirname "$COL_CACHE")"
  curl -s "${PM_URL}/api/tables/${TABLE_ID}" -H "$AUTH_HEADER" 2>/dev/null | python3 -c "
import sys, json
t = json.load(sys.stdin)
json.dump({c['name']: c['column_id'] for c in t['columns']}, open('${COL_CACHE}', 'w'))
" 2>/dev/null
}

# Get column ID by name from cache
pm_col() {
  local name="$1"
  python3 -c "import json; print(json.load(open('${COL_CACHE}')).get('${name}',''))" 2>/dev/null
}

# ─── Row status ──────────────────────────────────────────────────────────────

# pm_set_status <row_number> <new_status>
pm_set_status() {
  local rn="$1" status="$2"
  [ -z "$rn" ] || [ -z "$TABLE_ID" ] && return
  local sid; sid=$(pm_col Status)
  local cur; cur=$(curl -s "${PM_URL}/api/tables/${TABLE_ID}/rows?limit=500&sort=asc" \
    -H "$AUTH_HEADER" | python3 -c "import sys,json; rows=json.load(sys.stdin); r=next((r for r in rows if r['row_number']==${rn}),None); print(json.dumps(r['row_data']) if r else '{}')" 2>/dev/null)
  local upd; upd=$(echo "$cur" | python3 -c "import sys,json; d=json.load(sys.stdin); d['${sid}']='${status}'; print(json.dumps(d))")
  curl -s -X PUT "${PM_URL}/api/tables/${TABLE_ID}/rows/${rn}" \
    -H "$AUTH_HEADER" -H "Content-Type: application/json" \
    -d "{\"row_data\": ${upd}}" > /dev/null
}

# ─── Row doc (MinIO markdown) ────────────────────────────────────────────────

# pm_read_doc <row_number> → stdout
pm_read_doc() {
  local rn="$1"
  [ -z "$rn" ] || [ -z "$TABLE_ID" ] && return
  curl -s "${PM_URL}/api/tables/${TABLE_ID}/rows/${rn}/doc" \
    -H "$AUTH_HEADER" 2>/dev/null || echo ""
}

# pm_append_doc <row_number> <message>
pm_append_doc() {
  local rn="$1" msg="$2"
  [ -z "$rn" ] || [ -z "$TABLE_ID" ] && return
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local cur; cur=$(pm_read_doc "$rn")
  local updated="${cur}
- ${ts} ${msg}"
  curl -s -X PUT "${PM_URL}/api/tables/${TABLE_ID}/rows/${rn}/doc" \
    -H "$AUTH_HEADER" -H "Content-Type: text/plain" \
    --data-raw "$updated" > /dev/null
}

# pm_write_doc <row_number> <full_content>
pm_write_doc() {
  local rn="$1" content="$2"
  [ -z "$rn" ] || [ -z "$TABLE_ID" ] && return
  curl -s -X PUT "${PM_URL}/api/tables/${TABLE_ID}/rows/${rn}/doc" \
    -H "$AUTH_HEADER" -H "Content-Type: text/plain" \
    --data-raw "$content" > /dev/null
}

# ─── Create ticket ───────────────────────────────────────────────────────────

# pm_create_ticket <title> <type> <priority> <parent_rn> → row_number on stdout
pm_create_ticket() {
  local title="$1" type="${2:-task}" priority="${3:-medium}" parent_rn="${4:-}"
  local tid; tid=$(pm_col Title)
  local tyid; tyid=$(pm_col Type)
  local sid; sid=$(pm_col Status)
  local pid; pid=$(pm_col Priority)
  local prid; prid=$(pm_col Parent)
  local stid; stid=$(pm_col "Start Date")
  local duid; duid=$(pm_col "Due Date")
  local today; today=$(date -u +%Y-%m-%d)

  local data="{\"${tid}\":\"${title}\",\"${tyid}\":\"${type}\",\"${sid}\":\"todo\",\"${pid}\":\"${priority}\",\"${stid}\":\"${today}\",\"${duid}\":\"${today}\""
  [ -n "$parent_rn" ] && data="${data},\"${prid}\":\"${parent_rn}\""
  data="${data}}"

  curl -s -X POST "${PM_URL}/api/tables/${TABLE_ID}/rows" \
    -H "$AUTH_HEADER" -H "Content-Type: application/json" \
    -d "{\"row_data\": ${data}}" | python3 -c "import sys,json; print(json.load(sys.stdin)['row_number'])" 2>/dev/null
}

# ─── Query tickets ───────────────────────────────────────────────────────────

# pm_get_todo_tasks → prints "row_number|title" lines
pm_get_todo_tasks() {
  local sid; sid=$(pm_col Status)
  local filter; filter=$(python3 -c "import urllib.parse; print(urllib.parse.quote('{\"${sid}\":\"todo\"}'))")
  curl -s "${PM_URL}/api/tables/${TABLE_ID}/rows?limit=100&filter_json=${filter}" \
    -H "$AUTH_HEADER" 2>/dev/null | python3 -c "
import sys, json
rows = json.load(sys.stdin)
tyid = '$(pm_col Type)'; tid = '$(pm_col Title)'
todo = [r for r in rows if r['row_data'].get(tyid) in ('task', 'bug')]
todo.sort(key=lambda x: x['row_number'])
for r in todo:
    print(f\"{r['row_number']}|{r['row_data'].get(tid, '?')}\")
" 2>/dev/null
}
