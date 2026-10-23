# Shadow Term

Shadow Term 0.0.1 is a GTK4/Vala terminal host for an interactive shell or any terminal command. Each window owns a VTE emulator and PTY, including keyboard input, terminal replies, alternate-screen programs and resizing. It does not require ClaudeVassal, Kitty or layer-shell.

## Build and launch

Dependencies: Vala 0.56, Meson, Ninja, a C compiler, GTK ≥ 4.12, Granite ≥ 7.7, VTE GTK4 ≥ 0.78 and JSON-GLib. GTK's X11 backend and Xlib are optional build dependencies for automatic positioning. Run from this directory:

```fish
env VALAC=valac-0.56 meson setup build
nice -n 15 meson compile -C build -j 1
./build/shadow-term
```

If the compiler is named `valac`, omit `VALAC=valac-0.56`. The build installs nothing. The terminal launches `$SHELL`, falling back to `/bin/sh`, in the invoking directory. Shell startup configuration works normally. `--help` and `--version` work without a display.

```fish
# A separate shell session, with a preferred initial size in logical pixels.
./build/shadow-term --session work --cwd ~/Homework --size 1100x750

# An arbitrary command, with literal arguments after --.
./build/shadow-term --session monitor -- top

# Retain output and offer Restart when a short command exits.
./build/shadow-term --session listing --hold -- ls -la
```

One application process manages named sessions through the local session bus. The first invocation stays running while it owns sessions; subsequent invocations return after applying their request. Use `&` when launching from a shell that you want to keep using. Repeating the default invocation shows the existing `default` session; choose another name or use New Terminal for another PTY.

## Persistent and quick-access sessions

```fish
./build/shadow-term --session work --hide
./build/shadow-term --session work --show
./build/shadow-term --session work --toggle
./build/shadow-term --list
./build/shadow-term --session work --quit
```

Toggle hides a focused window and presents a hidden or unfocused one. Hide retains the child process, terminal state and scratchpad. Closing a window, Ctrl+Shift+W or `--quit` ends that session and signals its child/foreground process groups; normal child exit closes its window unless `--hold` was selected. Other sessions remain running. `--list` prints session name, visibility and child PID; zero indicates a launch failure or an exited held command. A spawn failure stays visible with a Restart action.

For a taskittyUI-style launcher, point a desktop shortcut at a named command session:

```fish
./build/shadow-term --session tasks --toggle --hide-on-focus-loss -- /path/to/tasklineUI
```

Build the complete tasklineUI package once; do not compile it on every toggle. Identical launch options can be repeated to control an existing session. Conflicting launch options produce an error instead of silently replacing a running command. Hide-on-focus-loss is armed only after actual activation; an activation request denied by the compositor leaves the window visible. Focus moves into this application's transient dialogs do not hide the parent. Global shortcut registration is left to the desktop.

Initial sizing is constrained to available monitor geometry. User size is saved per session under `$XDG_STATE_HOME/shadow-term/geometry.ini` (normally `~/.local/state/shadow-term/geometry.ini`). X11 builds can center new windows and restore their position; native Wayland placement follows compositor policy. Showing an existing window preserves its geometry. Window-manager rules can override placement requests.

## Terminal and rich scratchpad

- Ctrl+Shift+N creates a terminal; Ctrl+Shift+H hides the current one.
- Ctrl+Shift+C copies terminal selection; Ctrl+Shift+V pastes the clipboard. Ctrl+C remains the terminal's interrupt key.
- Ctrl+Shift+Plus/Minus zoom; Ctrl+Shift+0 resets font size. Mouse selection and scrolling are VTE operations.
- Compose or Ctrl+Shift+M opens a Markdown/fish scratchpad using the [shared rich editor](../rich-input/README.md). Show Source reveals hidden markup. The draft survives hide/show.
- Paste into Terminal or Ctrl+Shift+Enter pastes the scratchpad's canonical source, including hidden delimiters, without clearing it or appending Enter. Ctrl+Shift+C in the scratchpad copies selected source including hidden characters; ordinary editor Ctrl+C retains GTK's visible-text behavior.

[VTE's paste operation](https://gnome.pages.gitlab.gnome.org/vte/gtk4/method.Terminal.paste_text.html) uses bracketed paste when the child enables it. The running program determines paste semantics: multiline text can execute in shells without bracketed-paste support. This is a terminal paste operation, separate from ClaudeVassal's exact prompt-to-argv/cache protocol. Keyboard shortcuts work in the terminal and scratchpad; GTK's normal clipboard and undo keys remain available in the editor.

## Verification and limits

```fish
nice -n 15 meson test -C build --num-processes 1 --print-errorlogs
nice -n 15 python3 tests/integration.py
```

The integration check requires Python, fish, Xvfb, xdotool and D-Bus. It uses a private software-X11 display and a private bus with service activation disabled. It checks real shell input, argv/cwd/environment, interrupt handling, PTY resize, process reuse, rich-source and clipboard paste, focus/hide and child cleanup. It does not write real Taskwarrior data or use desktop windows. Test processes are cleaned up.

The existing [CV shadow client](../rich-input/README.md) remains available independently. This version provides authoritative command sessions; it does not capture/reparent another emulator's window or clone a running external terminal. Multiple views of one PTY, detach/reattach, a public raw-stream subscription API, arbitrary programmatic overlays/modals, desktop docking and Kitty image/text-sizing parity are separate extensions. In particular, tasklineUI's Kitty OSC 66 labels need a rendering compatibility check before assuming identical appearance. Native Wayland focus/placement, IME and assistive-technology behavior require actual-desktop validation; isolated X11 checks do not establish those properties.
