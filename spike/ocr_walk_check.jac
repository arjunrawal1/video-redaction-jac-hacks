"""Runtime check for the OCR pass over a whole video."""

import os;
import time;
import from ingest { ingest_video }
import from ocr { ReadText }

include graph;

with entry {
    src = os.getenv("DEMO_VIDEO", "");
    if not src or not os.path.exists(src) {
        print("set DEMO_VIDEO to a video file first");
    } else {
        vid = ingest_video(src, fps=float(os.getenv("DEMO_FPS", "8")));
        frames = [vid ->:Contains:->];
        print(f"{len(frames)} frames in graph");

        t0 = time.perf_counter();
        run = ReadText() spawn vid;
        dt = time.perf_counter() - t0;
        print(f"read {run.frames_read} frames, {run.words_added} words in {dt:.1f}s");

        total_words = sum([len(f.words) for f in frames]);
        print(f"words stored inline: {total_words}");

        sample = [f for f in frames if f.index == 1][0];
        print(f"frame 1 has {len(sample.words)} words, e.g. {[w.text for w in sample.words[:6]]}");

        t1 = time.perf_counter();
        again = ReadText() spawn vid;
        print(f"second pass read {again.frames_read} frames in {time.perf_counter() - t1:.2f}s");
    }
}
