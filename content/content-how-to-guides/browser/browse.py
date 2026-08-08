"""
Browse and screenshot tool for how-to-guides.

Usage:
    docker compose --profile browser up -d
    docker compose --profile browser exec browser python browse.py <url> [--steps steps.json]

Without --steps: opens URL, takes a single screenshot.
With --steps: executes each step (click, fill, wait, scroll) and screenshots after each.

Steps JSON format:
[
    {"action": "screenshot", "name": "01-landing"},
    {"action": "click", "selector": "#login-btn", "name": "02-click-login"},
    {"action": "fill", "selector": "#email", "value": "user@example.com", "name": "03-fill-email"},
    {"action": "wait", "ms": 2000, "name": "04-after-wait"},
    {"action": "scroll", "y": 500, "name": "05-scrolled"},
    {"action": "screenshot", "name": "06-final"}
]

Output: /output/<name>.png for each step
Then convert with: ffmpeg -i input.png input.webp
"""

import argparse
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright


OUTPUT_DIR = Path("/output")


def take_screenshot(page, name: str):
    path = OUTPUT_DIR / f"{name}.png"
    page.screenshot(path=str(path), full_page=False)
    print(f"  screenshot: {path}")


def run_steps(page, steps: list):
    for i, step in enumerate(steps):
        action = step.get("action", "screenshot")
        name = step.get("name", f"step-{i:02d}")

        if action == "screenshot":
            take_screenshot(page, name)

        elif action == "click":
            selector = step["selector"]
            print(f"  click: {selector}")
            page.click(selector)
            page.wait_for_load_state("networkidle")
            take_screenshot(page, name)

        elif action == "fill":
            selector = step["selector"]
            value = step["value"]
            print(f"  fill: {selector} = {value}")
            page.fill(selector, value)
            take_screenshot(page, name)

        elif action == "wait":
            ms = step.get("ms", 1000)
            print(f"  wait: {ms}ms")
            page.wait_for_timeout(ms)
            take_screenshot(page, name)

        elif action == "scroll":
            y = step.get("y", 500)
            print(f"  scroll: {y}px")
            page.evaluate(f"window.scrollBy(0, {y})")
            page.wait_for_timeout(500)
            take_screenshot(page, name)

        else:
            print(f"  unknown action: {action}, skipping")


def main():
    parser = argparse.ArgumentParser(description="Browse and screenshot for how-to-guides")
    parser.add_argument("url", help="URL to open")
    parser.add_argument("--steps", help="Path to steps JSON file")
    parser.add_argument("--width", type=int, default=1280, help="Viewport width")
    parser.add_argument("--height", type=int, default=720, help="Viewport height")
    args = parser.parse_args()

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": args.width, "height": args.height})

        print(f"Opening: {args.url}")
        page.goto(args.url, wait_until="networkidle")

        if args.steps:
            with open(args.steps) as f:
                steps = json.load(f)
            run_steps(page, steps)
        else:
            take_screenshot(page, "screenshot")

        browser.close()
    print("Done.")


if __name__ == "__main__":
    main()
