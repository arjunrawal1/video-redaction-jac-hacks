"""Runtime check: policy evaluation against real frames.

Ingests, OCRs, plans a policy, then evaluates it on a few frames and reports
which words it would redact.
"""

import os;
import time;
import from ingest { ingest_video }
import from ocr { ReadText }
import from policy { plan }
import from detect { EvalPredicate, SeedDetect, CollectAsks }

include graph;

with entry {
    src = os.getenv("DEMO_VIDEO", "");
    if not src or not os.path.exists(src) {
        print("set DEMO_VIDEO to a video file first");
    } else {
        vid = ingest_video(src, fps=float(os.getenv("DEMO_FPS", "8")));
        read = ReadText() spawn vid;
        frames = [vid ->:Contains:->];
        print(f"{len(frames)} frames, {read.frames_read} newly read");

        pol = plan("the contents of the spreadsheet cells that the user typed");
        for a in (CollectAsks() spawn pol).asks {
            print(f"  the policy will ask: {a.scope!r}");
        }

        for idx in [1, 20, 40] {
            picked = [f for f in frames if f.index == idx];
            if not picked { continue; }
            fr = picked[0];

            t0 = time.perf_counter();
            ev = EvalPredicate(frame=fr) spawn pol;
            dt = time.perf_counter() - t0;

            words = [fr.words[i].text for i in ev.result];
            print("");
            print(f"frame {fr.index} (t={fr.timestamp:.2f}s, {len(fr.words)} words) -> {len(ev.result)} hits in {dt:.1f}s, {ev.llm_calls} model call(s)");
            print(f"  {words}");
        }

        print("");
        t0 = time.perf_counter();
        seeded = SeedDetect(policy=pol) spawn vid;
        dt = time.perf_counter() - t0;
        print(f"seeded {len(seeded.seeds)} frames -> {seeded.boxes_added} boxes in {dt:.1f}s ({seeded.model_calls} model calls)");

        for fr in frames {
            boxes = [fr ->:Detected:->];
            if boxes {
                print(f"  frame {fr.index}: " + ", ".join([
                    f"{b.text!r}@[{b.y0},{b.x0},{b.y1},{b.x1}]" for b in boxes
                ]));
            }
        }

        t1 = time.perf_counter();
        again = SeedDetect(policy=pol) spawn vid;
        print(f"re-running added {again.boxes_added} more boxes in {time.perf_counter() - t1:.1f}s");
    }
}
