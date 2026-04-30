#!/bin/bash
# pm_tools.sh — Shared PM helpers for orchestrator, worker, and AI scripts
# Source this: source "$(dirname "$0")/pm_tools.sh"
#
# Required env vars: PM_URL, TABLE_ID, PROJECT_DIR, PM_USER (defaults to "claude")
# Optional: PM_PASS (ignored when AUTH_REQUIRED=false), WORKSPACE_ID
# Sets after pm_login: PM_TOKEN, AUTH_HEADER

PM_URL="${PM_URL:-http://localhost:13491}"
TABLE_ID="${TABLE_ID:?Set TABLE_ID}"
PM_USER="${PM_USER:-claude}"
PM_PASS="${PM_PASS:-}"
TOKEN_CACHE="${PROJECT_DIR:-.}/.tmp/claude-bot/_pm_token"
COL_CACHE="${PROJECT_DIR:-.}/.tmp/claude-bot/_col_cache.json"

# ─── Login ───────────────────────────────────────────────────────────────────

# pm_login → sets $PM_TOKEN and $AUTH_HEADER, caches token to disk
pm_login() {
  mkdir -p "$(dirname "$TOKEN_CACHE")"
  PM_TOKEN=$(curl -s -X POST "${PM_URL}/api/v1/login/password" \
    -H "Content-Type: application/json" \
    -d "{\"user_name\":\"${PM_USER}\",\"password\":\"${PM_PASS}\"}" \
    | python3 -c "import sys,json
try:
    print(json.load(sys.stdin)['access_token'])
except Exception:
    pass" 2>/dev/null)
  if [ -z "$PM_TOKEN" ]; then
    echo "pm_login: failed for user=${PM_USER}" >&2
    return 1
  fi
  echo "$PM_TOKEN" > "$TOKEN_CACHE"
  AUTH_HEADER="Authorization: Bearer ${PM_TOKEN}"
  export PM_TOKEN AUTH_HEADER
}

# Auto-login on source if no token yet
[ -z "$PM_TOKEN" ] && pm_login >/dev/null

# ─── Column helpers ──────────────────────────────────────────────────────────

# Cache all column IDs (call once at startup)
pm_cache_cols() {
  mkdir -p "$(dirname "$COL_CACHE")"
  local url="${PM_URL}/api/v1/tables/${TABLE_ID}"
  [ -n "$WORKSPACE_ID" ] && url="${url}?workspace_id=${WORKSPACE_ID}"
  curl -s "$url" -H "$AUTH_HEADER" 2>/dev/null | python3 -c "
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
  local ws=""
  [ -n "$WORKSPACE_ID" ] && ws="?workspace_id=${WORKSPACE_ID}"
  local cur; cur=$(curl -s "${PM_URL}/api/v1/tables/${TABLE_ID}/rows${ws}&limit=500" \
    -H "$AUTH_HEADER" | python3 -c "import sys,json
d=json.load(sys.stdin)
rows=d if isinstance(d,list) else d.get('rows',[])
r=next((r for r in rows if r['row_number']==${rn}),None)
print(json.dumps(r['row_data']) if r else '{}')" 2>/dev/null)
  local upd; upd=$(echo "$cur" | python3 -c "import sys,json; d=json.load(sys.stdin); d['${sid}']='${status}'; print(json.dumps(d))")
  curl -s -X PUT "${PM_URL}/api/v1/tables/${TABLE_ID}/rows/${rn}" \
    -H "$AUTH_HEADER" -H "Content-Type: application/json" \
    -d "{\"row_data\": ${upd}}" > /dev/null
}

# ─── Row doc (MinIO markdown) ────────────────────────────────────────────────

# pm_read_doc <row_number> → stdout
pm_read_doc() {
  local rn="$1"
  [ -z "$rn" ] || [ -z "$TABLE_ID" ] && return
  curl -s "${PM_URL}/api/v1/tables/${TABLE_ID}/rows/${rn}/doc" \
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
  curl -s -X PUT "${PM_URL}/api/v1/tables/${TABLE_ID}/rows/${rn}/doc" \
    -H "$AUTH_HEADER" -H "Content-Type: text/plain" \
    --data-raw "$updated" > /dev/null
}

# pm_write_doc <row_number> <full_content>
pm_write_doc() {
  local rn="$1" content="$2"
  [ -z "$rn" ] || [ -z "$TABLE_ID" ] && return
  curl -s -X PUT "${PM_URL}/api/v1/tables/${TABLE_ID}/rows/${rn}/doc" \
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

  local url="${PM_URL}/api/v1/tables/${TABLE_ID}/rows"
  [ -n "$WORKSPACE_ID" ] && url="${url}?workspace_id=${WORKSPACE_ID}"

  curl -s -X POST "$url" \
    -H "$AUTH_HEADER" -H "Content-Type: application/json" \
    -d "{\"row_data\": ${data}}" | python3 -c "import sys,json; print(json.load(sys.stdin)['row_number'])" 2>/dev/null
}

# ─── Query tickets ───────────────────────────────────────────────────────────

# pm_get_todo_tasks → prints "row_number|title" lines
pm_get_todo_tasks() {
  local sid; sid=$(pm_col Status)
  local filter; filter=$(python3 -c "import urllib.parse; print(urllib.parse.quote('{\"${sid}\":\"todo\"}'))")
  local url="${PM_URL}/api/v1/tables/${TABLE_ID}/rows?limit=100&filter_json=${filter}"
  [ -n "$WORKSPACE_ID" ] && url="${url}&workspace_id=${WORKSPACE_ID}"
  curl -s "$url" -H "$AUTH_HEADER" 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
rows = d if isinstance(d, list) else d.get('rows', [])
tyid = '$(pm_col Type)'; tid = '$(pm_col Title)'
todo = [r for r in rows if r['row_data'].get(tyid) in ('task', 'bug')]
todo.sort(key=lambda x: x['row_number'])
for r in todo:
    print(f\"{r['row_number']}|{r['row_data'].get(tid, '?')}\")
" 2>/dev/null
}
