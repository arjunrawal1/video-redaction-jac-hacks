"""Read a pipeline stream from the command line and stop at the end marker.

curl holds the socket open after the server's last frame, which makes a run
that has already finished look like one that hung. This closes as soon as the
`event: end` frame arrives, printing each stage as it lands and writing the raw
frames out so a finished run can be replayed.
"""

import json
import sys
import time
import urllib.request

route = sys.argv[1]
payload = json.loads(sys.argv[2])
out_path = sys.argv[3] if len(sys.argv) > 3 else ""

req = urllib.request.Request(
    f"http://localhost:8000/function/{route}",
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json"},
)

started = time.time()
frames = []
buf = ""

with urllib.request.urlopen(req) as resp:
    while True:
        chunk = resp.read1(4096)
        if not chunk:
            break
        buf += chunk.decode("utf-8", "replace")
        blocks = buf.split("\n\n")
        buf = blocks.pop()
        done = False
        for block in blocks:
            if block.startswith("event: end"):
                done = True
                continue
            for line in block.split("\n"):
                if not line.startswith("data: "):
                    continue
                raw = json.loads(line[6:])
                frames.append(raw)
                step = json.loads(raw)
                print(
                    f"[{time.time() - started:6.1f}s] "
                    f"{step['stage']:<8} {step['message']}",
                    flush=True,
                )
        if done:
            break

if out_path:
    with open(out_path, "w") as fh:
        json.dump(frames, fh, indent=1)

print(f"--- {len(frames)} frame(s) in {time.time() - started:.1f}s ---", flush=True)
