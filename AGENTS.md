# Working in this project

A video redaction pipeline written in Jac. A video is ingested into a
persistent graph of frames; OCR, policy evaluation, LLM detection, and
cascading agents all operate on that graph; the result is exported as a
redacted video.

## Reference guides

Jac's syntax has evolved and is easily confused with Python or JSX. The `jac`
CLI ships the authoritative guides:

- `jac guide` lists them, `jac guide <name>` prints one
- Start with `jac guide jac-core-cheatsheet`, `jac guide jac-node-edge-patterns`,
  `jac guide jac-walker-patterns`

## Validate your work

- `jac check <file>` type-checks and lints. Run it after every edit; the
  diagnostics are good and link to the relevant guide.
- `jac check .` checks the whole project.
- `jac run <file>` executes a script. Spikes in `spike/` are runnable checks.
- `jac start --dev main.jac` runs the app.

Never leave a file failing `jac check`.

## Architecture

| File | Role |
|---|---|
| `graph.jac` | Every node/edge/obj archetype. Read it first. |
| `ingest.sv.jac` | Video file into a `Next`-linked `Frame` chain |
| `ocr.sv.jac` | Textract words, written inline onto frames |
| `medialib/` | Python: ffmpeg, perceptual hashing, Textract |
| `spike/` | Runnable checks, one per subsystem |

`medialib/*.py` each have a `.pyi` stub so the Jac side stays typed. Update
the stub whenever you change a signature, or the Jac callers silently degrade
to `any`.

## Hard-won constraints

These were all found by measurement or by a confusing failure. Trust them.

**Graph writes cost time proportional to the whole graph.** Inserting N nodes
is O(N squared). Storing a video's OCR output as ~9,000 `Word` nodes made one
pass take 345 seconds; the same data inline on frames as `list[WordBox]` takes
24 seconds and still persists with full typing. Nodes are for things the
pipeline reasons about and traverses between: frames, boxes, tracks, agents,
policy. Bulk data goes in a field. If you are about to create thousands of
nodes, stop.

**`flow` does not capture its arguments.** `flow expr` compiles to
`thread_run(lambda: expr)` -- a lambda taking nothing -- so every name in the
expression is read again on the worker thread, after the launching loop has
moved on. Launching from a loop sends the *last* iteration's arguments for
every task in the batch. Nothing raises, the shapes are right, and the results
are quietly wrong; here that means confidently redacting the wrong words.
Copying into a fresh local inside the loop body does not help -- the body
shares one binding too. Two forms are safe: unroll into one never-reassigned
name per call, or launch through a helper so each launch gets its own frame:

```jac
def launch(x: str) -> object { return flow work(x); }
futures = [launch(x) for x in xs];
```

The bug hides itself. The first fan-out in a process has to start a thread per
task, which lets each worker read its arguments before the launcher moves on,
so a cold-pool test passes and every later fan-out corrupts. That, not scope,
is why the same code looked fine from a module-level `with entry` and broke
inside a walker ability. `spike/flow_capture_check.jac` shows all of it with no
network calls.

This is not specific to byLLM. `ocr.sv.jac` still has the unsafe form, and it
is losing data: on the demo video 37 of 38 non-chunk-end frames carry their
chunk's last word list. Consecutive frames of a screen recording read almost
the same, so the text looks plausible while the box coordinates belong to
another frame.

**Overlap model calls with `async`, not `flow`.** byLLM routes
`async def f(...) -> T by llm();` through litellm's `acompletion`, and a
coroutine binds its arguments when it is built, so `asyncio.gather` cannot
lose them the way `flow` does. `run_asks` in `detect.sv.jac` is the pattern:
read every node field on the calling thread, hand plain values to the batch,
gather behind a semaphore. byLLM itself is thread-safe -- the same fan-out is
correct under `flow` once each launch gets its own frame
(`spike/async_llm_check.jac`). Against Vertex, throughput stops improving past
three or four requests in flight (`spike/inflight_check.jac`).

**Never touch the graph inside a `flow`.** Reading a node's fields from a
worker thread can return another thread's data and raise `WriteConflict` on an
all-zero anchor. Do every node read on the calling thread, pass plain strings
and ints across the boundary, and write results back after `wait`. Spawning
walkers concurrently is unsafe for the same reason -- traversal carries ambient
context.

**Persistence is scoped per entry file.** `jac run spike/foo.jac` reads and
writes `.jac/data/foo.db`; a different entry file sees a different graph. Two
spikes cannot observe each other's data, and the app under `jac start` uses
the project-named database. Put a check and the thing it checks in the same
entry file.

**Walker traversal is queue-driven, so a shared depth counter is not tree
depth.** It records the order nodes were reached, which looks plausible and is
wrong. To report hierarchy, emit an explicit parent id per node (follow the
parent edge backwards) and let the caller nest them.

**Never move `graph.jac`.** Archetype identity includes the module path, so
relocating it orphans every persisted node, with no error at compile or query
time.

**Jac does not load `.env`.** Importing `medialib` does it. Anything needing
credentials must import `medialib` (directly or transitively). Symptom if you
forget: Textract reports "Unable to locate credentials" while `.env` looks
correct. Verify with an empty environment: `env -i HOME="$HOME" PATH=... jac run ...`

**byLLM ships inside the `jac` binary.** Import from `jaclang.byllm.lib`, not
`byllm.lib`. Do not `jac install byllm` -- the PyPI package is a different,
incompatible codebase whose own source fails to parse.

**`by llm()` needs an explicit model in scope.** `glob llm: Model = Model(...)`.
The `[byllm.model]` table in `jac.toml` does not wire up the ambient `llm` in
this version; the symptom is `'NoneType' object has no attribute`.

**LLM return types must be `obj`, never `node`.** Have the model fill an `obj`,
then copy fields onto a node to persist.

**Do not name a Python package `py/`.** It collides with a PyPI module of that
name and silently shadows. This project uses `medialib/`.

## Syntax notes that cost time

- An edge query cannot go inside an f-string -- `f"{len([v ->:Contains:->])}"`
  fails to parse, because `:->` collides with the format-spec `:`. Bind it to a
  name first. `jac check` reports this as an internal crash
  (`'Name' object has no attribute 'left'`) rather than a syntax error, so
  bisect toward the f-string when you see that.
- Filters are `[?:Type]` and `[?field == x]`, combined as `[?:Type, field == x]`.
  The old `` (`?Type) `` and `(?field == x)` forms are gone.
- Docstrings go **before** a `def`, not inside the body.
- `has` fields without defaults must precede fields with defaults, including
  across archetype inheritance. A defaulted field on a base type prevents
  subtypes from declaring required ones -- this is why `PredNode` is empty.
- Bare names inside a filter resolve to node fields first, so
  `[?:Video, video_hash == video_hash]` is a tautology. Name the parameter
  something else.
- `flow expr()` / `wait f` overlaps blocking calls. Launch the whole batch,
  then wait; a `wait` inside the launch loop serializes it. Never launch one
  straight from a loop variable -- see the capture note above.
- `report` is a walker statement, so a `def report(...)` is unreachable: the
  call parses as `report (args);` and prints a tuple instead.
- A walker that never `visit`s should be a `def:pub` function instead.

## Web layer notes

**There is no FastAPI here.** Without `fastapi`/`starlette` installed, the
runtime falls back to a bare `http.server` that routes only `/function/*`,
`/walker/*`, `/user/*`, static assets, and the SPA catch-all. `@restspec`
custom paths silently fall through to the SPA HTML rather than erroring, and
raw-bytes responses (`envelope=False, produces=...`) do not exist on this
server. Frames and exports are served instead by the static resolver:
`assets/media` symlinks to `media/`, and `/static/media/<rel>` resolves under
both `jac start` and `jac start --dev`.

**An endpoint must be named in `main.jac`'s import** or it answers 405.

**One request cannot delete nodes and then create more.** The new ones are
silently discarded: the walker reports the right counts, the response is 200,
nothing is logged, and the graph ends up empty. Delete in its own request.

**`skip` does not suppress sibling JSX children.** `{if cond { ... skip; }}`
followed by a sibling renders both. Use `if/else`.

**Per-component `.style.css` annexes 500 in this runtime** -- the compiler
injects an import for `Comp.css` while only `Comp.style.css` reaches the
bundle. All styling lives in `assets/theme.css` with per-component prefixes.

**Restarting the server needs `pkill -f "jac start"` and `pkill -f "jac/rt"`.**
The child outlives the parent, and accumulated runtimes wedge the
single-threaded server.

**Reads run on the calling user's root**, so the app's graph cannot be seeded
by a spike -- seed it over HTTP.

## Media notes

- Screen recordings often carry non-full-range YUV, which the mjpeg encoder
  rejects. The extract filter chain normalizes with `format=yuvj420p`.
- Box geometry is stored in box_2d order `[y0, x0, y1, x1]` on a 0..1000 scale,
  normalized against the frame. Convert to pixels only at export, and to CSS
  only in `components/overlay_geometry.cl.jac`. This is the easiest thing in
  the project to get wrong.
- ffmpeg dies with SIGBUS and an *empty* stderr somewhere above ~3,600 chained
  `drawbox` filters. The export splits into sequential passes of 1,500 to stay
  clear of it, and reports the signal when ffmpeg dies silently -- otherwise a
  long run ships an unredacted video that looks like a success.
- A long filter chain also blows the argv limit, so it goes to a file read with
  `-filter_complex_script`.
- The export filename carries a hash of the exact spans burned into it, so a
  changed box set cannot be served yesterday's video.

## Conventions

- Commit messages describe behaviour and why, not file lists.
- Comments explain constraints the code cannot show. No narration.
- Secrets live in `.env` (git-ignored). `.env.example` documents the keys.
