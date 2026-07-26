"""The redaction policy, as a subgraph.

A policy is not a JSON blob that some evaluator walks with a switch statement.
It is nodes and edges, and evaluating it is a walker whose abilities are
selected by the type of node it arrives at. Adding a new kind of condition is
one archetype and one ability -- there is no evaluator to extend, no union to
widen, no parser to teach.

Policies hang off `root`, so a policy is a durable, reusable thing: describe
it once and apply it to the next video.
"""

import hashlib;
import from ai { PredKind, PlanNode, PolicyPlan, plan_policy }

include graph;

"""Find a policy already planned for this request."""
def find_policy(request: str) -> Policy | None {
    digest = hashlib.sha256(request.strip().lower().encode()).hexdigest()[:16];
    matches = [root -->[?:Policy, hash == digest]];
    return matches[0] if matches else None;
}

"""Create the graph node matching one planned node's kind."""
def materialize(spec: PlanNode) -> PredNode {
    if spec.kind == PredKind.AND { return AndOp(); }
    if spec.kind == PredKind.OR { return OrOp(); }
    if spec.kind == PredKind.NOT { return NotOp(); }
    if spec.kind == PredKind.TEXT {
        return TextLeaf(text=spec.text, fuzzy=spec.fuzzy);
    }
    if spec.kind == PredKind.REGION {
        return RegionLeaf(
            description=spec.description, all_instances=spec.all_instances
        );
    }
    return SemanticLeaf(category=spec.category, description=spec.description);
}

"""Plan a redaction request into a policy subgraph hanging off root.

Re-asking for the same policy returns the existing one rather than paying for
another planning call.
"""
def:pub plan(request: str) -> Policy {
    existing = find_policy(request);
    if existing is not None {
        return existing;
    }

    result = plan_policy(request);
    digest = hashlib.sha256(request.strip().lower().encode()).hexdigest()[:16];
    pol = Policy(prompt=request, hash=digest);
    root ++> pol;

    # The model returns the tree flattened with parent indices, because a
    # recursive schema is not something structured output handles well. The
    # flattening is a wire format only; what lands on the graph is real typed
    # nodes with real edges.
    built: list[PredNode] = [];
    for spec in result.nodes {
        made = materialize(spec);
        built.append(made);
        if spec.parent < 0 or spec.parent >= len(built) - 1 {
            pol +>:Governs:+> made;
        } else {
            built[spec.parent] +>:Child:+> made;
        }
    }

    return pol;
}

"""One node of a policy, flattened with a parent link for rendering."""
obj PolicyRow {
    has id: str;
    has parent: str;
    has kind: str;
    has detail: str;
}

"""Read a policy subgraph back as rows a caller can render as a tree.

Rows carry an explicit parent id rather than an indent level. A walker's
traversal is queue-driven, so a shared depth counter would describe the order
nodes were reached rather than how they nest -- which looks plausible and is
wrong. The parent link comes from following the Child edge backwards, so the
shape reported is the shape stored.
"""
walker ReadPolicy {
    has rows: list[PolicyRow] = [];

    can on_policy with Policy entry {
        visit [here ->:Governs:->];
    }

    can on_and with AndOp entry {
        self.emit(here, "all of", "");
        visit [here ->:Child:->];
    }

    can on_or with OrOp entry {
        self.emit(here, "any of", "");
        visit [here ->:Child:->];
    }

    can on_not with NotOp entry {
        self.emit(here, "except", "");
        visit [here ->:Child:->];
    }

    can on_text with TextLeaf entry {
        self.emit(here, "text", here.text);
    }

    can on_region with RegionLeaf entry {
        self.emit(here, "region", here.description);
    }

    can on_semantic with SemanticLeaf entry {
        self.emit(here, "semantic", f"{here.category}: {here.description}");
    }

    def emit(at: PredNode, kind: str, detail: str) {
        up = [at <-:Child:<-];
        self.rows.append(
            PolicyRow(
                id=jid(at),
                parent=jid(up[0]) if up else "",
                kind=kind,
                detail=detail
            )
        );
    }
}
