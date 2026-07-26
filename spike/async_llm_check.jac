"""Is byLLM safe to call concurrently, and does the async path work?

Twelve deliberately tiny calls. Each asks for the uppercase of one word, so
the right answer is obvious and a mix-up is unmistakable.

Four ways of asking the same three questions:
  sequential          -- the baseline the pipeline uses today
  flow, loop variable -- the shape that corrupts
  flow, via launcher  -- same threads, but each launch gets its own frame
  asyncio.gather      -- no threads at all

If `flow via launcher` is correct then byLLM is thread-safe and the corruption
is purely the argument capture, not model state.
"""

import asyncio;
import os;
import time;
import medialib;
import from jaclang.byllm.lib { Model }

glob llm: Model = Model(
    model_name=os.getenv("REDACTION_MODEL", "vertex_ai/gemini-2.5-flash")
);

def shout(word: str) -> str by llm();
sem shout = "Reply with the given word in upper case and nothing else.";
sem shout.word = "The word to upper-case.";

async def shout_async(word: str) -> str by llm();
sem shout_async = "Reply with the given word in upper case and nothing else.";
sem shout_async.word = "The word to upper-case.";

"""Launch one call from its own call frame, so `flow`'s zero-argument lambda
closes over this frame rather than over the caller's loop variable."""
def launch_shout(word: str) -> object {
    return flow shout(word);
}

async def shout_all(words: list[str]) -> list[str] {
    return list(await asyncio.gather(*[shout_async(w) for w in words]));
}

# `report` is a walker statement in Jac, so a helper cannot be called that.
def show(label: str, got: list[str], want: list[str], secs: float) -> bool {
    verdict = "correct" if got == want else "CORRUPT";
    print("  " + label.ljust(22) + verdict.ljust(9) + str(round(secs, 1)) + "s  " + str(got));
    return got == want;
}

def warm_pool {
    # The first fan-out in a process starts a thread per task, which lets the
    # worker read its arguments before the launching loop moves on. Every
    # later fan-out reuses idle threads and loses that race. Burn the cold
    # run here so the measurements below are the steady state.
    futs = [flow len(s) for s in ["a", "bb", "ccc", "dddd"]];
    for f in futs {
        wait f;
    }
}

with entry {
    words = ["apple", "river", "stone", "cloud"];
    want = [w.upper() for w in words];
    warm_pool();

    t0 = time.perf_counter();
    got = [shout(w) for w in words];
    show("sequential", got, want, time.perf_counter() - t0);

    t0 = time.perf_counter();
    futs = [flow shout(w) for w in words];
    show("flow, loop variable", [wait f for f in futs], want, time.perf_counter() - t0);

    t0 = time.perf_counter();
    futs = [launch_shout(w) for w in words];
    show("flow, via launcher", [wait f for f in futs], want, time.perf_counter() - t0);

    t0 = time.perf_counter();
    show("asyncio.gather", asyncio.run(shout_all(words)), want, time.perf_counter() - t0);
}
