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

# Boxes written by `seed_demo_cascade` carry this in their reason, so a view can
# say out loud that it is drawing fixtures rather than a real detection pass.
glob FIXTURE_MARK: str = "(fixture)";

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

"""One frame an agent inspected, and what it left on it."""
obj AgentStop {
    has index: int,
        timestamp: float,
        box_count: int,
        texts: list[str];
}

"""One cascade agent: where it started, how far it got, and why it stopped.

`seed_index` is the frame the agent was launched from and `reach_index` the
furthest frame it claimed, so `[seed_index, reach_index]` is the span the UI
draws. Neither is `focus`: the walker overwrites `focus` with each frame it
inspects, so on a finished agent it is the last frame reached, not the seed.
"""
obj AgentView {
    has id: str,
        agent_id: str,
        direction: str,
        seed_index: int,
        reach_index: int,
        focus: int,
        steps: int,
        box_count: int,
        still_visible: bool,
        reason: str,
        summary: str,
        targets: list[str],
        stops: list[AgentStop];
}

"""One frame a track was seen on."""
obj TrackStop {
    has index: int,
        timestamp: float,
        box_count: int,
        seeded: bool;
}

"""One real-world value, followed across every frame it stayed visible on."""
obj TrackView {
    has id: str,
        label: str,
        box_count: int,
        seed_boxes: int,
        cascade_boxes: int,
        first_index: int,
        last_index: int,
        stops: list[TrackStop];
}

"""A frame as the cascade axis needs it: position and how covered it is."""
obj FrameMark {
    has index: int,
        timestamp: float,
        box_count: int,
        seed_count: int;
}

"""Everything the cascade view draws for one video."""
obj CascadeView {
    has video_id: str,
        frame_count: int,
        agent_count: int,
        track_count: int,
        box_count: int,
        seed_box_count: int,
        cascade_box_count: int,
        fixture_box_count: int,
        seed_frames: list[int],
        agents: list[AgentView],
        tracks: list[TrackView],
        frames: list[FrameMark];
}

"""One box on one frame, with the agent that placed it and the track it joins."""
obj BoxProvenance {
    has box_id: str,
        text: str,
        origin: str,
        confidence: float,
        reason: str,
        agent_id: str,
        direction: str,
        agent_reason: str,
        seed_index: int,
        track_label: str,
        track_boxes: int;
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
    boxes = v.box_total if v.box_total >= 0
        else sum([len([f ->:Detected:->[?:Box]]) for f in frames]);
    words = v.word_total if v.word_total >= 0
        else sum([len(f.words) for f in frames]);
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
        box_count=boxes,
        word_count=words
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
        # A card needs a count and a poster. The chain walk is the ordering
        # authority the studio wants, and walking five hundred frames to draw
        # one thumbnail is what made this page take twenty seconds.
        frames = sorted(
            [v ->:Contains:->[?:Frame]], key=lambda (f: Frame) { f.index; }
        );
        out.append(_video_view(v, frames));
    }
    return out;
}

"""One video with its frames in order and each frame's redaction boxes.

Building a frame's view costs an edge query, so a video kept at its own frame
rate would have the studio wait on five hundred of them before drawing
anything. Past `most`, the timeline is thinned to an evenly spaced sample that
still spans the whole video, keeping the first and last frame. Each frame
carries its real index, so what is shown is a subset of the truth rather than
a renumbering of it, and the header still reports the full count.
"""
def:pub get_video(video_id: str, most: int = 60) -> VideoDetail | None {
    v = _find_video(video_id);
    if v is None {
        return None;
    }
    frames = _ordered_frames(v);
    shown = frames;
    if most > 1 and len(frames) > most {
        last = len(frames) - 1;
        picks = sorted({(i * last) // (most - 1) for i in range(most)});
        shown = [frames[i] for i in picks];
    }
    return VideoDetail(
        video=_video_view(v, frames),
        frames=[_frame_view(f) for f in shown]
    );
}

# ---------------------------------------------------------------- cascade

"""The frame a box was detected on, or None if it hangs off nothing."""
def _holder(b: Box) -> Frame | None {
    holders = [b <-:Detected:<-[?:Frame]];
    return holders[0] if holders else None;
}

"""The frame an agent was launched from.

`agent_id` is `<direction>-<seed index>`, which is the only record of where the
walk began: `focus` moves with the agent. The claimed frames are the fallback
for an id that does not carry an index -- one step back from the near end of the
span is where the agent must have come from.
"""
def _seed_index(a: Agent, claimed: list[int]) -> int {
    tail = a.agent_id.rsplit("-", 1);
    if len(tail) == 2 and tail[1].isdigit() {
        return int(tail[1]);
    }
    if not claimed {
        return a.focus;
    }
    return (min(claimed) - 1) if a.direction == "forward" else (max(claimed) + 1);
}

def _agent_view(a: Agent, allowed: set[str]) -> AgentView {
    grouped: dict[int, list[Box]] = {};
    stamp: dict[int, float] = {};
    for b in [a <-:AddedBy:<-[?:Box]] {
        f = _holder(b);
        if f is None or jid(f) not in allowed {
            continue;
        }
        if f.index not in grouped {
            grouped[f.index] = [];
        }
        grouped[f.index].append(b);
        stamp[f.index] = f.timestamp;
    }

    claimed = sorted(grouped.keys());
    ahead = a.direction == "forward";
    # Travel order, not numeric order: a backward agent's first step is its
    # highest frame index.
    walked = claimed if ahead else list(reversed(claimed));

    stops: list[AgentStop] = [];
    targets: list[str] = [];
    total = 0;
    for i in walked {
        texts = sorted({b.text for b in grouped[i] if b.text});
        for t in texts {
            if t not in targets {
                targets.append(t);
            }
        }
        total += len(grouped[i]);
        stops.append(
            AgentStop(
                index=i,
                timestamp=stamp[i],
                box_count=len(grouped[i]),
                texts=texts
            )
        );
    }

    seed = _seed_index(a, claimed);
    reach = seed;
    if claimed {
        reach = max(claimed) if ahead else min(claimed);
    }

    # An agent that never left its seed is finished without `finish()` ever
    # running, so its stop reason exists only inside the summary sentence.
    why = a.reason;
    if not why and "no frame that way" in a.summary {
        why = "no frame that way";
    }

    return AgentView(
        id=jid(a),
        agent_id=a.agent_id,
        direction=a.direction,
        seed_index=seed,
        reach_index=reach,
        focus=a.focus,
        steps=a.steps,
        box_count=total,
        still_visible=a.still_visible,
        reason=why,
        summary=a.summary,
        targets=targets,
        stops=stops
    );
}

def _track_view(t: Track, allowed: set[str]) -> TrackView {
    grouped: dict[int, list[Box]] = {};
    stamp: dict[int, float] = {};
    for b in [t <-:MemberOf:<-[?:Box]] {
        f = _holder(b);
        if f is None or jid(f) not in allowed {
            continue;
        }
        if f.index not in grouped {
            grouped[f.index] = [];
        }
        grouped[f.index].append(b);
        stamp[f.index] = f.timestamp;
    }

    seen = sorted(grouped.keys());
    stops = [
        TrackStop(
            index=i,
            timestamp=stamp[i],
            box_count=len(grouped[i]),
            seeded=len([b for b in grouped[i] if b.origin == "seed"]) > 0
        )
        for i in seen
    ];
    members = [b for i in seen for b in grouped[i]];

    return TrackView(
        id=jid(t),
        label=t.label,
        box_count=len(members),
        seed_boxes=len([b for b in members if b.origin == "seed"]),
        cascade_boxes=len([b for b in members if b.origin == "cascade"]),
        first_index=seen[0] if seen else 0,
        last_index=seen[-1] if seen else 0,
        stops=stops
    );
}

def _agent_order(v: AgentView) -> tuple {
    return (v.seed_index, 0 if v.direction == "forward" else 1, v.agent_id);
}

def _track_order(t: TrackView) -> tuple {
    return (-t.box_count, t.label);
}

"""The cascade over one video: its agents, its tracks, and the frame axis.

Agents hang off `root` rather than off the video, so a video claims an agent by
owning the frames the agent wrote on. An agent that placed nothing -- the
backward agent of a seed on frame 1, say -- has no frames to be claimed by, and
is attributed to the only video when there is only one. With several videos in
the graph those boxless agents are dropped rather than guessed at; giving Agent
an edge to its Video is the fix, and that is a `graph.jac` change.
"""
def:pub get_cascade(video_id: str) -> CascadeView | None {
    v = _find_video(video_id);
    if v is None {
        return None;
    }
    frames = _ordered_frames(v);
    allowed = {jid(f) for f in frames};

    marks: list[FrameMark] = [];
    seed_frames: list[int] = [];
    seeded = 0;
    cascaded = 0;
    fixtures = 0;
    total = 0;
    for f in frames {
        boxes = [f ->:Detected:->[?:Box]];
        heads = len([b for b in boxes if b.origin == "seed"]);
        total += len(boxes);
        seeded += heads;
        cascaded += len([b for b in boxes if b.origin == "cascade"]);
        fixtures += len([b for b in boxes if FIXTURE_MARK in b.reason]);
        if heads > 0 {
            seed_frames.append(f.index);
        }
        marks.append(
            FrameMark(
                index=f.index,
                timestamp=f.timestamp,
                box_count=len(boxes),
                seed_count=heads
            )
        );
    }

    lone = len([root -->[?:Video]]) == 1;
    agents: list[AgentView] = [];
    for a in [root -->[?:Agent]] {
        view = _agent_view(a, allowed);
        if view.box_count > 0 or lone {
            agents.append(view);
        }
    }

    tracks = [_track_view(t, allowed) for t in [root -->[?:Track]]];
    tracks = [t for t in tracks if t.box_count > 0];

    return CascadeView(
        video_id=jid(v),
        frame_count=len(frames),
        agent_count=len(agents),
        track_count=len(tracks),
        box_count=total,
        seed_box_count=seeded,
        cascade_box_count=cascaded,
        fixture_box_count=fixtures,
        seed_frames=seed_frames,
        agents=sorted(agents, key=_agent_order),
        tracks=sorted(tracks, key=_track_order),
        frames=marks
    );
}

"""Provenance for every box on one frame: which agent placed it, which track.

Keyed by frame index rather than id so the caller can ask with what the URL
already gives it.
"""
def:pub get_frame_provenance(video_id: str, frame_index: int) -> list[BoxProvenance] {
    v = _find_video(video_id);
    if v is None {
        return [];
    }
    hits = [f for f in _ordered_frames(v) if f.index == frame_index];
    if not hits {
        return [];
    }

    out: list[BoxProvenance] = [];
    for b in [hits[0] ->:Detected:->[?:Box]] {
        placed = [b ->:AddedBy:->[?:Agent]];
        joined = [b ->:MemberOf:->[?:Track]];
        agent_id = placed[0].agent_id if placed else "";
        out.append(
            BoxProvenance(
                box_id=jid(b),
                text=b.text,
                origin=b.origin,
                confidence=b.confidence,
                reason=b.reason,
                agent_id=agent_id,
                direction=placed[0].direction if placed else "",
                agent_reason=placed[0].reason if placed else "",
                seed_index=_seed_index(placed[0], []) if placed else 0,
                track_label=joined[0].label if joined else "",
                track_boxes=len([joined[0] <-:MemberOf:<-[?:Box]]) if joined else 0
            )
        );
    }
    return out;
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
