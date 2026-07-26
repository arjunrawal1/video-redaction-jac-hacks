"""How wide can the Textract fan-out usefully go?

The pass batches conservatively. This measures whether Textract is actually
the constraint or whether the batch width was just a guess.
"""

import os;
import time;
import from ingest { ingest_video }
import from ocr { launch_ocr }

include graph;

def timed(paths: list[str], width: int) -> float {
    t0 = time.perf_counter();
    start = 0;
    total = 0;
    while start < len(paths) {
        chunk = paths[start:start + width];
        futures = [launch_ocr(p) for p in chunk];
        for fut in futures {
            total += len(wait fut);
        }
        start += width;
    }
    elapsed = time.perf_counter() - t0;
    per = elapsed / len(paths);
    print(f"  width {width:>2}: {elapsed:6.1f}s for {len(paths)} frames ({per:.2f}s each), {total} words");
    return elapsed;
}

with entry {
    vid = ingest_video(os.getenv("DEMO_VIDEO", ""), fps=float(os.getenv("DEMO_FPS", "8")));
    frames = [vid ->:Contains:->];
    paths = [f.jpeg_path for f in frames];
    sizes = [os.path.getsize(p) for p in paths];
    avg_kb = sum(sizes) / len(sizes) / 1024;
    print(f"{len(paths)} frames, average {avg_kb:.0f} KB per frame");

    # A cold pool starts a thread per task, so the first fan-out is not
    # representative. Burn one before measuring.
    timed(paths[:4], 4);
    print("measurements:");
    for width in [1, 8, 16, 32] {
        timed(paths, width);
    }
}
