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

**Do not run `by llm()` calls concurrently.** Fanning them out with `flow`
returns the *same* answer for every call in the batch. Measured directly:
seven frames run one at a time gave seven different correct answers; the same
seven in batches of four gave one answer per batch, repeated. Nothing raises,
the shapes are right, and the results are quietly wrong -- for this pipeline
that means confidently redacting the wrong words. Textract calls under `flow`
are fine (that is the 11x win in the OCR pass), so this is specific to byLLM.
The boundary is not fully characterised: the same fan-out from a module-level
`with entry` did return distinct answers. Until that is understood, model
calls stay sequential.

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
  then wait; a `wait` inside the launch loop serializes it. This is an 11x
  speedup on Textract.
- A walker that never `visit`s should be a `def:pub` function instead.

## Media notes

- Screen recordings often carry non-full-range YUV, which the mjpeg encoder
  rejects. The extract filter chain normalizes with `format=yuvj420p`.
- Box geometry is stored in box_2d order `[y0, x0, y1, x1]` on a 0..1000 scale,
  normalized against the frame. Convert to pixels only at export. This is the
  easiest thing in the project to get wrong.

## Conventions

- Commit messages describe behaviour and why, not file lists.
- Comments explain constraints the code cannot show. No narration.
- Secrets live in `.env` (git-ignored). `.env.example` documents the keys.
