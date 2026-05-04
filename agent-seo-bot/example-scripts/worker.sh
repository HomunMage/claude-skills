#!/usr/bin/env bash
# seo-bot/worker.sh — Fresh claude -p call for ONE article.
# Inputs come from the orchestrator's CSV-driven cross product.
# Usage: worker.sh <a_title> <a_desc> <b_title> <b_desc> <c_title> <c_desc>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SEO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck disable=SC1091
source "${SEO_DIR}/config.sh"
HELPER="${SEO_DIR}/table_helper.sh"

A_TITLE="${1:?a_title required}";  A_DESC="${2:?a_desc required}"
B_TITLE="${3:?b_title required}";  B_DESC="${4:?b_desc required}"
C_TITLE="${5:?c_title required}";  C_DESC="${6:?c_desc required}"

ARTICLE_TITLE="${A_TITLE}-${B_TITLE}-${C_TITLE}"
ARTICLE_FILE="${SEO_DIR}/.tmp/article-${ARTICLE_TITLE}.md"
PROMPT_FILE="${SEO_DIR}/.tmp/prompt-${ARTICLE_TITLE}.md"

log() { echo "$(date '+%H:%M:%S') [W ${ARTICLE_TITLE}] $*"; }

cat > "$PROMPT_FILE" <<EOF
You are an SEO copywriter. Write ONE article for this exact combination.

## Target Audience persona — ${A_TITLE}
${A_DESC}

## Promotion / 檔期 — ${B_TITLE}
${B_DESC}

## Featured Product — ${C_TITLE}
${C_DESC}

## Constraints
- Output ONE markdown file. First line is "# <title>" (the title).
- Length: at least 400 characters of substantive prose.
- Mention the persona name "${A_TITLE}" by name at least once.
- Mention the promotion name "${B_TITLE}" or its Chinese variant at least once.
- Mention the product name "${C_TITLE}" by name at least once.
- Persona-relevant pain point → product as solution → promo CTA.
- No filler. Don't include this prompt in the output.
- Do NOT mention any other persona name, promotion, or product. The
  driver's verifier checks this — single-combination only.

## Output
Write the article to this exact path: ${ARTICLE_FILE}

Then exit. Do NOT upload — the orchestrator handles upload.
EOF

log "spawning fresh claude -p (timeout 120s)"
timeout 120 claude -p --dangerously-skip-permissions "$(cat "$PROMPT_FILE")" \
    >/dev/null 2>&1 || true

if [ ! -s "$ARTICLE_FILE" ]; then
    log "FAIL: claude did not produce $ARTICLE_FILE"
    exit 1
fi

LEN=$(wc -c < "$ARTICLE_FILE")
log "article written, ${LEN} bytes"

if ! bash "$HELPER" articles create "$ARTICLE_TITLE" -f "$ARTICLE_FILE" >/dev/null 2>&1; then
    log "FAIL: upload via table_helper"
    exit 1
fi
log "uploaded OK"
