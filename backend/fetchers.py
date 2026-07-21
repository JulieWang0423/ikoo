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


_BROWSER_HEADERS = {
    "User-Agent": MOBILE_UA,
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9,zh-CN;q=0.8",
}


def _fetch_og(client: httpx.Client, url: str) -> dict:
    resp = client.get(url, headers=_BROWSER_HEADERS)
    resp.raise_for_status()
    og = _parse_og(resp.text)
    return {
        "raw_title": og.get("title"),
        "raw_description": og.get("description"),
        "thumbnail_url": og.get("image"),
    }


def fetch(url: str) -> dict:
    """Returns {source, fetch_status, raw_title, raw_description}."""
    source = detect_source(url)
    result = {
        "source": source,
        "fetch_status": "unreachable",
        "raw_title": None,
        "raw_description": None,
        "thumbnail_url": None,
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
            else:
                result.update(_fetch_og(client, url))

            if result["raw_title"] or result["raw_description"]:
                result["fetch_status"] = "ok"
    except httpx.HTTPError:
        pass
    return result
