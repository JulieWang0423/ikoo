# ikoo

Save places and events from TikTok / RedNote, see them on a map, and get a
notification when you're walking past one.

## Layout

- `ikoo/` — iOS app (SwiftUI, iOS 17+): map, saved list, geofence engine
- `ikooShareExtension/` — iOS share extension: receives shared posts, drops
  them into the App Group inbox
- `backend/` — FastAPI service: resolves TikTok/RedNote links and extracts
  place/event candidates with Claude
- `project.yml` — [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec; the
  `.xcodeproj` is generated, don't hand-edit it

## Build the app

```sh
brew install xcodegen        # once
xcodegen generate            # after any project.yml change
open ikoo.xcodeproj          # build & run the `ikoo` scheme
```

Before running on a device, change the bundle id prefix + App Group id
(`com.sihewang` / `group.com.sihewang.ikoo`) in `project.yml`,
`ikoo/Support/AppGroup.swift` to match your Apple developer team.

## Run the backend

```sh
cd backend
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
export ANTHROPIC_API_KEY=sk-ant-...   # or put it in backend/.env (gitignored); without it, link fetch still works
export IKOO_APP_TOKEN=dev-token
.venv/bin/uvicorn main:app --port 8000
```

The app finds it via `IkooExtractBaseURL` in `project.yml` (defaults to
`http://127.0.0.1:8000`, which works from the simulator). Set it to `""` to
disable extraction entirely — the app falls back to manual search. Deploy with
the included `Dockerfile` (Fly.io/Render) when ready.

## Test the geofence loop

1. Run the app in the simulator, add a pin at "The Rotunda" (Charlottesville).
2. Tap the bell → enable notifications + location (choose "Always" in
   Settings for background alerts).
3. Simulator menu: Features → Location → GPX… →
   `ikoo/SupportingFiles/WalkPastPin.gpx` (walks down University Ave past the
   Rotunda).
4. A "The Rotunda is …m away" notification should fire; a second pass within
   72 h should stay silent (cooldown).

Significant-location-change relaunches don't simulate — do one real-world
walk test on a device before trusting background behavior.

## Test the share flow

Simulator: open Safari, share any TikTok URL → ikoo → "Saved" toast → open
ikoo → confirm screen appears. On device, share directly from the TikTok or
RedNote app (for RedNote, "copy link"-style text shares work too — ikoo pulls
the link out of the text).
