"""video-redaction-jac-hacks - Entry Point.

Every endpoint the client calls is named in the import below: registration
tracks the exact name, so an endpoint missing from this list 405s no matter
what the client imports.
"""

import from library {
    BoxView, WordView, FrameView, FrameWords, VideoView, VideoDetail,
    AgentStop, AgentView, TrackStop, TrackView, FrameMark, CascadeView,
    BoxProvenance,
    list_videos, get_video, get_frame_words, get_cascade, get_frame_provenance
}
import from endpoints {
    IngestOutcome, CascadeSeed, CascadeWipe,
    request_ingest, seed_from_path, seed_demo_cascade, clear_demo_cascade,
    clear_video_boxes
}
# The two streams are read with a raw fetch to get the frames as they arrive,
# so no generated stub mentions them and only this import registers the routes.
import from pipeline {
    RunRecord, run_pipeline, replay_pipeline, get_run_record, record_run,
    refresh_counts
}

cl {
    import "./assets/theme.css";
    import from .frontend { app as RedactionApp }

    def:pub app -> JsxElement {
        return <RedactionApp/>;
    }
}
