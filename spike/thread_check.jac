"""Why do concurrent policy asks return the wrong frame's answer?

Runs the same run_ask calls sequentially and concurrently over real frames and
prints the raw indices each returned, so a mix-up is visible directly.
"""

import os;
import time;
import from ingest { ingest_video }
import from ocr { ReadText }
import from ai { format_words }
import from detect { run_ask }

include graph;

with entry {
    src = os.getenv("DEMO_VIDEO", "");
    vid = ingest_video(src, fps=float(os.getenv("DEMO_FPS", "8")));
    ReadText() spawn vid;
    frames = [vid ->:Contains:->];

    picked: list[Frame] = [];
    for want in [1, 9, 17, 25] {
        hit = [f for f in frames if f.index == want];
        if hit { picked.append(hit[0]); }
    }

    scope = "spreadsheet-cell-contents: values the user typed into grid cells";

    print("sequential:");
    t0 = time.perf_counter();
    for fr in picked {
        got = run_ask(
            fr.jpeg_path, scope,
            format_words([w.text for w in fr.words]), len(fr.words)
        );
        print(f"  frame {fr.index:2}: {got} -> {[fr.words[i].text for i in got]}");
    }
    print(f"  ({time.perf_counter() - t0:.1f}s)");

    print("concurrent, node reads done up front:");
    t0 = time.perf_counter();
    # Every graph read happens here, on this thread. What crosses into the
    # thread pool is nothing but strings and ints.
    prepared = [
        (fr.jpeg_path, format_words([w.text for w in fr.words]), len(fr.words))
        for fr in picked
    ];
    futures = [flow run_ask(p0, scope, p1, p2) for (p0, p1, p2) in prepared];
    results = [wait fut for fut in futures];
    for (fr, got) in zip(picked, results) {
        print(f"  frame {fr.index:2}: {got} -> {[fr.words[i].text for i in got]}");
    }
    print(f"  ({time.perf_counter() - t0:.1f}s)");

    distinct = len({str(r) for r in results});
    print(f"distinct concurrent answers: {distinct} of {len(results)}");
}
