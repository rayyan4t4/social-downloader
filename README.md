# Social Downloader

Flutter app + small backend that downloads videos from TikTok, Instagram,
YouTube, Facebook and X. Paste a link in the app, pick HD / SD / MP3, the file
saves in the app and can be shared anywhere.

## How it works

- `app/` — the Flutter app (Android + iOS). It never downloads directly from
  social sites; it calls the backend.
- `backend/` — FastAPI + yt-dlp server. Endpoints: `POST /resolve` (title,
  thumbnail, duration), `GET /fetch?url=...&mode=hd|sd|mp3` (the file),
  `GET /stats`, `GET /health`. Downloaded files are cached on the server for
  24 hours so repeat links are instant. Free limit: 30 requests/day per IP
  (change with the `DAILY_LIMIT` env var). Max file size 200 MB.

## Step 1 — Backend (ALREADY DEPLOYED)

The backend is live on Vercel at
**https://social-downloader-api-seven.vercel.app** (project
`social-downloader-api`; note: the plain `social-downloader-api.vercel.app`
address belongs to someone else's broken project — always use the `-seven`
one). The app already has this URL built in, so this step is done.

Verified live 2026-11-12: `/health`, `/resolve` on a real TikTok video, and
`/fetch` returning a real MP4. On Vercel there is no ffmpeg, so HD/SD use the
best single-file format and MP3 mode returns the original audio file (usually
.m4a) — the app reads the real extension from the server automatically.

To redeploy the backend after changing code, either push to GitHub and import
the repo in Vercel with root directory `backend/`, or use the Docker route
anywhere else (Render/Railway/VPS — the Dockerfile has ffmpeg, so MP3 mode
returns true .mp3 there):

```
cd backend
docker build -t downloader .
docker run -d -p 8000:8000 downloader
```

**YouTube note:** YouTube blocks many server IPs ("Sign in to confirm you're
not a bot"). TikTok, Instagram, Facebook and X usually work as-is. If YouTube
fails on your server, export cookies from youtube.com in your browser (any
"Get cookies.txt" extension), save the file as `backend/cookies.txt`, and
redeploy — the backend picks it up automatically. Never share that file.

## Step 2 — Backend URL in the app

Already built in (see Step 1) — the app works out of the box. You only need
Settings → Backend URL if you later move the backend somewhere else.
The same Settings screen switches the app between English and Roman Urdu.

## Step 3 — Build the IPA with Codemagic

1. Put this whole `social-downloader-app` folder into a GitHub repo (it must
   be the repo root — `codemagic.yaml` and `app/` at the top level).
2. Log in at codemagic.io with that GitHub account and add the repo as an app.
   Codemagic reads `codemagic.yaml` automatically.
3. Run the **iOS Unsigned IPA** workflow. When it finishes, download the
   `SocialDownloader-unsigned.ipa` artifact.
4. The IPA is unsigned. Put it on your iPhone with AltStore or SideStore
   (free, sign with your own Apple ID, re-sign every 7 days), or sign it with
   an Apple Developer account ($99/year) for a 1-year install / TestFlight.

The **Android APK** workflow in the same file builds a normal signed-debug
style release APK you can install directly.

## Local development

```
cd backend && pip install -r requirements.txt && uvicorn main:app --port 8000
cd app && flutter pub get && flutter run
```

In the app settings, use `http://10.0.2.2:8000` on the Android emulator or
your computer's LAN IP on a real phone.
