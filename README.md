# ikoo

**Save places from social media, then get a quiet nudge when you're actually walking past one.**

You scroll TikTok or RedNote (小红书), see an amazing café or viewpoint, save the post — and never think about it again. ikoo fixes that. Share a post (or a travel article, or even a screenshot) and ikoo pulls out every place it names, pins them on your map, and — months later, when you happen to be nearby — taps you on the shoulder so you finally go.

ikoo is a native **iOS 17+ SwiftUI app** with a small **FastAPI** backend for place extraction. It's built to be private (your location never leaves your device) and terms-of-service–safe (no scraping of your accounts).

- 📍 **Wishlist that lives in the real world** — your saved places, organized and waiting until you're near them
- 🔔 **Proximity notifications** — background geofencing nudges you when you approach a saved spot
- 🧠 **Extraction from posts, articles _and_ screenshots** — captions, blog text, and on-device OCR all become pins
- 🌏 **English + Chinese** — tuned for TikTok and RedNote

> **Status:** an actively developed MVP / prototype. Expect rough edges, and see [Known limitations](#known-limitations).

---

## Contents

- [How it works](#how-it-works)
- [The screens](#the-screens)
- [Tech stack](#tech-stack)
- [Getting started](#getting-started)
  - [1. Backend](#1-run-the-backend)
  - [2. iOS app](#2-build-the-ios-app)
  - [3. Make it yours](#3-make-it-yours-signing--ids)
- [Using ikoo](#using-ikoo)
- [Testing without a phone](#testing-without-a-phone)
- [Configuration](#configuration)
- [Project structure](#project-structure)
- [Known limitations](#known-limitations)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [Credits & license](#credits--license)

---

## How it works

Three ways to capture a place, one shared pipeline:

```
 TikTok / RedNote post ──(Share sheet)──┐
 Any URL ─────────────(Paste a link)────┤
 A screenshot ────────(on-device OCR)───┘
                                        │  text
                                        ▼
                           POST /extract  (FastAPI backend)
                     resolve link · read article/caption · Claude
                                        │  place & event candidates
                                        ▼
              Confirm screen  ──▶  geocode (Apple Maps) ──▶  you pick/edit
                                        │
                                        ▼
                        SavedPin (SwiftData)  ──▶  Map + Nearby + Saved
                                        │
                                        ▼
        GeofenceManager  ──▶  nearest ~18 regions  ──▶  local notification
```

Key design decisions:

- **Share extension stays thin.** It only drops a small JSON file into an App Group inbox and exits — the main app does the network + database work on next launch. No cross-process database, no extension memory limits.
- **The confirm screen is the safety net.** Extraction only decides how pre-filled it is; you always review before anything is saved, so a bad guess is a speed bump, not bad data.
- **A dead backend never breaks the app.** If extraction is unreachable, you fall back to manual search.
- **Location stays on device.** OCR runs on-device (Apple Vision); only recognized _text_ (never the image, never your location) is ever sent anywhere.

## The screens

| Tab | What it's for |
| --- | --- |
| **Home** | A branded dashboard — stats, collections (as a color carousel), cities, recent saves, and prominent "Add a place / Import a post" buttons. |
| **Nearby** | The pull-twin of the notification: saved places bucketed by distance from where you are right now. |
| **Map** | Every pin, color-coded by category, with a compact place card on tap and a one-button toggle between "centered on me" and "fit all". |
| **Saved** | Your wishlist — filter by **Want to go / Visited / All**, search, and swipe to check places off. Visited places drop off the map's nudges. |

Places are **color-coded by category** (food, café, sights, nature, shops, nightlife, events), so a list reads as color at a glance.

## Tech stack

- **App:** Swift, SwiftUI, SwiftData, MapKit, CoreLocation (region monitoring), UserNotifications, Vision (OCR), PhotosUI
- **Backend:** Python, FastAPI, httpx, the Anthropic SDK (Claude)
- **Tooling:** [XcodeGen](https://github.com/yonaskolb/XcodeGen) (the `.xcodeproj` is generated, never hand-edited)

---

## Getting started

**Prerequisites**

- macOS with **Xcode 16+** (iOS 17 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- **Python 3.11+** for the backend
- An **[Anthropic API key](https://console.anthropic.com/)** (optional but recommended — without it, links still resolve but no places are extracted)
- An Apple Developer account (free tier is fine for the simulator; a team is needed for on-device App Groups)

### 1. Run the backend

```sh
cd backend
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt

# Put secrets in backend/.env (gitignored) — never commit a real key:
cat > .env <<'EOF'
ANTHROPIC_API_KEY=sk-ant-...
IKOO_APP_TOKEN=dev-token
EOF

set -a && source .env && set +a
.venv/bin/uvicorn main:app --port 8000
```

Check it's up: `curl localhost:8000/healthz` → `{"ok":true}`.

The single endpoint is `POST /extract` — it takes `{url?, caption?, shared_at?}` plus a bearer token and returns geocode-ready place candidates. Deploy it anywhere that runs a container (a `Dockerfile` is included; Fly.io / Render work well). `127.0.0.1:8000` is reachable from the iOS simulator as-is.

> Prefer [`uv`](https://github.com/astral-sh/uv)? `uv venv && uv pip install -r requirements.txt && uv run uvicorn main:app --port 8000`.

### 2. Build the iOS app

```sh
xcodegen generate     # regenerate ikoo.xcodeproj from project.yml
open ikoo.xcodeproj   # then run the `ikoo` scheme (⌘R)
```

Run `xcodegen generate` again any time you edit `project.yml` or add files.

### 3. Make it yours (signing & IDs)

The repo ships with the placeholder identifier `com.sihewang.ikoo`. Before running on a **device**, change it to your own team's:

- `project.yml` — `bundleIdPrefix`, the two `PRODUCT_BUNDLE_IDENTIFIER`s, and the App Group `group.com.sihewang.ikoo`
- `ikoo/Support/AppGroup.swift` — the `AppGroup.id` constant
- Then re-run `xcodegen generate` and set your Team in Xcode's Signing & Capabilities.

The **simulator** runs without any of this.

---

## Using ikoo

**Add a place — three ways:**

1. **Share a post.** In TikTok or RedNote (or Safari, or anything with a share sheet), tap **Share → ikoo**. Open ikoo and a confirm screen appears with the places it found. *(RedNote "copy link" text shares work too — ikoo pulls the link out.)*
2. **Paste a link.** Home → **Import a post → Paste a link**. Works with posts _and_ travel articles / blogs / newsletters — a listicle becomes a whole set of pins.
3. **From a screenshot.** Home → **Import a post → From a screenshot**. Pick a screenshot of a note; on-device OCR reads the text (English or Chinese) and finds the places. Great for RedNote, where full-collection links aren't accessible.

You can also **Add a place** by name/address search, or long-nothing — just tap the map's **+**.

**Turn on nearby alerts.** Tap the prompt on Home (or the bell on the Map). ikoo needs notification access and, for background nudges, **"Always" location**. It works fully without alerts — you just won't get the surprise-you're-nearby moment. At most one alert per place every ~72 h; visited places go quiet automatically (with a per-place override for favorites).

**Work your wishlist.** The **Saved** tab defaults to "Want to go." Swipe a place to mark **Been here** — it moves to Visited and stops nudging you. Group places into **Collections** (a trip, a theme) from any place's detail screen.

## Testing without a phone

**Geofence loop (simulator):**

1. Add a pin, e.g. search "The Rotunda" (Charlottesville).
2. Enable notifications + location (**Always**, via Settings, for background).
3. Simulator → **Features → Location → GPX…** → `ikoo/SupportingFiles/WalkPastPin.gpx` (walks past the Rotunda).
4. A "*The Rotunda is …m away*" notification fires; a second pass within 72 h stays silent (cooldown).

> Significant-location-change relaunches don't simulate — do one real-world walk test on a device before trusting background behavior.

**Share / import flow (simulator):** open Safari, share a TikTok URL → ikoo → reopen ikoo → confirm screen. Or use **Paste a link** / **From a screenshot** directly.

## Configuration

App-side (in `project.yml` under the app target's `Info` — baked into the build):

| Key | Purpose | Default |
| --- | --- | --- |
| `IkooExtractBaseURL` | Backend base URL. Set to `""` to disable extraction (manual search only). | `http://127.0.0.1:8000` |
| `IkooExtractToken` | Bearer token sent to the backend. | `dev-token` |

Backend-side (in `backend/.env`, gitignored):

| Var | Purpose |
| --- | --- |
| `ANTHROPIC_API_KEY` | Claude API key. Omit and links still resolve, but no places are extracted. |
| `IKOO_APP_TOKEN` | Must match the app's `IkooExtractToken`. |
| `IKOO_MODEL` | Optional Claude model override (defaults to a fast model). |

## Project structure

```
ikoo/
├── ikoo/                      # iOS app
│   ├── Models/                # SavedPin (SwiftData), IngestItem
│   ├── Services/              # GeofenceManager, OCRService, ExtractClient,
│   │                          #   GeocodingService, NotificationService, IngestService
│   ├── Support/               # Theme (design system), CategoryStyle, AppGroup, SampleData
│   ├── Views/                 # Home, Nearby, Map, Saved, ConfirmPin, PinDetail, cards…
│   └── SupportingFiles/       # WalkPastPin.gpx
├── ikooShareExtension/        # Share extension → App Group inbox
├── backend/                   # FastAPI: main.py, fetchers.py, extractor.py, Dockerfile
└── project.yml                # XcodeGen spec (generates ikoo.xcodeproj)
```

## Known limitations

- **RedNote collection/board links can't be read.** The notes inside a board load through RedNote's private, authenticated API, so only individual posts (or screenshots) work — not a shared collection link.
- **Geocoding isn't perfect.** Apple Maps sometimes resolves a non-English place name to the right neighborhood rather than the exact spot; the confirm screen lets you fix any match in a tap.
- **Some publishers block scraping.** Big sites (e.g. major magazines, Wikimedia) refuse bot requests, so a pasted link may come back empty — the app degrades to manual search.
- **Background alerts require "Always" location** and one real-device test; the simulator can't reproduce terminated-app relaunches.

## Roadmap

- Accept shared **images** in the share extension (screenshot → share → done, no app reopen)
- Onboarding / confirm screens finished in the same visual language
- Optional richer place cards (hours, photos) via Apple's native place data
- A "collection links aren't supported yet" hint when a RedNote board URL is pasted

## Contributing

Issues and PRs are welcome. A few notes:

- **Don't hand-edit `ikoo.xcodeproj`** — change `project.yml` and run `xcodegen generate`.
- Never commit secrets; keep API keys in `backend/.env`.
- The app is built around one design system in `ikoo/Support/Theme.swift` (colors, type, spacing). Reuse those tokens rather than hardcoding values.
- Keep the share extension thin (no networking / SwiftData) — the main app does that work.

## Credits & license

- **[Big Shoulders](https://github.com/xotypeco/big_shoulders)** display font — SIL Open Font License 1.1 (bundled in `ikoo/Resources/Fonts/`, with its `OFL.txt`).
- Built on Apple's SwiftUI / MapKit / Vision frameworks and [Anthropic's Claude](https://www.anthropic.com/).

No project license file is included yet, so the code is **all rights reserved** by default — add a `LICENSE` to grant reuse if you intend this to be open source.
