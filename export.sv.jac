"""Turning the graph back into a video, with every Box burned in.

The mirror image of ingest: that pass walked a file into a Frame chain, this
one walks the chain back out to a file. It is the only consumer of `Box`
geometry, and the last point at which the 0..1000 box_2d coordinates the rest
of the pipeline speaks are still abstract.

Timing comes from the chain, not from the frame rate. Frames were
deduplicated, so a kept frame is not an instant, it is a claim about a window:
its boxes hold until the next kept frame's timestamp, and the last frame's
hold until the end of the video. Reading a frame as an instant would leave
every redaction flickering for one frame and exposed for the rest.
"""

import os;
import hashlib;
import from medialib.export { BoxSpan, export_redacted }

include graph;

glob EXPORT_ROOT: str = "media/exports";

walker RenderRedacted {
    """Write a redacted copy of the source video and record it on the Video."""

    has frames: list[Frame] = [];
    has spans: list[BoxSpan] = [];
    has output_path: str = "";
    has reused: bool = False;
    has reports: list[str] = [];

    can start with Video entry {
        visit [here ->:Contains:->[?:Frame, index == 1]];
    }

    can collect with Frame entry {
        # The Next chain is linear, so arrival order is timeline order and the
        # neighbour that ends this frame's window is simply the next element.
        self.frames.append(here);
        visit [here ->:Next:->];
    }

    can render with Video exit {
        for (i, fr) in enumerate(self.frames) {
            t_end = self.frames[i + 1].timestamp
                if i + 1 < len(self.frames)
                else here.duration;
            if t_end <= fr.timestamp {
                continue;
            }
            for b in [fr ->:Detected:->[?:Box]] {
                self.spans.append(
                    BoxSpan(
                        y0=b.y0, x0=b.x0, y1=b.y1, x1=b.x1,
                        t_start=fr.timestamp, t_end=t_end
                    )
                );
            }
        }

        # The rendered file is a pure function of these spans, so naming it
        # after them makes reuse exact. Keying on the video alone would serve
        # yesterday's redactions after the agents changed their minds, which
        # is the one failure here nobody would notice by looking.
        out = os.path.join(EXPORT_ROOT, f"{here.video_hash}-{self.signature()}.mp4");
        if os.path.exists(out) {
            self.reused = True;
        } else {
            export_redacted(here.source_path, out, self.spans);
        }

        here.export_path = out;
        self.output_path = out;
        report out;
    }

    """Fingerprint the exact set of redactions this export would burn in."""
    def signature -> str {
        parts = sorted([
            f"{s.y0},{s.x0},{s.y1},{s.x1}@{s.t_start:.3f}-{s.t_end:.3f}"
            for s in self.spans
        ]);
        digest = hashlib.sha256("|".join(parts).encode()).hexdigest();
        return f"{len(self.spans):04d}-{digest[:12]}";
    }
}
