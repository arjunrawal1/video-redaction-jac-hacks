"""The redacted render, once one exists.

`Video.export_path` is a file on the server's disk; the read layer turns it into
a URL under /static/media so the browser can stream it. Empty until the export
pass has run for this video.
"""

def:pub ExportPanel(export_url: str, box_count: int) -> JsxElement {
    return <section className="panel">
        <header className="panel-head">
            <h2 className="panel-title">Redacted export</h2>
            {if export_url {
                <span className="panel-flag panel-flag-ok">ready</span>
            } else {
                <span className="panel-flag">not rendered</span>
            }}
        </header>

        {if export_url {
            <video className="exp-video" src={export_url} controls={True} preload="metadata"/>
            <p className="panel-note">
                Streamed from the file the export pass wrote. Boxes are burned in
                at pixel resolution; everything upstream stayed on the 0..1000
                scale.
            </p>
            <a className="exp-dl" href={export_url} download="redacted.mp4">Download mp4</a>
        } else {
            <div className="exp-empty">
                <div className="exp-empty-art" aria-hidden="true">
                    <span className="exp-empty-bar"/>
                    <span className="exp-empty-bar"/>
                    <span className="exp-empty-bar"/>
                </div>
                <p className="panel-empty">
                    No export for this video yet. The export pass walks the frame
                    chain, turns each frame's boxes into a time span, and burns
                    them into a copy of the source.
                </p>
                <p className="exp-hint">
                    {f"{box_count} boxes on the chain right now."}
                </p>
            </div>
        }}
    </section>;
}
