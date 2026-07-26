"""The upload affordance.

A browser hands over a file's name, not its path, so the server looks for that
name where recordings live rather than receiving bytes. A recording it already
holds is returned as-is; one it cannot find is refused in its own words. Either
way the answer shown here is the server's, so this panel needs no change when
the search widens.
"""

import from "@jac/runtime" { Link }

def:pub UploadPanel(
    filename: str,
    pending: bool,
    outcome: str,
    accepted: bool,
    open_to: str,
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
        </div>
        <p className="up-copy">
            Pick a screen recording. It is decoded into a deduplicated frame
            chain and read for text before you say what to cover.
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
            {"Reading the video..." if pending else "Ingest"}
        </button>
        {if outcome {
            <p className={"up-out up-out-" + ("ok" if accepted else "no")}>{outcome}</p>
        }}
        {if accepted and open_to {
            <Link className="up-open" to={open_to}>Open it and choose what to redact</Link>
        }}
    </form>;
}
