# V Composer

V Composer is a reusable GTK4/Vala text-input component intended as an alternative to readline-style editing, with editable Markdown presentation and basic fish highlighting. `src/editor.vala` owns the generic editor; `src/application.vala` is a demonstration host with an optional ClaudeVassal adapter and terminal shadow. The editor's tagged `Gtk.TextBuffer` retains Markdown source even when delimiters are hidden. Switching modes changes presentation only.

[Shadow Term](../shadow-terminal/README.md), the working implementation name for the general Pane role, embeds Composer as the normal interactive fish frontend. Its fish adapter owns readiness, source handoff and prompt/program focus; the generic editor owns no shell transport. A separate styled card displays accepted source beside the ordinary terminal screen. General routing remains tentative: Composer may supply text through Pane, or components may communicate directly with their counterpart or the shell. Independently of routing, Composer and Pane are an interaction layer over ordinary command and output streams; styling preserves those underlying streams. The executable and source paths below retain their existing names.

## Build and run

Build dependencies: Vala 0.56, a C compiler, Meson, Ninja, GTK ≥ 4.12, Granite ≥ 7.7, VTE's GTK4 library, and JSON-GLib. Nothing is installed by the build.

```fish
env VALAC=valac-0.56 meson setup build
nice -n 15 meson compile -C build -j 1
./build/vibrant-rich-input
```

If your compiler is named `valac`, omit `VALAC=valac-0.56`. Standalone mode opens only the editor. To use it with `cv`, run from the ClaudeVassal repository:

```fish
python3 shadow_terminal.py run --rich-input --gui ../Vibrant/rich-input/build/vibrant-rich-input
```

Omit `--rich-input` to retain fish input and use the window as a shadow display. The client can also attach separately with `./build/vibrant-rich-input --socket PATH`. See [[../../ClaudeVassal/SHADOW_PROTOCOL]] for launch options, messages, acknowledgement semantics, exact-source guarantees, and transport limits.

## Interaction

- Markdown mode styles ATX headings, `**bold**`, `*italic*`, inline backtick code, and fenced code. Inline delimiters are hidden away from the cursor's line; the current line reveals them for editing. Fenced code retains its markers. Unsupported Markdown remains source; this is not a CommonMark implementation.
- Show Source reveals all punctuation. Fish mode highlights a small lexical subset: keywords, quoted strings, comments, variables, and options. It neither executes code nor reproduces fish's parser, completions, command validation or history.
- Native selection, clipboard and undo remain GTK operations. In the CV demonstration host, Send or Ctrl+Enter sends the full source, including hidden characters, only when `cv` is ready; Enter inserts a newline. While a turn runs, drafts remain editable. Ctrl+Q closes that window. Shadow Term defines its own Run/Enter and shell-readiness behavior.
- Edit Last Prompt restores accepted source into an empty draft. It is disabled when a draft exists. Disconnection and rejection keep the draft and display feedback.
- In Markdown mode, the toolbar and Ctrl+B/Ctrl+I/Ctrl+grave toggle bold, italic and inline-code delimiters. An empty selection creates a pair with the cursor inside. These are explicit, undoable source edits, disabled in Fish mode. The editor also exposes source-aware literal search to its host; Shadow Term supplies its search bar.
- Ctrl+Space or Suggestions opens builtin help or Markdown snippets; hosts that supply a working directory also get local filename suggestions in Fish mode. Up/Down selects, Enter/Tab inserts, Escape dismisses. Selecting a suggestion edits the draft without submitting it. Draft edits, cursor moves, mode changes and directory changes invalidate outstanding results.

The [elementary HIG](https://docs.elementary.io/hig) informs the native controls, concise action labels, window title, keyboard access and feedback. [Always Provide an Undo](https://docs.elementary.io/hig/user-workflow/always-provide-an-undo) informs retaining GTK undo, and the [Gtk.TextBuffer.get_text documentation](https://docs.gtk.org/gtk4/method.TextBuffer.get_text.html) defines extraction with hidden characters included. Granite follows the desktop style preference; lexical colours have light and dark variants. Desktop theme contrast, screen-reader behavior, IME and real Wayland interaction require manual validation.

## Completion providers

`src/completion.vala` defines `VCom.CompletionContext`, `CompletionItem` and the asynchronous `CompletionProvider.complete(context, cancellable)` contract. The immutable context carries full source, cursor, mode and working directory. All edit ranges use Unicode character offsets, matching `Gtk.TextBuffer`; the syntax highlighter's `RichSpan` byte offsets are a separate boundary. `CompletionItem` carries a display label, literal replacement source and contextual description.

`src/assistance.vala` supplies `ComposerAssist`: attach its `panel` beside a `RichInput`, route input through `handle_key` before handling submission, and register additional providers with `add_provider`. Both demonstration and Shadow Term hosts use this controller. It checks source/cursor/mode/directory snapshots again before applying a candidate and groups the replacement as one undo action. Unmapping the editor cancels its request. Providers must honor cancellation; the consumer requests cancellation after 1.5 seconds and discards late results. No provider runs on each keystroke or in the background.

The builtin provider supplies a small static fish help catalog and Markdown snippets. The local-files provider asynchronously reads directory metadata, inspects at most 512 entries and returns at most 64 candidates. The controller displays at most 128 candidates per request. No file contents are read and no shell code is evaluated; complex current tokens are deliberately left to native editing. Directory traversal order can affect which names appear when these limits are reached. Future shell-aware or language-server providers can use the same snapshot/edit contract; those integrations are not implemented here. Source handoff and execution remain the consumer adapter's responsibility.

## Checks

On a test display, run `meson test -C build --print-errorlogs --num-processes 1`. The editor tests cover source round trips, hidden delimiters, Unicode offsets, undo, opaque code ranges and fish spans. The integration check requires Xvfb, xdotool, D-Bus, Python, fish, and a sibling ClaudeVassal checkout:

```fish
nice -n 15 python3 tests/integration.py --cv ../../ClaudeVassal
```

It creates a private Xvfb/D-Bus session using software rendering with D-Bus service activation disabled, drives the actual GTK editor, and verifies source in a stub Claude CLI's argv and the session cache, including recall and resubmission. It shuts down its own processes; it uses no live API or desktop windows. `--screenshot PATH` optionally captures the private test window and requires ImageMagick's `import`.
