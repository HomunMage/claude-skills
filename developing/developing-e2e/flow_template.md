# E2E Flow Template

Canonical sequence that exercises CRUD across workspaces, tables,
schemas, and views. Each step:

- one Playwright action
- one DB check
- one UI check
- decorated with `@snapshot`

```
== bootstrap (no browser, runs once per file) ========================
PG    : INSERT admin user_id=00…ad1 into auth.users + gdpr.user_info
BE    : POST /login/password → ADMIN_TOKEN
BE    : POST /admin/users    → creates test_usr_<YYYYMMDD>
BE    : POST /login/password → USER_TOKEN
BE    : POST /workspaces     → default workspace named like the user

== auth (Playwright) =================================================
step_login_as_admin         → DB: session/last_login; UI: .user-menu
step_logout                 → DB: token revoked; UI: /login route
step_login_as_user          → DB: session; UI: workspace list visible

== workspace ========================================================
step_use_default_workspace  → DB: workspace_members has user; UI: sidebar shows ws
step_create_workspace_test2 → DB: row in public.workspaces; UI: sidebar adds entry

== tables ==========================================================
step_create_table_from_pm    → DB: tables row + table_schemas.config.columns ≠ []
                                 + table_views ≥ 1 row;
                               UI: sidebar entry + main grid header
step_create_table_blank      → DB: tables row + table_schemas.config.columns == default;
                               UI: sidebar entry + empty main grid

== schema ==========================================================
step_add_column             → DB: table_schemas.config.columns appended +
                                  idx_rd_<tid>_<col> index exists;
                              UI: new column header in grid
step_update_column_label    → DB: columns[i].name updated;
                              UI: header text updated
step_delete_column          → DB: column removed + idx dropped;
                              UI: column gone from grid

== views ==========================================================
step_create_kanban_view     → DB: table_views row + view_id in view_order;
                              UI: view tab appears
step_change_kanban_group_by → DB: view.config.group_by = new col_id;
                              UI: kanban regroups (.kanban-column-header)
step_set_default_view       → DB: table_schemas.config.default_view = view_id;
                              UI: default badge / route resolution

== data ==========================================================
step_add_row                → DB: rows table row + row_id auto-assigned;
                              UI: new row in grid
step_edit_row_cell          → DB: row_data jsonb patched;
                              UI: cell text updated
step_delete_row             → DB: row gone;
                              UI: row removed from grid

== cleanup ==========================================================
DELETE FROM auth.users WHERE user_name LIKE 'test\\_%' ESCAPE '\\';
```

Use this as the skeleton for `browser/e2e_test_basic.py`. Add /
remove steps per feature focus, but **never skip the paired
DB-check + UI-check** for any mutation.
