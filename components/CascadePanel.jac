"""RESERVED: agent-cascade visualization.

=============================================================================
This region is a placeholder and is owned by the lead engineer. Nothing here
reads the graph on purpose - it holds the space, the frame and the styling so
the cascade view can be dropped in without touching the studio layout.

To fill it in, replace the body of this component. What it is sized and styled
for: Agent nodes (agent_id, direction, focus, summary, still_visible, steps)
walked from a Box through AddedBy, and their lineage along SpawnedBy. The panel
is a flex column inside the studio rail, scrolls on its own, and gets
--cascade-accent / --cascade-soft from the semantic palette.

Props are deliberately minimal: whatever the cascade view needs should be
fetched by this component or passed from StudioPage, which already holds the
video id and the selected frame.
=============================================================================
"""

def:pub CascadePanel(video_id: str, frame_index: int) -> JsxElement {
    return <section className="panel panel-reserved">
        <header className="panel-head">
            <h2 className="panel-title">Agent cascade</h2>
            <span className="panel-flag panel-flag-reserved">reserved</span>
        </header>
        <div className="casc-slot">
            <div className="casc-art" aria-hidden="true">
                <span className="casc-node casc-node-seed"/>
                <span className="casc-edge"/>
                <span className="casc-node"/>
                <span className="casc-edge"/>
                <span className="casc-node casc-node-dim"/>
            </div>
            <p className="panel-empty">
                Reserved for the cascade visualization: agents spawned from a
                detection, walking the chain forward and backward until the thing
                they were following stops being visible.
            </p>
            <p className="casc-ctx">
                {f"context: video {video_id[:8]} · frame {frame_index}"}
            </p>
        </div>
    </section>;
}
