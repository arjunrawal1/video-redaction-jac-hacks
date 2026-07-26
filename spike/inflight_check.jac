"""How much parallelism does the provider actually give us?

Asks the same seven questions about the same seven seed frames at several
concurrency limits. One in flight is the sequential baseline through the exact
same code path. If wall clock stops improving as the limit rises, the provider
is the ceiling; if answers stop being distinct, something is corrupting them.
Those are different failures and this tells them apart.
"""

import os;
import time;
import from ingest { ingest_video }
import from ocr { ReadText }
import from ai { format_words }
import from detect { AskJob, run_asks }

include graph;

glob SCOPE: str = "spreadsheet-cell-contents: values the user typed into grid cells";
glob SEEDS: list[int] = [1, 9, 17, 25, 33, 41, 49];

with entry {
    src = os.getenv("DEMO_VIDEO", "");
    vid = ingest_video(src, fps=float(os.getenv("DEMO_FPS", "8")));
    ReadText() spawn vid;

    by_index = {f.index: f for f in [vid ->:Contains:->]};
    picked = [by_index[i] for i in SEEDS if i in by_index];

    jobs = [
        AskJob(
            frame_path=fr.jpeg_path,
            scope=SCOPE,
            listing=format_words([w.text for w in fr.words]),
            limit=len(fr.words)
        )
        for fr in picked
    ];

    print(f"{len(jobs)} asks over {len(jobs)} frames");
    print("  limit   wall    per-call   distinct");
    for limit in [1, 3, 7] {
        t0 = time.perf_counter();
        answers = run_asks(jobs, max_inflight=limit);
        secs = time.perf_counter() - t0;
        distinct = len({str(a) for a in answers});
        print(
            "  "
            + str(limit).ljust(8)
            + (str(round(secs, 1)) + "s").ljust(8)
            + (str(round(secs / len(jobs), 1)) + "s").ljust(11)
            + f"{distinct} of {len(answers)}"
        );
    }
}
