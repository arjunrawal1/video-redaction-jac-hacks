"""Runtime check: does a plain-English request become a real policy subgraph?

Renders each policy from the stored edges, so the printed shape is the shape
on the graph rather than the order a walker happened to reach nodes in.
"""

import time;
import from policy { plan, ReadPolicy, PolicyRow }

include graph;

def render(rows: list[PolicyRow], parent: str, depth: int) {
    for r in rows {
        if r.parent == parent {
            suffix = f" {r.detail}" if r.detail else "";
            print(f"{'  ' * (depth + 1)}{r.kind}{suffix}");
            render(rows, r.id, depth + 1);
        }
    }
}

with entry {
    requests = [
        "redact the contents of the spreadsheet cells",
        "hide every email address and phone number, but not the ones in the sidebar",
        "black out the browser address bar, and any full name that is not mine"
    ];

    for req in requests {
        pol = plan(req);
        rows = (ReadPolicy() spawn pol).rows;
        print("");
        print(f"  policy: {req}");
        render(rows, "", 0);
        orphans = [r for r in rows if r.parent == "" ];
        print(f"    (nodes: {len(rows)}, roots: {len(orphans)})");
    }

    print("");
    print(f"policies persisted on root: {len([root -->[?:Policy]])}");
    t0 = time.perf_counter();
    plan(requests[0]);
    print(f"replanning the first request took {(time.perf_counter() - t0) * 1000:.1f}ms");
}
