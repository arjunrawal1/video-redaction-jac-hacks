"""Handler bodies for the library page."""

impl LibraryPage.loadLibrary -> None {
    try {
        videos = await list_videos();
        load_error = "";
    } except Exception as e {
        load_error = "Could not read the library: " + str(e);
    }
    loading = False;
}

impl LibraryPage.submitIngest -> None {
    if not pick {
        return;
    }
    ingest_pending = True;
    result = await request_ingest(pick);
    ingest_pending = False;
    if result is not None {
        ingest_accepted = result.accepted;
        ingest_message = result.message;
        ingest_video_id = result.video_id;
        if result.accepted {
            videos = await list_videos();
        }
    } else {
        ingest_accepted = False;
        ingest_message = "The server did not answer the ingest request.";
    }
}
