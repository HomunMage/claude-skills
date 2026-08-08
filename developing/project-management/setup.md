# First-Time Setup

Only needed once per project. After setup, use the main skill for daily operations.

## How Auth Works (dev mode)

`.env` has `AUTH_REQUIRED=false`. In this mode:
- `POST /api/v1/login/password` accepts any password and returns the user's UUID as `access_token`
- The token IS the `user_id` (UUID) — pass it as `Authorization: Bearer <uuid>` for every subsequent call
- **Auto-create-user is DISABLED** (since v0.21, to avoid multi-worker INSERT races) — calling an endpoint with an unknown identifier returns 403, NOT an auto-created user
- New users must be created by an admin via `POST /api/v1/admin/users`

## Setup Sequence

### 1. Ensure running
```bash
curl -s http://localhost:13491/api/v1/status 2>/dev/null | grep -q '"ok"'
```

If not running, tell user:
> **LatticeCast PM is not running.** Start it:
> ```bash
> cd <LatticeCast-repo> && docker compose up -d
> ```

### 2. Login as admin → get $ADMIN_TOKEN

The admin user must already exist (seeded via DBA on first deploy). Login:

```bash
ADMIN_TOKEN=$(curl -s -X POST http://localhost:13491/api/v1/login/password \
  -H "Content-Type: application/json" \
  -d '{"user_name":"<admin_user_name>","password":""}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
```

### 3. Create bot user `claude` (admin-only)

```bash
curl -s -X POST http://localhost:13491/api/v1/admin/users \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"user_name":"claude","email":"claude@bot.local","role":"user"}'
```

### 4. Login as bot → get $TOKEN

```bash
TOKEN=$(curl -s -X POST http://localhost:13491/api/v1/login/password \
  -H "Content-Type: application/json" \
  -d '{"user_name":"claude","password":""}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
```

### 5. Create workspace
```bash
PROJECT_NAME="$(basename $(git rev-parse --show-toplevel 2>/dev/null || pwd))"
WORKSPACE_ID=$(curl -s -X POST http://localhost:13491/api/v1/workspaces \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"workspace_name\": \"${PROJECT_NAME}\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['workspace_id'])")
# WORKSPACE_ID is a UUID
```

### 6. Ask user for team members
Ask: **"Which user IDs should have access? (e.g. lattice, alice@example.com)"**

### 7. Add members
```bash
# Each member must already be a registered user. If not, admin creates them first
# (step 3 pattern). Then add to workspace:
curl -s -X POST "http://localhost:13491/api/v1/workspaces/${WORKSPACE_ID}/members" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"user_name": "<member_user_name>", "role": "member"}'
```

### 8. Create PM table
```bash
curl -s -X POST http://localhost:13491/api/v1/tables/template/pm \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"${PROJECT_NAME}\", \"workspace_id\": \"${WORKSPACE_ID}\"}"
```

### 9. Report URL
```
Project board: http://localhost:13491/${WORKSPACE_ID}/${PROJECT_NAME}
Views: Table | Sprint Board (Kanban) | Roadmap (Timeline)
```
