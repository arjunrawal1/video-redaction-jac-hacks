"""Type surface for the export helper, so the Jac side stays fully typed."""

from dataclasses import dataclass

class ExportError(Exception): ...

@dataclass
class BoxSpan:
    y0: int
    x0: int
    y1: int
    x1: int
    t_start: float
    t_end: float

def export_redacted(source_path: str, out_path: str, spans: list[BoxSpan]) -> str: ...
