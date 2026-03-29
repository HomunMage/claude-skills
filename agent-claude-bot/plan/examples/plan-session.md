# Example Planning Session

This shows what a `/claude-bot plan` session looks like.

---

## User starts

```
/claude-bot plan
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
> I'll write the design to `.tmp/llm.design.api.md` for your review.

## Claude writes design doc

Written to `.tmp/llm.design.api.md` — user reviews and approves.

## Claude produces tickets

> Here are the tickets. Each is <15 min, independently testable:
>
> ### Phase 1: Setup (2 tickets)
> - Add Prisma with PostgreSQL — schema with User, Post, Comment models
> - Add base Express app with error handling, CORS, health check
>
> ### Phase 2: Auth (2 tickets)
> - Add register endpoint — POST /auth/register, bcrypt hash, return JWT
> - Add login endpoint + auth middleware — POST /auth/login, JWT verify
>
> ### Phase 3: CRUD (3 tickets)
> - Add Post CRUD — GET/POST /posts, GET/PUT/DELETE /posts/:id
> - Add Comment endpoints — GET/POST /posts/:id/comments, DELETE /comments/:id
> - Add pagination to GET /posts and GET /posts/:id/comments
>
> **Total: 7 tickets, 3 phases**
>
> **Approve these tickets? I'll create them in LatticeCast PM.**

## User approves

> Looks good, go!

## Claude creates tickets in LatticeCast PM

Actions taken:
1. Ensured LatticeCast PM is running (`curl http://localhost:13491/api/status`)
2. Created 7 tickets in LatticeCast PM table (each as a row with Title, Type=task, Status=todo, Priority, Tags=phase-N)
3. Wrote detailed notes to each ticket's doc in MinIO (`PUT /api/tables/{id}/rows/{id}/doc`)
4. Created `.tmp/claude-bot/start.sh` — launches workers in tmux

Now the user can run:
```bash
bash .tmp/claude-bot/start.sh
```

Workers will query LatticeCast PM for `todo` tickets and start working.
