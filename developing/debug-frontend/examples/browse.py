#!/usr/bin/env python3
"""
Browser automation script for frontend debugging via Docker.

Setup:
    docker compose --profile browser up -d browser

Usage:
    docker compose exec browser python browse.py status [URL]
    docker compose exec browser python browse.py screenshot [name]
    docker compose exec browser python browse.py click "Button Text"
    docker compose exec browser python browse.py menu
    docker compose exec browser python browse.py buttons
"""

import sys
import json
from datetime import datetime
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeout

# Change this to your dev server URL
BASE_URL = "http://host.docker.internal:5173"
SCREENSHOT_DIR = "/output"


def get_browser():
    """Create a browser instance."""
    playwright = sync_playwright().start()
    browser = playwright.chromium.launch(headless=True)
    context = browser.new_context(
        viewport={"width": 1280, "height": 720},
        ignore_https_errors=True
    )
    page = context.new_page()
    return playwright, browser, page


def cmd_status(page, url=BASE_URL):
    """Check page status and return info."""
    try:
        response = page.goto(url, wait_until="networkidle", timeout=30000)

        result = {
            "url": page.url,
            "title": page.title(),
            "status": response.status if response else "unknown",
            "ok": response.ok if response else False,
            "timestamp": datetime.now().isoformat(),
        }

        # Check for visible elements
        result["elements"] = {
            "buttons": len(page.locator("button").all()),
            "inputs": len(page.locator("input, textarea").all()),
            "links": len(page.locator("a").all()),
        }

        # Check for error messages
        error_el = page.locator("text=/error|failed|not found/i").first
        if error_el.count() > 0:
            result["error_visible"] = True
            result["error_text"] = error_el.text_content()
        else:
            result["error_visible"] = False

        # Get page text summary
        body_text = page.locator("body").text_content() or ""
        result["text_preview"] = body_text[:500].strip()

        print(json.dumps(result, indent=2))
        return result

    except PlaywrightTimeout:
        print(json.dumps({"error": "Timeout loading page", "url": url}))
        return None
    except Exception as e:
        print(json.dumps({"error": str(e), "url": url}))
        return None


def cmd_screenshot(page, url=BASE_URL, name=None):
    """Take a screenshot of the page."""
    try:
        page.goto(url, wait_until="networkidle", timeout=30000)

        if name is None:
            name = datetime.now().strftime("%Y%m%d_%H%M%S")

        filepath = f"{SCREENSHOT_DIR}/{name}.png"
        page.screenshot(path=filepath, full_page=True)

        print(json.dumps({
            "success": True,
            "file": filepath,
            "url": page.url,
            "title": page.title()
        }))
        return filepath

    except Exception as e:
        print(json.dumps({"error": str(e)}))
        return None


def cmd_click(page, selector, url=BASE_URL):
    """Click an element on the page."""
    try:
        page.goto(url, wait_until="networkidle", timeout=30000)

        # Try different selector strategies
        element = None
        strategies = [
            lambda: page.locator(f"[data-testid='{selector}']").first,
            lambda: page.locator(f"text={selector}").first,
            lambda: page.locator(f"button:has-text('{selector}')").first,
            lambda: page.locator(f"[aria-label*='{selector}']").first,
            lambda: page.locator(selector).first,
        ]

        for strategy in strategies:
            try:
                el = strategy()
                if el.count() > 0:
                    element = el
                    break
            except Exception:
                continue

        if element is None:
            print(json.dumps({"error": f"Element not found: {selector}"}))
            return None

        # Click the element
        element.click()
        page.wait_for_load_state("networkidle", timeout=5000)

        # Take screenshot after click
        filepath = f"{SCREENSHOT_DIR}/after_click_{datetime.now().strftime('%H%M%S')}.png"
        page.screenshot(path=filepath)

        print(json.dumps({
            "success": True,
            "clicked": selector,
            "current_url": page.url,
            "screenshot": filepath
        }))
        return True

    except Exception as e:
        print(json.dumps({"error": str(e)}))
        return None


def cmd_menu(page, url=BASE_URL):
    """Open the menu and list available options."""
    try:
        page.goto(url, wait_until="networkidle", timeout=30000)

        # Find and click menu button (prefer data-testid)
        menu_btn = page.locator("[data-testid='menu-toggle']").first
        if menu_btn.count() == 0:
            menu_btn = page.locator("[aria-label='Toggle menu']").first
        if menu_btn.count() == 0:
            menu_btn = page.locator("button").filter(has=page.locator("svg")).first

        if menu_btn.count() > 0:
            menu_btn.click()
            page.wait_for_timeout(500)

            # Get menu items (prefer data-testid nav)
            menu_nav = page.locator("[data-testid='menu-nav']")
            if menu_nav.count() > 0:
                menu_items = menu_nav.locator("button").all()
            else:
                menu_items = page.locator("nav button").all()
            items = [btn.text_content().strip() for btn in menu_items]

            # Take screenshot
            filepath = f"{SCREENSHOT_DIR}/menu_{datetime.now().strftime('%H%M%S')}.png"
            page.screenshot(path=filepath)

            print(json.dumps({
                "success": True,
                "menu_open": True,
                "items": items,
                "screenshot": filepath
            }))
            return items
        else:
            print(json.dumps({"error": "Menu button not found"}))
            return None

    except Exception as e:
        print(json.dumps({"error": str(e)}))
        return None


def cmd_buttons(page, url=BASE_URL):
    """List all visible buttons on the page."""
    try:
        page.goto(url, wait_until="networkidle", timeout=30000)

        buttons = page.locator("button:visible").all()
        button_info = []

        for btn in buttons:
            try:
                text = btn.text_content().strip()
                disabled = btn.is_disabled()
                button_info.append({
                    "text": text[:50] if text else "(no text)",
                    "disabled": disabled,
                    "visible": btn.is_visible()
                })
            except Exception:
                continue

        print(json.dumps({
            "url": page.url,
            "buttons": button_info,
            "count": len(button_info)
        }, indent=2))
        return button_info

    except Exception as e:
        print(json.dumps({"error": str(e)}))
        return None


def main():
    if len(sys.argv) < 2:
        print("Usage: python browse.py <command> [args]")
        print("Commands: status, screenshot, click <selector>, menu, buttons")
        sys.exit(1)

    command = sys.argv[1]

    playwright, browser, page = get_browser()

    try:
        if command == "status":
            url = sys.argv[2] if len(sys.argv) > 2 else BASE_URL
            cmd_status(page, url)

        elif command == "screenshot":
            name = sys.argv[2] if len(sys.argv) > 2 else None
            cmd_screenshot(page, BASE_URL, name)

        elif command == "click":
            if len(sys.argv) < 3:
                print("Usage: python browse.py click <selector>")
                sys.exit(1)
            cmd_click(page, sys.argv[2])

        elif command == "menu":
            cmd_menu(page)

        elif command == "buttons":
            cmd_buttons(page)

        else:
            print(f"Unknown command: {command}")
            sys.exit(1)

    finally:
        browser.close()
        playwright.stop()


if __name__ == "__main__":
    main()
