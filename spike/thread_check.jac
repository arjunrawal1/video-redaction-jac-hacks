"""Do concurrent policy asks still return each frame's own answer?

Puts the same question about seven real seed frames to the model twice: one at
a time, then all at once through `run_asks`. Prints the raw indices and the
words behind them, so a mix-up is visible directly.

Also sanity-checks the OCR the answers are built on, because `ocr.sv.jac`
fans out with `flow` over a loop variable -- the shape that corrupts here.
"""

import os;
import time;
import from ingest { ingest_video }
import from ocr { ReadText }
import from ai { format_words }
import from detect { AskJob, run_ask, run_asks }

include graph;

glob SCOPE: str = "spreadsheet-cell-contents: values the user typed into grid cells";
glob SEEDS: list[int] = [1, 9, 17, 25, 33, 41, 49];

# `report` is a walker statement in Jac, so a helper cannot be called that.
def show(fr: Frame, got: list[int]) {
    print(f"  frame {fr.index:2}: {got} -> {[fr.words[i].text for i in got]}");
}

def summarize(label: str, answers: list[list[int]], secs: float) {
    distinct = len({str(a) for a in answers});
    print(f"  {label}: {secs:.1f}s, {distinct} distinct of {len(answers)}");
}

with entry {
    src = os.getenv("DEMO_VIDEO", "");
    vid = ingest_video(src, fps=float(os.getenv("DEMO_FPS", "8")));
    ReadText() spawn vid;
    frames = [vid ->:Contains:->];

    by_index = {f.index: f for f in frames};
    picked = [by_index[i] for i in SEEDS if i in by_index];

    # ocr.sv.jac launches `flow detect_words(fr.jpeg_path) for fr in chunk`
    # with a batch size of 8. If that fan-out is losing its arguments the same
    # way, every frame in a chunk carries the last-of-chunk word list.
    ordered = [by_index[k] for k in sorted(by_index.keys())];
    matches = 0;
    checked = 0;
    for (i, fr) in enumerate(ordered) {
        last = min(i - (i % 8) + 7, len(ordered) - 1);
        if last != i {
            checked += 1;
            if [w.text for w in fr.words] == [w.text for w in ordered[last].words] {
                matches += 1;
            }
        }
    }
    print(f"OCR: {matches}/{checked} frames carry their chunk's last word list");

    # Every graph read happens here. The jobs carry plain values only.
    jobs = [
        AskJob(
            frame_path=fr.jpeg_path,
            scope=SCOPE,
            listing=format_words([w.text for w in fr.words]),
            limit=len(fr.words)
        )
        for fr in picked
    ];
    print(f"{len(jobs)} seed frames, word counts {[j.limit for j in jobs]}");

    print("");
    print("sequential:");
    t0 = time.perf_counter();
    seq = [run_ask(j.frame_path, j.scope, j.listing, j.limit) for j in jobs];
    seq_secs = time.perf_counter() - t0;
    for (fr, got) in zip(picked, seq) {
        show(fr, got);
    }
    summarize("sequential", seq, seq_secs);

    print("");
    print("batched, all in flight at once:");
    t0 = time.perf_counter();
    batch = run_asks(jobs);
    bat_secs = time.perf_counter() - t0;
    for (fr, got) in zip(picked, batch) {
        show(fr, got);
    }
    summarize("batched", batch, bat_secs);

    agree = len([1 for (a, b) in zip(seq, batch) if a == b]);
    print("");
    print(f"{agree} of {len(jobs)} batched answers match the sequential answer");
    print(f"speedup {seq_secs / max(bat_secs, 0.001):.1f}x");
}
