"""Claude structured extraction: caption text -> place/event candidates."""

import json
import os

import anthropic

MODEL = os.environ.get("IKOO_MODEL", "claude-haiku-4-5-20251001")

EXTRACT_TOOL = {
    "name": "report_candidates",
    "description": "Report every distinct physical place or dated event mentioned in the post.",
    "input_schema": {
        "type": "object",
        "properties": {
            "candidates": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "name": {
                            "type": "string",
                            "description": "Name of the place/event. If the post is in Chinese, keep the original name AND append a romanized or English form in parentheses if one is well known.",
                        },
                        "kind": {"type": "string", "enum": ["place", "event"]},
                        "category": {
                            "type": "string",
                            "description": "One of: restaurant, cafe, bar, sight, shop, nature, event, other",
                        },
                        "city_hint": {"type": "string", "description": "City or area, if inferable"},
                        "address_hint": {"type": "string", "description": "Street/district hint if mentioned"},
                        "event_start": {"type": "string", "description": "ISO date YYYY-MM-DD if explicit"},
                        "event_end": {"type": "string", "description": "ISO date YYYY-MM-DD if explicit"},
                        "raw_date_text": {"type": "string", "description": "Verbatim date phrase, e.g. 'this weekend'"},
                        "confidence": {
                            "type": "number",
                            "description": "0-1: how confident you are this is a real, findable place",
                        },
                        "evidence": {"type": "string", "description": "Short quote from the post mentioning it"},
                    },
                    "required": ["name", "kind", "confidence"],
                },
            }
        },
        "required": ["candidates"],
    },
}

SYSTEM = """You extract physical places and dated events from shared content — \
social media captions (TikTok, RedNote/Xiaohongshu) AND travel articles, blog \
posts, newsletters, and "best of" listicles. Content may be English, Chinese, \
or mixed. Report every distinct named place a person could physically visit and \
locate on a map — a long article may name a dozen restaurants, cafes, and sights, \
so extract them all. Skip vague mentions ("this city"), hashtag spam, website \
navigation/boilerplate, and author or publication names. Resolve relative dates \
("this Saturday") against the share date when given, and put the verbatim phrase \
in raw_date_text. Lower your confidence when a place name is generic or ambiguous."""


def extract(text: str, shared_at: str | None, locale_hint: str | None) -> list[dict]:
    client = anthropic.Anthropic()
    user_content = f"Post content:\n{text}"
    if shared_at:
        user_content += f"\n\nShared on: {shared_at}"
    if locale_hint:
        user_content += f"\nUser locale: {locale_hint}"

    message = client.messages.create(
        model=MODEL,
        max_tokens=4096,
        system=SYSTEM,
        tools=[EXTRACT_TOOL],
        tool_choice={"type": "tool", "name": "report_candidates"},
        messages=[{"role": "user", "content": user_content}],
    )
    for block in message.content:
        if block.type == "tool_use" and block.name == "report_candidates":
            candidates = block.input.get("candidates", [])
            return [c for c in candidates if isinstance(c, dict) and c.get("name")]
    return []
