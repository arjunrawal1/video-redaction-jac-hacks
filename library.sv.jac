"""Read side of the redaction graph: everything the browser needs to render it.

The UI never sees a `node`. Each read returns a view `obj` carrying `jid()` as
its id, so the client gets hydrated typed instances with dot access and stable
keys, and a later schema change on the graph does not silently reshape the wire
format.

Frame JPEGs and exported MP4s are files on local disk. The serve runtime hands
any request whose path ends in a media extension to its static-file resolver,
which looks under `assets/`, so `assets/media` is linked at import time to the
directory the pipeline writes into and `media_url()` turns a stored disk path
into the URL that resolves there. Coordinates stay in box_2d order on the
0..1000 scale all the way to the browser; only the CSS turns them into a
position.
"""

import os;

include graph;

glob MEDIA_ROOT: str = "media";

# /static/<path> is the one URL prefix the serve runtime resolves against
# assets/ AND the dev server proxies through to it, so it is the only prefix
# that works both under `jac start` and `jac start --dev`.
glob MEDIA_URL_PREFIX: str = "/static/media";

# ---------------------------------------------------------------- view models

"""One redaction rectangle, box_2d order on the 0..1000 scale."""
obj BoxView {
    has id: str,
        y0: int,
        x0: int,
        y1: int,
        x1: int,
        text: str,
        origin: str,
        confidence: float,
        reason: str;
}

"""One OCR word, box_2d order on the 0..1000 scale."""
obj WordView {
    has text: str,
        y0: int,
        x0: int,
        y1: int,
        x1: int,
        conf: float;
}

"""A frame as the timeline and the inspector need it, minus the bulk words."""
obj FrameView {
    has id: str,
        index: int,
        source_index: int,
        timestamp: float,
        width: int,
        height: int,
        image_url: str,
        ocr_done: bool,
        word_count: int,
        boxes: list[BoxView];
}

"""One frame's full OCR output, fetched only for the frame being inspected."""
obj FrameWords {
    has id: str,
        index: int,
        words: list[WordView];
}

obj VideoView {
    has id: str,
        title: str,
        video_hash: str,
        source_fps: float,
        width: int,
        height: int,
        duration: float,
        source_path: str,
        poster_url: str,
        export_url: str,
        frame_count: int,
        ocr_frame_count: int,
        box_count: int,
        word_count: int;
}

"""A video plus its frames in Next-chain order."""
obj VideoDetail {
    has video: VideoView,
        frames: list[FrameView];
}

# ---------------------------------------------------------------- media files

"""Link media/ under assets/ so the serve runtime's static resolver finds it.

The runtime resolves a `/static/<path>` URL against `assets/<path>` and friends
and has no hook for streaming an arbitrary disk path, so the link is what makes
`/static/media/frames/<hash>/frame_000001.jpg` a real byte-for-byte JPEG
response. Created here rather than committed so a fresh clone works.
"""
def _publish_media_dir -> bool {
    link = os.path.join("assets", "media");
    try {
        if os.path.islink(link) or os.path.exists(link) {
            return True;
        }
        os.makedirs("assets", exist_ok=True);
        os.symlink(os.path.join("..", MEDIA_ROOT), link);
        return True;
    } except OSError {
        return False;
    }
}

"""Browser URL for a file the pipeline wrote, or "" if it is not under media/."""
def media_url(disk_path: str) -> str {
    if not disk_path {
        return "";
    }
    media_dir = os.path.abspath(MEDIA_ROOT);
    full = os.path.abspath(disk_path);
    if not full.startswith(media_dir + os.sep) {
        return "";
    }
    rel = full[len(media_dir) + 1:].replace(os.sep, "/");
    return f"{MEDIA_URL_PREFIX}/{rel}";
}

with entry {
    _publish_media_dir();
}

# ---------------------------------------------------------------- projections

def _box_view(b: Box) -> BoxView {
    return BoxView(
        id=jid(b),
        y0=b.y0, x0=b.x0, y1=b.y1, x1=b.x1,
        text=b.text,
        origin=b.origin,
        confidence=b.confidence,
        reason=b.reason
    );
}

def _frame_view(f: Frame) -> FrameView {
    return FrameView(
        id=jid(f),
        index=f.index,
        source_index=f.source_index,
        timestamp=f.timestamp,
        width=f.width,
        height=f.height,
        image_url=media_url(f.jpeg_path),
        ocr_done=f.ocr_done,
        word_count=len(f.words),
        boxes=[_box_view(b) for b in [f ->:Detected:->[?:Box]]]
    );
}

def _video_view(v: Video, frames: list[Frame]) -> VideoView {
    return VideoView(
        id=jid(v),
        title=v.title,
        video_hash=v.video_hash,
        source_fps=v.source_fps,
        width=v.width,
        height=v.height,
        duration=v.duration,
        source_path=v.source_path,
        poster_url=media_url(frames[0].jpeg_path) if frames else "",
        export_url=media_url(v.export_path),
        frame_count=len(frames),
        ocr_frame_count=len([f for f in frames if f.ocr_done]),
        box_count=sum([len([f ->:Detected:->[?:Box]]) for f in frames]),
        word_count=sum([len(f.words) for f in frames])
    );
}

# ---------------------------------------------------------------- traversal

"""Report the frames of a video in the order the cascade would walk them.

Arrival order along Next *is* timeline order, so the chain is the ordering
authority rather than a sort on `index`: a gap or a re-link shows up here
instead of being papered over.
"""
walker FrameChain {
    has ordered: list[Frame] = [];

    can start with Video entry {
        visit [here ->:Contains:->[?:Frame, index == 1]];
    }

    can step with Frame entry {
        self.ordered.append(here);
        visit [here ->:Next:->];
    }
}

"""Frames of a video in chain order, falling back to index order if unchained."""
def _ordered_frames(v: Video) -> list[Frame] {
    attached = [v ->:Contains:->[?:Frame]];
    walked = (FrameChain() spawn v).ordered;
    if len(walked) == len(attached) {
        return walked;
    }
    return sorted(attached, key=lambda (f: Frame) { f.index; });
}

# ---------------------------------------------------------------- endpoints

"""Resolve a `jid()` string back to the node it names.

`jobj()` is the O(1) route and is tried first, but it comes back empty for
anchors this request context has not already loaded, so the scan is the one
that actually answers a cold request.
"""
def _find_video(video_id: str) -> Video | None {
    hit = jobj(video_id);
    if isinstance(hit, Video) {
        return hit;
    }
    for v in [root -->[?:Video]] {
        if jid(v) == video_id {
            return v;
        }
    }
    return None;
}

def _find_frame(frame_id: str) -> Frame | None {
    hit = jobj(frame_id);
    if isinstance(hit, Frame) {
        return hit;
    }
    for v in [root -->[?:Video]] {
        for f in [v ->:Contains:->[?:Frame]] {
            if jid(f) == frame_id {
                return f;
            }
        }
    }
    return None;
}

"""Every video the graph has ingested, with its OCR and redaction counts."""
def:pub list_videos -> list[VideoView] {
    out: list[VideoView] = [];
    for v in [root -->[?:Video]] {
        out.append(_video_view(v, _ordered_frames(v)));
    }
    return out;
}

"""One video with its frames in order and each frame's redaction boxes."""
def:pub get_video(video_id: str) -> VideoDetail | None {
    v = _find_video(video_id);
    if v is None {
        return None;
    }
    frames = _ordered_frames(v);
    return VideoDetail(
        video=_video_view(v, frames),
        frames=[_frame_view(f) for f in frames]
    );
}

"""Every OCR word on one frame - the debug overlay's data, fetched on demand."""
def:pub get_frame_words(frame_id: str) -> FrameWords | None {
    f = _find_frame(frame_id);
    if f is None {
        return None;
    }
    return FrameWords(
        id=jid(f),
        index=f.index,
        words=[
            WordView(text=w.text, y0=w.y0, x0=w.x0, y1=w.y1, x1=w.x1, conf=w.conf)
            for w in f.words
        ]
    );
}
