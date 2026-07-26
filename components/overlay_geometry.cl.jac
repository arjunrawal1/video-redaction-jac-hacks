"""The one place box_2d coordinates become CSS.

Geometry is stored in box_2d order - [y0, x0, y1, x1] - normalized to a 0..1000
scale against the frame, so y comes FIRST and a 0..1000 value is a percentage
times ten. Dividing by ten and positioning in percent means the overlay tracks
the displayed image at any size, with no pixel math and nothing to keep in sync
when the layout changes.

Every rectangle the UI draws - redaction Box nodes and the debug OCR word
overlay both - comes through here, so if the overlay is ever misaligned there is
exactly one function to fix.
"""

"""CSS box for one box_2d rectangle, as a fraction of the displayed frame."""
def:pub rect_style(y0: int, x0: int, y1: int, x1: int) -> dict[str, object] {
    return {
        "top": f"{y0 / 10.0}%",
        "left": f"{x0 / 10.0}%",
        "height": f"{max(y1 - y0, 0) / 10.0}%",
        "width": f"{max(x1 - x0, 0) / 10.0}%"
    };
}

"""`m:ss.mmm` for a timestamp in seconds.

Zero-padded by hand: the width-and-zero form (`:06.3f`) pads with a space in
the compiled client, which makes the whole filmstrip read ragged.
"""
def:pub clock(seconds: float) -> str {
    total = seconds if seconds > 0.0 else 0.0;
    mins = int(total) // 60;
    secs = total - (mins * 60.0);
    body = f"{secs:.3f}";
    return f"{mins}:0{body}" if secs < 10.0 else f"{mins}:{body}";
}
