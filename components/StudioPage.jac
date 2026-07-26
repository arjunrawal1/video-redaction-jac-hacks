"""One video: its frame chain, the frame under inspection, and what came out.

The selected frame lives in the URL rather than in state, so every frame is a
link, a bookmark and a back-button step. Everything else the page needs is
`has` state on this shell; the sections below are stateless.
"""

import from "@jac/runtime" { Link, useParams }
import from .AppHeader { AppHeader }
import from .CascadePanel { CascadePanel }
import from .ExportPanel { ExportPanel }
import from .FrameInspector { FrameInspector }
import from .FramePanel { FramePanel }
import from .FrameStrip { FrameStrip }
import from .MetaChip { MetaChip }

sv import from ..library { VideoDetail, FrameView, WordView, get_video, get_frame_words }

def:pub StudioPage -> JsxElement {
    has detail: VideoDetail | None = None,
        loading: bool = True,
        load_error: str = "",
        words: list[WordView] = [],
        words_frame: str = "",
        words_loading: bool = False,
        show_boxes: bool = True,
        show_words: bool = False;

    params = useParams();
    video_id: str = str(params["id"]) if params["id"] else "";
    asked: int = int(params["index"]) if params["index"] else 1;

    frames: list[FrameView] = detail.frames if detail is not None else [];
    total = len(frames);
    pos = asked;
    if not (pos >= 1 and pos <= total) {
        pos = 1;
    }
    frame_id = frames[pos - 1].id if total > 0 else "";

    async def loadVideo(vid: str) -> None;
    async def syncWords(fid: str) -> None;

    can with [video_id] entry {
        loadVideo(video_id);
    }

    can with (frame_id, show_words) entry {
        syncWords(frame_id);
    }

    if loading {
        return <div className="studio">
            <AppHeader subtitle="reading the frame chain" crumb="loading"/>
            <div className="studio-wait">Walking the graph...</div>
        </div>;
    }

    if load_error or detail is None {
        return <div className="studio">
            <AppHeader subtitle="that video is not in the graph" crumb="not found"/>
            <div className="studio-wait">
                <p>{load_error if load_error else "No video with that id."}</p>
                <Link className="studio-back" to="/">Back to the library</Link>
            </div>
        </div>;
    }

    video = detail.video;
    current = frames[pos - 1];

    return <div className="studio">
        <AppHeader
            subtitle={f"{video.width}x{video.height} · {video.duration:.1f}s"}
            crumb={video.title}
        >
            <MetaChip label="frames" value={str(total)}/>
            <MetaChip label="words" value={str(video.word_count)} tone="accent"/>
            <MetaChip
                label="boxes"
                value={str(video.box_count)}
                tone={"danger" if video.box_count > 0 else "muted"}
            />
            <MetaChip
                label="export"
                value={"ready" if video.export_url else "none"}
                tone={"success" if video.export_url else "muted"}
            />
        </AppHeader>

        <div className="studio-grid">
            <main className="studio-stage">
                <FrameInspector
                    frame={current}
                    words={words}
                    show_boxes={show_boxes}
                    show_words={show_words}
                    words_loading={words_loading}
                    prev_to={f"/video/{video_id}/frame/{pos - 1}"}
                    next_to={f"/video/{video_id}/frame/{pos + 1}"}
                    has_prev={pos > 1}
                    has_next={pos < total}
                    onToggleBoxes={lambda { show_boxes = not show_boxes; }}
                    onToggleWords={lambda { show_words = not show_words; }}
                />
                <FrameStrip
                    frames={frames}
                    video_id={video_id}
                    current_index={pos}
                />
                {#* The cascade is a timeline over the whole frame chain, so it
                    lives under the other timeline rather than in the 360px
                    rail, where its axis would be too short to read. *#}
                <CascadePanel video_id={video_id} frame_index={pos}/>
            </main>

            <aside className="studio-rail">
                <FramePanel frame={current} words={words} show_words={show_words}/>
                <ExportPanel export_url={video.export_url} box_count={video.box_count}/>
            </aside>
        </div>
    </div>;
}
