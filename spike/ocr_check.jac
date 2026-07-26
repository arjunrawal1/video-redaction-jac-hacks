"""Runtime check for Textract word geometry."""

import os;
import time;
import from medialib.ocr { detect_words }

with entry {
    shot = "media/testframe.jpg";
    if not os.path.exists(shot) {
        print(f"missing {shot}");
    } else {
        t0 = time.perf_counter();
        words = detect_words(shot);
        dt = (time.perf_counter() - t0) * 1000;
        print(f"textract returned {len(words)} words in {dt:.0f}ms");
        for w in words[:8] {
            print(f"  {w.text!r:24} box_2d=[{w.y0},{w.x0},{w.y1},{w.x1}] conf={w.conf:.2f}");
        }
        bad = [w for w in words if w.y1 <= w.y0 or w.x1 <= w.x0
               or w.y0 < 0 or w.x0 < 0 or w.y1 > 1000 or w.x1 > 1000];
        print(f"geometry violations: {len(bad)}");
    }
}
