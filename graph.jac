"""The redaction graph: every archetype the pipeline stores state in.

The graph is not a serialization of pipeline state, it *is* the pipeline state.
Everything hangs off `root`, so a video and all of its derived work survives
process restarts and can be replayed without recomputation.

Box geometry convention: coordinates are stored in box_2d order
[y_min, x_min, y_max, x_max] on a 0..1000 scale, normalized against the frame.
Conversion to pixels happens only at export. Nothing upstream of export should
ever see a pixel coordinate.

Do not move this file. Archetype identity includes the module path, so
relocating it orphans every already-persisted node with no error at either
compile or query time.

What is a node and what is a field: every graph write costs time proportional
to the total size of the graph, so bulk data must not become nodes. Raw OCR
output is tens of thousands of words per video and lives inline on the frame
that produced it. Nodes are reserved for things the pipeline reasons about and
traverses between: frames, redactions, tracks, agents, policy. Measured, that
is the difference between a six-minute OCR pass and a thirty-second one.
"""

# ---------------------------------------------------------------- media

node Video {
    has title: str;
    has video_hash: str;
    has source_fps: float = 0.0;
    has width: int = 0;
    has height: int = 0;
    has duration: float = 0.0;
    has source_path: str = "";
    has export_path: str = "";
}

"""One word Textract found, in box_2d order on the 0..1000 scale."""
obj WordBox {
    has text: str;
    has y0: int;
    has x0: int;
    has y1: int;
    has x1: int;
    has conf: float = 0.0;
}

node Frame {
    has index: int;              # 1-based position among kept frames
    has source_index: int;       # 0-based index in the original decode order
    has timestamp: float = 0.0;  # seconds into the source video
    has width: int = 0;
    has height: int = 0;
    has jpeg_path: str = "";
    has ocr_done: bool = False;
    has words: list[WordBox] = [];
}

# ---------------------------------------------------------------- redaction

node Box {
    has y0: int;
    has x0: int;
    has y1: int;
    has x1: int;
    has text: str = "";
    has origin: str = "curator";   # curator | cascade | gap-fill
    has confidence: float = 1.0;
    has reason: str = "";
}

node Track {
    has label: str;
}

node Agent {
    has agent_id: str;
    has direction: str;            # forward | backward
    has seed_index: int = 0;       # frame it launched from, fixed for life
    has focus: int = 0;            # frame index this agent is inspecting
    has summary: str = "";
    has still_visible: bool = True;
    has reason: str = "";
    has steps: int = 0;
}

# ---------------------------------------------------------------- policy

"""Base type for every policy node.

Deliberately field-free: subtypes declare required fields, and a defaulted
field here would make that impossible.
"""
node PredNode {}

node AndOp(PredNode) {}
node OrOp(PredNode) {}
node NotOp(PredNode) {}

node TextLeaf(PredNode) {
    has text: str;
    has fuzzy: bool = True;
}

node RegionLeaf(PredNode) {
    has description: str;
    has all_instances: bool = False;
}

node SemanticLeaf(PredNode) {
    has category: str;
    has description: str = "";
}

node Policy {
    has prompt: str;
    has hash: str = "";
}

# ---------------------------------------------------------------- edges

edge Contains : Video --> Frame {}
edge Next     : Frame --> Frame {}     # the road the cascade walks
edge Detected : Frame --> Box {}
edge MemberOf : Box --> Track {}       # identity of one redaction across frames
edge AddedBy  : Box --> Agent {}       # provenance
edge SpawnedBy: Agent --> Agent {}     # cascade lineage
edge Ran      : Video --> Agent {}     # an agent belongs to its video even
                                       # when it placed nothing
edge Governs  : Policy --> PredNode {}
edge Child    : PredNode --> PredNode {}
edge AppliedTo: Policy --> Video {}
