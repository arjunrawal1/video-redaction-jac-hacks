"""One agent's walk, drawn as a lane along the frame axis.

The lane is the agent's whole life in one line: the amber diamond is the frame
it was launched from, the bar is the ground it covered, its direction is the way
the bar grows out of the diamond, each pip is a frame where it wrote at least
one box, and the label at the open end is why it stopped. A lane with no bar is
an agent that never got a step -- the backward agent of a seed on frame 1 has
nowhere to walk, and that is worth seeing rather than hiding.

Every marker is a `<Link>` to that frame, so the picture is also the navigation.
"""

import from "@jac/runtime" { Link }
import from .cascade_geometry {
    span_style, mark_style, pin_style, lane_style, tip_style, tip_flipped
}
import from .overlay_geometry { clock }

sv import from ..library { AgentView }

def:pub CascadeLane(
    agent: AgentView,
    total: int,
    video_id: str,
    current: int,
    rank: int,
    opens_seed: bool = False
) -> JsxElement {
    ahead = agent.direction == "forward";
    way = "casc-fwd" if ahead else "casc-back";
    walked = len(agent.stops) > 0;
    tip_at = agent.reach_index if walked else agent.seed_index;
    on_seed = agent.seed_index == current;

    # A step limit means coverage the run did not finish; a value that went
    # away means the cascade did its job. Worth different colours.
    tone = "";
    if "step limit" in agent.reason {
        tone = " casc-why-cut";
    } elif "nothing left" in agent.reason {
        tone = " casc-why-done";
    }
    flipped = tip_flipped(tip_at, total, ahead);
    tip_class = "casc-why casc-why-flip" + tone if flipped else "casc-why" + tone;

    # The two agents of one seed are a pair; a rule above the first of them
    # keeps that visible when the lanes stack up.
    group = " casc-row-open" if opens_seed else "";

    return <div className={"casc-row " + way + group} style={lane_style(rank)}>
        <div className="casc-row-id">
            <span className="casc-row-name">
                <span className={"casc-arrow " + way}>{"▸" if ahead else "◂"}</span>
                {agent.agent_id}
            </span>
            <span className="casc-row-meta">
                {f"{agent.steps} step(s) · {agent.box_count} box(es)"}
            </span>
        </div>

        <div className="casc-track">
            <span className="casc-rail"/>

            {if walked {
                <span
                    className={"casc-span " + way}
                    style={span_style(agent.seed_index, agent.reach_index, total)}
                >
                    <span className="casc-comet"/>
                </span>
            } else {
                <span className="casc-stub" style={pin_style(agent.seed_index, total)}/>
            }}

            <Link
                className={"casc-seed" + (" casc-on" if on_seed else "")}
                style={pin_style(agent.seed_index, total)}
                to={f"/video/{video_id}/frame/{agent.seed_index}"}
                title={
                    f"seed · frame {agent.seed_index} · following "
                    + (", ".join(agent.targets) if agent.targets else "nothing")
                }
            />

            {for (i, s) in enumerate(agent.stops) {
                <Link
                    key={agent.id + "s" + str(s.index)}
                    className={
                        "casc-mark casc-on" if s.index == current else "casc-mark"
                    }
                    style={mark_style(s.index, total, (rank * 3) + i)}
                    to={f"/video/{video_id}/frame/{s.index}"}
                    title={
                        f"frame {s.index} · {clock(s.timestamp)} · "
                        f"{s.box_count} box(es): " + ", ".join(s.texts)
                    }
                >
                    <span className={"casc-pip casc-pip-" + str(min(s.box_count, 3))}/>
                </Link>
            }}

            <span className={tip_class} style={tip_style(tip_at, total, rank, flipped)}>
                {agent.reason if agent.reason else "still running"}
            </span>
        </div>
    </div>;
}
