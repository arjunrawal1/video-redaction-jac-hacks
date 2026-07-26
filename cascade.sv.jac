"""Agents that carry a detection into the frames detection missed.

Judging a frame on its own cannot distinguish content that has left the screen
from content it failed to see; both are simply absent. An agent settles that by
walking the Next chain from a frame where the value was found into the frames
where it was not, checking each one against the value it is carrying. A value
the model confirms is gone is dropped; an agent with nothing left to follow
stops.

The walk is the algorithm. There is no queue to manage and no visited set to
maintain: the agent moves along an edge, the arrival ability runs, and the
graph records where it went. Every box an agent creates points back at it, so
any redaction in the finished video can name the agent that placed it and the
frame it came from.

An agent asks about all of its live targets in a single call per frame, which
is what keeps a full pass affordable.
"""

import from jaclang.byllm.lib { Image }
import from ai { track_targets, format_words }
import from detect { merge_picks }

include graph;

glob MIN_TRACK_CONFIDENCE: float = 0.5;

walker Cascade {
    """One agent, walking one direction until its targets are gone."""

    has agent: Agent;
    has targets: list[str];
    has why: str;
    has tracks: dict[str, Track];
    has forward: bool = True;
    has max_steps: int = 8;
    has steps: int = 0;
    has boxes_added: int = 0;
    has stopped_because: str = "";
    has trail: list[str] = [];

    can step with Frame entry {
        if not self.targets {
            self.finish("every value it was following had gone");
            disengage;
        }
        if self.steps >= self.max_steps {
            self.finish("reached its step limit");
            disengage;
        }
        if not here.words {
            self.finish(f"frame {here.index} has no text on it");
            disengage;
        }

        # Meeting a detection that is already there means another agent, or a
        # seed, has covered this ground. Walking on would duplicate its work.
        settled = {b.text for b in [here ->:Detected:->]};
        if settled and set(self.targets) <= settled {
            self.finish(f"frame {here.index} was already covered");
            disengage;
        }

        self.steps += 1;
        self.agent.focus = here.index;
        self.agent.steps = self.steps;

        listing = format_words([w.text for w in here.words]);
        # Targets are numbered for the same reason words are: a model echoing
        # a string back mangles it, but it can carry an integer faithfully.
        findings = track_targets(
            Image(here.jpeg_path),
            format_words(self.targets),
            self.why,
            listing
        );

        surviving: list[str] = [];
        placed = 0;
        for f in findings {
            if not (0 <= f.target < len(self.targets)) {
                continue;
            }
            name = self.targets[f.target];
            if name in surviving {
                continue;
            }

            gone = (not f.present) or (not f.indices)
                or f.confidence < MIN_TRACK_CONFIDENCE;
            if gone {
                continue;
            }

            valid = [i for i in f.indices if 0 <= i < len(here.words)];
            if not valid {
                continue;
            }

            surviving.append(name);
            for m in merge_picks(here.words, valid) {
                box = Box(
                    y0=m.y0, x0=m.x0, y1=m.y1, x1=m.x1,
                    text=name,
                    origin="cascade",
                    confidence=f.confidence,
                    reason=f.reason
                );
                here +>:Detected:+> box;
                box +>:AddedBy:+> self.agent;
                if name in self.tracks {
                    box +>:MemberOf:+> self.tracks[name];
                }
                placed += 1;
                self.boxes_added += 1;
            }
        }

        dropped = [t for t in self.targets if t not in surviving];
        self.targets = surviving;
        self.trail.append(
            f"frame {here.index}: kept {len(surviving)}, dropped {len(dropped)}, {placed} box(es)"
        );

        if not self.targets {
            self.finish(f"nothing left to follow after frame {here.index}");
            disengage;
        }

        if self.forward {
            visit [here ->:Next:->] else {
                self.finish("reached the end of the video");
            }
        } else {
            visit [here <-:Next:<-] else {
                self.finish("reached the start of the video");
            }
        }
    }

    def finish(reason: str) {
        self.stopped_because = reason;
        self.agent.reason = reason;
        self.agent.still_visible = len(self.targets) > 0;
        # `focus` moves with the agent, so the seed has to come from the field
        # that does not: otherwise a finished agent reports launching from
        # wherever it happened to stop.
        self.agent.summary = (
            f"{self.agent.direction} from frame {self.agent.seed_index}: "
            f"{self.boxes_added} box(es) over {self.steps} step(s), stopped because {reason}"
        );
    }
}

walker SeedCascades {
    """Send an agent wherever a detected value stops being detected.

    Every frame is put to the model, so most of the video is covered before an
    agent moves at all. What detection cannot do is tell a value that left the
    screen apart from one it simply failed to see: both look like absence on a
    single frame. Only the frames on either side answer that.

    So an agent launches at a boundary -- a frame holding a value its neighbour
    does not -- and walks into the gap carrying just the values that went
    missing there. It writes a box wherever the value is still visible and
    stops when the model says it is genuinely gone, or when it reaches ground
    already covered. Frames where detection agreed with itself never need one,
    which is why the number of agents is a reading of how much detection
    missed.
    """

    has why: str = "matched the redaction policy";
    has max_steps: int = 8;
    has agents: list[Agent] = [];
    has boxes_added: int = 0;
    has tracks: dict[str, Track] = {};
    has video: Video | None = None;

    can start with Video entry {
        self.video = here;
        frames = sorted(
            [here ->:Contains:->[?:Frame]], key=lambda (f: Frame) { f.index; }
        );

        # Detection has to be read whole before any agent moves: a boundary is
        # a fact about two frames, and an agent that started earlier would be
        # writing boxes into the very map being read.
        found: dict[int, set[str]] = {};
        for f in frames {
            seeded = [b for b in [f ->:Detected:->[?:Box]] if b.origin == "seed"];
            for b in seeded {
                self.enrol(b);
            }
            found[f.index] = {b.text for b in seeded};
        }

        order = [f.index for f in frames];
        for (pos, f) in enumerate(frames) {
            mine = found[f.index];
            if not mine {
                continue;
            }
            if pos + 1 < len(order) {
                gap = sorted(mine - found[order[pos + 1]]);
                if gap {
                    self.launch(f, gap, True);
                }
            }
            if pos > 0 {
                gap = sorted(mine - found[order[pos - 1]]);
                if gap {
                    self.launch(f, gap, False);
                }
            }
        }
    }

    """Give a detected value its track, so every box for it is one thing."""
    def enrol(b: Box) {
        if b.text not in self.tracks {
            fresh = Track(label=b.text);
            root ++> fresh;
            self.tracks[b.text] = fresh;
        }
        b +>:MemberOf:+> self.tracks[b.text];
    }

    def launch(at: Frame, targets: list[str], ahead: bool) {
        name = "forward" if ahead else "backward";
        agent = Agent(
            agent_id=f"{name}-{at.index}",
            direction=name,
            seed_index=at.index,
            focus=at.index
        );
        root ++> agent;
        # An agent that places no boxes has no frames to be found through, so
        # the video claims it directly.
        if self.video is not None {
            self.video +>:Ran:+> agent;
        }
        self.agents.append(agent);

        run = Cascade(
            agent=agent,
            targets=list(targets),
            why=self.why,
            tracks=self.tracks,
            forward=ahead,
            max_steps=self.max_steps
        );

        neighbours = [at ->:Next:->] if ahead else [at <-:Next:<-];
        if neighbours {
            run spawn neighbours[0];
            self.boxes_added += run.boxes_added;
        } else {
            agent.summary = f"{name} from frame {at.index}: no frame that way";
        }
    }
}
