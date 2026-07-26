"""Write side of the API: getting a new video into the graph.

Only one of these is real. `request_ingest` is the endpoint the upload control
in the UI calls, and it deliberately refuses: nothing behind it turns an
uploaded file into a Frame chain yet, and a control that reported success would
be lying about a pipeline that never ran. The refusal is server-authoritative
so that wiring ingest up is a change here, not in the client.

`seed_from_path` is the dev hook that fills the graph from a video already on
this machine. It exists because reads run against the *calling user's* root, so
data ingested by a `jac run` script lands somewhere the served app cannot see;
seeding over HTTP puts the video on the same root the UI reads from.

Importing the pipeline passes at module level is deliberate: an import inside
an endpoint body resolves against a different path at request time and fails
with `No module named 'medialib'`, and importing medialib is also what loads
`.env`, so the credentials OCR needs are only there on this route.
"""

import os;
import from ingest { ingest_video }
import from ocr { ReadText }

include graph;

"""What the UI shows after asking the server to take a video."""
obj IngestOutcome {
    has accepted: bool,
        message: str,
        video_id: str;
}

"""Refuse an upload, in the words the UI should show.

Replace the body with the real ingest when the upload path exists; the client
already renders whatever this returns.
"""
def:pub request_ingest(filename: str) -> IngestOutcome {
    return IngestOutcome(
        accepted=False,
        message=(
            f"'{filename}' was not processed. Upload is not connected yet: the "
            "ingest, OCR and export passes all run today, but nothing carries an "
            "uploaded file into them, so this control refuses rather than report "
            "a run that never happened."
        ),
        video_id=""
    );
}

"""Ingest a video already on the server's disk and OCR it. Dev seeding only."""
def:pub seed_from_path(source_path: str, fps: float = 8.0) -> IngestOutcome {
    if not os.path.exists(source_path) {
        return IngestOutcome(
            accepted=False, message=f"no such file: {source_path}", video_id=""
        );
    }
    vid = ingest_video(source_path, fps=fps);
    run = ReadText() spawn vid;
    frames = [vid ->:Contains:->[?:Frame]];
    return IngestOutcome(
        accepted=True,
        message=(
            f"{len(frames)} frames, {run.frames_read} newly read, "
            f"{run.words_added} words"
        ),
        video_id=jid(vid)
    );
}
