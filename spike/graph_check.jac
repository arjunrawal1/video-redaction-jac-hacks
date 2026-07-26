"""Runtime check for the graph model.

Verifies the three behaviours the pipeline leans on: bidirectional traversal
along Next edges, subtype dispatch on arrival, and persistence across runs.
Run twice; the second run should find the graph already there.
"""

include graph;

walker WalkForward {
    has seen: list[int] = [];

    can start with Video entry {
        visit [here ->:Contains:->[?:Frame, index == 1]];
    }

    can step with Frame entry {
        self.seen.append(here.index);
        visit [here ->:Next:->];
    }
}

walker WalkBackward {
    has seen: list[int] = [];

    can step with Frame entry {
        self.seen.append(here.index);
        visit [here <-:Next:<-];
    }
}

walker Describe {
    has lines: list[str] = [];

    can on_policy with Policy entry { visit [here ->:Governs:->]; }
    can on_and with AndOp entry { self.lines.append("AND"); visit [here ->:Child:->]; }
    can on_or with OrOp entry { self.lines.append("OR"); visit [here ->:Child:->]; }
    can on_text with TextLeaf entry { self.lines.append(f"text({here.text})"); }
    can on_semantic with SemanticLeaf entry { self.lines.append(f"semantic({here.category})"); }
}

with entry {
    videos = [root -->[?:Video]];

    if videos {
        print(f"found existing graph: {len(videos)} video(s) already persisted");
        vid = videos[0];
    } else {
        print("building a fresh graph");
        vid = Video(title="demo", video_hash="abc123", width=1600, height=1034);
        root ++> vid;

        built = [Frame(index=i, source_index=(i - 1) * 6, timestamp=(i - 1) * 0.1)
                 for i in range(1, 5)];
        for f in built {
            vid +>:Contains:+> f;
        }
        for i in range(1, len(built)) {
            built[i - 1] +>:Next:+> built[i];
        }

        pol = Policy(prompt="redact spreadsheet cell contents");
        root ++> pol;
        top = OrOp();
        pol +>:Governs:+> top;
        top +>:Child:+> TextLeaf(text="TEST WORD");
        top +>:Child:+> SemanticLeaf(category="user-typed-content");
    }

    frames = [vid ->:Contains:->];
    print(f"frames in graph: {len(frames)}");

    fwd = WalkForward() spawn vid;
    print(f"forward:  {fwd.seen}");

    last = [vid ->:Contains:->[?:Frame, index == len(frames)]][0];
    bwd = WalkBackward() spawn last;
    print(f"backward: {bwd.seen}");

    pol = [root -->[?:Policy]][0];
    d = Describe() spawn pol;
    print(f"policy:   {d.lines}");
}
