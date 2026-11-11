import hashlib
import json
import os
import re
import shutil
import time
from pathlib import Path

import yt_dlp
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel

BASE = Path(__file__).parent
CACHE = Path("/tmp/cache") if os.getenv("VERCEL") else BASE / "cache"
CACHE.mkdir(parents=True, exist_ok=True)
HAS_FFMPEG = shutil.which("ffmpeg") is not None
STATS_FILE = CACHE / "stats.json"
MAX_BYTES = int(os.getenv("MAX_BYTES", str(200 * 1024 * 1024)))
DAILY_LIMIT = int(os.getenv("DAILY_LIMIT", "30"))
CACHE_TTL = 24 * 3600

app = FastAPI(title="Social Downloader API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

hits = {}
COOKIE_CANDIDATES = [BASE / "cookies.txt", BASE.parent / "cookies.txt"]


def ydl_base():
    opts = {"quiet": True, "no_warnings": True, "noplaylist": True}
    for c in COOKIE_CANDIDATES:
        if c.exists():
            opts["cookiefile"] = str(c)
            break
    return opts


class ResolveIn(BaseModel):
    url: str


def load_stats():
    if STATS_FILE.exists():
        return json.loads(STATS_FILE.read_text())
    return {"resolves": 0, "downloads": 0, "platforms": {}}


def save_stats(s):
    STATS_FILE.write_text(json.dumps(s))


def platform_of(url, extractor=""):
    u = url.lower()
    if "tiktok" in u:
        return "TikTok"
    if "instagram" in u:
        return "Instagram"
    if "youtube" in u or "youtu.be" in u:
        return "YouTube"
    if "facebook" in u or "fb.watch" in u:
        return "Facebook"
    if "twitter" in u or "x.com" in u:
        return "X"
    return extractor.capitalize() or "Other"


def check_limit(request: Request):
    ip = request.client.host if request.client else "unknown"
    day = time.strftime("%Y-%m-%d")
    key = f"{ip}:{day}"
    hits[key] = hits.get(key, 0) + 1
    if hits[key] > DAILY_LIMIT:
        raise HTTPException(429, "Daily free limit reached. Try again tomorrow.")


def clean_cache():
    now = time.time()
    for f in CACHE.iterdir():
        if f.is_file() and f.name != "stats.json" and now - f.stat().st_mtime > CACHE_TTL:
            f.unlink(missing_ok=True)


@app.on_event("startup")
def startup():
    clean_cache()


@app.get("/health")
def health():
    return {"ok": True}


@app.get("/stats")
def stats():
    return load_stats()


@app.post("/resolve")
def resolve(body: ResolveIn, request: Request):
    check_limit(request)
    url = body.url.strip()
    if not re.match(r"^https?://", url):
        raise HTTPException(400, "Paste a valid link starting with http")
    try:
        with yt_dlp.YoutubeDL(ydl_base()) as ydl:
            info = ydl.extract_info(url, download=False)
    except yt_dlp.utils.DownloadError as e:
        raise HTTPException(422, f"Could not read this link. It may be private or blocked. {e}")
    s = load_stats()
    s["resolves"] += 1
    p = platform_of(url, info.get("extractor_key", ""))
    s["platforms"][p] = s["platforms"].get(p, 0) + 1
    save_stats(s)
    return {
        "title": info.get("title") or "Untitled",
        "thumbnail": info.get("thumbnail"),
        "duration": info.get("duration"),
        "platform": p,
        "webpage_url": info.get("webpage_url") or url,
    }


if HAS_FFMPEG:
    FORMATS = {
        "hd": "bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/best[height<=720][ext=mp4]/best[height<=720]/best",
        "sd": "bestvideo[height<=480][ext=mp4]+bestaudio[ext=m4a]/best[height<=480][ext=mp4]/best[height<=480]/worst",
        "mp3": "bestaudio/best",
    }
else:
    FORMATS = {
        "hd": "best[height<=720][ext=mp4]/best[height<=720]/best",
        "sd": "best[height<=480][ext=mp4]/best[height<=480]/worst",
        "mp3": "bestaudio[ext=m4a]/bestaudio/best",
    }


@app.get("/fetch")
def fetch(url: str, mode: str = "hd", request: Request = None):
    if mode not in FORMATS:
        raise HTTPException(400, "mode must be hd, sd or mp3")
    if request is not None:
        check_limit(request)
    key = hashlib.sha256(f"{url}|{mode}".encode()).hexdigest()[:20]
    for f in CACHE.glob(f"{key}.*"):
        if f.name != "stats.json":
            return FileResponse(f, filename=f.name)
    out = str(CACHE / f"{key}.%(ext)s")
    opts = {
        **ydl_base(),
        "outtmpl": out,
        "format": FORMATS[mode],
        "max_filesize": MAX_BYTES,
    }
    if mode == "mp3" and HAS_FFMPEG:
        opts["postprocessors"] = [
            {"key": "FFmpegExtractAudio", "preferredcodec": "mp3", "preferredquality": "192"}
        ]
    elif mode != "mp3" and HAS_FFMPEG:
        opts["merge_output_format"] = "mp4"
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            ydl.download([url])
    except yt_dlp.utils.DownloadError as e:
        raise HTTPException(422, f"Download failed. The link may be private or blocked. {e}")
    files = [f for f in CACHE.glob(f"{key}.*") if f.name != "stats.json"]
    if not files:
        raise HTTPException(413, "File too large or download produced no file.")
    f = files[0]
    if f.stat().st_size > MAX_BYTES:
        f.unlink(missing_ok=True)
        raise HTTPException(413, "File is larger than the 200 MB limit.")
    s = load_stats()
    s["downloads"] += 1
    save_stats(s)
    return FileResponse(f, filename=f.name)
