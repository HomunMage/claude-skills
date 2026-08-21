#!/usr/bin/env bash
# seo-bot/orchestrator.sh — Pure shell. Reads source data from
# audiences.csv, promotions.csv, products.csv; loops the full
# cross product; spawns a fresh claude -p worker for each combination.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SEO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${SEO_DIR}/.env"
if [ -f "${ENV_FILE}" ]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi
: "${SKILLS_DIR:?SKILLS_DIR must be set in .env}"
# shellcheck disable=SC1091
source "${SKILLS_DIR}/developing/project-management/lc_api.sh"
LOG="${SEO_DIR}/.tmp/seo-bot.log"
mkdir -p "${SEO_DIR}/.tmp"
: > "$LOG"
LC_USER="${LC_USER:-}"
LC_PASS="${LC_PASS:-}"

log() { echo "$(date '+%H:%M:%S') [ORCH] $*" | tee -a "$LOG"; }

# Parse a CSV (title,description) into two parallel arrays via python
# to handle quoted fields cleanly. Outputs `title<TAB>description` lines.
parse_csv() {
    python3 -c "
import csv, sys
with open(sys.argv[1]) as f:
    next(f)  # skip header
    for row in csv.reader(f):
        if not row or not row[0].strip(): continue
        title = row[0].strip()
        desc  = (row[1] if len(row) > 1 else '').strip()
        print(f'{title}\t{desc}')
" "$1"
}

mapfile -t A_LINES < <(parse_csv "${SCRIPT_DIR}/audiences.csv")
mapfile -t B_LINES < <(parse_csv "${SCRIPT_DIR}/promotions.csv")
mapfile -t C_LINES < <(parse_csv "${SCRIPT_DIR}/products.csv")

log "loaded ${#A_LINES[@]} audiences, ${#B_LINES[@]} promotions, ${#C_LINES[@]} products from CSV"
EXPECTED=$(( ${#A_LINES[@]} * ${#B_LINES[@]} * ${#C_LINES[@]} ))
log "full cross product = $EXPECTED combinations"

: "${ARTICLES_TABLE_ID:?ARTICLES_TABLE_ID must be set in .env}"
: "${TITLE_COLUMN_ID:?TITLE_COLUMN_ID must be set in .env}"

if [ -z "${LC_AUTH_HEADER:-}" ] && [ -n "${LC_USER}" ]; then
    LC_TOKEN=""
    if [ -n "${LC_PASS}" ]; then
        LC_TOKEN=$(curl -s -X POST "${LC_API}/login/password" \
            -H "Content-Type: application/json" \
            -d "{\"user_name\":\"${LC_USER}\",\"password\":\"${LC_PASS}\"}" \
            | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")
    fi
    [ -n "${LC_TOKEN}" ] || LC_TOKEN="${LC_USER}"
    export LC_AUTH_HEADER="Authorization: Bearer ${LC_TOKEN}"
fi

# Build skip-set from existing articles
mapfile -t EXISTING < <(
    lc_row_list "$ARTICLES_TABLE_ID" 500 2>/dev/null \
      | python3 -c "
import json, sys
rows = json.load(sys.stdin)
for r in rows:
    t = r.get('row_data', {}).get('$TITLE_COLUMN_ID', '')
    if t: print(t)
" 2>/dev/null
)
log "existing articles: ${#EXISTING[@]}"

contains() {
    local needle="$1"; shift
    local h
    for h in "$@"; do [ "$h" = "$needle" ] && return 0; done
    return 1
}

DONE=0; SPAWNED=0; FAILED=0
for a_line in "${A_LINES[@]}"; do
    a_title="${a_line%%$'\t'*}"; a_desc="${a_line#*$'\t'}"
    for b_line in "${B_LINES[@]}"; do
        b_title="${b_line%%$'\t'*}"; b_desc="${b_line#*$'\t'}"
        for c_line in "${C_LINES[@]}"; do
            c_title="${c_line%%$'\t'*}"; c_desc="${c_line#*$'\t'}"
            article_title="${a_title}-${b_title}-${c_title}"
            if [ ${#EXISTING[@]} -gt 0 ] && contains "$article_title" "${EXISTING[@]}"; then
                log "[skip] $article_title already exists"
                DONE=$((DONE + 1))
                continue
            fi
            log "[spawn] worker for $article_title"
            if bash "${SCRIPT_DIR}/worker.sh" \
                "$a_title" "$a_desc" \
                "$b_title" "$b_desc" \
                "$c_title" "$c_desc" 2>&1 | tee -a "$LOG"; then
                DONE=$((DONE + 1))
            else
                FAILED=$((FAILED + 1))
                log "[fail] worker $article_title returned non-zero"
            fi
            SPAWNED=$((SPAWNED + 1))
            sleep 1
        done
    done
done

log "spawned=$SPAWNED done=$DONE failed=$FAILED expected=$EXPECTED"
[ "$DONE" -ge "$EXPECTED" ] || { log "FAIL: only $DONE/$EXPECTED done"; exit 1; }
log "ALL_DONE"
