"""Handler bodies for the studio shell."""

impl StudioPage.loadVideo(vid: str) -> None {
    if not vid {
        return;
    }
    try {
        found = await get_video(vid);
        detail = found;
        load_error = "" if found is not None else "No video with that id.";
    } except Exception as e {
        load_error = "Could not read that video: " + str(e);
    }
    loading = False;
}

impl StudioPage.syncWords(fid: str) -> None {
    # The debug overlay is the only reader of the bulk word list, so it is
    # fetched per frame and only once that overlay is on.
    if not show_words or not fid or words_frame == fid {
        return;
    }
    words_loading = True;
    result = await get_frame_words(fid);
    words = result.words if result is not None else [];
    words_frame = fid;
    words_loading = False;
}
