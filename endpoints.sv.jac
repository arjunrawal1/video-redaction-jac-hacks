"""Write side of the API: getting a new video into the graph.

Only one of these is real. `request_ingest` is the endpoint the upload control
in the UI calls, and it deliberately refuses: nothing behind it turns an
uploaded file into a Frame chain yet, and a control that reported success would
be lying about a pipeline that never ran. The refusal is server-authoritative
so that wiring ingest up is a change here, not in the client.

`seed_from_path` is the dev hook that fills the graph from a video already on
this machine. It exists because reads run against the *calling user's* root, so
data ingested by a `jac run` script lands somewhere the served app cannot see;
seeding over HTTP puts the video on the same root the UI reads from.

Importing the pipeline passes at module level is deliberate: an import inside
an endpoint body resolves against a different path at request time and fails
with `No module named 'medialib'`, and importing medialib is also what loads
`.env`, so the credentials OCR needs are only there on this route.
"""

import os;
import from ingest { ingest_video }
import from ocr { ReadText }
import from library { FIXTURE_MARK }

include graph;

"""What the UI shows after asking the server to take a video."""
obj IngestOutcome {
    has accepted: bool,
        message: str,
        video_id: str;
}

"""Take a chosen recording, ingesting it if this machine can find the file.

The browser hands over a name, not a path, so this looks for the file where
screen recordings land and where the project keeps its own media. A recording
already in the graph is handed straight back rather than decoded again -- the
frames, the text and any finished run are all still there.

When the file is nowhere this machine can reach, it says so instead of
reporting a run that never happened.
"""
def:pub request_ingest(filename: str, fps: float = 4.0) -> IngestOutcome {
    if not filename {
        return IngestOutcome(accepted=False, message="No file chosen.", video_id="");
    }

    for v in [root -->[?:Video]] {
        if v.title == filename or os.path.basename(v.source_path) == filename {
            frames = [v ->:Contains:->[?:Frame]];
            return IngestOutcome(
                accepted=True,
                message=(
                    f"'{filename}' is already in the graph: {len(frames)} frames, "
                    "text read. Ready to redact."
                ),
                video_id=jid(v)
            );
        }
    }

    for folder in SEARCH_DIRS {
        candidate = os.path.join(os.path.expanduser(folder), filename);
        if os.path.exists(candidate) {
            vid = ingest_video(candidate, fps=fps);
            run = ReadText() spawn vid;
            frames = [vid ->:Contains:->[?:Frame]];
            return IngestOutcome(
                accepted=True,
                message=(
                    f"{len(frames)} frames kept, {run.words_added} words read "
                    f"from '{filename}'. Ready to redact."
                ),
                video_id=jid(vid)
            );
        }
    }

    return IngestOutcome(
        accepted=False,
        message=(
            f"'{filename}' is not somewhere this server can read. A browser "
            "hands over the name but not the path, so the file has to be on "
            "this machine, in the project's media folder or with the screen "
            "recordings."
        ),
        video_id=""
    );
}

# Where a chosen file might actually live. The browser gives a bare name, so
# the server looks rather than guesses.
glob SEARCH_DIRS: list[str] = [
    "media", "~/Documents", "~/Desktop", "~/Movies", "~/Downloads"
];

"""Ingest a video already on the server's disk and OCR it. Dev seeding only."""
def:pub seed_from_path(
    source_path: str, fps: float = 8.0, title: str = ""
) -> IngestOutcome {
    if not os.path.exists(source_path) {
        return IngestOutcome(
            accepted=False, message=f"no such file: {source_path}", video_id=""
        );
    }
    vid = ingest_video(source_path, title=title, fps=fps);
    run = ReadText() spawn vid;
    frames = [vid ->:Contains:->[?:Frame]];
    return IngestOutcome(
        accepted=True,
        message=(
            f"{len(frames)} frames, {run.frames_read} newly read, "
            f"{run.words_added} words"
        ),
        video_id=jid(vid)
    );
}

# ------------------------------------------------------- fixture cascade
#
# Detection and the cascade both cost model calls and a policy, and the app
# graph has neither yet, so the cascade view had nothing to draw. This builds
# the same node and edge shapes those two passes produce, out of OCR text that
# is already on the frames: a few seed frames, some values on each, and a
# forward and a backward agent per seed that follow those values along the Next
# chain the same way `Cascade` does -- a value survives a frame if the frame's
# words still contain it, and an agent stops for the same reasons, with the same
# summary wording.
#
# What is NOT real here: which words count as sensitive. The pipeline decides
# that with a policy and a vision model; this ranks the frame's own words by a
# crude "looks like a value, not chrome" heuristic, or takes the list the caller
# passes. Every box it writes carries FIXTURE_MARK in its reason so the UI can
# label the data as fabricated and `clear_demo_cascade` can lift it back out.

"""What a fixture cascade run put into the graph."""
obj CascadeSeed {
    has accepted: bool,
        message: str,
        video_id: str,
        seed_frames: list[int],
        targets: list[str],
        agents: int,
        tracks: int,
        seed_boxes: int,
        cascade_boxes: int;
}

"""What a fixture teardown took back out."""
obj CascadeWipe {
    has boxes: int,
        agents: int,
        tracks: int,
        message: str;
}

# Chrome, menus and product names: present on every frame of a screen recording
# and never the thing a redaction policy is after.
glob FIXTURE_CHROME: set[str] = {
    "chrome", "history", "bookmarks", "profiles", "window", "file", "edit",
    "view", "insert", "format", "extensions", "tools", "help", "untitled",
    "spreadsheet", "google", "googli", "github", "youtube", "classroom",
    "chatgpt", "network", "student", "impact", "commons", "charger", "rating",
    "featured", "project", "tables", "custom", "palettes", "includes",
    "notifications", "redaction", "visualizer", "problem", "search", "share"
};

"""Comparison key for a word: what it is, ignoring case and punctuation."""
def _key(text: str) -> str {
    return "".join([c for c in text if c.isalnum()]).lower();
}

def _hop(f: Frame, ahead: bool) -> Frame | None {
    nxt = [f ->:Next:->[?:Frame]] if ahead else [f <-:Next:<-[?:Frame]];
    return nxt[0] if nxt else None;
}

"""Every word on a frame whose key matches, in reading order."""
def _matching_words(f: Frame, key: str) -> list[WordBox] {
    return [w for w in f.words if _key(w.text) == key];
}

"""Frame index -> the set of word keys on it, so persistence is a set lookup."""
def _key_index(frames: list[Frame]) -> dict[int, set[str]] {
    return {f.index: {_key(w.text) for w in f.words} for f in frames};
}

"""How many frames a value stays on screen from `at`, walking one way.

Capped at `cap`, and the cap is also what "never went away while we were
looking" reports. Positional rather than edge-walking because it runs for every
candidate word on a seed frame; the agents themselves follow the Next chain.
"""
def _survives(
    order: list[int],
    at: int,
    key: str,
    keys: dict[int, set[str]],
    ahead: bool,
    cap: int
) -> int {
    pos = order.index(at);
    steps = 0;
    while steps < cap {
        nxt = (pos + 1) if ahead else (pos - 1);
        if nxt < 0 or nxt >= len(order) or key not in keys[order[nxt]] {
            break;
        }
        pos = nxt;
        steps += 1;
    }
    return steps;
}

"""Choose the values a seed frame hands its two agents.

Two things make a good fixture target. It has to look like a value rather than
browser chrome -- long, lowercase, not a menu label -- and the walk it produces
has to be interesting: a value that outlives the step limit everywhere only ever
demonstrates one of the four ways an agent can stop. So candidates that leave
the screen inside the window win, longest-lived first, and the chosen set is
kept to values that disappear at about the same time, because an agent lives
until its *last* target is gone.
"""
def _pick_targets(
    seed_frame: Frame,
    order: list[int],
    keys: dict[int, set[str]],
    cap: int,
    per_seed: int
) -> list[str] {
    seen: dict[str, str] = {};
    for w in seed_frame.words {
        k = _key(w.text);
        if len(k) < 7 or k in FIXTURE_CHROME or k.isdigit() {
            continue;
        }
        if k not in seen {
            seen[k] = w.text;
        }
    }

    pos = order.index(seed_frame.index);
    reach: dict[str, int] = {};
    for k in seen.keys() {
        legs: list[int] = [];
        if pos + 1 < len(order) {
            legs.append(_survives(order, seed_frame.index, k, keys, True, cap));
        }
        if pos > 0 {
            legs.append(_survives(order, seed_frame.index, k, keys, False, cap));
        }
        reach[k] = min(legs) if legs else 0;
    }

    ranked = sorted(
        seen.keys(),
        key=lambda (k: str) {
            (
                0 if reach[k] < cap else 1,   # ends inside the window
                -reach[k],                    # but lives as long as possible
                0 if seen[k] == k else 1,     # a pasted value, not a Menu Label
                -len(k),
                k
            );
        }
    );
    if not ranked {
        return [];
    }

    lead = ranked[0];
    ends = reach[lead] < cap;
    group = [
        k for k in ranked
        if (reach[k] < cap) == ends and abs(reach[k] - reach[lead]) <= 1
    ];
    return group[:per_seed];
}

"""Attach a fixture cascade to a video that is already ingested and OCR'd.

Seeds every `stride` frames from frame 1, so one backward agent always has
nowhere to go -- that is a real outcome of the pass and the view should show it.
Pass `targets` to choose the tracked values by hand; the default picks them off
the seed frames. Refuses if the video already carries boxes: run
`clear_demo_cascade` first, in its own request.
"""
def:pub seed_demo_cascade(
    video_id: str,
    seeds: int = 4,
    stride: int = 16,
    per_seed: int = 2,
    max_steps: int = 8,
    targets: list[str] | None = None
) -> CascadeSeed {
    video: Video | None = None;
    for v in [root -->[?:Video]] {
        if jid(v) == video_id {
            video = v;
        }
    }
    if video is None {
        return CascadeSeed(
            accepted=False,
            message=f"no video with id {video_id}",
            video_id=video_id,
            seed_frames=[], targets=[], agents=0, tracks=0,
            seed_boxes=0, cascade_boxes=0
        );
    }

    frames = sorted([video ->:Contains:->[?:Frame]], key=lambda (f: Frame) { f.index; });
    if not frames {
        return CascadeSeed(
            accepted=False,
            message="that video has no frames",
            video_id=video_id,
            seed_frames=[], targets=[], agents=0, tracks=0,
            seed_boxes=0, cascade_boxes=0
        );
    }

    # A request that deletes nodes and then creates more throws the new ones
    # away: seeding on top of an existing fixture reported 8 agents and 88
    # boxes and left the graph empty, with a 200 and nothing in the log. So
    # this refuses instead of wiping first, and the teardown is its own call.
    standing = len([b for f in frames for b in [f ->:Detected:->[?:Box]]]);
    if standing > 0 {
        return CascadeSeed(
            accepted=False,
            message=(
                f"{standing} box(es) are already on this video. Call "
                "clear_demo_cascade first: deleting and creating in one "
                "request silently loses the new nodes."
            ),
            video_id=video_id,
            seed_frames=[], targets=[], agents=0, tracks=0,
            seed_boxes=0, cascade_boxes=0
        );
    }

    at_index: dict[int, Frame] = {f.index: f for f in frames};
    order = [f.index for f in frames];
    keys = _key_index(frames);
    asked = targets if targets is not None else [];
    wanted = [_key(t) for t in asked if _key(t)];

    known: dict[str, Track] = {};
    for t in [root -->[?:Track]] {
        known[_key(t.label)] = t;
    }

    seed_indices: list[int] = [];
    n = 1;
    while len(seed_indices) < seeds and n in at_index {
        seed_indices.append(n);
        n += stride;
    }

    all_targets: list[str] = [];
    agents = 0;
    seed_boxes = 0;
    cascade_boxes = 0;

    for si in seed_indices {
        seed_frame = at_index[si];
        picked = [k for k in wanted if _matching_words(seed_frame, k)];
        if not picked {
            picked = _pick_targets(seed_frame, order, keys, max_steps, per_seed);
        }
        picked = picked[:per_seed];
        if not picked {
            continue;
        }

        labels: dict[str, str] = {};
        live: list[str] = [];
        for k in picked {
            hits = _matching_words(seed_frame, k);
            if not hits {
                continue;
            }
            labels[k] = hits[0].text;
            live.append(k);
            if k not in known {
                fresh = Track(label=hits[0].text);
                root ++> fresh;
                known[k] = fresh;
            }
            if hits[0].text not in all_targets {
                all_targets.append(hits[0].text);
            }
            for w in hits[:2] {
                box = Box(
                    y0=w.y0, x0=w.x0, y1=w.y1, x1=w.x1,
                    text=hits[0].text,
                    origin="seed",
                    confidence=0.94,
                    reason=f"matched the redaction policy on a seed frame {FIXTURE_MARK}"
                );
                seed_frame +>:Detected:+> box;
                box +>:MemberOf:+> known[k];
                seed_boxes += 1;
            }
        }

        if not live {
            continue;
        }

        for ahead in [True, False] {
            run = _run_fixture_agent(seed_frame, ahead, live, labels, known, max_steps);
            cascade_boxes += run;
            agents += 1;
        }
    }

    return CascadeSeed(
        accepted=True,
        message=(
            f"seeded {len(seed_indices)} frame(s): {agents} agent(s), "
            f"{len(all_targets)} track(s), {seed_boxes} seed box(es), "
            f"{cascade_boxes} cascaded box(es). Fixture data - reasons carry "
            f"'{FIXTURE_MARK}'."
        ),
        video_id=video_id,
        seed_frames=seed_indices,
        targets=all_targets,
        agents=agents,
        tracks=len(all_targets),
        seed_boxes=seed_boxes,
        cascade_boxes=cascade_boxes
    );
}

"""One agent's walk. Returns the number of boxes it placed.

Mirrors `Cascade`: arrive, stop if the limit is up, otherwise check every live
value against the frame's words, write a box per surviving value, drop the rest,
and move on until there is nowhere left to go. The summary string is built with
the same expression the real walker uses, including its use of `focus` (the last
frame inspected) rather than the seed.
"""
def _run_fixture_agent(
    seed_frame: Frame,
    ahead: bool,
    keys: list[str],
    labels: dict[str, str],
    tracks: dict[str, Track],
    max_steps: int
) -> int {
    name = "forward" if ahead else "backward";
    agent = Agent(
        agent_id=f"{name}-{seed_frame.index}",
        direction=name,
        focus=seed_frame.index
    );
    root ++> agent;

    first = _hop(seed_frame, ahead);
    if first is None {
        agent.summary = f"{name} from frame {seed_frame.index}: no frame that way";
        return 0;
    }

    here: Frame = first;
    live = list(keys);
    steps = 0;
    placed = 0;
    reason = "";

    while True {
        if steps >= max_steps {
            reason = "reached its step limit";
            break;
        }

        steps += 1;
        agent.focus = here.index;
        agent.steps = steps;

        survivors: list[str] = [];
        for k in live {
            hits = _matching_words(here, k);
            if not hits {
                continue;
            }
            survivors.append(k);
            for w in hits[:2] {
                box = Box(
                    y0=w.y0, x0=w.x0, y1=w.y1, x1=w.x1,
                    text=labels[k],
                    origin="cascade",
                    confidence=max(0.62, 0.93 - (0.04 * steps)),
                    reason=(
                        f"still on screen {steps} frame(s) from the seed "
                        f"{FIXTURE_MARK}"
                    )
                );
                here +>:Detected:+> box;
                box +>:AddedBy:+> agent;
                box +>:MemberOf:+> tracks[k];
                placed += 1;
            }
        }

        live = survivors;
        if not live {
            reason = f"nothing left to follow after frame {here.index}";
            break;
        }

        onward = _hop(here, ahead);
        if onward is None {
            reason = "reached the end of the video" if ahead
                else "reached the start of the video";
            break;
        }
        here = onward;
    }

    agent.reason = reason;
    agent.still_visible = len(live) > 0;
    agent.summary = (
        f"{agent.direction} from frame {agent.focus}: "
        f"{placed} box(es) over {steps} step(s), stopped because {reason}"
    );
    return placed;
}

"""Remove the fixture cascade: every marked box, the agents that placed only
those, and any track left with no members. Real detector output is left alone.
"""
def _wipe_fixtures(frames: list[Frame]) -> CascadeWipe {
    boxes = 0;
    for f in frames {
        for b in [f ->:Detected:->[?:Box]] {
            if FIXTURE_MARK in b.reason {
                del b;
                boxes += 1;
            }
        }
    }

    agents = 0;
    for a in [root -->[?:Agent]] {
        if not [a <-:AddedBy:<-[?:Box]] {
            del a;
            agents += 1;
        }
    }

    tracks = 0;
    for t in [root -->[?:Track]] {
        if not [t <-:MemberOf:<-[?:Box]] {
            del t;
            tracks += 1;
        }
    }

    return CascadeWipe(
        boxes=boxes,
        agents=agents,
        tracks=tracks,
        message=(
            f"removed {boxes} fixture box(es), {agents} agent(s) left with "
            f"nothing to their name, {tracks} empty track(s)"
        )
    );
}

"""Take every redaction off a video so a different request can be run.

`clear_demo_cascade` only lifts fixture data; this removes real detector output
too, along with the agents and tracks left with nothing to their name. Its own
call because deleting and creating inside one request throws the new nodes
away.
"""
def:pub clear_video_boxes(video_id: str) -> CascadeWipe {
    target: Video | None = None;
    for v in [root -->[?:Video]] {
        if jid(v) == video_id {
            target = v;
        }
    }
    if target is None {
        return CascadeWipe(
            boxes=0, agents=0, tracks=0, message=f"no video with id {video_id}"
        );
    }

    # The edge goes, not the node. Deleting the Box itself reports success and
    # leaves it on the graph after the request; dropping the edge that makes it
    # part of the frame is what actually takes effect, and an unreachable box
    # is invisible to every reader here.
    boxes = 0;
    for f in [target ->:Contains:->[?:Frame]] {
        for e in [edge f ->:Detected:->] {
            del e;
            boxes += 1;
        }
    }

    agents = 0;
    for a in [root -->[?:Agent]] {
        if not [a <-:AddedBy:<-[?:Box]] {
            del a;
            agents += 1;
        }
    }

    tracks = 0;
    for t in [root -->[?:Track]] {
        if not [t <-:MemberOf:<-[?:Box]] {
            del t;
            tracks += 1;
        }
    }

    target.run_log = [];
    target.run_request = "";

    return CascadeWipe(
        boxes=boxes,
        agents=agents,
        tracks=tracks,
        message=f"removed {boxes} box(es), {agents} agent(s), {tracks} track(s)"
    );
}

"""Take the fixture cascade back out of the graph. Dev only."""
def:pub clear_demo_cascade(video_id: str) -> CascadeWipe {
    for v in [root -->[?:Video]] {
        if jid(v) == video_id {
            return _wipe_fixtures([v ->:Contains:->[?:Frame]]);
        }
    }
    return CascadeWipe(
        boxes=0, agents=0, tracks=0, message=f"no video with id {video_id}"
    );
}
