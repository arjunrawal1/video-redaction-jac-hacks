"""Where does the OCR pass actually spend its time?

Separates the Textract fan-out from graph writes, because they have very
different fixes.
"""

import os;
import time;
import from medialib.ocr { detect_words }
import from ingest { ingest_video }

include graph;

with entry {
    src = os.getenv("DEMO_VIDEO", "");
    vid = ingest_video(src, fps=float(os.getenv("DEMO_FPS", "8")));
    frames = [vid ->:Contains:->[?:Frame, index <= 8]];
    paths = [f.jpeg_path for f in frames];
    print(f"benchmarking {len(paths)} frames");

    t0 = time.perf_counter();
    for p in paths[:2] {
        detect_words(p);
    }
    t_serial = (time.perf_counter() - t0) / 2;
    print(f"serial textract: {t_serial:.2f}s per frame");

    t0 = time.perf_counter();
    futures = [flow detect_words(p) for p in paths];
    batch = [wait fut for fut in futures];
    t_par = time.perf_counter() - t0;
    total = sum([len(b) for b in batch]);
    print(f"parallel textract: {len(paths)} frames in {t_par:.2f}s ({t_par/len(paths):.2f}s each), {total} words");

    t0 = time.perf_counter();
    scratch = Frame(index=9999, source_index=0);
    vid +>:Contains:+> scratch;
    scratch.words = [
        WordBox(text=w.text, y0=w.y0, x0=w.x0, y1=w.y1, x1=w.x1, conf=w.conf)
        for w in batch[0]
    ];
    t_write = time.perf_counter() - t0;
    print(f"inline write: {len(batch[0])} words in {t_write*1000:.1f}ms");
}
