"""Running the whole pipeline for one video, reporting as it goes.

Every pass already works on its own; this is the seam that puts them in order
and lets the browser watch. A full run takes minutes -- most of it waiting on a
vision model -- so a request that answered only at the end would look like a
hung page. Each stage leaves the server the moment it finishes.

Progress frames are JSON objects with a `stage` and a human sentence. The
client renders the sentence and uses `stage` to decide what to highlight, so
adding detail here does not require a client change.
"""

import json;
import os;
import time;
import from typing { Generator }

import from policy { plan, ReadPolicy }
import from ocr { ReadText }
import from detect { SeedDetect }
import from cascade { SeedCascades }
import from export { RenderRedacted }
import from library { FIXTURE_MARK }

include graph;

"""Find a video by the id the client was given.

Named for what it matches on: the ingest pass has its own lookup keyed by
content hash, and two functions called `find_video` in scope resolve to one of
them, which answers None for every id it is handed.
"""
def video_by_id(video_id: str) -> Video | None {
    for v in [root -->[?:Video]] {
        if jid(v) == video_id {
            return v;
        }
    }
    return None;
}

"""One progress frame, as the client will read it."""
def event(stage: str, message: str, extra: dict | None = None) -> str {
    payload = {"stage": stage, "message": message};
    if extra is not None {
        payload.update(extra);
    }
    return json.dumps(payload);
}

"""Record a frame on a run's log and hand it straight back to be yielded."""
def keep(log: list[str], frame: str) -> str {
    log.append(frame);
    return frame;
}

"""Plan a policy, find what it covers, follow it across the video, and export.

Refuses when boxes are already present rather than redacting on top of them:
deleting and creating inside one request loses the new nodes, so clearing is
the caller's own separate call.
"""
def:pub run_pipeline(
    video_id: str,
    request: str,
    stride: int = 8,
    max_steps: int = 8,
    reread: bool = False
) -> Generator {
    # Resolved out here, not inside the generator. The generator body runs
    # while the response is being written, and `root` is not the caller's root
    # by then -- every graph query made from in there comes back empty.
    # Anything reached before the first yield stays reachable afterwards.
    found = video_by_id(video_id);
    frames = [found ->:Contains:->[?:Frame]] if found is not None else [];
    standing = [b for f in frames for b in [f ->:Detected:->[?:Box]]];

    def stream -> Generator[str, None, None] {
        started = time.perf_counter();

        if found is None {
            yield event("error", f"No video with id {video_id}.");
            return;
        }
        vid: Video = found;

        if standing {
            fixture = len([b for b in standing if FIXTURE_MARK in b.reason]);
            hint = " They are fixture boxes; clear_demo_cascade removes them." if fixture else "";
            yield event(
                "error",
                f"{len(standing)} box(es) are already on this video.{hint}"
            );
            return;
        }

        # Every frame is kept as it goes out so the run can be played back
        # later at its own pace instead of asking the model again.
        log: list[str] = [];

        yield keep(log, event(
            "start",
            f"{vid.title}: {len(frames)} frames, {vid.duration:.1f}s.",
            {"frames": len(frames)}
        ));

        # --- policy -------------------------------------------------------
        yield keep(log, event("policy", f"Reading the request: {request!r}"));
        mark = time.perf_counter();
        pol = plan(request);
        rows = (ReadPolicy() spawn pol).rows;
        shape = [
            {"id": r.id, "parent": r.parent, "kind": r.kind, "detail": r.detail}
            for r in rows
        ];
        yield keep(log, event(
            "policy",
            f"Policy is {len(rows)} condition(s) in {time.perf_counter() - mark:.1f}s.",
            {"policy": shape, "policy_id": jid(pol)}
        ));

        # --- ocr ----------------------------------------------------------
        # `reread` exists because OCR is cached on the frame and there is no
        # other way to replace text that was read by an older build.
        if reread {
            for f in frames {
                f.ocr_done = False;
                f.words = [];
            }
        }
        unread = len([f for f in frames if not f.ocr_done]);
        if unread {
            yield keep(log, event("ocr", f"Reading text off {unread} frame(s)."));
            mark = time.perf_counter();
            read = ReadText() spawn vid;
            yield keep(log, event(
                "ocr",
                f"{read.words_added} words from {read.frames_read} frame(s) in {time.perf_counter() - mark:.1f}s."
            ));
        } else {
            words = sum([len(f.words) for f in frames]);
            yield keep(log, event("ocr", f"Text already read: {words} words on the graph."));
        }

        # --- detection ----------------------------------------------------
        yield keep(log, event("detect", f"Judging every {stride}th frame against the policy."));
        mark = time.perf_counter();
        found = SeedDetect(policy=pol, stride=stride) spawn vid;
        yield keep(log, event(
            "detect",
            f"{found.boxes_added} redaction(s) on {len(found.seeds)} seed frame(s), "
            f"{found.model_calls} model call(s) in {time.perf_counter() - mark:.1f}s.",
            {
                "seeds": [f.index for f in found.seeds],
                "boxes": found.boxes_added
            }
        ));

        if not found.boxes_added {
            empty = keep(log, event(
                "done",
                "Nothing on this video matches that policy, so there is nothing to redact."
            ));
            vid.run_request = request;
            vid.run_log = log;
            yield empty;
            return;
        }

        # --- cascade ------------------------------------------------------
        yield keep(log, event("cascade", "Sending agents out from each seed frame."));
        mark = time.perf_counter();
        run = SeedCascades(max_steps=max_steps) spawn vid;
        for a in run.agents {
            yield keep(log, event(
                "agent",
                a.summary,
                {
                    "agent_id": a.agent_id,
                    "direction": a.direction,
                    "seed_index": a.seed_index,
                    "steps": a.steps,
                    "reason": a.reason
                }
            ));
        }
        covered = len([f for f in frames if [f ->:Detected:->[?:Box]]]);
        yield keep(log, event(
            "cascade",
            f"{len(run.agents)} agents added {run.boxes_added} redaction(s) in "
            f"{time.perf_counter() - mark:.1f}s; {covered} of {len(frames)} frames covered.",
            {"covered": covered, "agents": len(run.agents)}
        ));

        # --- export -------------------------------------------------------
        yield keep(log, event("export", "Burning the redactions into a copy of the video."));
        mark = time.perf_counter();
        rendered = RenderRedacted() spawn vid;
        verb = "Reused" if rendered.reused else "Wrote";
        yield keep(log, event(
            "export",
            f"{verb} {os.path.basename(rendered.output_path)} from "
            f"{len(rendered.spans)} span(s) in {time.perf_counter() - mark:.1f}s.",
            {"export_path": rendered.output_path}
        ));

        total = len([b for f in frames for b in [f ->:Detected:->[?:Box]]]);
        final = keep(log, event(
            "done",
            f"Done in {time.perf_counter() - started:.1f}s: {total} redaction(s) "
            f"across {covered} frame(s).",
            {"boxes": total, "covered": covered}
        ));
        vid.run_request = request;
        vid.run_log = log;
        yield final;
    }

    report stream();
}

"""Play a finished run back, one frame at a time.

The passes are not re-run: this reads the frames the run itself emitted and
paces them out so the sequence is watchable. A run costs minutes of model time
and the same answer twice, so asking again to show what happened would be
wasteful and would risk a different result on stage.
"""
def:pub replay_pipeline(video_id: str, beat: float = 0.55) -> Generator {
    found = video_by_id(video_id);
    recorded = list(found.run_log) if found is not None else [];

    def stream -> Generator[str, None, None] {
        if found is None {
            yield event("error", f"No video with id {video_id}.");
            return;
        }
        if not recorded {
            yield event(
                "error",
                "No recorded run for this video. Press run to make one."
            );
            return;
        }
        for frame in recorded {
            time.sleep(max(0.0, beat));
            yield frame;
        }
    }

    report stream();
}

"""Whether a video has a run worth replaying, and what was asked for."""
obj RunRecord {
    has present: bool;
    has request: str;
    has steps: int;
}

"""Attach the frames a run emitted to the video it ran on. Dev hook.

A run that finished before the log field existed still happened, and its frames
were captured on the way past. This puts them where `replay_pipeline` looks
rather than spending another few minutes of model time to regenerate text that
is already known.
"""
def:pub record_run(video_id: str, request: str, lines: list[str]) -> RunRecord {
    vid = video_by_id(video_id);
    if vid is None {
        return RunRecord(present=False, request="", steps=0);
    }
    vid.run_request = request;
    vid.run_log = lines;
    return RunRecord(present=len(lines) > 0, request=request, steps=len(lines));
}

"""Report whether a video already has a run the console can play back."""
def:pub get_run_record(video_id: str) -> RunRecord {
    vid = video_by_id(video_id);
    if vid is None {
        return RunRecord(present=False, request="", steps=0);
    }
    return RunRecord(
        present=len(vid.run_log) > 0,
        request=vid.run_request,
        steps=len(vid.run_log)
    );
}
