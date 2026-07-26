"""Turning a video file into the Frame chain the rest of the pipeline walks.

This is the one pass with no traversal in it: there is no graph to walk yet,
we are building the road. Everything downstream is a walker.
"""

import os;
import hashlib;
import from medialib.media { probe, extract_frames }

include graph;

glob FRAME_ROOT: str = "media/frames";

"""Content hash of the source video, used to recognize a re-upload."""
def file_digest(path: str) -> str {
    h = hashlib.sha256();
    with open(path, "rb") as fh {
        while True {
            chunk = fh.read(1 << 20);
            if not chunk { break; }
            h.update(chunk);
        }
    }
    return h.hexdigest()[:16];
}

"""Return an already-ingested video with this content hash, if any."""
def find_video(digest: str) -> Video | None {
    matches = [root -->[?:Video, video_hash == digest]];
    return matches[0] if matches else None;
}

"""Extract deduplicated frames and hang them off root as a Next-linked chain.

Re-ingesting the same file is a no-op: the content hash finds the existing
Video, and its frames, words, and boxes are still on the graph.
"""
def:pub ingest_video(
    source_path: str,
    title: str = "",
    fps: float = 0.0,
    max_width: int = 1600
) -> Video {
    digest = file_digest(source_path);
    existing = find_video(digest);
    if existing is not None {
        return existing;
    }

    info = probe(source_path);
    out_dir = os.path.join(FRAME_ROOT, digest);
    extracted = extract_frames(source_path, out_dir, max_width, fps=fps);

    vid = Video(
        title=title or os.path.basename(source_path),
        video_hash=digest,
        source_fps=info.fps,
        width=info.width,
        height=info.height,
        duration=info.duration,
        source_path=source_path
    );
    root ++> vid;

    prev: Frame | None = None;
    for (i, ex) in enumerate(extracted) {
        f = Frame(
            index=i + 1,
            source_index=ex.source_index,
            timestamp=ex.timestamp,
            width=ex.width,
            height=ex.height,
            jpeg_path=ex.path
        );
        vid +>:Contains:+> f;
        if prev is not None {
            prev +>:Next:+> f;
        }
        prev = f;
    }

    return vid;
}
