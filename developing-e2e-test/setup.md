# E2E Setup — Bootstrap Test Users

Before Playwright runs, build the user fixture via direct PG + BE.

## Naming

| Role | Name |
|---|---|
| Admin | `test_ad` (constant) |
| Regular | `test_usr_<YYYYMMDD>` (date-suffixed) |
| Workspace | same as regular user_name |

Date suffix avoids cross-run collision. For multiple runs/day use
`test_usr_<YYYYMMDDhhmm>`.

## Steps

1. **PG INSERT admin**

   ```sql
   INSERT INTO auth.users (user_id, role)
   VALUES ('00000000-0000-0000-0000-000000000ad1', 'admin')
   ON CONFLICT (user_id) DO NOTHING;

   INSERT INTO gdpr.user_info (user_id, email, user_name, config)
   VALUES (
       '00000000-0000-0000-0000-000000000ad1',
       'test_ad@e2e.local',
       'test_ad',
       '{}'::JSONB
   )
   ON CONFLICT (user_id) DO NOTHING;
   ```

2. **BE login admin** → admin token

   ```bash
   ADMIN_TOKEN=$(curl -s -X POST $URL/api/v1/login/password \
     -H 'Content-Type: application/json' \
     -d '{"user_name":"test_ad","password":""}' \
     | jq -r .access_token)
   ```

3. **BE admin creates regular user**

   ```bash
   USER=test_usr_$(date -u +%Y%m%d)
   curl -X POST $URL/api/v1/admin/users \
     -H "Authorization: Bearer $ADMIN_TOKEN" \
     -H 'Content-Type: application/json' \
     -d "{\"user_name\":\"$USER\",\"email\":\"$USER@e2e.local\"}"
   ```

4. **BE login regular user** → token + default workspace

   ```bash
   USER_TOKEN=$(curl -s -X POST $URL/api/v1/login/password \
     -H 'Content-Type: application/json' \
     -d "{\"user_name\":\"$USER\",\"password\":\"\"}" \
     | jq -r .access_token)

   curl -X POST $URL/api/v1/workspaces \
     -H "Authorization: Bearer $USER_TOKEN" \
     -H 'Content-Type: application/json' \
     -d "{\"workspace_name\":\"$USER\"}"
   ```

## Idempotent re-runs

`ON CONFLICT DO NOTHING` on `auth.users` + `gdpr.user_info` makes the PG
step safe to repeat. BE endpoints return 409 on duplicate — wrap in
`|| true` if you ignore that.

To wipe fully:

```sql
DELETE FROM auth.users WHERE user_id IN (
    SELECT user_id FROM gdpr.user_info WHERE user_name LIKE 'test\_%' ESCAPE '\'
);
-- gdpr.user_info CASCADEs from auth.users
-- workspaces / tables / rows CASCADE from workspace_members
```
