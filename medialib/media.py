"""ffmpeg and perceptual-hash helpers.

The only part of the pipeline that touches raw media. Everything above this
line works in terms of frames, words, and boxes; everything below is ffmpeg
invocations and pixel math.
"""

from __future__ import annotations

import glob
import json
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

import imagehash
from PIL import Image

# 16x16 gives a 256-bit phash (DCT-based, catches global content change) and a
# 240-bit dhash (gradient-based, catches small local shifts that phash smears
# across low-frequency coefficients). A frame is kept when *either* distance
# exceeds the threshold, because each hash is blind to what the other catches.
HASH_SIZE = 16

# Hamming distance on a ~250-bit hash. At 2 that's under 1% of bits, so only
# near-identical frames collapse and a cursor nudge still keeps the frame.
# Over-keeping costs OCR time; under-keeping loses redactions outright.
DEDUP_THRESHOLD = 2

# Force-keep after this many consecutive drops, even when the hashes agree.
# Slow continuous motion stays under threshold frame-to-frame while drifting a
# long way in aggregate, and export assumes a kept frame's boxes cover the
# window up to the next kept frame.
MAX_GAP = 1

# Screen recordings often carry non-full-range YUV, which the mjpeg encoder
# rejects outright. Normalizing in the filter chain keeps extraction working
# across both camera video and screen captures.
PIXEL_FORMAT = "yuvj420p"


class MediaError(Exception):
    """ffmpeg or ffprobe failed, or produced nothing usable."""


@dataclass
class VideoInfo:
    width: int = 0
    height: int = 0
    fps: float = 0.0
    duration: float = 0.0
    frame_count: int = 0


@dataclass
class ExtractedFrame:
    source_index: int
    path: str
    width: int
    height: int
    timestamp: float


def _run(cmd: list[str], what: str) -> subprocess.CompletedProcess:
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip() or "unknown error"
        raise MediaError(f"{what} failed: {detail}")
    return proc


def _parse_rate(rate: str | None) -> float:
    if not rate or "/" not in rate:
        return 0.0
    num_s, den_s = rate.split("/", 1)
    try:
        num, den = float(num_s), float(den_s)
    except ValueError:
        return 0.0
    return num / den if den > 0 and num > 0 else 0.0


def probe(video_path: str) -> VideoInfo:
    """Read dimensions, frame rate, and duration from the source video."""
    proc = _run(
        [
            "ffprobe", "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height,avg_frame_rate,r_frame_rate,nb_frames",
            "-show_entries", "format=duration",
            "-of", "json",
            video_path,
        ],
        "ffprobe",
    )
    payload = json.loads(proc.stdout or "{}")
    streams = payload.get("streams") or []
    if not streams:
        raise MediaError("no video stream found")
    s = streams[0]
    fmt = payload.get("format") or {}

    # avg_frame_rate matches the cadence ffmpeg actually emits; r_frame_rate is
    # the container's nominal rate and only a fallback.
    fps = _parse_rate(s.get("avg_frame_rate")) or _parse_rate(s.get("r_frame_rate"))

    return VideoInfo(
        width=int(s.get("width") or 0),
        height=int(s.get("height") or 0),
        fps=fps,
        duration=float(fmt.get("duration") or 0.0),
        frame_count=int(s.get("nb_frames") or 0),
    )


def _decode_all(
    video_path: str, out_dir: str, max_width: int, fps: float = 0.0
) -> list[Path]:
    Path(out_dir).mkdir(parents=True, exist_ok=True)
    filters = [f"scale='min({max_width},iw)':-2", f"format={PIXEL_FORMAT}"]
    if fps > 0:
        filters.insert(0, f"fps={fps}")
    vf = ",".join(filters)
    _run(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-i", video_path,
            "-vf", vf,
            "-q:v", "3",
            str(Path(out_dir) / "raw_%06d.jpg"),
        ],
        "ffmpeg extract",
    )
    frames = sorted(Path(p) for p in glob.glob(str(Path(out_dir) / "raw_*.jpg")))
    if not frames:
        raise MediaError("no frames extracted; check the container and codec")
    return frames


def extract_frames(
    video_path: str,
    out_dir: str,
    max_width: int = 1600,
    threshold: int = DEDUP_THRESHOLD,
    max_gap: int = MAX_GAP,
    fps: float = 0.0,
) -> list[ExtractedFrame]:
    """Decode frames, then keep only those that visibly differ.

    `source_index` is the 0-based position in the decode sequence, which is
    what maps a kept frame back to a timestamp in the original video. Dropped
    frames are deleted; kept frames are renamed to a stable name.

    `fps` resamples before dedup. At 0 every frame is decoded, which is the
    accurate setting; a lower rate trades coverage for a faster run.
    """
    info = probe(video_path)
    effective_fps = fps if fps > 0 else info.fps
    all_frames = _decode_all(video_path, out_dir, max_width, fps)

    kept: list[ExtractedFrame] = []
    last_p: imagehash.ImageHash | None = None
    last_d: imagehash.ImageHash | None = None
    last_kept_i = -1

    for i, path in enumerate(all_frames):
        with Image.open(path) as im:
            im = im.convert("RGB")
            width, height = im.size
            ph = imagehash.phash(im, hash_size=HASH_SIZE)
            dh = imagehash.dhash(im, hash_size=HASH_SIZE)

        first = last_p is None or last_d is None
        moved = not first and (
            (ph - last_p) > threshold or (dh - last_d) > threshold
        )
        gapped = not first and (i - last_kept_i) > max_gap + 1

        if first or moved or gapped:
            stable = Path(out_dir) / f"frame_{len(kept) + 1:06d}.jpg"
            path.replace(stable)
            kept.append(
                ExtractedFrame(
                    source_index=i,
                    path=str(stable),
                    width=width,
                    height=height,
                    timestamp=(i / effective_fps) if effective_fps > 0 else 0.0,
                )
            )
            last_p, last_d, last_kept_i = ph, dh, i
        else:
            path.unlink(missing_ok=True)

    return kept
