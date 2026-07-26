"""video-redaction-jac-hacks - Entry Point.

Every endpoint the client calls is named in the import below: registration
tracks the exact name, so an endpoint missing from this list 405s no matter
what the client imports.
"""

import from library {
    BoxView, WordView, FrameView, FrameWords, VideoView, VideoDetail,
    list_videos, get_video, get_frame_words
}
import from endpoints { IngestOutcome, request_ingest, seed_from_path }

cl {
    import "./assets/theme.css";
    import from .frontend { app as RedactionApp }

    def:pub app -> JsxElement {
        return <RedactionApp/>;
    }
}
