"""What the graph holds about the selected frame."""

import from .MetaChip { MetaChip }
import from .overlay_geometry { clock }

sv import from ..library { FrameView, WordView }

def:pub FramePanel(
    frame: FrameView,
    words: list[WordView],
    show_words: bool
) -> JsxElement {
    return <section className="panel">
        <header className="panel-head">
            <h2 className="panel-title">Frame {str(frame.index)}</h2>
            <span className="panel-sub">{clock(frame.timestamp)}</span>
        </header>

        <div className="panel-chips">
            <MetaChip label="source" value={"#" + str(frame.source_index)}/>
            <MetaChip label="size" value={f"{frame.width}x{frame.height}"}/>
            <MetaChip
                label="ocr"
                value={"done" if frame.ocr_done else "pending"}
                tone={"success" if frame.ocr_done else "muted"}
            />
            <MetaChip label="words" value={str(frame.word_count)} tone="accent"/>
        </div>

        <div className="panel-block">
            <h3 className="panel-h3">
                Redactions
                <span className="panel-count">{str(len(frame.boxes))}</span>
            </h3>
            {if len(frame.boxes) == 0 {
                <p className="panel-empty">
                    No Box nodes on this frame. Detection has not run yet - when
                    it writes boxes through the Detected edge they appear here and
                    on the frame, using the same geometry the word overlay is
                    drawn with.
                </p>
            } else {
                <ul className="boxlist">
                    {for b in frame.boxes {
                        <li className="boxrow" key={b.id}>
                            <div className="boxrow-top">
                                <span className="boxrow-text">
                                    {b.text or "(region)"}
                                </span>
                                <span className={"boxrow-origin origin-" + b.origin}>
                                    {b.origin}
                                </span>
                            </div>
                            <div className="boxrow-geo">
                                {f"[{b.y0}, {b.x0}, {b.y1}, {b.x1}]"}
                                <span className="boxrow-conf">
                                    {f"{b.confidence:.2f}"}
                                </span>
                            </div>
                            {if b.reason {
                                <p className="boxrow-why">{b.reason}</p>
                            }}
                        </li>
                    }}
                </ul>
            }}
        </div>

        {if show_words {
            <div className="panel-block">
                <h3 className="panel-h3">
                    OCR words
                    <span className="panel-count">{str(len(words))}</span>
                </h3>
                <p className="panel-note">
                    Debug overlay: these are the words Textract read, drawn with
                    the same percentage math the redaction boxes use.
                </p>
                <ul className="wordlist">
                    {for (i, w) in enumerate(words[:14]) {
                        <li className="wordrow" key={"wr" + str(i)}>
                            <span className="wordrow-text">{w.text}</span>
                            <span className="wordrow-geo">
                                {f"[{w.y0}, {w.x0}, {w.y1}, {w.x1}]"}
                            </span>
                        </li>
                    }}
                </ul>
                {if len(words) > 14 {
                    <p className="panel-more">{f"+{len(words) - 14} more"}</p>
                }}
            </div>
        }}
    </section>;
}
