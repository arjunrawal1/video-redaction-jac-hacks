"""Does the batched OCR pass agree with the sequential one, frame for frame?

A batch of one cannot lose arguments, so it is the reference. Anything the
fanned-out pass reads differently is the `flow` capture bug putting one
frame's word geometry onto another.
"""

import os;
import time;
import from ingest { ingest_video }
import from ocr { ReadText }

include graph;

"""A cheap fingerprint of what OCR attached to a frame."""
def summarise(fr: Frame) -> str {
    if not fr.words {
        return "empty";
    }
    head = fr.words[0];
    tail = fr.words[-1];
    return f"{len(fr.words)}|{head.text}@{head.x0},{head.y0}|{tail.text}@{tail.x0},{tail.y0}";
}

def read_all(vid: Video, size: int) -> dict[int, str] {
    for fr in [vid ->:Contains:->] {
        fr.words = [];
        fr.ocr_done = False;
    }
    t0 = time.perf_counter();
    run = ReadText(batch_size=size) spawn vid;
    elapsed = time.perf_counter() - t0;
    print(f"  batch_size={size}: {run.frames_read} frames, {run.words_added} words, {elapsed:.1f}s");
    return {fr.index: summarise(fr) for fr in [vid ->:Contains:->]};
}

with entry {
    vid = ingest_video(os.getenv("DEMO_VIDEO", ""), fps=float(os.getenv("DEMO_FPS", "8")));
    all_frames = [vid ->:Contains:->];
    print(f"{len(all_frames)} frames");

    reference = read_all(vid, 1);
    batched = read_all(vid, 8);

    disagree = [i for i in sorted(reference) if reference[i] != batched[i]];
    print("");
    print(f"frames where the batched pass disagrees with sequential: {len(disagree)} of {len(reference)}");
    for i in disagree[:5] {
        print(f"  frame {i}: sequential {reference[i]}");
        print(f"           batched    {batched[i]}");
    }

    # Distinct frames of a real recording never read byte-identically; when
    # they do, one frame's words have been copied onto another.
    twins = 0;
    keys = sorted(batched);
    for pos in range(len(keys) - 1) {
        here_key = keys[pos];
        next_key = keys[pos + 1];
        if batched[here_key] == batched[next_key] {
            twins += 1;
        }
    }
    print(f"adjacent frames with identical word lists: {twins}");
}
