"""Burning redaction boxes into a video with ffmpeg.

The last stage of the pipeline and the only place a pixel coordinate exists.
Everything upstream works in box_2d order [y0, x0, y1, x1] on a 0..1000 scale
normalized against the frame; the conversion against the *source* video's real
dimensions happens here and nowhere else.

A real video yields hundreds to low thousands of spans, and one drawbox per
span overruns the command-line argument limit long before that. The filter
graph goes to a temp file read with -filter_complex_script instead. Measured:
an equivalent -vf argument raises OSError "Argument list too long" at roughly
15,000 spans, while the script file has no such ceiling.

ffmpeg has its own, lower ceiling. A single chain of drawbox filters crashes
it with SIGBUS somewhere between 3,525 (clean) and 3,675 (crash) filters, with
an empty stderr, which looks exactly like a silent success if you only check
that a file appeared. Long runs are therefore split across sequential passes.
"""

from __future__ import annotations

import os
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

from .media import probe

# Coordinates arrive normalized against this scale, not against pixels.
SCALE = 1000

# Solid fill: an opaque box is the point, and drawbox's default is an outline.
BOX_COLOR = "black@1.0"

# veryfast keeps a 3456x2234 source inside a minute or so on a laptop. The
# encode is the whole cost of the pass; the filter chain itself is noise
# because timeline-disabled drawboxes are skipped before they touch pixels.
VIDEO_CODEC = "libx264"
PRESET = "veryfast"
CRF = "23"

# Sub-millisecond precision is meaningless against frame boundaries and only
# makes the filter script longer.
TIME_PRECISION = 3

# ffmpeg configures a filter chain recursively and blows its stack just under
# 3,600 drawbox links (measured: 3,525 clean, 3,675 SIGBUS, reproducible).
# Staying a factor of two below that leaves room for a deeper stack frame in
# another ffmpeg build. Overflow spills into a second pass over the video.
MAX_FILTERS_PER_PASS = 1500

# Intermediate passes are re-encoded, so they run near-transparent to keep
# generation loss off the final file. Only reached above MAX_FILTERS_PER_PASS.
INTERMEDIATE_CRF = "16"
INTERMEDIATE_PRESET = "ultrafast"


class ExportError(Exception):
    """ffmpeg failed to write the redacted video."""


@dataclass
class BoxSpan:
    """One rectangle, visible for one half-open time window.

    Geometry is box_2d order on the 0..1000 scale: y comes first. The window
    is [t_start, t_end) in seconds from the start of the video.
    """

    y0: int
    x0: int
    y1: int
    x1: int
    t_start: float
    t_end: float


@dataclass
class _PixelBox:
    x: int
    y: int
    w: int
    h: int
    t_start: float
    t_end: float


def _clamp(value: int, lo: int, hi: int) -> int:
    return max(lo, min(hi, value))


def _to_pixels(span: BoxSpan, width: int, height: int) -> _PixelBox | None:
    """Project one 0..1000 box_2d span onto the source frame, or drop it.

    Returns None for a span that would draw nothing: zero or negative extent
    in either axis, an empty time window, or a rectangle entirely off-frame.
    """
    if span.t_end <= span.t_start:
        return None

    # y first. Swapping these silently produces a video that looks redacted
    # in the wrong places, which no exit code will tell you about.
    top = _clamp(round(span.y0 * height / SCALE), 0, height)
    bottom = _clamp(round(span.y1 * height / SCALE), 0, height)
    left = _clamp(round(span.x0 * width / SCALE), 0, width)
    right = _clamp(round(span.x1 * width / SCALE), 0, width)

    if right <= left or bottom <= top:
        return None

    return _PixelBox(
        x=left,
        y=top,
        w=right - left,
        h=bottom - top,
        t_start=max(0.0, span.t_start),
        t_end=span.t_end,
    )


def _coalesce(boxes: list[_PixelBox]) -> list[_PixelBox]:
    """Join time-adjacent spans that land on the same pixel rectangle.

    Static text is the common case: the same word sits in the same place for
    dozens of consecutive frames and arrives as dozens of one-frame spans.
    Merging them cuts the filter count by roughly an order of magnitude on
    screen recordings, which is the difference between an ffmpeg run that
    parses instantly and one that spends real time on the graph.
    """
    by_rect: dict[tuple[int, int, int, int], list[_PixelBox]] = {}
    for b in boxes:
        by_rect.setdefault((b.x, b.y, b.w, b.h), []).append(b)

    merged: list[_PixelBox] = []
    for group in by_rect.values():
        group.sort(key=lambda b: b.t_start)
        current = group[0]
        for nxt in group[1:]:
            # Half-open windows from consecutive frames touch exactly, so
            # anything at or before the current end continues the same run.
            if nxt.t_start <= current.t_end + 1e-6:
                current.t_end = max(current.t_end, nxt.t_end)
            else:
                merged.append(current)
                current = nxt
        merged.append(current)

    merged.sort(key=lambda b: (b.t_start, b.y, b.x))
    return merged


def _filter_graph(boxes: list[_PixelBox]) -> str:
    """The full filtergraph text, written to a script file rather than argv.

    The enable expression is single-quoted because its commas would otherwise
    read as filter separators to the filtergraph parser.
    """
    steps = [
        "drawbox="
        f"x={b.x}:y={b.y}:w={b.w}:h={b.h}:"
        f"color={BOX_COLOR}:t=fill:"
        f"enable='between(t,{b.t_start:.{TIME_PRECISION}f},{b.t_end:.{TIME_PRECISION}f})'"
        for b in boxes
    ]
    if not steps:
        steps = ["null"]
    return "[0:v]" + ",".join(steps) + "[vout]"


def _run(cmd: list[str], what: str) -> subprocess.CompletedProcess:
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip()
        if not detail:
            # A crashed ffmpeg says nothing at all, so the signal is the only
            # evidence there is. Reporting the bare code here is what makes a
            # filter-chain stack overflow identifiable instead of mysterious.
            detail = (
                f"killed by signal {-proc.returncode}"
                if proc.returncode < 0
                else f"exit code {proc.returncode}, no output"
            )
        raise ExportError(f"{what} failed: {detail}")
    return proc


def _encode_pass(
    source: str, dest: str, boxes: list[_PixelBox], final: bool, label: str
) -> None:
    """One ffmpeg invocation drawing `boxes`, with the graph in a script file."""
    handle, script_path = tempfile.mkstemp(prefix="redact_filter_", suffix=".txt")
    try:
        with os.fdopen(handle, "w") as fh:
            fh.write(_filter_graph(boxes))

        _run(
            [
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-i", source,
                "-filter_complex_script", script_path,
                "-map", "[vout]",
                # The trailing ? makes the audio mapping optional, so a source
                # with no audio track maps nothing instead of failing.
                "-map", "0:a?",
                "-c:v", VIDEO_CODEC,
                "-preset", PRESET if final else INTERMEDIATE_PRESET,
                "-crf", CRF if final else INTERMEDIATE_CRF,
                "-pix_fmt", "yuv420p",
                "-c:a", "copy",
                "-movflags", "+faststart",
                dest,
            ],
            f"ffmpeg redact ({label})",
        )
    finally:
        Path(script_path).unlink(missing_ok=True)


def export_redacted(source_path: str, out_path: str, spans: list[BoxSpan]) -> str:
    """Write `source_path` to `out_path` with every span burned in as a box.

    Spans are in box_2d order on the 0..1000 scale and are resolved against
    the source video's real dimensions. Degenerate spans are dropped and
    time-adjacent repeats of the same rectangle are merged, so passing one
    span per frame per word is the expected calling convention.

    Audio is stream-copied when the source has any and omitted when it does
    not; a video with no audio track is not an error.
    """
    if not os.path.exists(source_path):
        raise ExportError(f"source video not found: {source_path}")

    info = probe(source_path)
    if info.width <= 0 or info.height <= 0:
        raise ExportError(f"source has no usable dimensions: {source_path}")

    pixel_boxes = [
        px for px in (_to_pixels(s, info.width, info.height) for s in spans)
        if px is not None
    ]
    boxes = _coalesce(pixel_boxes)

    Path(out_path).parent.mkdir(parents=True, exist_ok=True)

    chunks = [
        boxes[i:i + MAX_FILTERS_PER_PASS]
        for i in range(0, len(boxes), MAX_FILTERS_PER_PASS)
    ] or [[]]

    # Every box is opaque, so splitting the chain is safe: which pass draws a
    # given rectangle cannot change the result.
    scratch: list[str] = []
    try:
        source = source_path
        for i, chunk in enumerate(chunks):
            final = i == len(chunks) - 1
            if final:
                dest = out_path
            else:
                handle, dest = tempfile.mkstemp(prefix="redact_pass_", suffix=".mp4")
                os.close(handle)
                scratch.append(dest)
            _encode_pass(source, dest, chunk, final, f"pass {i + 1}/{len(chunks)}")
            source = dest
    finally:
        for path in scratch:
            Path(path).unlink(missing_ok=True)

    if not os.path.exists(out_path) or os.path.getsize(out_path) == 0:
        raise ExportError(f"ffmpeg reported success but wrote nothing to {out_path}")

    return out_path
