"""Runtime check for ingest: frame chain, timestamps, and re-ingest reuse."""

import os;
import from ingest { ingest_video }

include graph;

walker ChainLength {
    has count: int = 0;
    has last: int = 0;

    can step with Frame entry {
        self.count += 1;
        self.last = here.index;
        visit [here ->:Next:->];
    }
}

with entry {
    src = os.getenv("DEMO_VIDEO", "");
    if not src or not os.path.exists(src) {
        print("set DEMO_VIDEO to a video file first");
    } else {
        vid = ingest_video(src, fps=float(os.getenv("DEMO_FPS", "8")));
        frames = [vid ->:Contains:->];
        print(f"video: {vid.title} {vid.width}x{vid.height} @ {vid.source_fps:.2f}fps hash={vid.video_hash}");
        print(f"frames attached: {len(frames)}");

        first = [vid ->:Contains:->[?:Frame, index == 1]][0];
        chain = ChainLength() spawn first;
        print(f"Next chain reaches: {chain.count} frames, last index {chain.last}");

        ok = chain.count == len(frames);
        print(f"chain covers every frame: {ok}");

        on_disk = len([f for f in frames if os.path.exists(f.jpeg_path)]);
        print(f"frames present on disk: {on_disk}/{len(frames)}");

        again = ingest_video(src, fps=float(os.getenv("DEMO_FPS", "8")));
        print(f"re-ingest reused the same video: {jid(again) == jid(vid)}");
        print(f"videos on root: {len([root -->[?:Video]])}");
    }
}
