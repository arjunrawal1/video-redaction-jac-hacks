"""The upload affordance.

The control is real and the answer comes from the server, but the answer today
is a refusal: `request_ingest` has nothing behind it that turns a file into a
Frame chain. Showing the server's own words is the honest version of "not yet
connected" - when the endpoint starts accepting, this panel starts succeeding
without a change here.
"""

def:pub UploadPanel(
    filename: str,
    pending: bool,
    outcome: str,
    accepted: bool,
    onPick: Callable[[str], None],
    onSubmit: Callable[[], None]
) -> JsxElement {
    def handle_pick(e: ChangeEvent) {
        # A DOM FileList is a genuine untyped boundary: it is not a Jac list.
        files: any = e.target.files;
        name: str = "";
        if files {
            first: any = files[0];
            if first {
                name = str(first.name);
            }
        }
        onPick(name);
    }

    def handle_submit(e: FormEvent) {
        e.preventDefault();
        onSubmit();
    }

    return <form className="up" onSubmit={handle_submit}>
        <div className="up-head">
            <h2 className="up-title">Add a recording</h2>
            <span className="up-badge">pipeline not connected</span>
        </div>
        <p className="up-copy">
            Ingest, OCR and export all run in the graph today, but nothing yet
            carries an uploaded file into them. This control asks the server and
            reports exactly what it says.
        </p>
        <label className="up-drop">
            <input
                className="up-input"
                type="file"
                accept="video/*"
                onChange={handle_pick}
            />
            <span className="up-drop-glyph" aria-hidden="true"/>
            <span className="up-drop-text">
                {filename if filename else "Choose a screen recording"}
            </span>
            <span className="up-drop-hint">.mov / .mp4</span>
        </label>
        <button className="up-go" type="submit" disabled={pending or not filename}>
            {"Asking the server..." if pending else "Send to pipeline"}
        </button>
        {if outcome {
            <p className={"up-out up-out-" + ("ok" if accepted else "no")}>{outcome}</p>
        }}
    </form>;
}
