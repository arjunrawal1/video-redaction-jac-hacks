"""Reading text off every frame.

The walk itself is trivial - follow Next to the end of the chain - but it is
where the pipeline stops being sequential. Textract calls block, so frames are
collected during the walk and fanned out in batches once it finishes.

Words are written inline on the frame rather than as nodes. A video yields
tens of thousands of them, and graph writes cost time proportional to the
whole graph, so promoting raw OCR to nodes makes the pass quadratic.

Frames remember that they have been read, so a second run over the same video
does no network work at all.
"""

import os;
import from medialib.ocr { detect_words }

include graph;

"""Launch one Textract call on the pool.

`flow` compiles to a lambda taking no arguments, so a `flow` written directly
inside a loop re-reads the loop variable on the worker and every task in the
batch ends up reading the last frame. Going through a call gives each launch
its own frame, and `path` cannot be reassigned underneath it. See AGENTS.md.
"""
def launch_ocr(path: str) -> object {
    return flow detect_words(path);
}

walker ReadText {
    """Attach a Word node per token Textract finds, for every unread frame."""

    # Textract's synchronous API takes far more concurrency than one video
    # needs, so the batch is sized to keep the pass short rather than to stay
    # clear of a limit. Overridable for the same reason it is not larger
    # still: the ceiling is the account's, not this code's.
    has batch_size: int = int(os.getenv("REDACTION_OCR_BATCH", "32"));
    has pending: list[Frame] = [];
    has frames_read: int = 0;
    has words_added: int = 0;

    can start with Video entry {
        visit [here ->:Contains:->[?:Frame, index == 1]];
    }

    can collect with Frame entry {
        if not here.ocr_done {
            self.pending.append(here);
        }
        visit [here ->:Next:->];
    }

    can run_ocr with Video exit {
        start = 0;
        while start < len(self.pending) {
            chunk = self.pending[start:start + self.batch_size];

            # Read the paths here, on the walker's own thread: a worker that
            # touches the graph reads another thread's data.
            paths = [fr.jpeg_path for fr in chunk];

            # Launch the whole batch before waiting on any of it; a wait
            # inside the launch loop would serialize the calls.
            futures = [launch_ocr(p) for p in paths];
            batch = [wait fut for fut in futures];

            for (fr, words) in zip(chunk, batch) {
                fr.words = [
                    WordBox(text=w.text, y0=w.y0, x0=w.x0, y1=w.y1, x1=w.x1, conf=w.conf)
                    for w in words
                ];
                fr.ocr_done = True;
                self.frames_read += 1;
                self.words_added += len(words);
            }

            start += self.batch_size;
        }
    }
}
