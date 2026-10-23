# Shadow Term

Shadow Term 0.0.3 is a GTK4/Vala terminal host for an interactive shell or any terminal command. [V Composer](../rich-input/README.md) is the normal input frontend for interactive fish; foreground programs receive ordinary terminal input. Each window owns a VTE emulator and PTY, including terminal replies, alternate-screen programs and resizing. It does not require ClaudeVassal, Kitty or layer-shell.

## Build and launch

Dependencies: Vala 0.56, Meson, Ninja, a C compiler, GTK ≥ 4.12, Granite ≥ 7.7, VTE GTK4 ≥ 0.78 and JSON-GLib. GTK's X11 backend and Xlib are optional build dependencies for automatic positioning. Run from this directory:

```fish
env VALAC=valac-0.56 meson setup build
nice -n 15 meson compile -C build -j 1
./build/shadow-term
```

If the compiler is named `valac`, omit `VALAC=valac-0.56`. The build installs nothing. The terminal launches `$SHELL`, falling back to `/bin/sh`, in the invoking directory. Shell startup configuration works normally. Keep the source tree and build directory in place: the executable uses their fish adapter and helper paths. `--help` and `--version` work without a display.

```fish
# A separate shell session, with a preferred initial size in logical pixels.
./build/shadow-term --session work --cwd ~/Homework --size 1100x750

# Explicitly select Composer with fish, regardless of $SHELL.
./build/shadow-term --session composer --input composer -- fish

# Use the shell's native terminal editor instead.
./build/shadow-term --session native --input terminal -- fish

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

Toggle hides a focused window and presents a hidden or unfocused one. Hide retains the child process, terminal state and Composer draft. Closing a window, Ctrl+Shift+W or `--quit` ends that session and signals its child/foreground process groups; normal child exit closes its window unless `--hold` was selected. Other sessions remain running. `--list` prints session name, visibility and child PID; zero indicates a launch failure or an exited held command. A spawn failure stays visible with a Restart action.

For a taskittyUI-style launcher, point a desktop shortcut at a named command session:

```fish
./build/shadow-term --session tasks --toggle --hide-on-focus-loss -- /path/to/tasklineUI
```

Build the complete tasklineUI package once; do not compile it on every toggle. Identical launch options can be repeated to control an existing session. Conflicting launch options produce an error instead of silently replacing a running command. Hide-on-focus-loss is armed only after actual activation; an activation request denied by the compositor leaves the window visible. Focus moves into this application's transient dialogs do not hide the parent. Global shortcut registration is left to the desktop.

Initial sizing is constrained to available monitor geometry. User size is saved per session under `$XDG_STATE_HOME/shadow-term/geometry.ini` (normally `~/.local/state/shadow-term/geometry.ini`). X11 builds can center new windows and restore their position; native Wayland placement follows compositor policy. Showing an existing window preserves its geometry. Window-manager rules can override placement requests.

## Composer and terminal input

With the default `--input auto`, an interactive fish session opens Composer in Fish mode and focuses it at each prompt. `--input composer` requires interactive fish; `--input terminal` disables the adapter. Other shells, fish scripts and `fish -c` use ordinary VTE input. Markdown/Fish chooses presentation only; commands still follow fish syntax.

- Enter submits the full draft. Shift+Enter inserts a line; Ctrl+Enter or Run submits without automatically adding a line when fish reports incomplete syntax.
- An incomplete Enter submission stays editable and gains a line. Invalid syntax, a nonempty native fish buffer, cancellation or a three-second handoff timeout retain the draft. Cancel or Escape cancels a pending handoff; an accepted command has already been handed to fish.
- Accepted input appears in a read-only, styled Last input card above the terminal. The unchanged submitted draft clears; edits made while acceptance was pending remain. Recall Last or Ctrl+Shift+L restores accepted source into an empty draft.
- While a command runs, focus moves to VTE for its stdin, control keys and terminal interaction. At the next fish prompt, Composer regains focus if visible. Its draft remains editable while programs run, but Run is disabled.
- V Composer or Ctrl+Shift+M toggles the editor. Hide it to use native fish editing, history or completions. A partial native command must be finished or cleared before Composer can submit.

The adapter is sourced through the launched fish process's `--init-command`; it changes no configuration files. It reserves Ctrl+Alt+O in that process's default and insert binding modes for the source handoff. Nested fish sessions use native input. User startup code that later replaces this binding or removes the event functions can disable the adapter; native terminal input remains available.

Composer retains canonical UTF-8 source, including hidden Markdown delimiters and trailing newlines. Each submission is limited to 65,536 bytes. `input-session.vala` tracks readiness and one pending handoff. A local D-Bus bridge and GIO-only `vcom-shell` helper transfer source with per-spawn identity and one-use retrieval. The PTY carries only the binding's key sequence; fish sets its ordinary commandline buffer, validates syntax and invokes its native execute action. Transport code never evaluates or shell-quotes the source. Prompt and preexec events report state; no background polling is needed.

The Last input card styles the accepted source separately from VTE's unchanged terminal screen. Fish still echoes and executes its ordinary commandline, and program output is not rewritten. This adapter is one concrete Composer/Pane/shell arrangement; the general component routing remains replaceable.

Terminal controls and explicit source paste remain available in every mode:

- Ctrl+Shift+N creates a terminal; Ctrl+Shift+H hides the current one.
- Ctrl+Shift+C copies terminal selection; Ctrl+Shift+V pastes the clipboard. Ctrl+C remains the terminal's interrupt key.
- Ctrl+Shift+Plus/Minus zoom; Ctrl+Shift+0 resets font size. Mouse selection and scrolling are VTE operations.
- Show Source reveals hidden markup in the [shared rich editor](../rich-input/README.md). The draft survives hide/show.
- Paste into Terminal or Ctrl+Shift+Enter pastes the scratchpad's canonical source, including hidden delimiters, without clearing it or appending Enter. Ctrl+Shift+C in the scratchpad copies selected source including hidden characters; ordinary editor Ctrl+C retains GTK's visible-text behavior.

[VTE's paste operation](https://gnome.pages.gitlab.gnome.org/vte/gtk4/method.Terminal.paste_text.html) uses bracketed paste when the child enables it. The running program determines paste semantics: multiline text can execute in shells without bracketed-paste support. Explicit paste is separate from Run's fish source handoff and ClaudeVassal's prompt-to-argv/cache protocol. Keyboard shortcuts work in the terminal and editor; GTK's normal clipboard and undo keys remain available in Composer.

## Appearance, search and suggestions

Preferences (the header gear or Ctrl+,) changes the terminal and Composer fonts, terminal background opacity (0–100%) and scrollback limit (100–100,000 lines). Font sizes accept 6–72 points/pixels. Changes apply across open sessions and are saved under `$XDG_CONFIG_HOME/shadow-term/preferences.ini`; Restore Defaults resets them. Slider motion is coalesced before saving, and closing flushes any pending change. Only the terminal background becomes transparent; controls and text remain opaque. Actual blending depends on compositor support.

Ctrl+Shift+F opens literal terminal search; Ctrl+F while editing searches Composer source, including hidden delimiters. The search bar also lets you choose the target. Enter finds the next match, Shift+Enter finds the previous one, and Escape closes the bar. Search is case insensitive and wraps. It never alters the source or sends search text to the child process.

In Markdown mode, Ctrl+B and Ctrl+I toggle bold and italic delimiters around the selection; Ctrl+grave toggles inline code. The formatting buttons expose the same actions. An empty selection inserts a delimiter pair with the cursor inside it. Each action is one undoable source edit. These actions are disabled in Fish mode so a formatting shortcut cannot silently rewrite a shell command. Preview support remains the [editor's documented Markdown subset](../rich-input/README.md#interaction).

Ctrl+Space or Suggestions opens an on-demand candidate list with contextual descriptions. Up/Down changes selection; Enter or Tab inserts the selected candidate, and Escape dismisses the panel. Insertion is one undoable edit and never executes the command; press Enter again after editing to run it. Typing or moving the cursor invalidates the old results. While providers are working, Enter/Tab do not submit the partial command.

The first providers offer a small fish builtin/keyword help catalog, Markdown snippets and local filename completion. For example, `pri` suggests `printf`, and `cat ./Doc` can complete a local name. Filenames containing spaces, quotes, backslashes or Unicode are inserted as literal fish arguments. The shell-reported working directory supplies the lookup base. Only simple unquoted tokens are handled; quoted/escaped tokens and variable expressions retain native editing as a fallback. These providers do not invoke fish completion functions or commands. Functions, aliases, options, full fish history/completion and language-server integration remain separate extensions to the [provider interface](../rich-input/README.md#completion-providers).

## Verification and limits

```fish
nice -n 15 meson test -C build --no-rebuild --num-processes 1 --print-errorlogs
nice -n 15 python3 tests/integration.py
nice -n 15 python3 tests/integration.py --frontend
```

The integration checks require Python, fish, Xvfb, xdotool and D-Bus; the frontend check also uses PyGObject with GTK4 for exact Unicode clipboard input. They use a private software-X11 display, synthetic fish configuration and a private bus with service activation disabled. The baseline checks shell input, argv/cwd/environment, interrupts, PTY resize, process reuse, source/clipboard paste, focus/hide and child cleanup. The frontend check covers builtin/quoted-filename completion, literal terminal search, preferences access, Unicode and multiline argv, shell status, pipelines, incomplete syntax, recall, occupied native buffers, foreground stdin/interrupt, nested fish, concurrent draft edits, cancellation and timeout recovery. Editor/appearance checks also exercise formatting undo, source-aware search, stale provider results, and preference persistence. They do not write real Taskwarrior data or use desktop windows. Test processes are cleaned up.

The existing [CV shadow client](../rich-input/README.md) remains available independently. Composer supplies basic fish highlighting and the bounded suggestions above; full fish completion/history UI and syntax-highlighting parity are outside this version. Native editing remains reachable. This version provides authoritative command sessions; it does not capture/reparent another emulator's window or clone a running external terminal. Multiple views of one PTY, detach/reattach, a public raw-stream subscription API, arbitrary programmatic overlays/modals, desktop docking and Kitty image/text-sizing parity are separate extensions. In particular, tasklineUI's Kitty OSC 66 labels need a rendering compatibility check before assuming identical appearance. Native Wayland focus/placement, IME and assistive-technology behavior require actual-desktop validation; isolated X11 checks do not establish those properties.
