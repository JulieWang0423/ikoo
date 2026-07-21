"""Resolve shared URLs into raw text (title/caption) without logging in.

Everything here is best-effort: any failure degrades to fetch_status
"unreachable"/"partial" and the app falls back to manual search.
"""

import re

import httpx

TIMEOUT = 6.0

MOBILE_UA = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
)

# Article/blog sites often block the mobile Safari UA but accept a desktop one.
DESKTOP_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
)

_OG_PATTERNS = {
    "title": [
        re.compile(r'<meta[^>]+property=["\']og:title["\'][^>]+content=["\']([^"\']*)["\']', re.I),
        re.compile(r'<meta[^>]+content=["\']([^"\']*)["\'][^>]+property=["\']og:title["\']', re.I),
    ],
    "description": [
        re.compile(r'<meta[^>]+property=["\']og:description["\'][^>]+content=["\']([^"\']*)["\']', re.I),
        re.compile(r'<meta[^>]+content=["\']([^"\']*)["\'][^>]+property=["\']og:description["\']', re.I),
    ],
    "image": [
        re.compile(r'<meta[^>]+property=["\']og:image["\'][^>]+content=["\']([^"\']*)["\']', re.I),
        re.compile(r'<meta[^>]+content=["\']([^"\']*)["\'][^>]+property=["\']og:image["\']', re.I),
    ],
}


def detect_source(url: str) -> str:
    lowered = url.lower()
    if "tiktok.com" in lowered:
        return "tiktok"
    if "xhslink.com" in lowered or "xiaohongshu.com" in lowered:
        return "rednote"
    return "generic"


def _parse_og(html: str) -> dict:
    out = {}
    for key, patterns in _OG_PATTERNS.items():
        for pattern in patterns:
            match = pattern.search(html)
            if match:
                out[key] = match.group(1)
                break
    return out


_SCRIPT_STYLE = re.compile(r"<(script|style|noscript|svg)[^>]*>.*?</\1>", re.I | re.S)
_TAG = re.compile(r"<[^>]+>")
_WS = re.compile(r"\s+")
_ENTITIES = {"&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&#39;": "'", "&nbsp;": " "}


def _extract_article_text(html: str, limit: int = 8000) -> str | None:
    """Best-effort readable text from an article/blog/newsletter page. Strips
    scripts and tags rather than pulling a clean article body — good enough to
    feed the extractor, which is asked to pick out place names."""
    body = _SCRIPT_STYLE.sub(" ", html)
    # Prefer the <body> if present to skip <head> metadata noise.
    m = re.search(r"<body[^>]*>(.*)</body>", body, re.I | re.S)
    if m:
        body = m.group(1)
    text = _TAG.sub(" ", body)
    for ent, ch in _ENTITIES.items():
        text = text.replace(ent, ch)
    text = _WS.sub(" ", text).strip()
    if len(text) < 40:
        return None
    return text[:limit]


_BROWSER_HEADERS = {
    "User-Agent": MOBILE_UA,
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9,zh-CN;q=0.8",
}


def _fetch_og(client: httpx.Client, url: str, want_article: bool = False) -> dict:
    headers = dict(_BROWSER_HEADERS)
    if want_article:
        headers["User-Agent"] = DESKTOP_UA
    resp = client.get(url, headers=headers)
    resp.raise_for_status()
    og = _parse_og(resp.text)
    out = {
        "raw_title": og.get("title"),
        "raw_description": og.get("description"),
        "thumbnail_url": og.get("image"),
    }
    # For generic web pages (articles, newsletters, listicles), the og
    # description is just a teaser — pull the full body so every place named
    # in the article is available to the extractor.
    if want_article:
        out["raw_text"] = _extract_article_text(resp.text)
    return out


def fetch(url: str) -> dict:
    """Returns {source, fetch_status, raw_title, raw_description}."""
    source = detect_source(url)
    result = {
        "source": source,
        "fetch_status": "unreachable",
        "raw_title": None,
        "raw_description": None,
        "thumbnail_url": None,
        "raw_text": None,
    }
    try:
        with httpx.Client(timeout=TIMEOUT, follow_redirects=True) as client:
            if source == "tiktok":
                canonical = str(client.head(url, headers={"User-Agent": MOBILE_UA}).url)
                try:
                    oembed = client.get(
                        "https://www.tiktok.com/oembed", params={"url": canonical}
                    )
                    oembed.raise_for_status()
                    data = oembed.json()
                    result["raw_title"] = data.get("title")
                    result["raw_description"] = data.get("author_name")
                    result["thumbnail_url"] = data.get("thumbnail_url")
                    result["fetch_status"] = "ok" if data.get("title") else "partial"
                    return result
                except httpx.HTTPError:
                    # Photo-mode posts often 404 on oEmbed; try og tags.
                    result.update(_fetch_og(client, canonical))
            elif source == "rednote":
                result.update(_fetch_og(client, url))
            else:
                # Generic web page — pull the full article body too.
                result.update(_fetch_og(client, url, want_article=True))

            if result["raw_title"] or result["raw_description"] or result["raw_text"]:
                result["fetch_status"] = "ok"
    except httpx.HTTPError:
        pass
    return result
