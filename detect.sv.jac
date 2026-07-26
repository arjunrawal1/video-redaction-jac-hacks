"""Deciding which words on a frame the policy requires redacting.

Evaluation is a walk over the policy subgraph. Each leaf answers for itself,
each operator combines what its children answered, and the runtime picks which
ability runs by the type of node the walker arrived at. There is no evaluator
function and no kind switch.

The combining step relies on exit abilities running post-order: children are
reached on the way down and have all reported by the time the operator's exit
ability fires on the way back up.

Only a sparse set of seed frames is evaluated. Propagating a detection across
neighbouring frames is the cascade's job, and it is far cheaper than asking a
model about every frame.
"""

import asyncio;
import os;
import from concurrent.futures { ThreadPoolExecutor }
import from difflib { SequenceMatcher }
import from jaclang.byllm.lib { Image }
import from ai { pick_sensitive, format_words }

include graph;

glob FUZZY_THRESHOLD: float = 0.82;

# Picks below this are more often the model reaching than finding. Redacting
# the wrong thing is visible and embarrassing; the cascade gets a second look
# at anything genuinely present.
glob MIN_PICK_CONFIDENCE: float = 0.5;

# Vertex stops giving more throughput past three or four requests in flight;
# beyond that each one just takes longer. See spike/inflight_check.jac.
glob MAX_INFLIGHT: int = int(os.getenv("REDACTION_MAX_INFLIGHT", "4"));

"""Loose text match tolerating the odd OCR error."""
def soft_match(word: str, needle: str, fuzzy: bool) -> bool {
    a = " ".join(word.lower().split());
    b = " ".join(needle.lower().split());
    if not b {
        return False;
    }
    if b in a or a in b {
        return True;
    }
    if not fuzzy {
        return False;
    }
    return SequenceMatcher(None, a, b).ratio() >= FUZZY_THRESHOLD;
}

"""Merge picked words into as few rectangles as cover them.

A redaction should read as one bar over a value, not a row of tiles over each
of its words. Words merge when they share a line and nearly touch.
"""
def merge_picks(words: list[WordBox], indices: list[int]) -> list[WordBox] {
    chosen = [words[i] for i in sorted(indices) if 0 <= i < len(words)];
    if not chosen {
        return [];
    }

    # Reading order: down the page, then across.
    keyed = sorted([(w.y0 * 10000 + w.x0, i) for (i, w) in enumerate(chosen)]);
    ordered = [chosen[i] for (_, i) in keyed];
    merged: list[WordBox] = [ordered[0]];

    for w in ordered[1:] {
        last = merged[-1];
        height = max(1, last.y1 - last.y0);
        same_line = abs(w.y0 - last.y0) <= height // 2;
        # A space between words is roughly half a line height wide.
        adjacent = w.x0 - last.x1 <= height;

        if same_line and adjacent and w.x0 >= last.x0 {
            merged[-1] = WordBox(
                text=f"{last.text} {w.text}",
                y0=min(last.y0, w.y0),
                x0=min(last.x0, w.x0),
                y1=max(last.y1, w.y1),
                x1=max(last.x1, w.x1),
                conf=min(last.conf, w.conf)
            );
        } else {
            merged.append(w);
        }
    }

    return merged;
}

"""How a region leaf is phrased when put to the model."""
def region_scope(leaf: RegionLeaf) -> str {
    scope = f"text located in or on {leaf.description}";
    return f"{scope} (every instance)" if leaf.all_instances else scope;
}

"""How a semantic leaf is phrased when put to the model."""
def semantic_scope(leaf: SemanticLeaf) -> str {
    return f"{leaf.category}: {leaf.description}";
}

"""One question, prepared off the graph and ready to send.

Carries plain values only. Nothing that runs off this thread -- a coroutine or
a `flow` -- may read a node, so every field is filled on the walker's own
thread before the batch goes out.
"""
obj AskJob {
    has frame_path: str;
    has scope: str;
    has listing: str;
    has limit: int;
}

"""Ask about one frame, holding a place in the rate-limit queue while it runs."""
async def ask_one(job: AskJob, gate: asyncio.Semaphore) -> list[int] {
    async with gate {
        picks = await pick_sensitive(Image(job.frame_path), job.scope, job.listing);
    }
    return sorted({
        p.index for p in picks
        if 0 <= p.index < job.limit and p.confidence >= MIN_PICK_CONFIDENCE
    });
}

async def ask_all(jobs: list[AskJob], max_inflight: int) -> list[list[int]] {
    gate = asyncio.Semaphore(max(1, max_inflight));
    return list(await asyncio.gather(*[ask_one(job, gate) for job in jobs]));
}

"""Put a batch of questions to the model with all of them in flight at once.

Answers come back in the order the jobs were given.

The batch is gathered rather than fanned out with `flow` because `flow expr`
compiles to a zero-argument lambda: nothing is captured, and every name in the
expression is read again on the worker thread, after the launching loop has
moved on. A `flow` launched from a loop therefore sends the *last* iteration's
arguments for every call in the batch, silently, with valid-looking results.
Building a coroutine binds its arguments there and then, so this cannot
happen. See `spike/flow_capture_check.jac`.
"""
def run_asks(jobs: list[AskJob], max_inflight: int = 0) -> list[list[int]] {
    if not jobs {
        return [];
    }
    batch = ask_all(jobs, max_inflight or MAX_INFLIGHT);
    in_loop = True;
    try {
        asyncio.get_running_loop();
    } except RuntimeError {
        in_loop = False;
    }
    if not in_loop {
        return asyncio.run(batch);
    }
    # Called from inside an event loop already, e.g. a server endpoint. Give
    # the batch its own loop on one worker rather than blocking the caller's.
    with ThreadPoolExecutor(max_workers=1) as pool {
        return pool.submit(asyncio.run, batch).result();
    }
}

"""Put one question to the model about one frame."""
def run_ask(frame_path: str, scope: str, listing: str, limit: int) -> list[int] {
    return run_asks([
        AskJob(frame_path=frame_path, scope=scope, listing=listing, limit=limit)
    ])[0];
}

"""A question one policy leaf needs answered about a frame."""
obj Ask {
    has leaf_id: str;
    has scope: str;
}

walker CollectAsks {
    """Gather the leaves that need a model call, without making any."""

    has asks: list[Ask] = [];

    can on_policy with Policy entry { visit [here ->:Governs:->]; }

    can on_op with AndOp | OrOp | NotOp entry { visit [here ->:Child:->]; }

    can on_region with RegionLeaf entry {
        self.asks.append(Ask(leaf_id=jid(here), scope=region_scope(here)));
    }

    can on_semantic with SemanticLeaf entry {
        self.asks.append(Ask(leaf_id=jid(here), scope=semantic_scope(here)));
    }
}

walker EvalPredicate {
    """Report the indices of a frame's words that satisfy a policy."""

    has frame: Frame;
    has cache: dict[str, list[int]] = {};
    has hits: dict[str, list[int]] = {};
    has result: list[int] = [];
    has llm_calls: int = 0;

    can on_policy with Policy entry {
        visit [here ->:Governs:->];
    }

    can on_op with AndOp | OrOp | NotOp entry {
        visit [here ->:Child:->];
    }

    can on_text with TextLeaf entry {
        self.hits[jid(here)] = [
            i for (i, w) in enumerate(self.frame.words)
            if soft_match(w.text, here.text, here.fuzzy)
        ];
    }

    can on_region with RegionLeaf entry {
        self.hits[jid(here)] = self.ask(here, region_scope(here));
    }

    can on_semantic with SemanticLeaf entry {
        self.hits[jid(here)] = self.ask(here, semantic_scope(here));
    }

    can and_done with AndOp exit {
        self.combine(here, "and");
    }

    can or_done with OrOp exit {
        self.combine(here, "or");
    }

    can not_done with NotOp exit {
        inner: set[int] = set();
        for k in [here ->:Child:->] {
            inner |= set(self.hits.get(jid(k), []));
        }
        everything = set(range(len(self.frame.words)));
        self.hits[jid(here)] = sorted(everything - inner);
    }

    can finish with Policy exit {
        governed = [here ->:Governs:->];
        picked: set[int] = set();
        for g in governed {
            picked |= set(self.hits.get(jid(g), []));
        }
        self.result = sorted(picked);
    }

    """Answer a leaf's question, preferring a pre-fetched answer.

    Callers that evaluate many frames fill `cache` first so the walk itself
    makes no network calls (see `SeedDetect`).
    """
    def ask(leaf: PredNode, scope: str) -> list[int] {
        key = jid(leaf);
        if key in self.cache {
            return self.cache[key];
        }
        if not self.frame.words {
            return [];
        }
        self.llm_calls += 1;
        return run_ask(
            self.frame.jpeg_path,
            scope,
            format_words([w.text for w in self.frame.words]),
            len(self.frame.words)
        );
    }

    def combine(at: PredNode, how: str) {
        kids = [at ->:Child:->];
        sets = [set(self.hits.get(jid(k), [])) for k in kids];
        if not sets {
            self.hits[jid(at)] = [];
            return;
        }
        out = sets[0];
        for s in sets[1:] {
            out = (out & s) if how == "and" else (out | s);
        }
        self.hits[jid(at)] = sorted(out);
    }
}

"""Evaluate one frame against a policy."""
def evaluate_frame(pol: Policy, fr: Frame) -> list[int] {
    return (EvalPredicate(frame=fr) spawn pol).result;
}

walker SeedDetect {
    """Detect on a sparse set of frames and attach the resulting boxes.

    Every frame is not worth a model call. Seeds are spaced across the video
    and the cascade carries each detection outwards from there, which is both
    cheaper and the only way the pipeline can claim to track content rather
    than re-find it.
    """

    has policy: Policy;
    has stride: int = 8;
    has redetect: bool = False;
    has seeds: list[Frame] = [];
    has boxes_added: int = 0;
    has model_calls: int = 0;

    can start with Video entry {
        visit [here ->:Contains:->[?:Frame, index == 1]];
    }

    can pick with Frame entry {
        due = (here.index - 1) % self.stride == 0;
        already = len([here ->:Detected:->]) > 0;
        if due and here.words and (self.redetect or not already) {
            self.seeds.append(here);
        }
        visit [here ->:Next:->];
    }

    can detect with Video exit {
        asks = (CollectAsks() spawn self.policy).asks;

        # Every graph read happens here, on this thread. What goes into the
        # batch is nothing but strings and ints.
        keys: list[tuple[str, str]] = [];
        jobs: list[AskJob] = [];
        for fr in self.seeds {
            listing = format_words([w.text for w in fr.words]);
            for a in asks {
                keys.append((jid(fr), a.leaf_id));
                jobs.append(AskJob(
                    frame_path=fr.jpeg_path,
                    scope=a.scope,
                    listing=listing,
                    limit=len(fr.words)
                ));
            }
        }

        cached: dict[str, dict[str, list[int]]] = {};
        for ((frame_key, leaf_id), found) in zip(keys, run_asks(jobs)) {
            if frame_key not in cached {
                cached[frame_key] = {};
            }
            cached[frame_key][leaf_id] = found;
        }
        self.model_calls = len(jobs);

        for fr in self.seeds {
            ev = EvalPredicate(frame=fr, cache=cached.get(jid(fr), {}))
                spawn self.policy;
            for m in merge_picks(fr.words, ev.result) {
                fr +>:Detected:+> Box(
                    y0=m.y0, x0=m.x0, y1=m.y1, x1=m.x1,
                    text=m.text,
                    origin="seed",
                    confidence=m.conf,
                    reason="matched the policy on a seed frame"
                );
                self.boxes_added += 1;
            }
        }
    }
}
