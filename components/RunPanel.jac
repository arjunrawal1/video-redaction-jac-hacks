"""Ask for a redaction in words, then watch the passes go.

A run costs minutes, nearly all of it spent waiting on a vision model, so the
server sends a frame per stage instead of one answer at the end. This reads
those frames with a raw fetch: the generated RPC stubs await a whole response,
which would put the page back where it started.

When the request being asked for is one this video has already answered, the
recorded run is played back instead of repeated. That is the difference between
a few seconds and several minutes, and it is the same text either way -- the
panel says which of the two is happening rather than blurring them.
"""

import from "@jac/runtime" { Link }

sv import from ..pipeline { RunRecord, get_run_record }

"""One progress frame, already parsed."""
obj RunStep {
    has stage: str;
    has message: str;
}

def:pub RunPanel(video_id: str, box_count: int) -> JsxElement {
    has request: str = "",
        stride: int = 4,
        running: bool = False,
        replaying: bool = False,
        steps: list[RunStep] = [],
        failed: bool = False,
        done: bool = False,
        record: RunRecord | None = None;

    async def start -> None;
    async def loadRecord(vid: str) -> None;

    can with [video_id] entry {
        loadRecord(video_id);
    }

    def handle_submit(e: FormEvent) {
        e.preventDefault();
        start();
    }

    asked = request.strip().lower();
    recorded = record.request.strip().lower() if record is not None and record.present else "";
    recorded_steps = record.steps if record is not None else 0;
    will_replay = bool(recorded) and asked == recorded;
    blocked = box_count > 0 and not will_replay and not running;

    return <section className="run">
        <div className="run-head">
            <h2 className="run-title">Redact</h2>
            {if running {
                <span className="run-badge run-badge-live">
                    {"replaying" if replaying else "running"}
                </span>
            } elif done and not failed {
                <span className="run-badge run-badge-ok">finished</span>
            }}
        </div>

        <form className="run-form" onSubmit={handle_submit}>
            <label className="run-label" htmlFor="run-request">
                What should be covered?
            </label>
            <textarea
                id="run-request"
                className="run-input"
                rows={2}
                value={request}
                placeholder={recorded if recorded else "all emails"}
                disabled={running}
                onChange={lambda (e: ChangeEvent) { request = str(e.target.value); }}
            />
            {if not will_replay {
                <div className="run-row">
                    <label className="run-label" htmlFor="run-stride">Judge every</label>
                    <input
                        id="run-stride"
                        className="run-stride"
                        type="number"
                        min="1"
                        max="32"
                        value={str(stride)}
                        disabled={running}
                        onChange={lambda (e: ChangeEvent) { stride = int(e.target.value or 1); }}
                    />
                    <span className="run-label">th frame</span>
                </div>
            }}
            <button
                className="run-go"
                type="submit"
                disabled={running or not asked or blocked}
            >
                {"Working..." if running
                    else ("Show the run" if will_replay else "Plan, detect, follow, export")}
            </button>
        </form>

        {if will_replay and not running and not done {
            <p className="run-hint">
                This video has already answered that. Pressing the button plays
                back the {recorded_steps} frame(s) that run reported, rather than
                paying the model for the same answer twice.
            </p>
        }}

        {if blocked {
            <p className="run-note">
                {video_boxes_note(box_count, recorded)}
            </p>
        }}

        {if steps {
            <ol className="run-log">
                {[
                    <li className={"run-step run-step-" + s.stage} key={str(i)}>
                        <span className="run-stage">{s.stage}</span>
                        <span className="run-msg">{s.message}</span>
                    </li>
                    for (i, s) in enumerate(steps)
                ]}
            </ol>
        }}

        {if done and not failed {
            <Link className="run-seeexport" to={f"/video/{video_id}"}>
                Reload the page to see the redacted video
            </Link>
        }}
    </section>;
}

"""Why a fresh run will not start on a video that already carries boxes."""
def video_boxes_note(box_count: int, recorded: str) -> str {
    if recorded {
        return (
            f"{box_count} redaction(s) are already on this video, from the run "
            f"for '{recorded}'. Ask for that again to watch it, or clear the "
            "boxes to run something else."
        );
    }
    return (
        f"{box_count} redaction(s) are already on this video. A run refuses "
        "rather than redact on top of them; clear them first."
    );
}
