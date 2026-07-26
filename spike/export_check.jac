"""Runtime check for the export pass: does a box in the graph become black pixels?

There is no detector yet, so this stands one in: OCR words already carry real,
per-frame, moving box_2d geometry, and a few of them per frame make a
realistic redaction set. Anything a real detector emits is the same shape.

Checking the exit code proves nothing here -- ffmpeg exits 0 for a filter
graph that draws in the wrong place, or nowhere at all. So the check ends by
pulling a frame out of the finished file and reading the pixels inside a
rectangle it knows should be covered, plus a control patch that should not be.
"""

import os;
import json;
import time;
import subprocess;
import from PIL { Image, ImageStat }
import from ingest { ingest_video }
import from ocr { ReadText }
import from export { RenderRedacted }

include graph;

glob BOXES_PER_FRAME: int = 3;

# Alongside the export, which is where the evidence belongs. Git-ignored.
glob STILL_DIR: str = "media/exports";

# yuv420p subsamples chroma, so the outermost pixel or two of a drawn box can
# carry a little bleed from its surroundings. Sampling starts inside that.
glob EDGE_INSET: int = 3;

# h264 is lossy, so a drawn box is not bit-exact black: DCT ringing around the
# high-contrast border pushes a handful of pixels into the teens. These are
# the thresholds for "opaque", not for "identical", and both numbers below are
# far under what any legible content would score.
glob DARK_LEVEL: int = 16;
glob DARK_FRACTION: float = 0.99;
glob DARK_MEAN: float = 3.0;

"""Pixel rect for one box, using the conversion export.py performs."""
def to_pixels(b: Box, width: int, height: int) -> tuple[int, int, int, int] {
    return (
        round(b.x0 * width / 1000),
        round(b.y0 * height / 1000),
        round(b.x1 * width / 1000),
        round(b.y1 * height / 1000)
    );
}

"""A square that overlaps none of `rects`, to prove the whole frame is not black."""
def control_patch(
    rects: list[tuple[int, int, int, int]], width: int, height: int, size: int
) -> tuple[int, int, int, int] {
    y = size;
    while y + size < height {
        x = size;
        while x + size < width {
            clear = True;
            for r in rects {
                if x < r[2] and x + size > r[0] and y < r[3] and y + size > r[1] {
                    clear = False;
                }
            }
            if clear {
                return (x, y, x + size, y + size);
            }
            x += size;
        }
        y += size;
    }
    return (0, 0, size, size);
}

"""Luma min, max, mean and the share of pixels at or below DARK_LEVEL."""
def luma_stats(image_path: str, rect: tuple[int, int, int, int]) -> tuple[int, int, float, float] {
    img = Image.open(image_path);
    crop = img.crop(rect).convert("L");
    (lo, hi) = crop.getextrema();
    hist = crop.histogram();
    total = sum(hist);
    dark = sum(hist[:DARK_LEVEL + 1]) / total if total > 0 else 0.0;
    return (lo, hi, ImageStat.Stat(crop).mean[0], dark);
}

"""Pull a single frame at `t` seconds out of `video`, decoding from the start."""
def still_at(video: str, t: float, dest: str) -> str {
    subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-i", video, "-ss", f"{t:.3f}", "-frames:v", "1", dest
        ],
        capture_output=True, text=True
    );
    return dest;
}

"""Compare source and export pixels inside one frame's boxes, mid-window.

Reports True only when every box is opaque in the export, the source actually
had something there, and a patch outside every box survived untouched. The
last condition is what separates a working export from one that blacked out
the entire picture.
"""
def check_window(fr: Frame, window_end: float, vid: Video, out: str, tag: str) -> bool {
    boxes = [fr ->:Detected:->[?:Box]];
    # Just short of the end of the video there may be no later frame to
    # decode, so the probe never sits on the final timestamp itself.
    t_probe = min(
        fr.timestamp + 0.6 * (window_end - fr.timestamp),
        max(fr.timestamp, vid.duration - 0.05)
    );
    print(
        f"[{tag}] frame {fr.index}, window {fr.timestamp:.3f}..{window_end:.3f}s, "
        f"probe t={t_probe:.3f}s, {len(boxes)} boxes: {[b.text for b in boxes]}"
    );

    shot = still_at(out, t_probe, os.path.join(STILL_DIR, f"{vid.video_hash}_{tag}_export.png"));
    before = still_at(vid.source_path, t_probe, os.path.join(STILL_DIR, f"{vid.video_hash}_{tag}_source.png"));
    if not os.path.exists(shot) or not os.path.exists(before) {
        print(f"  could not extract a still at {t_probe:.3f}s");
        return False;
    }

    rects = [to_pixels(b, vid.width, vid.height) for b in boxes];
    all_covered = True;
    had_content = False;
    for (b, r) in zip(boxes, rects) {
        inner = (r[0] + EDGE_INSET, r[1] + EDGE_INSET, r[2] - EDGE_INSET, r[3] - EDGE_INSET);
        if inner[2] <= inner[0] or inner[3] <= inner[1] {
            print(f"  box '{b.text}' too small to sample after inset, skipped");
            continue;
        }
        (lo, hi, mean, dark) = luma_stats(shot, inner);
        (_slo, _shi, smean, sdark) = luma_stats(before, inner);
        opaque = dark >= DARK_FRACTION and mean <= DARK_MEAN;
        if not opaque {
            all_covered = False;
        }
        if smean > 20.0 {
            had_content = True;
        }
        print(
            f"  box '{b.text}' px x{r[0]}..{r[2]} y{r[1]}..{r[3]} "
            f"({inner[2] - inner[0]}x{inner[3] - inner[1]} sampled): "
            f"source mean={smean:.1f} dark={sdark * 100:.1f}% -> "
            f"export min={lo} max={hi} mean={mean:.2f} dark={dark * 100:.2f}% opaque={opaque}"
        );
    }

    patch = control_patch(rects, vid.width, vid.height, 96);
    (clo, chi, cmean, _cdark) = luma_stats(shot, patch);
    intact = cmean > 40.0;
    print(
        f"  control patch x{patch[0]}..{patch[2]} y{patch[1]}..{patch[3]}: "
        f"min={clo} max={chi} mean={cmean:.2f}"
    );
    print(
        f"  [{tag}] boxes opaque={all_covered}, source had content={had_content}, "
        f"rest of frame intact={intact}"
    );
    return all_covered and had_content and intact;
}

with entry {
    src = os.getenv("DEMO_VIDEO", "");
    if not src or not os.path.exists(src) {
        print("set DEMO_VIDEO to a video file first");
    } else {
        vid = ingest_video(src, fps=float(os.getenv("DEMO_FPS", "8")));
        frames = [vid ->:Contains:->];
        frames.sort(key=lambda (f: Frame) { f.index; });
        print(f"video: {vid.width}x{vid.height} {vid.duration:.3f}s hash={vid.video_hash}");
        print(f"frames in chain: {len(frames)}");

        if sum([len(f.words) for f in frames]) == 0 {
            print("no OCR words on the graph yet, running ReadText first");
            ocr = ReadText() spawn vid;
            print(f"  read {ocr.frames_read} frames, {ocr.words_added} words");
        }

        # Stand in for the detector: real OCR words, sampled across each
        # frame's reading order so the boxes are spread over the picture and
        # move with the recording instead of all sitting in the menu bar.
        # Regenerated every run - last run's boxes are this run's input, and
        # accumulating them would make the check grade a mixture of runs.
        made = 0;
        dropped = 0;
        for fr in frames {
            for old in [fr ->:Detected:->[?:Box, origin == "spike"]] {
                del old;
                dropped += 1;
            }
            usable = [
                w for w in fr.words
                if len(w.text) >= 3 and w.x1 > w.x0 and w.y1 > w.y0
            ];
            stride = max(1, len(usable) // BOXES_PER_FRAME);
            picks = usable[::stride][:BOXES_PER_FRAME];
            for w in picks {
                fr +>:Detected:+> Box(
                    y0=w.y0, x0=w.x0, y1=w.y1, x1=w.x1,
                    text=w.text,
                    origin="spike",
                    reason="synthetic stand-in for the detector"
                );
            }
            made += len(picks);
        }
        total_boxes = sum([len([f ->:Detected:->[?:Box]]) for f in frames]);
        print(f"boxes: {dropped} stale removed, {made} created, {total_boxes} on the graph");

        # The synthetic box set changes between runs of this spike, so any
        # file from a previous run is stale. Clearing the path is what makes
        # the export below a real one rather than the idempotent skip.
        vid.export_path = "";

        t0 = time.perf_counter();
        run = RenderRedacted() spawn vid;
        dt = time.perf_counter() - t0;
        out = run.output_path;
        print(f"spans handed to ffmpeg: {len(run.spans)}");
        print(f"exported in {dt:.1f}s -> {out}");
        print(f"vid.export_path persisted: {vid.export_path}");
        print(f"file exists: {os.path.exists(out)}, {os.path.getsize(out)} bytes");

        # ---- ffprobe: is it a real video of the right shape?
        proc = subprocess.run(
            [
                "ffprobe", "-v", "error", "-of", "json",
                "-show_entries", "stream=codec_type,codec_name,width,height,nb_frames",
                "-show_entries", "format=duration",
                out
            ],
            capture_output=True, text=True
        );
        payload = json.loads(proc.stdout or "{}");
        streams = payload.get("streams") or [];
        vstreams = [s for s in streams if s.get("codec_type") == "video"];
        astreams = [s for s in streams if s.get("codec_type") == "audio"];
        vs = vstreams[0] if vstreams else {};
        out_dur = float((payload.get("format") or {}).get("duration") or 0.0);
        print(
            f"ffprobe: {len(vstreams)} video / {len(astreams)} audio stream(s), "
            f"{vs.get('codec_name')} {vs.get('width')}x{vs.get('height')} "
            f"{vs.get('nb_frames')} frames, {out_dur:.3f}s"
        );
        print(f"dimensions match source: {vs.get('width') == vid.width and vs.get('height') == vid.height}");
        print(f"duration within 0.1s of source: {abs(out_dur - vid.duration) <= 0.1} (delta {out_dur - vid.duration:+.3f}s)");

        # ---- pixels, mid-timeline and on the final frame. The last frame is
        # the interesting one: its boxes have no successor to end them, so it
        # is the only place the run-to-duration rule is exercised.
        with_boxes = [f for f in frames if len([f ->:Detected:->[?:Box]]) > 0];
        middle = with_boxes[len(with_boxes) // 2];
        mid_pos = frames.index(middle);
        mid_end = frames[mid_pos + 1].timestamp if mid_pos + 1 < len(frames) else vid.duration;
        mid_ok = check_window(middle, mid_end, vid, out, "middle");

        last = with_boxes[-1];
        last_pos = frames.index(last);
        last_end = frames[last_pos + 1].timestamp if last_pos + 1 < len(frames) else vid.duration;
        last_ok = check_window(last, last_end, vid, out, "last");

        print(f"REDACTION VERIFIED: {mid_ok and last_ok} (middle={mid_ok}, last frame={last_ok})");

        # ---- idempotency
        t1 = time.perf_counter();
        again = RenderRedacted() spawn vid;
        print(
            f"second run reused the existing export: {again.reused} "
            f"in {time.perf_counter() - t1:.3f}s -> {again.output_path}"
        );
    }
}
