"""Landing view: what is in the graph, and the door to putting more in.

Page state and every server call live here; the sections below it are stateless
functions of their props.
"""

import from .AppHeader { AppHeader }
import from .MetaChip { MetaChip }
import from .UploadPanel { UploadPanel }
import from .VideoCard { VideoCard }

sv import from ..library { VideoView, list_videos }
sv import from ..endpoints { IngestOutcome, request_ingest }

def:pub LibraryPage -> JsxElement {
    has videos: list[VideoView] = [],
        loading: bool = True,
        load_error: str = "",
        pick: str = "",
        ingest_pending: bool = False,
        ingest_message: str = "",
        ingest_accepted: bool = False,
        ingest_video_id: str = "";

    async can with entry {
        loadLibrary();
    }

    async def loadLibrary -> None;
    async def submitIngest -> None;

    total_frames = sum([v.frame_count for v in videos]);
    total_words = sum([v.word_count for v in videos]);
    total_boxes = sum([v.box_count for v in videos]);

    return <div className="lib">
        <AppHeader subtitle="frames, words and redactions, straight off the graph">
            <MetaChip label="videos" value={str(len(videos))}/>
            <MetaChip label="frames" value={str(total_frames)}/>
            <MetaChip label="words" value={str(total_words)} tone="accent"/>
            <MetaChip label="boxes" value={str(total_boxes)} tone={"danger" if total_boxes > 0 else "muted"}/>
        </AppHeader>

        <div className="lib-body">
            <section className="lib-main">
                <div className="lib-main-head">
                    <h1 className="lib-h1">Library</h1>
                    <p className="lib-lede">
                        Every video ingested into the persistent graph. Open one to
                        walk its frame chain and inspect what the pipeline sees.
                    </p>
                </div>

                {if loading {
                    <div className="lib-grid">
                        {for i in range(3) {
                            <div className="lib-skel" key={"skel" + str(i)}/>
                        }}
                    </div>
                } elif load_error {
                    <p className="lib-error">{load_error}</p>
                } elif len(videos) == 0 {
                    <div className="lib-empty">
                        <h2 className="lib-empty-h">The graph is empty</h2>
                        <p className="lib-empty-p">
                            No Video nodes hang off root yet. Ingest a recording
                            server-side and it appears here - frames, OCR words and
                            redaction boxes included.
                        </p>
                    </div>
                } else {
                    <div className="lib-grid">
                        {for v in videos {
                            <VideoCard key={v.id} video={v}/>
                        }}
                    </div>
                }}
            </section>

            <aside className="lib-side">
                <UploadPanel
                    filename={pick}
                    pending={ingest_pending}
                    outcome={ingest_message}
                    accepted={ingest_accepted}
                    open_to={f"/video/{ingest_video_id}" if ingest_video_id else ""}
                    onPick={lambda (name: str) { pick = name; ingest_message = ""; ingest_video_id = ""; }}
                    onSubmit={submitIngest}
                />
                <div className="lib-note">
                    <h3 className="lib-note-h">How a video gets here</h3>
                    <ol className="lib-note-l">
                        <li>frames extracted and deduplicated into a Next-linked chain</li>
                        <li>each frame OCR'd, words stored inline on the frame</li>
                        <li>an LLM decides what is sensitive, per frame</li>
                        <li>cascading agents carry each decision across frames</li>
                        <li>boxes burned in on export</li>
                    </ol>
                    <p className="lib-note-p">
                        Steps 1 and 2 are live. Step 3 onward writes Box nodes, and
                        this UI renders them the moment they exist.
                    </p>
                </div>
            </aside>
        </div>
    </div>;
}
