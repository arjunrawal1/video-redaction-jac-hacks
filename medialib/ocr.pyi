"""Type surface for the OCR helper, so the Jac side stays fully typed."""

from dataclasses import dataclass

class OcrError(Exception): ...

@dataclass
class OcrWord:
    text: str
    y0: int
    x0: int
    y1: int
    x1: int
    conf: float

def detect_words(image_path: str, min_confidence: float = ...) -> list[OcrWord]: ...
