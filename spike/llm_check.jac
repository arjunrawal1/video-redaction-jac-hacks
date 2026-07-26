"""Preflight check for the model layer.

Run this before a demo to confirm credentials, structured output, and vision
all work: `jac run spike/llm_check.jac`. Expects media/testframe.jpg to exist.
"""

import os;
import medialib;
import from jaclang.byllm.lib { Model, Image }

glob llm: Model = Model(
    model_name=os.getenv("REDACTION_MODEL", "vertex_ai/gemini-2.5-flash")
);

obj Finding {
    has text: str;
    has reason: str;
    has confidence: float;
}

sem Finding.text = "The exact on-screen text of the candidate.";
sem Finding.reason = "Why this text matches the policy, in one short clause.";
sem Finding.confidence = "Confidence between 0.0 and 1.0.";

def find_candidates(shot: Image, policy: str) -> list[Finding] by llm();
sem find_candidates = """Inspect the screenshot and list every piece of visible
text that matches the redaction policy. Return an empty list if nothing matches.""";
sem find_candidates.shot = "A single frame from a screen recording.";
sem find_candidates.policy = "A natural-language description of what must be redacted.";

with entry {
    shot = "media/testframe.jpg";
    if not os.path.exists(shot) {
        print(f"missing {shot}; extract a frame first");
    } else {
        found = find_candidates(
            Image(shot),
            "any cell contents typed by the user into the spreadsheet grid"
        );
        print(f"vision + structured output ok: {len(found)} candidates");
        for f in found {
            print(f"  - {f.text!r} ({f.confidence:.2f}) {f.reason}");
        }
    }
}
