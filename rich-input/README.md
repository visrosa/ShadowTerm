# V Composer

V Composer is a reusable GTK4/Vala text-input component intended as an alternative to readline-style editing, with editable Markdown presentation and basic fish highlighting. `src/editor.vala` owns the generic editor; `src/application.vala` is a demonstration host with an optional ClaudeVassal adapter and terminal shadow. The editor's tagged `Gtk.TextBuffer` retains Markdown source even when delimiters are hidden. Switching modes changes presentation only.

[Shadow Term](../shadow-terminal/README.md), the working implementation name for the general Pane role, embeds Composer as the normal interactive fish frontend. Its fish adapter owns readiness, source handoff and prompt/program focus; the generic editor owns no shell transport. Its Composer options provide a collapsed styled Last Input disclosure. Shadow Term owns its compact layout, prompt replacement, contextual menus and optional live Pane-style inheritance; the reusable editor remains independent of those host choices. General routing remains tentative: Composer may supply text through Pane, or components may communicate directly with their counterpart or the shell. Independently of routing, Composer and Pane are an interaction layer over ordinary command and output streams; styling preserves those underlying streams. The executable and source paths below retain their existing names.

## Build and run

Build dependencies: Vala 0.56, a C compiler, Meson, Ninja, GTK ≥ 4.12, Granite ≥ 7.7, VTE's GTK4 library, and JSON-GLib. Nothing is installed by the build.

```fish
env VALAC=valac-0.56 meson setup build
nice -n 15 meson compile -C build -j 1
./build/vibrant-rich-input
```

If your compiler is named `valac`, omit `VALAC=valac-0.56`. Standalone mode opens only the editor. To use it with `cv`, run from the ClaudeVassal repository:

```fish
python3 shadow_terminal.py run --rich-input --gui ../ShadowTerm/rich-input/build/vibrant-rich-input
```

Omit `--rich-input` to retain fish input and use the window as a shadow display. The client can also attach separately with `./build/vibrant-rich-input --socket PATH`. See the [ClaudeVassal shadow protocol](../../ClaudeVassal/SHADOW_PROTOCOL.md) in the optional sibling checkout for launch options, messages, acknowledgement semantics, exact-source guarantees, and transport limits.

## Interaction

- Markdown mode styles ATX headings, `**bold**`, `*italic*`, inline backtick code, and fenced code. Inline delimiters are hidden away from the cursor's line; the current line reveals them for editing. Fenced code retains its markers. Unsupported Markdown remains source; this is not a CommonMark implementation.
- Show Source reveals all punctuation. Fish mode highlights a small lexical subset: keywords, quoted strings, comments, variables, and options. The generic widget does not execute code or reproduce fish’s parser, completions, validation or history. Shadow Term adds host-owned fish completion, static abbreviations and advisory live diagnostics without changing this widget’s source contract.
- Native selection, clipboard and undo remain GTK operations. In the CV demonstration host, Send or Ctrl+Enter sends the full source, including hidden characters, only when `cv` is ready; Enter inserts a newline. While a turn runs, drafts remain editable. Ctrl+Q closes that window. Shadow Term defines its own Send/Enter and shell-readiness behavior.
- Edit Last Prompt restores accepted source into an empty draft. It is disabled when a draft exists. Disconnection and rejection keep the draft and display feedback.
- In Markdown mode, the toolbar and Ctrl+B/Ctrl+I/Ctrl+grave toggle bold, italic and inline-code delimiters. An empty selection creates a pair with the cursor inside. These are explicit, undoable source edits, disabled in Fish mode. The editor also exposes source-aware literal search to its host; Shadow Term supplies its search bar.
- Ctrl+Space or Suggestions opens builtin help or Markdown snippets; hosts that supply a working directory also get local filename suggestions in Fish mode. Up/Down selects, Enter/Tab inserts, Escape dismisses. Selecting a suggestion edits the draft without submitting it. Draft edits, cursor moves, mode changes and directory changes invalidate outstanding results.

The [elementary HIG](https://docs.elementary.io/hig) informs the native controls, concise action labels, window title, keyboard access and feedback. [Always Provide an Undo](https://docs.elementary.io/hig/user-workflow/always-provide-an-undo) informs retaining GTK undo, and the [Gtk.TextBuffer.get_text documentation](https://docs.gtk.org/gtk4/method.TextBuffer.get_text.html) defines extraction with hidden characters included. Granite follows the desktop style preference; lexical colours have light and dark variants. Desktop theme contrast, screen-reader behavior, IME and real Wayland interaction require manual validation.

## Completion providers

`src/completion.vala` defines `VCom.CompletionContext`, `CompletionItem` and the asynchronous `CompletionProvider.complete(context, cancellable)` contract. The immutable context carries full source, cursor, mode and working directory. All edit ranges use Unicode character offsets, matching `Gtk.TextBuffer`; the syntax highlighter's `RichSpan` byte offsets are a separate boundary. `CompletionItem` carries a display label, literal replacement source, contextual description and optional character-offset cursor position within the insertion. Providers can implement synchronous `expand(context)` for snapshotted abbreviations; accepting either kind of edit preserves undo. `CompletionContext.literal` and `query_safe` distinguish quote-aware literal tokens from unsupported expansions and command-substitution queries; the default local provider still requires simple tokens.

Providers can override `complete_batch` to return `CompletionBatch` with complete, truncated, unknown, unavailable or failed state. Legacy arrays are treated as having unknown completeness and cannot justify unique insertion. Candidates optionally carry stable identity, kind/group/provenance, continuation and preview metadata. An authoritative batch stops later fallback providers. `preview(context, item, cancellable)` supplies selected-only content; its default returns the description. Hosts can connect `open_preview(title, text)` to promote that content without adding submission authority.

`src/assistance.vala` supplies `ComposerAssist`: construct it with a `RichInput`, route input through `handle_key` before handling submission, and register additional providers with `add_provider`. Its `panel` is a nonmodal, caret-anchored `Gtk.Popover` parented to the editor; do not append it to the host layout. Each candidate shows its description, with full labels/descriptions available as tooltips when clipped. The popup bounds its width to the host and scrolls long lists without resizing the editor or surrounding content. Keyboard focus stays in the editor except during explicit filtering. Edits within the same argument refresh the open session; Escape, context/cursor changes, editor scrolling, external focus loss or unmapping dismiss it. Ctrl+F filters labels/descriptions separately from source. `RichInput` unparents popup accessories during disposal. Both demonstration and Shadow Term hosts use this controller. It checks source/cursor/mode/directory snapshots again before applying a candidate and groups the replacement as one undo action. Unmapping the editor cancels its request. Providers must honor cancellation; the consumer requests cancellation after 1.5 seconds and discards late results. Completion providers remain on demand. Shadow Term separately schedules bounded newest-draft syntax/path analysis after settled edits, with cancellation and readiness checks.

The builtin provider supplies a small static fish help catalog and Markdown snippets. The local-files provider asynchronously reads directory metadata, inspects at most 512 entries and returns at most 64 candidates. The controller displays at most 128 candidates per request. The default providers read metadata only and evaluate no shell code; complex current tokens are deliberately left to native editing. Directory traversal order can affect which names appear when these limits are reached. Shadow Term’s fish provider uses the same snapshot/edit contract. It is separate from these default standalone providers; language-server integrations can follow that contract. Source handoff and execution remain the consumer adapter's responsibility.

## Checks

The completion model suite can run without a display: `meson test -C build completion --print-errorlogs --num-processes 1`. The `editor` suite is graphical; run it only on a private test display/bus. Shadow Term's build includes the same editor tests, and its [integration harness](../shadow-terminal/README.md#verification-and-limits) runs them with disposable XDG state, history and Compose data. It is the preferred shared-widget check. The editor tests cover source round trips, hidden delimiters, Unicode offsets, undo, opaque code ranges and fish spans.

The separate CV demonstration check requires Xvfb, xdotool, D-Bus, Python, fish, a built standalone demo and a sibling ClaudeVassal checkout. The harness redirects configuration, data, cache and state to temporary directories, overrides inherited fish history and provides a synthetic GTK Compose table. It verifies an actual fish-history write in that namespace.

```fish
nice -n 15 python3 tests/integration.py --cv ../../ClaudeVassal
```

It creates a private Xvfb/D-Bus session using software rendering with D-Bus service activation disabled, drives the actual GTK editor, and verifies source in a stub Claude CLI's argv and the session cache, including recall and resubmission. It shuts down its own processes and uses no live API or desktop windows. `--screenshot PATH` optionally captures the private test window and requires ImageMagick's `import`.
