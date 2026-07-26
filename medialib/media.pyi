"""Type surface for the media helpers, so the Jac side stays fully typed."""

from dataclasses import dataclass

class MediaError(Exception): ...

@dataclass
class VideoInfo:
    width: int
    height: int
    fps: float
    duration: float
    frame_count: int

@dataclass
class ExtractedFrame:
    source_index: int
    path: str
    width: int
    height: int
    timestamp: float

def probe(video_path: str) -> VideoInfo: ...
def extract_frames(
    video_path: str,
    out_dir: str,
    max_width: int = ...,
    threshold: int = ...,
    max_gap: int = ...,
    fps: float = ...,
) -> list[ExtractedFrame]: ...
