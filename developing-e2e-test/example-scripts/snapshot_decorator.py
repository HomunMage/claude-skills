"""@snapshot — opt-in per-step screenshot for e2e tests.

No-op unless set_snapshot_enabled(True). Output goes to /output/<step>.png
inside the browser container (bind-mounted to ./.browser/ on the host).
"""

from functools import wraps
from pathlib import Path

_ENABLED = False
_OUT_DIR = Path("/output")


def set_snapshot_enabled(flag: bool) -> None:
    global _ENABLED
    _ENABLED = bool(flag)


def set_output_dir(path: str) -> None:
    global _OUT_DIR
    _OUT_DIR = Path(path)


def snapshot(fn):
    """Per-step screenshot. Captures on success AND on assertion failure
    (try/finally) — a failed run still shows you the progression up to
    the failing step. Re-run a single test file with --snapshot to debug.
    """
    @wraps(fn)
    def wrapper(ctx, *args, **kwargs):
        try:
            return fn(ctx, *args, **kwargs)
        finally:
            if _ENABLED:
                _OUT_DIR.mkdir(parents=True, exist_ok=True)
                ctx.page.screenshot(
                    path=str(_OUT_DIR / f"{fn.__name__}.png"),
                    full_page=True,
                )
    return wrapper
