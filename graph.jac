"""The redaction graph: every archetype the pipeline stores state in.

The graph is not a serialization of pipeline state, it *is* the pipeline state.
Everything hangs off `root`, so a video and all of its derived work survives
process restarts and can be replayed without recomputation.

Box geometry convention: coordinates are stored in box_2d order
[y_min, x_min, y_max, x_max] on a 0..1000 scale, normalized against the frame.
Conversion to pixels happens only at export. Nothing upstream of export should
ever see a pixel coordinate.
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

node Frame {
    has index: int;              # 1-based position among kept frames
    has source_index: int;       # 0-based index in the original decode order
    has timestamp: float = 0.0;  # seconds into the source video
    has width: int = 0;
    has height: int = 0;
    has jpeg_path: str = "";
    has ocr_done: bool = False;
}

node Word {
    has text: str;
    has y0: int;
    has x0: int;
    has y1: int;
    has x1: int;
    has conf: float = 0.0;
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
edge Seen     : Frame --> Word {}
edge Detected : Frame --> Box {}
edge MemberOf : Box --> Track {}       # identity of one redaction across frames
edge Adopted  : Box --> Word {}        # this box was grounded in this OCR word
edge AddedBy  : Box --> Agent {}       # provenance
edge SpawnedBy: Agent --> Agent {}     # cascade lineage
edge Governs  : Policy --> PredNode {}
edge Child    : PredNode --> PredNode {}
edge AppliedTo: Policy --> Video {}
