"""Does `flow` see the arguments that were in scope when it was launched?

`flow expr` compiles to `thread_run(lambda: expr)` -- a zero-argument lambda.
Nothing is captured by value, so every name in the expression is looked up
again on the worker thread, after the launching loop has already moved on.

This runs the same fan-out several ways with a pure local function, so a
mix-up is visible with no model calls and no network. It also shows why the
bug looked like it depended on where the code lived: the outcome is a race
against the thread pool, and the first fan-out in a process runs against a
cold pool that has to start a thread per task, which lets the worker win.
"""

import from time { sleep }

# Long enough that the launching loop always finishes before a worker starts.
glob HOLD: float = 0.30;

"""Stand-in for a slow call. Returns something unique per argument pair."""
def echo(tag: str, payload: str) -> str {
    sleep(HOLD);
    return f"{tag}:{len(payload)}";
}

"""Launch one call from its own call frame.

Each invocation gets a fresh binding for `tag` and `payload`, so the lambda
`flow` builds closes over this frame rather than over a loop variable that is
about to be reassigned.
"""
def launch(tag: str, payload: str) -> object {
    return flow echo(tag, payload);
}

def tags -> list[str] {
    return ["a", "b", "c", "d"];
}

def payloads -> list[str] {
    return ["x" * 200, "y" * 400, "z" * 600, "w" * 800];
}

# `report` is a walker statement in Jac, so a helper cannot be called that.
def show(label: str, got: list[str], want: list[str]) -> bool {
    verdict = "correct" if got == want else "CORRUPT";
    print("  " + label.ljust(38) + verdict.ljust(9) + str(got));
    return got == want;
}

walker Fanout {
    """The same two fan-outs, run from inside a walker ability."""

    has via_loop_var: list[str] = [];
    has via_launcher: list[str] = [];

    can run with Root entry {
        ts = tags();
        ps = payloads();

        futs = [flow echo(t, p) for (t, p) in zip(ts, ps)];
        self.via_loop_var = [wait f for f in futs];

        futs2 = [launch(t, p) for (t, p) in zip(ts, ps)];
        self.via_launcher = [wait f for f in futs2];
    }
}

with entry {
    ts = tags();
    ps = payloads();
    want = [f"{t}:{len(p)}" for (t, p) in zip(ts, ps)];

    # First, before anything else has touched the thread pool.
    print("identical fan-out, repeated (cold pool first):");
    for rep in range(4) {
        futs = [flow echo(t, p) for (t, p) in zip(ts, ps)];
        show(f"module-level comprehension, rep {rep}", [wait f for f in futs], want);
    }

    print("");
    print("baseline:");
    show("sequential", [echo(t, p) for (t, p) in zip(ts, ps)], want);

    print("");
    print("module-level `with entry`, warm pool:");

    futs = [];
    for (t, p) in zip(ts, ps) {
        futs.append(flow echo(t, p));
    }
    show("for-loop over a loop variable", [wait f for f in futs], want);

    futs = [];
    for (t, p) in zip(ts, ps) {
        # Rebinding to a fresh name inside the body changes nothing: the body
        # shares one binding across every iteration too.
        my_t = t;
        my_p = p;
        futs.append(flow echo(my_t, my_p));
    }
    show("copied into a local inside the body", [wait f for f in futs], want);

    # No loop variable anywhere: four names, each assigned exactly once.
    (t0, t1, t2, t3) = ts;
    (p0, p1, p2, p3) = ps;
    f0 = flow echo(t0, p0);
    f1 = flow echo(t1, p1);
    f2 = flow echo(t2, p2);
    f3 = flow echo(t3, p3);
    show(
        "unrolled, one name per call", [wait f0, wait f1, wait f2, wait f3], want
    );

    futs = [launch(t, p) for (t, p) in zip(ts, ps)];
    show("launched from its own call frame", [wait f for f in futs], want);

    print("");
    print("inside a walker ability:");
    w = Fanout() spawn root;
    show("comprehension over a loop variable", w.via_loop_var, want);
    show("launched from its own call frame", w.via_launcher, want);

    print("");
    print("payload size (1-4 char payloads, loop variable):");
    tiny = ["1", "22", "333", "4444"];
    tiny_want = [f"{t}:{len(p)}" for (t, p) in zip(ts, tiny)];
    futs = [flow echo(t, p) for (t, p) in zip(ts, tiny)];
    show("tiny payloads", [wait f for f in futs], tiny_want);

    print("");
    print("call duration (no sleep at all, loop variable):");
    globals()["HOLD"] = 0.0;
    for rep in range(3) {
        futs = [flow echo(t, p) for (t, p) in zip(ts, ps)];
        show(f"instant call, rep {rep}", [wait f for f in futs], want);
    }
}
