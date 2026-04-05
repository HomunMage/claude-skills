# First-Time Setup

Only needed once per project. After setup, use the main skill for daily operations.

## How Auth Works (dev mode)

`.env` has `AUTH_REQUIRED=false`. In this mode:
- `Bearer <value>` → the value IS the user_id (no OAuth needed)
- If user doesn't exist → auto-created on first API call
- `Bearer claude` → user_id = "claude" (bot user)
- `Bearer alice@gmail.com` → user_id = "alice@gmail.com"

## Setup Sequence

### 1. Ensure running
```bash
curl -s http://localhost:13491/api/status 2>/dev/null | grep -q '"ok"'
```

If not running, tell user:
> **LatticeCast PM is not running.** Start it:
> ```bash
> cd <LatticeCast-repo> && docker compose up -d backend frontend
> ```

### 2. Create bot user
```bash
curl -s http://localhost:13491/api/login/me -H "Authorization: Bearer claude"
```

### 3. Create workspace
```bash
PROJECT_NAME="$(basename $(git rev-parse --show-toplevel 2>/dev/null || pwd))"
curl -s -X POST http://localhost:13491/api/workspaces \
  -H "Authorization: Bearer claude" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"${PROJECT_NAME}\"}"
# → workspace_id = "claude/<PROJECT_NAME>"
```

### 4. Ask user for team members
Ask: **"Which user IDs should have access? (e.g. homunmage@gmail.com)"**

### 5. Add members
```bash
WORKSPACE_ID="claude/${PROJECT_NAME}"
# Ensure member user exists first (auto-created in dev mode)
curl -s http://localhost:13491/api/login/me -H "Authorization: Bearer <user_id>"
# Add to workspace
curl -s -X POST "http://localhost:13491/api/workspaces/${WORKSPACE_ID}/members" \
  -H "Authorization: Bearer claude" \
  -H "Content-Type: application/json" \
  -d '{"user_name": "<display_id>", "role": "member"}'
```

### 6. Create PM table
```bash
curl -s -X POST http://localhost:13491/api/tables/template/pm \
  -H "Authorization: Bearer claude" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"${PROJECT_NAME}\", \"workspace_id\": \"claude/${PROJECT_NAME}\"}"
```

### 7. Report URL
```
Project board: http://localhost:13491/tables/<table_id>
Views: Table | Sprint Board (Kanban) | Roadmap (Timeline)
```
