# Graphics protocol feasibility

Production Shadow Term should retain VTE as the single terminal/PTY authority. The prepared VTE 0.82.4 source has no Kitty graphics or ctx vector implementation. Drawing a separate surface does not supply protocol parsing, placement lifetime or terminal replies. An opt-in emulator extension needs an explicit graphics-state contract before either protocol can be advertised.

## Pinned source evidence

In the prepared VTE tree, `src/parser.hh` sends APC strings into `ST_IGNORE`, and `src/parser-seq.py` has an empty APC sequence table. `src/modes.py` registers neither ctx mode 200 nor 7020. The existing SIXEL path in `src/vteseq.cc` does not establish support for either protocol. Shadow Term's private patch supplies presentation/state hooks, not a graphics decoder. These are source-audit findings; reference-protocol fidelity has not been established by running a Kitty renderer.

The ctx reference is [ctx 0.1.18](https://ctx.graphics/ctx-0.1.18.tar.bz2). Its downloaded archive has computed SHA-256 `5e22f1f983edda8f416c20b555e8da49c07ae9ecda0e69ad75146b990517b80c`; this identifies the inspected bytes, not an independently published checksum. In its `ctx.h`, the VT mode setter and query handler both use `case 200` for vector mode, creating line-owned drawlists and entering `vt_state_ctx`. This resolves framing for that release. The [protocol page](https://ctx.graphics/protocol/) also specifies 200, while the [terminal page](https://ctx.graphics/terminal/) says 7020; do not silently generalize the pinned result to every version.

The core header carries the ISC permission notice. Retain its notice and inspect the notices of enabled bundled dependencies/fonts when packaging an experiment; the core license label does not replace that inventory. The [SDK description](https://ctx.graphics/sdk/) identifies the single-header parser/rasterizer and its framebuffer API. The local fixture compiles that header directly and renders paths, text, a transform and a clip into a fixed 96×64 RGBA buffer, without a terminal or GUI backend. Its assertions establish nonempty drawing, an opaque interior and a clear outside pixel; they do not establish VT attachment, text shaping, protocol conformance or performance. The reference header emits a `strstr` macro-redefinition warning with this host compiler; no warning suppression is required to run the fixture.

| Capability                         | VTE 0.82.4 audit | Standalone ctx fixture |
| ---------------------------------- | ---------------- | ---------------------- |
| Kitty APC graphics dispatch        | Ignored          | Not exercised          |
| Kitty image/query/placement state  | Not implemented  | Not exercised          |
| ctx VT mode and line attachment    | Not registered   | Not exercised          |
| ctx path/text/transform/clip raster | Not integrated   | Fixed-buffer assertions pass |

## Bounded protocol experiments

[Kitty's protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/) uses APC graphics commands, base64 payloads, image/placement identities and terminal replies. A first extension can target direct RGB/RGBA transfer, query replies, chunk assembly, one cell-anchored placement and deletion. PNG decoding and decompression need independent decoded-size limits. File/shared-memory transfer, animation, relative/virtual placements and complete z-order behavior stay outside that experiment. The supplied fixtures cover a query followed by device attributes, inline RGBA, chunked transfer, deletion and malformed data. They describe producer input, not implemented Shadow Term support.

For ctx, begin with the pinned text parser and an in-memory raster surface. Associate the drawing context with an emulator-owned row/screen identity; retain drawlist/frame lifetime separately from its cached raster. Add framing only inside the emulator's parser, and specify reset, scrollback eviction, alternate-screen and resize behavior before attaching the surface. Interactive events, audio, uploads, sockets and compositor extensions are outside this rendering experiment. The [reference terminal](https://ctx.graphics/terminal/) documents a limited Kitty subset too; replacing VTE with it would not establish full Kitty compatibility.

Proposed experiment budgets are a 1 MiB vector frame, 4,096 operations, eight contexts, an 8 MiB decoded image and a shared 64 MiB retained-graphics ceiling. These are design limits to validate, not measured safe capacities. Reject oversize/invalid input before allocating the full representation; discard incomplete transfers on cancellation/reset. Bound retained placements and hidden animation work independently. Native selection, ordinary text/input, canonical copying, replies and resize remain emulator-owned.

## Backend decision

| Approach                         | Required boundary                                                       | Assessment |
| -------------------------------- | ----------------------------------------------------------------------- | ---------- |
| Extend private VTE               | Parser dispatch plus screen/row graphics state, replies and draw hooks    | Preserves current GTK/PTY ownership; substantial private-patch maintenance |
| VTE parser hook and host surface | Emulator owns framing/lifetime/placement; GTK draws explicit snapshots   | A possible rendering split, not an independent escape parser; still needs VTE changes |
| Another established emulator    | Revalidate source delivery, input/replies, selection, resize and graphics | A larger integration; choose only after subset/reference tests justify it |

An emulator hook is the smallest coherent experiment with the current host, but this is an architectural inference rather than a validated implementation. Reuse the ctx framebuffer renderer behind that boundary if its resource/fidelity tests pass. Keep production VTE and terminal identity unchanged until capability replies, malformed/fragmented input, scrolling/reflow, clipping, deletion, reset and alternate-screen tests establish a supported subset. A host-side parser racing VTE for the same bytes is excluded because it would split terminal authority.

## Reproduction

From `shadow-terminal/`, write binary producer fixtures to a fresh directory:

```fish
python3 tests/graphics/fixtures.py /tmp/shadow-graphics-fixtures
```

The generator writes files and a hash manifest, never terminal escape bytes to stdout. Feed those files only through an isolated emulator experiment. A query fixture is suitable for capturing capability replies; rendering fixtures require a selected reference backend. The generator refuses to overwrite existing files.

With the inspected SDK extracted separately:

```fish
set ctx_sdk /path/to/ctx-0.1.18
nice -n 15 cc -O0 -I"$ctx_sdk" tests/graphics/ctx-render-fixture.c -lm -o /tmp/shadow-ctx-fixture
/tmp/shadow-ctx-fixture
```

The fixture prints pixel evidence and exits nonzero on failure. It adds no runtime dependency to Shadow Term and installs nothing. Full Kitty reference rendering, emulator graphics-state integration and native desktop behavior remain separate experiments.
