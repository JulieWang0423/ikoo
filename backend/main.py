"""ikoo extraction backend.

POST /extract: shared URL and/or caption -> place/event candidates.
Stateless: no DB, no user data stored. All failures degrade to empty
candidates so the app's manual path keeps working.

Run locally:
    export ANTHROPIC_API_KEY=sk-ant-...   # optional; without it, fetch-only
    uvicorn main:app --port 8000
"""

import logging
import os

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel

import fetchers

logger = logging.getLogger("ikoo")
logging.basicConfig(level=logging.INFO)

APP_TOKEN = os.environ.get("IKOO_APP_TOKEN", "dev-token")

app = FastAPI(title="ikoo backend")

# Tiny in-memory cache so repeated shares of the same URL don't re-hit
# TikTok/RedNote (rate-limit protection). Reset on restart — fine.
_fetch_cache: dict[str, dict] = {}
_CACHE_MAX = 500


class ExtractRequest(BaseModel):
    url: str | None = None
    caption: str | None = None
    shared_at: str | None = None
    locale_hint: str | None = None


@app.post("/extract")
def extract(body: ExtractRequest, authorization: str = Header(default="")):
    if authorization != f"Bearer {APP_TOKEN}":
        raise HTTPException(status_code=401, detail="bad token")
    if not body.url and not body.caption:
        raise HTTPException(status_code=422, detail="need url or caption")

    result = {
        "source": "generic",
        "fetch_status": "ok",
        "raw_title": None,
        "raw_description": None,
        "candidates": [],
    }

    if body.url:
        if body.url in _fetch_cache:
            fetched = _fetch_cache[body.url]
        else:
            fetched = fetchers.fetch(body.url)
            if len(_fetch_cache) < _CACHE_MAX:
                _fetch_cache[body.url] = fetched
        result.update(fetched)

    text_parts = [
        p for p in (result["raw_title"], result["raw_description"], body.caption) if p
    ]
    text = "\n".join(dict.fromkeys(text_parts))  # dedupe, keep order

    if text and os.environ.get("ANTHROPIC_API_KEY"):
        try:
            import extractor

            result["candidates"] = extractor.extract(
                text, body.shared_at, body.locale_hint
            )
        except Exception:
            logger.exception("extraction failed")
            # Degrade: raw text still returned, app falls back to manual.

    return result


@app.get("/healthz")
def healthz():
    return {"ok": True}
