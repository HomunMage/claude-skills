# First-Time PM Setup

Do this once per project. Keep credentials and endpoint values in the
project's ignored `.env`, copied from the skill's `.env.example`.

```bash
set -a; source .env; set +a
source .agent-skills/developing/project-management/pm_tool.sh
lc_status
pm_login
```

The PM user must already be registered. Creating users is an admin action;
password login never creates an identity. A password-login response contains a
real JWT, not a user-name bearer token.

## Create workspace and PM table

```bash
WORKSPACE_NAME=<workspace-name-without-dots>
TABLE_ID=<pm-table-id>
WORKSPACE_JSON=$(lc_workspace_create "$WORKSPACE_NAME")
WORKSPACE_ID=$(printf '%s' "$WORKSPACE_JSON" | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["workspace_id"])')
lc_table_create_from_template "$TABLE_ID" "$WORKSPACE_ID"
```

Record `WORKSPACE_ID` and `TABLE_ID` in `.env`. The board is at
`<web-origin>/<workspace_id>/<table_id>`; derive the web origin from `LC_API`
instead of embedding a local host in automation. Workspace names must not
contain `.` because they become part of storage paths.

## Membership

Only an owner can add or change workspace members. Resolve a registered user
by UUID, user name, or email and add its intended `read`, `write`, or `owner`
level. The PM helper exposes `lc_workspace_member_add`; use a project-specific
wrapper when the member identifier is not a user name.

## Verify

```bash
pm_cache_cols
pm_col Title
pm_col Type
pm_col Status
pm_col Parent
```

Each command must emit a UUID. Do not start a hive until the PM template,
workspace membership, and `.env` values are verified.
