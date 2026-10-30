# Pane extraction boundary

VTE exposes rendered terminal state, not a lossless command transcript or a semantic scope tree. Keep emulator state, canonical command/output records and Pane presentation separate.

The pinned VTE 0.82.4 implementation in `src/vtegtk.cc` provides these established interfaces:

| Interface | Available information | Boundary |
| --------- | --------------------- | -------- |
| `get_text_format(TEXT/HTML)` | Visible terminal text, optionally rendered attributes | Viewport-dependent; cursor overwrites have already replaced bytes |
| `get_text_range_format` | Text in a row/column range and byte length | Cell coordinates are not canonical source offsets or stable scope identifiers |
| `get_text_selected_full` | Native selection as text/HTML | Selection is emulator-owned; not a structural command selection |
| `write_contents_sync` | Current terminal contents including retained scrollback | Synchronous, potentially blocks input; neither original stream nor complete history after eviction |
| Cursor and adjustment APIs | Grid/scroll position | Reflow, scrolling and alternate screens invalidate naïve external range maps |

The `/presentation/pane-extraction-fixture` test feeds a bounded nested-looking Unicode fixture, overwrites a progress line, extracts a row, switches alternate screens and resizes. It checks the current rendered text and restores the main screen without touching Composer source. Its indented child line is deliberately plain text: indentation does not prove semantic nesting. The test does not infer folds or command boundaries from colors, spacing or prompt text.

A production scope model needs explicit producer metadata: stable scope ID, parent ID, kind, source/output provenance, open/update/close events and retention policy. The host must associate authenticated command acceptance and completion with output before offering a command→response copy operation. Background output and cursor rewrites can cross command intervals; an interval alone is not a nested semantic tree. Canonical copying must either use retained producer records or clearly identify a rendered-terminal copy. Native selection and foreground program input remain usable alongside any structural interaction.

Use an emulator-owned extraction/notification hook for an alternate renderer only if it supplies coherent grid, damage, scroll/reflow, reset and alternate-screen lifetimes. A host surface cannot recover missing metadata from a screenshot or truncated replay tail. Keep any future semantic surface read-only with respect to the one VTE PTY/input/reply authority. A webview or another established emulator remains a backend option, not a consequence of this fixture.

[Graphics protocol feasibility](graphics-protocols.md) owns Kitty/ctx capabilities. Adding graphics or a richer rendering surface does not add semantic scope metadata. Folding, nested hover/copy and a replacement renderer require that additional contract; none is advertised by the extraction fixture.
