"""Word-level OCR geometry from AWS Textract.

Returns individual words with boxes rather than lines, because a redaction
rectangle should hug the sensitive token and not the whole row it sits in.

Coordinates come back in box_2d order [y0, x0, y1, x1] on a 0..1000 scale.
Textract is already resolution-independent (it reports 0..1 fractions), so
nothing here needs to know the frame's pixel dimensions.
"""

from __future__ import annotations

import os
import threading
import time
from dataclasses import dataclass
from typing import Any

# Textract scores 0-100. Screenshot text usually lands above 90; a low floor
# keeps small or faint text in the pool so the policy layer can still judge it.
MIN_CONFIDENCE = float(os.getenv("OCR_MIN_CONFIDENCE", "10"))

MAX_RETRIES = int(os.getenv("OCR_MAX_RETRIES", "3"))

SCALE = 1000

_client: Any = None
_client_lock = threading.Lock()


class OcrError(Exception):
    """Textract rejected the request or could not be reached."""


@dataclass
class OcrWord:
    text: str
    y0: int
    x0: int
    y1: int
    x1: int
    conf: float


def _get_client() -> Any:
    global _client
    if _client is not None:
        return _client
    with _client_lock:
        if _client is None:
            import boto3

            region = (
                os.getenv("AWS_REGION")
                or os.getenv("AWS_DEFAULT_REGION")
                or "us-east-1"
            )
            _client = boto3.client("textract", region_name=region)
    return _client


def _call(blob: bytes) -> dict:
    from botocore.exceptions import ClientError

    client = _get_client()
    delay = 0.5
    for attempt in range(MAX_RETRIES):
        try:
            return client.detect_document_text(Document={"Bytes": blob})
        except ClientError as e:
            code = e.response.get("Error", {}).get("Code", "")
            retriable = code in (
                "ThrottlingException",
                "ProvisionedThroughputExceededException",
                "ServiceUnavailable",
                "InternalServerError",
            )
            if not retriable or attempt == MAX_RETRIES - 1:
                raise OcrError(f"Textract failed ({code or 'unknown'}): {e}") from e
            time.sleep(delay)
            delay *= 2
    raise OcrError("Textract retries exhausted")


def detect_words(image_path: str, min_confidence: float = MIN_CONFIDENCE) -> list[OcrWord]:
    """Read one frame and return every word Textract is confident enough about."""
    with open(image_path, "rb") as fh:
        blob = fh.read()

    response = _call(blob)

    words: list[OcrWord] = []
    for block in response.get("Blocks") or []:
        if block.get("BlockType") != "WORD":
            continue
        conf = float(block.get("Confidence") or 0.0)
        if conf < min_confidence:
            continue
        text = str(block.get("Text") or "").strip()
        if not text:
            continue
        bbox = (block.get("Geometry") or {}).get("BoundingBox")
        if not bbox:
            continue

        left = float(bbox.get("Left") or 0.0)
        top = float(bbox.get("Top") or 0.0)
        width = float(bbox.get("Width") or 0.0)
        height = float(bbox.get("Height") or 0.0)

        words.append(
            OcrWord(
                text=text,
                y0=max(0, round(top * SCALE)),
                x0=max(0, round(left * SCALE)),
                y1=min(SCALE, round((top + height) * SCALE)),
                x1=min(SCALE, round((left + width) * SCALE)),
                conf=conf / 100.0,
            )
        )

    return words
