"""Rendert export/lageplan-waldenberg.jpg aus dem fertigen Lageplan.

Aufruf aus dem Repo-Wurzelverzeichnis:  python3 tools/render_export.py
Braucht Playwright; der Chromium-Pfad laesst sich ueber CHROMIUM_PATH setzen.
"""
import asyncio
import os
import pathlib

from playwright.async_api import async_playwright

REPO = pathlib.Path(__file__).resolve().parent.parent
CHROMIUM = os.environ.get("CHROMIUM_PATH", "/opt/pw-browsers/chromium")


async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch(executable_path=CHROMIUM)
        page = await browser.new_page(viewport={"width": 1400, "height": 700},
                                      device_scale_factor=2)
        await page.goto((REPO / "lageplan-waldenberg.html").as_uri())
        plan = await page.query_selector("svg.plan")
        await plan.screenshot(path=str(REPO / "export" / "lageplan-waldenberg.jpg"),
                              type="jpeg", quality=92)
        await browser.close()


asyncio.run(main())
