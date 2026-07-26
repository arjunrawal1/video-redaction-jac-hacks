"""Runtime check: do cascade agents carry detections off their seed frames?

Runs a deliberately small budget -- a couple of seeds, a few steps each -- so
the mechanics can be checked without paying for a whole video.
"""

import os;
import time;
import from ingest { ingest_video }
import from ocr { ReadText }
import from policy { plan }
import from detect { SeedDetect }
import from cascade { SeedCascades }

include graph;

with entry {
    src = os.getenv("DEMO_VIDEO", "");
    stride = int(os.getenv("SEED_STRIDE", "32"));
    steps = int(os.getenv("CASCADE_STEPS", "3"));

    vid = ingest_video(src, fps=float(os.getenv("DEMO_FPS", "8")));
    ReadText() spawn vid;
    frames = [vid ->:Contains:->];
    pol = plan("the contents of the spreadsheet cells that the user typed");

    t0 = time.perf_counter();
    seeded = SeedDetect(policy=pol, stride=stride) spawn vid;
    print(f"seeded {len(seeded.seeds)} frame(s) -> {seeded.boxes_added} boxes in {time.perf_counter() - t0:.1f}s");

    t0 = time.perf_counter();
    run = SeedCascades(max_steps=steps) spawn vid;
    print(f"{len(run.agents)} agents added {run.boxes_added} boxes in {time.perf_counter() - t0:.1f}s");
    print("");

    for a in run.agents {
        print(f"  {a.agent_id:>16}  {a.summary}");
    }

    print("");
    covered = [f for f in frames if [f ->:Detected:->]];
    print(f"frames with redactions: {len(covered)} of {len(frames)}");

    print("");
    print("tracks:");
    for tr in [root -->[?:Track]] {
        members = [tr <-:MemberOf:<-];
        seeds = len([b for b in members if b.origin == "seed"]);
        print(f"  {tr.label!r}: {len(members)} boxes ({seeds} seeded, {len(members) - seeds} cascaded)");
    }

    print("");
    print("provenance of a cascaded box:");
    for f in covered {
        picked = [b for b in [f ->:Detected:->] if b.origin == "cascade"];
        if picked {
            b = picked[0];
            by = [b ->:AddedBy:->];
            of = [b ->:MemberOf:->];
            print(f"  frame {f.index}: {b.text!r} placed by {by[0].agent_id if by else '?'}");
            print(f"    track   : {of[0].label!r}" if of else "    track   : none");
            print(f"    reason  : {b.reason}");
            print(f"    at      : [{b.y0},{b.x0},{b.y1},{b.x1}] conf {b.confidence:.2f}");
            break;
        }
    }
}
