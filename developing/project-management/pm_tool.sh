#!/usr/bin/env bash
# pm_tool.sh — PM domain helpers built on lc_api.sh.
#
# Composition:   .env + lc_api.sh + pm_*  (this file)
# Source order in your script:
#   set -a; source <project>/.env; set +a     # exports LC_API, PM_USER, PM_PASS, …
#   source <skills>/developing/lattice-cast/lc_api.sh
#   source <skills>/developing/project-management/pm_tool.sh
#
# pm_tool.sh sources lc_api.sh automatically from the sibling skill if
# you haven't sourced it yourself. The lattice-cast skill must live
# next to project-management in the same .agent-skills/developing/ tree.
#
# Required env (set by your .env):
#   LC_API           e.g. http://localhost:13491/api/v1
#   PM_USER          e.g. claude         (used for password-mode login)
#   WORKSPACE_ID     pm table's workspace UUID
#   TABLE_ID         the PM table's table_id (default: 'pm')
# Optional:
#   PM_PASS          ignored when AUTH_REQUIRED=false on backend
#   PROJECT_DIR      where to put caches (defaults to $PWD)

set -uo pipefail

PM_ENV_FILE="${PM_ENV_FILE:-${PROJECT_DIR:-$PWD}/.env}"
if [ -f "${PM_ENV_FILE}" ]; then
    set -a
    # shellcheck disable=SC1090
    source "${PM_ENV_FILE}"
    set +a
fi

# ── Locate sibling lc_api.sh and source it if not already ────────────────
_PM_TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -F lc_status >/dev/null; then
    # shellcheck disable=SC1091
    source "${_PM_TOOL_DIR}/../lattice-cast/lc_api.sh"
fi

# ── Defaults ─────────────────────────────────────────────────────────────
PM_USER="${PM_USER:-${LC_USER:-claude}}"
PM_PASS="${PM_PASS:-${LC_PASS:-}}"
TABLE_ID="${TABLE_ID:-pm}"
PROJECT_DIR="${PROJECT_DIR:-$PWD}"
PM_CACHE_DIR="${PROJECT_DIR}/.tmp/agentic-hive"
TOKEN_CACHE="${PM_CACHE_DIR}/_pm_token"
COL_CACHE="${PM_CACHE_DIR}/_col_cache.json"

mkdir -p "${PM_CACHE_DIR}"

# ── Auth / token cache ───────────────────────────────────────────────────

# pm_login → ensures LC_AUTH_HEADER is set; uses cached token if present.
# In AUTH_REQUIRED=false mode the token == PM_USER (resolves to user_id).
pm_login() {
    if [ -n "${LC_AUTH_HEADER:-}" ]; then return 0; fi
    local token=""
    if [ -f "${TOKEN_CACHE}" ]; then
        token=$(cat "${TOKEN_CACHE}")
    fi
    if [ -z "${token}" ]; then
        # Try password login; fall back to using PM_USER as the token (dev mode)
        if [ -n "${PM_PASS}" ]; then
            token=$(LC_AUTH_HEADER="Authorization: Bearer ${PM_USER}" \
                lc_login_password "${PM_USER}" "${PM_PASS}" 2>/dev/null) || token=""
        fi
        if [ -z "${token}" ]; then
            token="${PM_USER}"
        fi
        printf '%s' "${token}" > "${TOKEN_CACHE}"
    fi
    export LC_AUTH_HEADER="Authorization: Bearer ${token}"
}

# ── Column cache ─────────────────────────────────────────────────────────

# pm_cache_cols → fetches table columns and writes name→column_id map to
# COL_CACHE as JSON. Idempotent; safe to call multiple times.
# v40: per-aspect GET /columns is gone — read from GET /tables/{tid}.
pm_cache_cols() {
    pm_login
    lc_table_get "${TABLE_ID}" \
        | python3 -c '
import sys, json
t = json.load(sys.stdin)
out = {c["name"]: c["column_id"] for c in t["columns"]}
print(json.dumps(out))' \
        > "${COL_CACHE}"
}

# pm_col NAME → echoes column_id for the named column.
pm_col() {
    [ ! -s "${COL_CACHE}" ] && pm_cache_cols
    python3 -c "import json; print(json.load(open('${COL_CACHE}')).get('$1',''))"
}

# ── Row helpers ──────────────────────────────────────────────────────────

# pm_set_status ROW_ID STATUS — patches the Status field on the given row.
pm_set_status() {
    local rid="$1" status="$2"
    pm_login
    local sid; sid=$(pm_col Status)
    local cur upd
    cur=$(lc_row_get "${TABLE_ID}" "${rid}" \
        | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['row_data']))")
    upd=$(printf '%s' "${cur}" \
        | python3 -c "import sys,json;d=json.load(sys.stdin);d['${sid}']='${status}';print(json.dumps({'row_data':d}))")
    lc_row_update "${TABLE_ID}" "${rid}" "${upd}" >/dev/null
}

# pm_create_ticket TITLE TYPE PRIORITY [PARENT_RN]
# Echoes the new row_id on success.
pm_create_ticket() {
    pm_login
    local title="$1" type="${2:-task}" priority="${3:-medium}" parent="${4:-}"
    local TID; TID=$(pm_col Title)
    local TY;  TY=$(pm_col Type)
    local SID; SID=$(pm_col Status)
    local PR;  PR=$(pm_col Priority)
    local PRN; PRN=$(pm_col Parent)
    local SD;  SD=$(pm_col "Start Date")
    local DD;  DD=$(pm_col "Due Date")
    local today; today=$(date -u +%Y-%m-%d)

    local row_data
    row_data=$(python3 -c "
import json
rd = {
    '${TID}': '''${title}''',
    '${TY}':  '${type}',
    '${SID}': 'todo',
    '${PR}':  '${priority}',
    '${SD}':  '${today}',
    '${DD}':  '${today}',
}
parent = '${parent}'
if parent:
    rd['${PRN}'] = parent
print(json.dumps({'row_data': rd}))")
    lc_row_create "${TABLE_ID}" "${row_data}"
}

# pm_get_todo_tasks → echoes "row_id|title" lines.
pm_get_todo_tasks() {
    pm_login
    local SID; SID=$(pm_col Status)
    local TY;  TY=$(pm_col Type)
    local TI;  TI=$(pm_col Title)
    local filter; filter=$(printf '{"%s":"todo"}' "${SID}")
    lc_row_list "${TABLE_ID}" 200 "${filter}" \
        | python3 -c "
import sys, json
rows = json.load(sys.stdin)
todo = [r for r in rows if r['row_data'].get('${TY}') in ('task','bug')]
todo.sort(key=lambda r: r['row_id'])
for r in todo:
    print(f\"{r['row_id']}|{r['row_data'].get('${TI}','?')}\")"
}

# ── Doc helpers ──────────────────────────────────────────────────────────

pm_read_doc()   { pm_login; lc_doc_read "${TABLE_ID}" "$1"; }
pm_write_doc()  {
    # pm_write_doc RN CONTENT
    pm_login
    printf '%s' "$2" | lc_doc_write "${TABLE_ID}" "$1"
}
pm_append_doc() {
    # pm_append_doc RN MESSAGE — appends a timestamped line.
    pm_login
    local rn="$1" msg="$2"
    local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local cur; cur=$(lc_doc_read "${TABLE_ID}" "${rn}" 2>/dev/null || echo "")
    printf '%s\n- %s %s' "${cur}" "${ts}" "${msg}" \
        | lc_doc_write "${TABLE_ID}" "${rn}"
}
