"""Every decision in this pipeline that a model makes.

Kept in one module on purpose: the prompts are the tuning surface, and having
them in one file makes it obvious what the system is actually asking for. The
graph schema lives in `graph.jac` and evolves independently -- models fill
`obj` values here, and the walkers copy those onto nodes.

A note on geometry: the model is never asked where a box goes. It picks which
OCR words are sensitive, and the coordinates come from Textract. Models are
good at judgement and bad at pixels.
"""

import os;
import medialib;
import from jaclang.byllm.lib { Model, Image }

glob llm: Model = Model(
    model_name=os.getenv("REDACTION_MODEL", "vertex_ai/gemini-2.5-flash")
);

# ------------------------------------------------------------- policy

enum PredKind { AND, OR, NOT, TEXT, REGION, SEMANTIC }

sem PredKind.AND = "Every child must match.";
sem PredKind.OR = "At least one child must match.";
sem PredKind.NOT = "Inverts its single child.";
sem PredKind.TEXT = "Matches a specific literal string the user named.";
sem PredKind.REGION = "Matches text by where it sits on screen.";
sem PredKind.SEMANTIC = "Matches text by what it means, judged per frame.";

"""One node of a redaction policy, flattened so it can be returned as a list."""
obj PlanNode {
    has kind: PredKind;
    has parent: int;
    has text: str = "";
    has description: str = "";
    has category: str = "";
    has all_instances: bool = False;
    has fuzzy: bool = True;
}

sem PlanNode.kind = "What this node does.";
sem PlanNode.parent = "Index of this node's parent in the list, or -1 if it is the root. A node must always appear after its parent.";
sem PlanNode.text = "For TEXT only: the exact literal string to match.";
sem PlanNode.description = "For REGION: where on screen, e.g. 'the browser address bar'. For SEMANTIC: what to look for, e.g. 'a person's full name'.";
sem PlanNode.category = "For SEMANTIC only: a short lowercase-hyphenated label, e.g. 'email-address'.";
sem PlanNode.all_instances = "For REGION only: true when every match in the region should be redacted.";
sem PlanNode.fuzzy = "For TEXT only: true to tolerate small OCR errors.";

obj PolicyPlan {
    has summary: str;
    has nodes: list[PlanNode];
}

sem PolicyPlan.summary = "One sentence restating, in plain language, what will be redacted.";
sem PolicyPlan.nodes = "The policy as a flat list. Element 0 is the root and must have parent -1. Every other element points at an earlier element.";

def plan_policy(request: str) -> PolicyPlan by llm();
sem plan_policy = """Turn a redaction request into a policy tree.

Return the tree flattened into a list, parents before children. Use the
simplest structure that captures the request: a single leaf is a fine answer
and is preferred over an unnecessary OR with one child. Reach for AND/OR/NOT
only when the request genuinely combines or excludes conditions.

Choose leaf kinds by how the request identifies its target. If it names an
exact string, that is TEXT. If it points at a place on screen, that is REGION.
If it describes a category of meaning, that is SEMANTIC.""";
sem plan_policy.request = "What the user wants redacted, in their own words.";

# ------------------------------------------------------------- detection

"""A word the model believes should be redacted, identified by OCR index."""
obj WordPick {
    has index: int;
    has reason: str;
    has confidence: float;
}

sem WordPick.index = "The number shown beside the word in the supplied list.";
sem WordPick.reason = "Why this word matches the policy, in one short clause.";
sem WordPick.confidence = "Between 0.0 and 1.0. Use below 0.5 when genuinely unsure.";

def pick_sensitive(shot: Image, policy: str, words: str) -> list[WordPick] by llm();
sem pick_sensitive = """Decide which of a frame's OCR words the policy requires redacting.

The image shows what the user saw; the list gives the exact words OCR read
from it, each with an index. Judge with the image for context and answer only
with indices from the list.

Select every word that must be covered, including each word of a multi-word
value. Return an empty list when the frame contains nothing matching. Do not
select chrome the user did not ask about -- menus, toolbars, tab titles, and
application labels are not sensitive unless the policy says so.""";
sem pick_sensitive.shot = "The frame being examined.";
sem pick_sensitive.policy = "What must be redacted.";
sem pick_sensitive.words = "The frame's OCR words, one per line as 'index: text'.";

# ------------------------------------------------------------- cascade

"""One cascade agent's verdict about the frame it just stepped onto."""
obj TrackStep {
    has still_present: bool;
    has indices: list[int];
    has reason: str;
    has confidence: float;
}

sem TrackStep.still_present = "True if the tracked content is visible in this frame at all.";
sem TrackStep.indices = "Indices of the OCR words covering it now. Empty when it is gone.";
sem TrackStep.reason = "One short clause explaining the verdict.";
sem TrackStep.confidence = "Between 0.0 and 1.0.";

def track_across_frame(shot: Image, target: str, why: str, words: str) -> TrackStep by llm();
sem track_across_frame = """Follow one piece of sensitive content into an adjacent frame.

It was redacted in the neighbouring frame and you are checking whether it is
still on screen here. It may have moved, scrolled, been partly covered, or be
gone entirely.

Report it present only when you can actually see it, and give the OCR indices
covering it now -- they may differ from last frame. If it has left the screen,
say so plainly; a cascade that refuses to stop wastes work and over-redacts.""";
sem track_across_frame.shot = "The frame now being examined.";
sem track_across_frame.target = "The exact text being followed.";
sem track_across_frame.why = "Why it was considered sensitive.";
sem track_across_frame.words = "This frame's OCR words, one per line as 'index: text'.";

# ------------------------------------------------------------- helpers

"""Render OCR words as the indexed list the prompts above expect."""
def format_words(texts: list[str]) -> str {
    return "\n".join([f"{i}: {t}" for (i, t) in enumerate(texts)]);
}
