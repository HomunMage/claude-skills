---
name: developing-fastapi
description: FastAPI backend development — async-by-default. Use when writing FastAPI routes, DB access, or any I/O call in the backend.
version: 0.1.0
---

# FastAPI: Async by Default

**Every I/O call MUST be awaitable. One blocking call freezes the entire event loop — a single slow upload makes the whole backend appear dead to all other users.**

## Core Rule

Single-worker async servers share one event loop. Any sync I/O call blocks every concurrent request until it finishes.

```
one sync put_object(100MB) → every other user stares at a spinner for 30s
```

## Required Patterns

### DB (SQLAlchemy)
- `AsyncSession` + `await session.execute(...)` — never sync `Session`
- FastAPI dep: `session: AsyncSession = Depends(get_session)`

### S3 / MinIO / boto3 (sync library — must offload)
```python
await asyncio.to_thread(
    client.put_object, Bucket=..., Key=..., Body=...
)
await asyncio.to_thread(client.get_object, Bucket=..., Key=...)
```

### HTTP
- `httpx.AsyncClient` — never `requests`

### File I/O
- `aiofiles` or `await asyncio.to_thread(open, ...)`
- UploadFile large bodies: stream `async for chunk in file` — don't `await file.read()` on big files

### Sleep / Timers
- `await asyncio.sleep(n)` — never `time.sleep(n)`

## Anti-patterns (will freeze event loop)

```python
# BAD — sync boto3 in async route
@router.put("/file")
async def upload(file: UploadFile):
    client.put_object(Bucket=..., Body=await file.read())  # blocks

# GOOD
@router.put("/file")
async def upload(file: UploadFile):
    content = await file.read()
    await asyncio.to_thread(client.put_object, Bucket=..., Body=content)
```

```python
# BAD — requests in async route
r = requests.get(url)  # blocks

# GOOD
async with httpx.AsyncClient() as c:
    r = await c.get(url)
```

## Uvicorn Workers

- **Dev:** 1 worker (`--reload` requires it; avoids init races like duplicate auto-created users)
- **Prod I/O-bound (our case):** 1–2 workers is enough — async handles concurrency on one loop
- **Prod CPU-bound:** 1 worker per core

Never ship `--workers 4` as a default "for performance" on async code — it multiplies memory and race conditions without helping I/O throughput.

## Session Lifecycle

FastAPI session deps should be minimal:

```python
async def get_session():
    async with app_session_factory() as session:
        yield session
```

Don't wrap with `finally: rollback()` as a "safety net". If you need that, something upstream is leaking — fix the root cause. Unconditional rollback hides real bugs.

## Smell Test

Before merging, grep your diff:
- `requests.` → switch to `httpx.AsyncClient`
- `\.put_object\(|\.get_object\(|\.list_objects|\.head_object|\.delete_object` without `asyncio.to_thread` → wrap it
- `time\.sleep` → `asyncio.sleep`
- Any sync DB call in an async route → convert to async

## Why This Matters

Real incident: single large MinIO upload held the event loop for seconds. Every other user's request to list tables, fetch workspaces, or load the sidebar stalled. Looked like "backend died." Root cause: `client.put_object(...)` without `asyncio.to_thread`. See CHANGELOG v0.18.
