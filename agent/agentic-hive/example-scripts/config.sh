#!/bin/bash
# config.sh — project-local agentic-hive configuration template

export LC_API="http://localhost:13491/api/v1"
export LC_AUTH_HEADER="Authorization: Bearer lattice"
export PM_USER="lattice"
export TABLE_ID="demo_pm"
export WORKSPACE_ID="<workspace-uuid>"

_THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_DIR="$(cd "${_THIS_DIR}/../.." && pwd)"
export SKILLS_DIR="${PROJECT_DIR}/.agent-skills"

# LLM worker provider: claude or codex.
export LLM_PROVIDER="${LLM_PROVIDER:-${LLM_BACKEND:-claude}}"
export LLM_PROJECT_DIR="${PROJECT_DIR}"

# Optional provider-specific model overrides:
# export CLAUDE_MODEL="sonnet"
# export CODEX_MODEL="gpt-5.6-codex"
