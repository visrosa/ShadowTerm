# V Composer

V Composer is a reusable GTK4/Vala text-input component intended as an alternative to readline-style editing, with editable Markdown presentation and basic fish highlighting. `src/editor.vala` owns the generic editor; `src/application.vala` is a demonstration host with an optional ClaudeVassal adapter and terminal shadow. The editor's tagged `Gtk.TextBuffer` retains Markdown source even when delimiters are hidden. Switching modes changes presentation only.

[Shadow Term](../shadow-terminal/README.md), the working implementation name for the general Pane role, currently embeds the editor with an explicit paste action. Future routing is tentative: Composer may supply text through Pane, or components may communicate directly with their counterpart or the shell. Substituting Composer for a shell's line editor requires editing/session integration appropriate to that design. Independently of routing, Composer and Pane are an interaction layer over ordinary command and output streams; styling preserves those underlying streams. The executable and source paths below retain their existing names.

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
- Native selection, clipboard and undo remain GTK operations. Send or Ctrl+Enter sends the full source, including hidden characters, only when `cv` is ready. Enter inserts a newline. While a turn runs, drafts remain editable. Ctrl+Q closes the window.
- Edit Last Prompt restores accepted source into an empty draft. It is disabled when a draft exists. Disconnection and rejection keep the draft and display feedback.

The [elementary HIG](https://docs.elementary.io/hig) informs the native controls, concise action labels, window title, keyboard access and feedback. [Always Provide an Undo](https://docs.elementary.io/hig/user-workflow/always-provide-an-undo) informs retaining GTK undo, and the [Gtk.TextBuffer.get_text documentation](https://docs.gtk.org/gtk4/method.TextBuffer.get_text.html) defines extraction with hidden characters included. Granite follows the desktop style preference; lexical colours have light and dark variants. Desktop theme contrast, screen-reader behavior, IME and real Wayland interaction require manual validation.

## Checks

On a test display, run `meson test -C build --print-errorlogs --num-processes 1`. The editor tests cover source round trips, hidden delimiters, Unicode offsets, undo, opaque code ranges and fish spans. The integration check requires Xvfb, xdotool, D-Bus, Python, fish, and a sibling ClaudeVassal checkout:

```fish
nice -n 15 python3 tests/integration.py --cv ../../ClaudeVassal
```

It creates a private Xvfb/D-Bus session using software rendering with D-Bus service activation disabled, drives the actual GTK editor, and verifies source in a stub Claude CLI's argv and the session cache, including recall and resubmission. It shuts down its own processes; it uses no live API or desktop windows. `--screenshot PATH` optionally captures the private test window and requires ImageMagick's `import`.
