# Example Planning Session

This shows what a `/claude-plan` session looks like.

---

## User starts

```
/claude-plan /home/user/my-api-project
```

## Claude reads the project

> I've analyzed your project. Here's what I found:
>
> - **Tech stack**: Node.js + TypeScript + Express
> - **Existing code**: Empty scaffold with package.json and tsconfig.json
> - **Tests**: Jest configured but no tests yet
> - **Database**: None configured yet
>
> **What do you want to build?**

## User explains

> I want a REST API for a blog platform. Users can create posts, comment on posts.
> Authentication with JWT. PostgreSQL for storage. Keep it simple — MVP only.

## Claude proposes approach

> Got it. Here's my proposed approach:
>
> **Data models**: User (email, password_hash, name), Post (title, body, author_id), Comment (body, post_id, author_id)
>
> **API endpoints**:
> - POST /auth/register, POST /auth/login
> - GET/POST /posts, GET/PUT/DELETE /posts/:id
> - GET/POST /posts/:id/comments
>
> **Auth**: JWT tokens, bcrypt for passwords, middleware for protected routes
>
> **Database**: Prisma ORM with PostgreSQL
>
> **Questions**:
> 1. Do you want pagination on list endpoints?
> 2. Should users be able to edit/delete their own comments?
> 3. Any rate limiting needed for MVP?

## User answers

> 1. Yes, simple offset/limit pagination
> 2. Yes, delete only (no edit)
> 3. No, skip for MVP

## Claude produces tickets

> Here are the tickets. Each is <15 min, independently testable:
>
> ### Phase 1: Setup (2 tickets, parallelizable)
> - [ ] Add Prisma with PostgreSQL — schema with User, Post, Comment models, migration
> - [ ] Add base Express app with error handling, CORS, health check endpoint
>
> ### Phase 2: Auth (2 tickets, sequential)
> - [ ] Add register endpoint — POST /auth/register, bcrypt hash, return JWT
> - [ ] Add login endpoint + auth middleware — POST /auth/login, JWT verify middleware
>
> ### Phase 3: CRUD (3 tickets, parallelizable after auth)
> - [ ] Add Post CRUD — GET/POST /posts, GET/PUT/DELETE /posts/:id (auth required for write)
> - [ ] Add Comment endpoints — GET/POST /posts/:id/comments, DELETE /comments/:id (own only)
> - [ ] Add pagination to GET /posts and GET /posts/:id/comments (offset/limit query params)
>
> **Total: 7 tickets, 3 phases**
> **Parallelism: Phase 1 = 2 workers, Phase 2 = 1 worker, Phase 3 = 2-3 workers**
>
> **Ready to start `/claude-bot`?**

## User approves

> Looks good, go!

## Claude creates the files

Files written:
- `.tmp/llm.plan.status` — 7 tickets across 3 phases
- `CLAUDE.md` — dev rules with `npm test`, `npx prettier --write .`, Prisma conventions
- `.tmp/llm.working.log` — initialized with `[PLAN] 7 tickets across 3 phases`
- `.tmp/llm.working.notes` — design decisions (JWT, bcrypt, Prisma, pagination approach)
- `.tmp/claude-bot/worker1.sh` — worker for Phase 1-2 tickets (database + auth scope)
- `.tmp/claude-bot/worker2.sh` — worker for Phase 3 tickets (CRUD + pagination scope)
- `.tmp/claude-bot/start.sh` — launches both workers in tmux with orchestration

Now the user can run:
```bash
bash .tmp/claude-bot/start.sh
```
