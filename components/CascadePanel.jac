"""The agent cascade: who walked where, how far they got, and what they found.

Detection only looks at a few frames. Everything else in the redaction comes
from agents that carry those findings outwards along the Next chain, one
forward and one backward per seed, until the value they are following leaves the
screen. That is a journey along the timeline, so this draws it as one: a single
frame axis, an agent per lane, its seed marked and its reach drawn as a span in
the direction it travelled, with the reason it stopped at the open end.

Below the agents, the same axis carries the tracks - one row per real-world
value, a dot on every frame it was still visible on. The agents explain how the
graph was built; the tracks explain what it means.

Everything on the axis is a `<Link>` to that frame, and the blue playhead is the
frame the studio is showing, so the picture is a control as well as a report.
"""

import from "@jac/runtime" { Link }
import from .CascadeLane { CascadeLane }
import from .MetaChip { MetaChip }
import from .cascade_geometry { mark_style, pin_style, span_style, playhead_style }
import from .overlay_geometry { clock }

sv import from ..library {
    CascadeView, BoxProvenance, get_cascade, get_frame_provenance
}

def:pub CascadePanel(video_id: str, frame_index: int) -> JsxElement {
    has cascade: CascadeView | None = None,
        boxes: list[BoxProvenance] = [],
        loading: bool = True,
        load_error: str = "";

    async def loadCascade -> None {
        if not video_id {
            loading = False;
            return;
        }
        try {
            cascade = await get_cascade(video_id);
            load_error = "";
        } except Exception as e {
            load_error = "Could not read the cascade: " + str(e);
        }
        loading = False;
    }

    async def loadProvenance -> None {
        if not video_id {
            return;
        }
        found = await get_frame_provenance(video_id, frame_index);
        boxes = found if found is not None else [];
    }

    can with [video_id] entry {
        loadCascade();
    }

    can with (video_id, frame_index) entry {
        loadProvenance();
    }

    total = cascade.frame_count if cascade is not None else 0;
    agents = cascade.agents if cascade is not None else [];
    tracks = cascade.tracks if cascade is not None else [];
    covered = len([m for m in cascade.frames if m.box_count > 0]) if cascade is not None else 0;
    fixture = (
        cascade is not None
        and cascade.box_count > 0
        and cascade.fixture_box_count == cascade.box_count
    );

    # Axis labels every eighth of the chain, always including both ends.
    ticks: list[int] = [];
    if total > 0 {
        every = max(1, total // 8);
        n = 1;
        while n <= total {
            ticks.append(n);
            n += every;
        }
        if ticks[-1] != total {
            ticks.append(total);
        }
    }

    return <section className="panel casc">
        <header className="panel-head">
            <div className="casc-head-left">
                <h2 className="panel-title">Agent cascade</h2>
                <p className="casc-lede">
                    Two agents leave every seeded detection - one forward along
                    the frame chain, one back - and keep writing boxes until the
                    value they carry is no longer on screen. One lane per agent:
                    the diamond is the frame it started from, the bar is how far
                    it got, and the label at the open end is why it stopped.
                </p>
            </div>
            {if cascade is None or cascade.box_count == 0 {
                <span className="panel-flag">empty</span>
            } elif fixture {
                <span
                    className="panel-flag panel-flag-reserved"
                    title="Every box here was written by seed_demo_cascade, not by the detector."
                >
                    fixture
                </span>
            } else {
                <span className="panel-flag panel-flag-ok">live</span>
            }}
        </header>

        {if loading {
            <div className="casc-wait">Walking the agents...</div>
        } elif load_error {
            <p className="lib-error">{load_error}</p>
        } elif cascade is None or len(agents) == 0 {
            <div className="casc-slot">
                <div className="casc-art" aria-hidden="true">
                    <span className="casc-node casc-node-seed"/>
                    <span className="casc-edge"/>
                    <span className="casc-node"/>
                    <span className="casc-edge"/>
                    <span className="casc-node casc-node-dim"/>
                </div>
                <p className="panel-empty">
                    No Agent nodes on this graph yet. Run the detector and
                    SeedCascades, or POST to seed_demo_cascade for the fixture
                    walk, and every agent shows up here as a lane.
                </p>
            </div>
        } else {
            <div className="panel-chips">
                <MetaChip label="agents" value={str(cascade.agent_count)} tone="accent"/>
                <MetaChip label="seeds" value={str(len(cascade.seed_frames))}/>
                <MetaChip label="tracks" value={str(cascade.track_count)}/>
                <MetaChip
                    label="boxes"
                    value={f"{cascade.seed_box_count}+{cascade.cascade_box_count}"}
                    tone="danger"
                />
                <MetaChip label="frames covered" value={f"{covered}/{total}"}/>
            </div>

            <div className="casc-legend">
                <span className="casc-key">
                    <span className="casc-key-seed"/>seed detection
                </span>
                <span className="casc-key">
                    <span className="casc-key-fwd"/>forward reach
                </span>
                <span className="casc-key">
                    <span className="casc-key-back"/>backward reach
                </span>
                <span className="casc-key">
                    <span className="casc-key-pip"/>frame it claimed
                </span>
                <span className="casc-key">
                    <span className="casc-key-track"/>value on screen
                </span>
                <span className="casc-key">
                    <span className="casc-key-now"/>frame you are on
                </span>
            </div>

            <div className="casc-board">
                <div className="casc-row casc-row-axis">
                    <div className="casc-row-id">
                        <span className="casc-row-name">frame chain</span>
                        <span className="casc-row-meta">{f"1 - {total}"}</span>
                    </div>
                    <div className="casc-track">
                        <span className="casc-rail casc-rail-axis"/>
                        {for t in ticks {
                            <span
                                key={"tick" + str(t)}
                                className="casc-tick"
                                style={pin_style(t, total)}
                            >
                                {str(t)}
                            </span>
                        }}
                    </div>
                </div>

                <div className="casc-row casc-row-cover">
                    <div className="casc-row-id">
                        <span className="casc-row-name">coverage</span>
                        <span className="casc-row-meta">
                            {f"{cascade.box_count} box(es)"}
                        </span>
                    </div>
                    <div className="casc-track">
                        <span className="casc-rail"/>
                        {for m in cascade.frames {
                            if m.box_count > 0 {
                                <Link
                                    key={"cov" + str(m.index)}
                                    className={
                                        "casc-cover casc-on"
                                        if m.index == frame_index
                                        else "casc-cover"
                                    }
                                    style={span_style(m.index, m.index, total)}
                                    to={f"/video/{video_id}/frame/{m.index}"}
                                    title={
                                        f"frame {m.index} · {clock(m.timestamp)} · "
                                        f"{m.box_count} box(es)"
                                        + (" · seeded" if m.seed_count > 0 else "")
                                    }
                                >
                                    <span
                                        className={
                                            "casc-cover-bar casc-cover-seed"
                                            if m.seed_count > 0
                                            else "casc-cover-bar"
                                        }
                                    />
                                </Link>
                            }
                        }}
                    </div>
                </div>

                {for (i, a) in enumerate(agents) {
                    <CascadeLane
                        key={a.id}
                        agent={a}
                        total={total}
                        video_id={video_id}
                        current={frame_index}
                        rank={i}
                        opens_seed={i == 0 or agents[i - 1].seed_index != a.seed_index}
                    />
                }}

                <div className="casc-split">
                    <span className="casc-split-h">Tracks</span>
                    <span className="casc-split-p">
                        one value, followed across every frame it stayed visible on
                    </span>
                </div>

                {for (i, t) in enumerate(tracks) {
                    <div className="casc-row casc-row-track" key={t.id}>
                        <div className="casc-row-id">
                            <span className="casc-row-name casc-row-value">
                                {t.label}
                            </span>
                            <span className="casc-row-meta">
                                {f"{t.box_count} box(es) · {t.seed_boxes} seeded"}
                            </span>
                        </div>
                        <div className="casc-track">
                            <span className="casc-rail"/>
                            <span
                                className="casc-life"
                                style={span_style(t.first_index, t.last_index, total)}
                            />
                            {for (j, s) in enumerate(t.stops) {
                                <Link
                                    key={t.id + "f" + str(s.index)}
                                    className={
                                        "casc-mark casc-on"
                                        if s.index == frame_index
                                        else "casc-mark"
                                    }
                                    style={mark_style(s.index, total, j)}
                                    to={f"/video/{video_id}/frame/{s.index}"}
                                    title={
                                        f"'{t.label}' on frame {s.index} · "
                                        f"{s.box_count} box(es)"
                                        + (" · seed" if s.seeded else "")
                                    }
                                >
                                    <span
                                        className={
                                            "casc-pip casc-pip-track casc-pip-seeded"
                                            if s.seeded
                                            else "casc-pip casc-pip-track"
                                        }
                                    />
                                </Link>
                            }}
                        </div>
                    </div>
                }}

                <span
                    className="casc-playhead"
                    style={playhead_style(frame_index, total)}
                >
                    <span className="casc-playhead-tag">{"#" + str(frame_index)}</span>
                </span>
            </div>

            <div className="panel-block">
                <h3 className="panel-h3">
                    Provenance on frame {str(frame_index)}
                    <span className="panel-count">{str(len(boxes))}</span>
                </h3>
                {if len(boxes) == 0 {
                    <p className="panel-empty">
                        No agent reached this frame. The lanes above show where
                        each one stopped and why.
                    </p>
                } else {
                    <ul className="casc-prov">
                        {for b in boxes {
                            <li className="casc-prov-row" key={b.box_id}>
                                <span className="casc-prov-text">
                                    {b.text or "(region)"}
                                </span>
                                <span className={"boxrow-origin origin-" + b.origin}>
                                    {b.origin}
                                </span>
                                {if b.agent_id {
                                    <Link
                                        className="casc-prov-agent"
                                        to={f"/video/{video_id}/frame/{b.seed_index}"}
                                        title={f"placed by {b.agent_id}, which stopped because it {b.agent_reason}"}
                                    >
                                        {f"{b.agent_id} ↦ seeded on #{b.seed_index}"}
                                    </Link>
                                } else {
                                    <span className="casc-prov-agent casc-prov-none">
                                        seed detection
                                    </span>
                                }}
                                {if b.track_label {
                                    <span className="casc-prov-track">
                                        {f"track '{b.track_label}' · {b.track_boxes} box(es)"}
                                    </span>
                                }}
                                <span className="casc-prov-conf">
                                    {f"{b.confidence:.2f}"}
                                </span>
                            </li>
                        }}
                    </ul>
                }}
            </div>

            if fixture {
                <p className="panel-note">
                    Fixture cascade: these agents walked the real frame chain and
                    matched real OCR text, but the values they follow were picked
                    by a heuristic rather than by the policy and the detector.
                </p>
            }
        }}
    </section>;
}
