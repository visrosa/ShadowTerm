# Shadow Term

Shadow Term 0.0.6 is a GTK4/Vala terminal host for an interactive shell or any terminal command. [V Composer](../rich-input/README.md) is the normal input frontend for interactive fish; foreground programs receive ordinary terminal input. Each tab owns a VTE emulator and PTY, including terminal replies, alternate-screen programs and resizing; a window arranges independent tabs in its headerbar. It does not require ClaudeVassal, Kitty or layer-shell.

## Build and launch

Dependencies: Vala 0.56, Meson, Ninja, a C compiler, GTK ≥ 4.12, Granite ≥ 7.7, VTE GTK4 ≥ 0.78, PCRE2 headers and JSON-GLib. GTK's X11 backend and Xlib are optional build dependencies for automatic positioning. Run from this directory:

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

One application process manages named sessions through the local session bus. The first invocation stays running while it owns sessions; subsequent invocations return after applying their request. Use `&` when launching from a shell that you want to keep using. Repeating the default invocation shows the existing `default` session; choose another name for a separate window, or use the header’s + button / New Tab for another PTY in the same window.

## Persistent and quick-access sessions

```fish
./build/shadow-term --session work --hide
./build/shadow-term --session work --show
./build/shadow-term --session work --toggle
./build/shadow-term --list
./build/shadow-term --session work --quit
```

Toggle hides a focused window or selects and presents the requested tab when it is hidden, in the background or unfocused. Hide retains all tabs, child processes, terminal states and Composer drafts in that window. Ctrl+Shift+W, the tab’s close button or `--quit` ends only that session and signals its child/foreground process groups. Closing a window or Ctrl+Shift+Q ends all its tabs; normal child exit closes only its tab unless `--hold` was selected. The last tab closes its window. Other windows remain running. `--list` prints session name, visibility and child PID; only a window’s selected, presented tab is reported as visible; zero indicates a launch failure or an exited held command. A spawn failure stays visible with a Restart action.

For a taskittyUI-style launcher, point a desktop shortcut at a named command session:

```fish
./build/shadow-term --session tasks --toggle --hide-on-focus-loss -- /path/to/tasklineUI
```

Build the complete tasklineUI package once; do not compile it on every toggle. Identical launch options can be repeated to control an existing session. Conflicting launch options produce an error instead of silently replacing a running command. Hide-on-focus-loss is armed only after actual activation; an activation request denied by the compositor leaves the window visible. Focus moves into this application's transient dialogs do not hide the parent. Global shortcut registration is left to the desktop.

Initial sizing is constrained to available monitor geometry. User size is saved under the window’s first-session identity in `$XDG_STATE_HOME/shadow-term/geometry.ini` (normally `~/.local/state/shadow-term/geometry.ini`). X11 builds can center new windows and restore their position; native Wayland placement follows compositor policy. Showing an existing window preserves its geometry. Window-manager rules can override placement requests.

## Composer and terminal input

With the default `--input auto`, an interactive fish session opens Composer in Fish mode and focuses it at each prompt. `--input composer` requires interactive fish; `--input terminal` disables the adapter. Other shells, fish scripts and `fish -c` use ordinary VTE input. Markdown/Fish chooses presentation only; commands still follow fish syntax.

- Enter submits the full draft. Shift+Enter inserts a line; Ctrl+Enter or Run submits without automatically adding a line when fish reports incomplete syntax.
- An incomplete Enter submission stays editable and gains a line. Invalid syntax, a nonempty native fish buffer, cancellation or a three-second handoff timeout retain the draft. Cancel or Escape cancels a pending handoff; an accepted command has already been handed to fish.
- The unchanged submitted draft clears; edits made while acceptance was pending remain. Composer Options contains a collapsed, read-only Last Input disclosure. Recall Last Input or Ctrl+Shift+L restores accepted source into an empty draft.
- While a command runs, focus moves to VTE for its stdin, control keys and terminal interaction. At the next fish prompt, Composer regains focus if visible. Composer collapses while VTE reports an alternate screen, preserving its draft and enabled preference. An explicit V Composer toggle can show it there until the next screen transition. Ordinary foreground readers, including CV, retain the editor. Their Run control becomes Paste: Ctrl+Enter or Ctrl+Shift+Enter pastes canonical source without adding Enter, then focuses the terminal; the program’s own input controls accept it. Enter inside this foreground editor adds a line. Shell abbreviations and diagnostics pause outside shell-command readiness. This screen-state notification comes from the private VTE build below, without another escape-sequence parser.
- V Composer or Ctrl+Shift+M toggles the editor. Hide it to use native fish editing, history or completions. A partial native command must be finished or cleared before Composer can submit.

The adapter is sourced through the launched fish process's `--init-command`; it changes no configuration files. It reserves Ctrl+Alt+O for source handoff and Ctrl+Alt+P for prompt presentation in that process's default and insert binding modes. It saves the existing left/right prompt functions and skips their drawing while Composer is active. Hiding Composer restores those functions, including their shell-status context, and repaints without changing a partial native input buffer. Prompt functions and their side effects do not run while suppressed. This intentionally replaces shell prompt emission; command source and program output are not filtered. Presentation changes wait for prompt readiness before sending any control binding, so foreground programs receive none of these control sequences. Nested fish sessions use native input. Code that later replaces the private bindings, prompt wrappers or event functions can disable the adapter; native terminal input remains available.

Composer retains canonical UTF-8 source, including hidden Markdown delimiters and trailing newlines. Each submission is limited to 65,536 bytes. `input-session.vala` tracks readiness and one pending handoff. A local D-Bus bridge and GIO-only `vcom-shell` helper transfer source with per-spawn identity and one-use retrieval. The PTY carries only the binding's key sequence; fish sets its ordinary commandline buffer, validates syntax and invokes its native execute action. Transport code never evaluates or shell-quotes the source. Prompt and preexec events report state; no background polling is needed.

Last Input styles accepted source separately from VTE's terminal screen. Fish still echoes and executes its ordinary commandline, and program output is not rewritten. This adapter is one concrete Composer/Pane/shell arrangement; general routing and shell-independent submission remain separate design work.

## Workspace and contextual controls

The header contains a horizontally scrollable tab strip, + (New Tab) and Terminal Options. Each tab retains its own shell, current directory, terminal contents, Composer draft and input state. New tabs start a fresh configured shell in the active tab’s directory; switching tabs never restarts a shell. The selected tab scrolls into view when necessary. The header follows Pane styling when Inherit Pane Style is enabled, without a bottom separator. Search, Composer visibility, preferences, shortcut help and session actions live in Terminal Options. Composer grows from a compact prompt to a bounded multiline input. Its options menu contains presentation mode, Markdown source/formatting, suggestions, recall, search, explicit terminal paste and Last Input. Run appears for a nonempty shell draft; Cancel appears only during a pending submission. The status strip appears for pending input, errors and held exits rather than repeating prompt instructions. This follows the elementary HIG's guidance on [contextual controls](https://docs.elementary.io/hig/widgets/avoid-widgets-that-do-nothing) and [tool ordering](https://docs.elementary.io/hig/widgets/creating-layouts); visible menus and shortcut labels preserve discovery.

The Composer context row displays the shell-reported working directory and, when available, Git branch and changed-entry count. Detached HEAD and unborn branches are supported. The tooltip includes upstream status from Git's branch header. It refreshes at prompt notifications/directory changes or through Refresh Repository; no idle polling or indexing runs. Git status is asynchronous, uses literal argv without optional locks or external fsmonitor, ignores submodule contents, and is bounded to 1.5 seconds/64 KiB. A count is Git status entries, not changed lines. Nonrepositories, unavailable Git and failed/oversized/timed-out results leave the repository label empty; stale results are discarded. This is advisory context, independent of command execution.

Keyboard Shortcuts is available from Terminal Options, or F1 while editing Composer. Page Up/Page Down while editing Composer scroll the Pane; within suggestions they move selection by a page. Home/End, selection, word movement/deletion and undo retain GTK editor behavior. Ctrl+L clears the terminal at a shell prompt; Ctrl+C with no editor selection cancels its draft as an undoable edit and interrupts the empty shell prompt. Ctrl+C with a selection copies normally. Ctrl+D on an empty shell draft sends EOF. Bare F1/Page Up/Page Down in terminal input remain program keys, including in alternate-screen TUIs. Ctrl+C remains the terminal interrupt. Existing explicit application shortcuts retain their documented meaning.

Terminal controls and explicit source paste remain available in every mode:

- +, Ctrl+T or Ctrl+Shift+T creates a tab in the current directory. Ctrl+N creates one in the window’s initial launch directory (its default cwd); Ctrl+Shift+N creates a separate window. Ctrl+Page Up/Down cycles tabs. Ctrl+W, Ctrl+Shift+W or middle-clicking a header tab closes it; Ctrl+Shift+Q closes the window and all its tabs. Ctrl+Shift+H hides the window. These explicit workspace shortcuts apply in foreground programs too.
- Ctrl+Shift+C copies terminal selection (or the right-click word target); Ctrl+Shift+V pastes the clipboard. Ctrl+C remains the terminal's interrupt key.
- Ctrl+Shift+Plus/Minus zoom; Ctrl+Shift+0 resets font size. Mouse selection and scrolling are VTE operations.
- Show Markdown Source in Composer Options reveals hidden markup in the [shared rich editor](../rich-input/README.md). The draft survives hide/show.
- Paste into Terminal or Ctrl+Shift+Enter pastes the scratchpad's canonical source, including hidden delimiters, without clearing it or appending Enter. Ctrl+Shift+C in the scratchpad copies selected source including hidden characters; ordinary editor Ctrl+C retains GTK's visible-text behavior.

Ctrl+Shift+P or Command Palette in Terminal Options opens searchable UI actions with shortcut hints. Type to filter, use Up/Down to choose, Enter to activate and Escape to dismiss. Available actions reuse the menu commands; palette queries never enter the shell.

Secondary-clicking terminal text preserves an existing selection or highlights the word under the pointer and offers Copy, Paste and Command Palette. Word hit-testing uses VTE’s Unicode regex matcher and configured word-character exceptions. The host paints a temporary highlight and copies that word; it does not replace VTE’s native selection API. Wrapped words copy in full when VTE matches them, but the temporary highlight covers the clicked screen row only. Output changes, scrolling, typing or a primary click clear this target. Mouse handling remains VTE’s; a program’s mouse grab can take precedence over context-menu requests.

[VTE's paste operation](https://gnome.pages.gitlab.gnome.org/vte/gtk4/method.Terminal.paste_text.html) uses bracketed paste when the child enables it. The running program determines paste semantics: multiline text can execute in shells without bracketed-paste support. Explicit paste is separate from Run's fish source handoff and ClaudeVassal's prompt-to-argv/cache protocol. Keyboard shortcuts work in the terminal and editor; GTK's normal clipboard and undo keys remain available in Composer.

## Appearance, search and suggestions

Preferences (Terminal Options or Ctrl+,) changes the terminal and Composer fonts, Pane background opacity (0–100%) and scrollback limit (100–100,000 lines). Font sizes accept 6–72 points/pixels. Use System Colors follows desktop light/dark appearance; turn it off for native text/background color choosers. Inherit Pane Style is on by default and applies Pane colors and background opacity to Composer and the header live. Turn it off to use desktop theme styling for both Composer and the header while keeping the Pane’s appearance. Header Opacity Boost is an optional live adjustment: 0% matches Pane opacity; 100% keeps the header opaque. Intermediate values fill that fraction of the remaining transparency, so the header stays at least as opaque as the Pane. Its default is 0%; the control is disabled when inheritance is off. Fonts remain independently configurable; menus/preferences keep their native opaque styling. Changes apply across open sessions and are saved under `$XDG_CONFIG_HOME/shadow-term/preferences.ini`; Restore Defaults resets them. Slider motion is coalesced before saving, and closing flushes pending changes. Text stays opaque; actual desktop blending depends on compositor support.

Ctrl+Shift+F opens literal terminal search; Ctrl+F while editing searches Composer source, including hidden delimiters. The search bar also lets you choose the target. Enter finds the next match, Shift+Enter finds the previous one, and Escape closes the bar. Search is case insensitive and wraps. It never alters the source or sends search text to the child process.

In Markdown mode, Ctrl+B and Ctrl+I toggle bold and italic delimiters around the selection; Ctrl+grave toggles inline code. The formatting buttons expose the same actions. An empty selection inserts a delimiter pair with the cursor inside it. Each action is one undoable source edit. These actions are disabled in Fish mode so a formatting shortcut cannot silently rewrite a shell command. Preview support remains the [editor's documented Markdown subset](../rich-input/README.md#interaction).

Tab completes a unique fish candidate directly or opens the candidate list; Ctrl+Space or Suggestions always opens the list. Up/Down and Shift+Tab change selection; Page Up/Page Down moves five entries. Enter or Tab inserts the selected candidate and Escape dismisses the panel. Completion is one undoable edit and never executes the command. While a query is pending, Enter/Tab cannot submit the partial draft. Source, cursor, directory, syntax mode, readiness and updated shell metadata invalidate old results.

The fish provider runs `complete --escape --do-complete` in a disposable, noninteractive `fish --no-config` worker using the shell-reported cwd, completion definitions, supported static abbreviations and completion/function search paths. It supports command/option completion and literal filenames, including unfinished quoted tokens, spaces, backslashes and Unicode. Definitions refresh at shell prompts through the authenticated bridge. The query source is an argv value; drafts with command substitutions are excluded. Completion functions can run their usual helper commands, but they run outside the interactive shell. Workers have bounded output, deadlines and their own process groups, including descendant cleanup. Shell configuration is not rerun for each request. Private session globals, dynamically defined functions and subsequent environment changes are not cloned into these workers, so this is not full fish-state parity.

Static `abbr` definitions expand on Space or before Run/Enter as one undoable source edit. Command/anywhere positions, command restrictions and cursor markers are supported; a candidate can also expose an abbreviation in the completion list. Quoted tokens are not abbreviation triggers. Regex and function-generated abbreviations are not expanded by this implementation. Expansion changes the visible canonical draft before the ordinary source handoff; no terminal styling becomes command text. Foreground program drafting does not apply shell abbreviations.

Fish highlighting updates as text changes. After a 300 ms typing pause, a cancellable `fish --no-config --no-execute` worker checks syntax; asynchronous metadata checks annotate existing literal paths and missing required inputs. Missing-path warnings cover literal command paths, input redirections and simple file arguments to `cat`, `less`, `more`, `head`, `tail`, `stat`, `file`, `source`, `cd` and `ls`. Ambiguous option values and variable/glob/substitution expressions are left unmarked. Output redirections and new destinations for unrelated commands are not treated as missing inputs. Diagnostics are advisory and do not block Run or create files. Source bytes remain unchanged. Work is limited to 16 KiB drafts, 32 path checks, bounded output and a 1.5 s deadline, and stops when the editor is hidden or shell input is busy. This combines Composer’s lexical tags with a host-owned provider; it does not reproduce fish’s full semantic highlighter.

Markdown suggestions and native GTK editing remain available independently of these fish services. The shared [provider interface](../rich-input/README.md#completion-providers) remains replaceable.

## Private VTE presentation

[VTE 0.82.4](https://github.com/GNOME/vte/tree/0.82.4) hardcodes idle OSC 8 link decoration and exposes neither host cursor visibility nor alternate-screen state through its public GTK API. The [small presentation patch](patches/vte-0.82.4-hover-only-hyperlinks.patch) adds opt-in widget classes for hover-only links and Composer-time cursor hiding, plus a read-only alternate-screen property. Link destinations, explicit SGR underlines, emulator protocol handling and program cursor state are retained. The Pane does not implement another terminal parser.

To build these hooks privately after the normal Meson setup:

```fish
nice -n 19 ionice -c 3 python3 prepare-vte.py --configure
nice -n 15 meson compile -C build -j 1
```

The helper downloads GNOME’s pinned release, verifies its published SHA-256 and builds only the GTK4 library with one job. A C++ compiler and VTE’s build dependencies are needed. `--archive PATH` uses a local release tarball. Source and artifacts stay under `build/private-vte`; no system package is installed. Shadow Term’s runpath selects that library without exporting a library path into child programs. Keep this build directory in place. `meson configure build -Dvte-library-dir=` followed by a rebuild returns to system VTE. System VTE retains its idle link dots, has only an approximate background-colour cursor fallback, and cannot provide this automatic alternate-screen hiding. Future Pane presentation is intended to be independent of VT grid/style restrictions while retaining an established emulator for terminal semantics.

## Desktop identity

The executable embeds an application icon and uses the stable application/WM-class identity `io.github.visrosa.Vibrant.ShadowTerm`. Register the existing build with the current user’s launcher, dock and task switcher:

```fish
python3 register-desktop.py
```

This writes a desktop entry and scalable icon under `$XDG_DATA_HOME` (normally `~/.local/share`), refreshes the desktop database when the utility is available, and launches nothing. The entry points to this build’s absolute path; rerun after moving the checkout. A differing existing desktop entry is preserved as `.desktop.previous`. The script refuses to overwrite that backup; executable paths containing line breaks or `%` are rejected. Restart an already-running older build to load its icon and window identity changes. Actual dock grouping remains desktop policy.

## Verification and limits

```fish
nice -n 15 meson test -C build --no-rebuild --num-processes 1 --print-errorlogs
nice -n 15 python3 tests/integration.py
nice -n 15 python3 tests/integration.py --frontend
nice -n 15 python3 tests/integration.py --presentation
```

The integration checks require Python, fish, Xvfb, xdotool, xprop, ImageMagick’s `import` and D-Bus; the frontend check also uses PyGObject with GTK4 for exact Unicode clipboard input. They use a private software-X11 display, synthetic fish configuration, temporary XDG configuration/data/cache/state directories, a synthetic GTK Compose table and a private bus with service activation disabled. An explicit test-only fish history namespace overrides inherited history settings; the harness verifies that interactive commands were recorded under the temporary data directory. The baseline checks shell input, argv/cwd/environment, interrupts, PTY resize, process reuse, source/clipboard paste, focus/hide and child cleanup. The frontend check covers builtin/quoted-filename completion, literal terminal search, preferences access, command-palette activation, independent tab drafts/PTYs, cycling, whole-window cleanup, Unicode and multiline argv, shell status, pipelines, incomplete syntax, recall, occupied native buffers, foreground stdin/interrupt, nested fish, concurrent draft edits, cancellation and timeout recovery. Editor/appearance checks also exercise formatting undo, source-aware search, stale provider results, preference persistence, live Composer/header colors and rendered alpha (including the relative header boost), unchanged source, alternate-screen Composer collapse/restore and ordinary-reader availability, Unicode word hit-testing, real secondary-click copying, transparent popover corners and narrow layouts. Private presentation checks compare rendered pixels for idle/hovered links and a hidden caret at partial opacity, and exercise middle-click tab closure. The native program fixture checks bare Page Up/Page Down/F1; frontend checks include multiline/right-prompt restoration, shell-status preservation and shortcut discovery. The private presentation test writes previews to `/tmp/shadow-term-ui-wide.png` and `/tmp/shadow-term-ui-narrow.png`, with private popup captures in `/tmp/shadow-term-context-menu.png` and `/tmp/shadow-term-options-menu.png`; desktop compositor blending remains outside those rendered-alpha checks. They do not write real Taskwarrior data or use desktop windows. Test processes are cleaned up.

The existing [CV shadow client](../rich-input/README.md) remains available independently. Composer supplies the bounded fish services above; full live-shell state, dynamic/regex abbreviation expansion, history UI and semantic-highlighting parity remain outside this version. Native editing remains reachable. This version provides authoritative command sessions; it does not capture/reparent another emulator's window or clone a running external terminal. Multiple views of one PTY, detach/reattach, a public raw-stream subscription API, arbitrary programmatic overlays/modals, desktop docking and Kitty image/text-sizing parity are separate extensions. In particular, tasklineUI's Kitty OSC 66 labels need a rendering compatibility check before assuming identical appearance. Native Wayland focus/placement, IME and assistive-technology behavior require actual-desktop validation; isolated X11 checks do not establish those properties.

[gtk4-layer-shell](https://github.com/wmww/gtk4-layer-shell) is a possible optional panel backend for Wayland compositors implementing Layer Shell. It does not supply that protocol on unsupported compositors, GNOME Wayland or X11. Ordinary Shadow Term windows and dock identity do not depend on it.
