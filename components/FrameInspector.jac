"""The frame under the microscope, with rectangles drawn over it.

Both overlays - redaction boxes and the debug OCR words - are the same
percentage geometry from `rect_style`, so what lands on the words is proof of
what will land on the boxes.
"""

import from "@jac/runtime" { Link }
import from .overlay_geometry { rect_style, clock }

sv import from ..library { FrameView, WordView }

def:pub FrameInspector(
    frame: FrameView,
    words: list[WordView],
    show_boxes: bool,
    show_words: bool,
    words_loading: bool,
    prev_to: str,
    next_to: str,
    has_prev: bool,
    has_next: bool,
    onToggleBoxes: Callable[[], None],
    onToggleWords: Callable[[], None]
) -> JsxElement {
    return <section className="insp">
        <div className="insp-bar">
            <div className="insp-nav">
                {if has_prev {
                    <Link className="navb" to={prev_to} title="previous frame">
                        {"<"}
                    </Link>
                } else {
                    <span className="navb navb-off">{"<"}</span>
                }}
                <span className="insp-pos">
                    <span className="insp-pos-n">{"#" + str(frame.index)}</span>
                    <span className="insp-pos-t">{clock(frame.timestamp)}</span>
                </span>
                {if has_next {
                    <Link className="navb" to={next_to} title="next frame">
                        {">"}
                    </Link>
                } else {
                    <span className="navb navb-off">{">"}</span>
                }}
            </div>

            <div className="insp-toggles">
                <button
                    type="button"
                    className={"tgl tgl-box" + (" tgl-on" if show_boxes else "")}
                    onClick={lambda (e: MouseEvent) { onToggleBoxes(); }}
                >
                    <span className="tgl-swatch tgl-swatch-box"/>
                    {f"redactions ({len(frame.boxes)})"}
                </button>
                <button
                    type="button"
                    className={"tgl tgl-word" + (" tgl-on" if show_words else "")}
                    onClick={lambda (e: MouseEvent) { onToggleWords(); }}
                >
                    <span className="tgl-swatch tgl-swatch-word"/>
                    {f"ocr words ({frame.word_count})"}
                </button>
            </div>
        </div>

        <div className="insp-stage">
            <div className="insp-frame">
                <img
                    className="insp-img"
                    src={frame.image_url}
                    alt={f"frame {frame.index}"}
                />
                {if show_words {
                    for (i, w) in enumerate(words) {
                        <span
                            key={"w" + str(i)}
                            className="ov ov-word"
                            style={rect_style(w.y0, w.x0, w.y1, w.x1)}
                            title={f"{w.text} [{w.y0},{w.x0},{w.y1},{w.x1}]"}
                        />
                    }
                }}
                {if show_boxes {
                    for b in frame.boxes {
                        <span
                            key={b.id}
                            className="ov ov-box"
                            style={rect_style(b.y0, b.x0, b.y1, b.x1)}
                            title={f"{b.origin}: {b.reason}"}
                        >
                            <span className="ov-tag">{b.text or b.origin}</span>
                        </span>
                    }
                }}
            </div>
        </div>

        <div className="insp-foot">
            <span className="insp-foot-l">
                {f"{frame.width}x{frame.height} px · geometry is box_2d [y0,x0,y1,x1] on 0..1000"}
            </span>
            {if show_words {
                <span className="insp-foot-r">
                    {"loading words..." if words_loading else f"{len(words)} word boxes drawn"}
                </span>
            }}
        </div>
    </section>;
}
