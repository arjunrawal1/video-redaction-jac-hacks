"""Reading the pipeline's progress stream.

Frames are separated by a blank line and can split at any byte boundary, so
this buffers and keeps the trailing partial. The payload is double encoded --
SSE JSON-encodes the string the endpoint yielded, and that string is itself
the JSON object -- hence the two parses.

The accumulated list is local rather than read back out of state: inside this
loop the reactive value is the render-time snapshot, so appending to `steps`
directly would keep rediscovering an empty list.
"""

impl RunPanel.loadRecord(vid: str) -> None {
    if not vid {
        return;
    }
    try {
        record = await get_run_record(vid);
    } except Exception {
        record = None;
    }
}

impl RunPanel.start -> None {
    asked_now = request.strip();
    if running or not video_id or not asked_now {
        return;
    }

    prior = record.request.strip().lower() if record is not None and record.present else "";
    playback = bool(prior) and asked_now.lower() == prior;

    running = True;
    replaying = playback;
    done = False;
    failed = False;
    steps = [];

    route = "/function/replay_pipeline" if playback else "/function/run_pipeline";
    body = JSON.stringify({"video_id": video_id, "beat": 0.5}) if playback
        else JSON.stringify({
            "video_id": video_id,
            "request": asked_now,
            "stride": stride,
            "max_steps": 8
        });

    seen: list[RunStep] = [];
    nl = chr(10);

    try {
        resp = await fetch(route, {
            "method": "POST",
            "headers": {"Content-Type": "application/json"},
            "body": body
        });
        reader = resp.body.getReader();
        decoder = new(TextDecoder);
        buf = "";
        feeding = True;

        while feeding {
            part = await reader.read();
            if part.done {
                feeding = False;
                continue;
            }
            buf = buf + decoder.decode(part.value, {"stream": True});
            frames = buf.split(nl + nl);
            buf = frames.pop();
            for frame in frames {
                if frame.startswith("event:") {
                    continue;
                }
                for line in frame.split(nl) {
                    if not line.startswith("data: ") {
                        continue;
                    }
                    encoded: any = JSON.parse(line[6:]);
                    payload: any = JSON.parse(encoded);
                    step = RunStep(
                        stage=str(payload.stage),
                        message=str(payload.message)
                    );
                    seen = seen + [step];
                    steps = seen;
                    if step.stage == "error" {
                        failed = True;
                    }
                }
            }
        }
    } except Exception as e {
        seen = seen + [RunStep(stage="error", message="Stream broke: " + str(e))];
        steps = seen;
        failed = True;
    }

    running = False;
    done = True;
    if not playback {
        record = await get_run_record(video_id);
    }
}
