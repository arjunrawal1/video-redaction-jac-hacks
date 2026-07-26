"""Frame index to a position on the cascade axis, and nowhere else.

The cascade view is one horizontal axis - the frame chain, left to right - drawn
once per agent and once per track. Everything on it (a seed, a span, a claimed
frame, the playhead) is placed by the same two functions, so the lanes cannot
drift out of alignment with each other or with the axis above them.

A frame occupies a cell of the axis rather than a point: frame `i` of `n` owns
`[(i-1)/n, i/n]`, and a marker sits at the middle of its cell. That is what
keeps the first and last frame's markers inside the board instead of half off
each end.

The playhead is the exception, because it is positioned against the whole board
rather than against one lane's plot area. `--casc-gutter` is the width of the
lane-label column, so the calc below is the same arithmetic measured from the
board's left edge.
"""

"""Middle of frame `index`'s cell, as a percentage of the plot width."""
def:pub axis_pct(index: int, total: int) -> float {
    span = total if total > 0 else 1;
    slot = index - 1;
    if slot < 0 {
        slot = 0;
    }
    if slot > span - 1 {
        slot = span - 1;
    }
    return ((slot + 0.5) / span) * 100.0;
}

"""CSS box covering frames `a` through `b` inclusive."""
def:pub span_style(a: int, b: int, total: int) -> dict[str, object] {
    span = total if total > 0 else 1;
    lo = min(a, b);
    hi = max(a, b);
    left = ((lo - 1) / span) * 100.0;
    width = ((hi - lo + 1) / span) * 100.0;
    return {"left": f"{max(left, 0.0):.4f}%", "width": f"{min(width, 100.0):.4f}%"};
}

"""A marker on the axis, popped in after `rank` places in the queue."""
def:pub mark_style(index: int, total: int, rank: int) -> dict[str, object] {
    return {
        "left": f"{axis_pct(index, total):.4f}%",
        "animationDelay": f"{180 + (rank * 40)}ms"
    };
}

"""A marker on the axis with no entrance of its own."""
def:pub pin_style(index: int, total: int) -> dict[str, object] {
    return {"left": f"{axis_pct(index, total):.4f}%"};
}

"""Stagger one lane behind the last, so the agents draw as a sequence."""
def:pub lane_style(rank: int) -> dict[str, object] {
    return {"animationDelay": f"{rank * 90}ms"};
}

"""The current-frame line, measured from the left edge of the whole board."""
def:pub playhead_style(index: int, total: int) -> dict[str, object] {
    frac = axis_pct(index, total) / 100.0;
    return {
        "left": (
            "calc(var(--casc-gutter) + "
            f"(100% - var(--casc-gutter)) * {frac:.4f})"
        )
    };
}

"""Should the label at this point open leftwards?

A stop reason belongs on the far side of where the agent stopped -- past the end
of the span, in the direction it was travelling -- so it never sits on top of
the ground the agent covered. The exception is an end that is already against
the edge of the board, where the label has to turn back inwards to stay
readable.
"""
def:pub tip_flipped(index: int, total: int, ahead: bool) -> bool {
    pct = axis_pct(index, total);
    if ahead {
        return pct > 84.0;
    }
    return pct > 16.0;
}

"""Label anchored just past a point on the axis, opening the way it travelled."""
def:pub tip_style(
    index: int,
    total: int,
    rank: int,
    flipped: bool
) -> dict[str, object] {
    pct = axis_pct(index, total);
    delay = f"{300 + (rank * 90)}ms";
    if flipped {
        return {"right": f"{100.0 - pct:.4f}%", "animationDelay": delay};
    }
    return {"left": f"{pct:.4f}%", "animationDelay": delay};
}
