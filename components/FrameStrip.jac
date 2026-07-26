"""The timeline: a tick per frame, plus a filmstrip window around the current one.

A chain is 51 frames today and thousands later, so the two halves scale
differently on purpose. The tick bar is one link-sized element per frame - the
whole chain always visible, and cheap enough to stay that way. The filmstrip
below it only mounts images for frames near the cursor; everything outside that
window is never requested, so moving through a long video costs a handful of
JPEGs rather than the whole chain.
"""

import from "@jac/runtime" { Link }
import from .overlay_geometry { clock }

sv import from ..library { FrameView }

glob STRIP_RADIUS: int = 6;

def:pub FrameStrip(
    frames: list[FrameView],
    video_id: str,
    current_index: int
) -> JsxElement {
    total = len(frames);
    lo = max(1, min(current_index - STRIP_RADIUS, total - (STRIP_RADIUS * 2)));
    hi = min(total, lo + (STRIP_RADIUS * 2));
    window = [f for f in frames if f.index >= lo and f.index <= hi];

    return <section className="strip">
        <div className="strip-head">
            <h2 className="strip-title">Frame chain</h2>
            <span className="strip-meta">
                {f"{total} frames · Next-linked · showing {lo}-{hi}"}
            </span>
        </div>

        <div className="strip-ticks">
            {for f in frames {
                <Link
                    key={"tick" + f.id}
                    to={f"/video/{video_id}/frame/{f.index}"}
                    title={f"frame {f.index} · {clock(f.timestamp)}"}
                    className={
                        "tick tick-on"
                        if f.index == current_index
                        else ("tick tick-boxed" if len(f.boxes) > 0 else "tick")
                    }
                />
            }}
        </div>

        <div className="strip-rail">
            {for f in window {
                <Link
                    key={f.id}
                    to={f"/video/{video_id}/frame/{f.index}"}
                    className={
                        "tile tile-on" if f.index == current_index else "tile"
                    }
                >
                    <span className="tile-shot">
                        <img
                            className="tile-img"
                            src={f.image_url}
                            alt={f"frame {f.index}"}
                            loading="lazy"
                        />
                        {if len(f.boxes) > 0 {
                            <span className="tile-boxes">{str(len(f.boxes))}</span>
                        }}
                    </span>
                    <span className="tile-foot">
                        <span className="tile-n">{"#" + str(f.index)}</span>
                        <span className="tile-t">{clock(f.timestamp)}</span>
                    </span>
                </Link>
            }}
        </div>
    </section>;
}
