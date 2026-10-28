# Shadow Term

Shadow Term 0.0.9 is a GTK4/Vala terminal host for an interactive shell or any terminal command. [V Composer](../rich-input/README.md) is the normal input frontend for interactive fish; foreground programs receive ordinary terminal input. Each live session owns a VTE emulator and PTY, including terminal replies, alternate-screen programs and resizing. Windows contain header tabs; each tab arranges one or more sessions in resizable splits. Sessions can move between these layouts without restarting. It does not require ClaudeVassal, Kitty or layer-shell.

## Build and launch

Dependencies: Vala 0.56, Meson, Ninja, a C compiler, GTK ≥ 4.12, Granite ≥ 7.7, VTE GTK4 ≥ 0.78, PCRE2 headers, JSON-GLib and libxml2. GTK's X11 backend and Xlib are optional build dependencies for automatic positioning. Run from this directory:

```fish
env VALAC=valac-0.56 meson setup build
nice -n 15 meson compile -C build -j 1
./build/shadow-term
```

If the compiler is named `valac`, omit `VALAC=valac-0.56`. Compilation installs nothing. The terminal launches `$SHELL`, falling back to `/bin/sh`, in the invoking directory. Shell startup configuration works normally. Development builds use helper and fish adapter paths in the source/build tree, which must remain in place. `--help` and `--version` work without a display.

For packaging, configure a separate build with `-Dinstalled-layout=true --prefix=/usr`. `meson install` then installs `shadow-term`, the shell/content helpers under `libexec/shadowterm`, the fish adapter under `share/shadowterm`, and the desktop entry/icon. Runtime paths refer to the final prefix, independently of `DESTDIR`; development builds remain usable directly from their build directory. A supplied `vte-library-dir` is retained as the installed executable's runpath without exporting `LD_LIBRARY_PATH` to child programs. The Gentoo live packages in [the personal overlay](../../dotfiles/overlay/app-shells/shadowterm/README.md) track this repository's `main` and provide a separate private patched VTE.

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

Toggle hides a focused window or selects and presents the requested tab when it is hidden, in the background or unfocused. Hide retains all tabs, child processes, terminal states and Composer drafts in that window. Ctrl+W or `--quit` ends the selected/named session and signals its child/foreground process groups. Ctrl+Shift+W, the tab’s close button or middle-clicking a tab closes all sessions in that tab. Closing a window or Ctrl+Shift+Q ends all its tabs; normal child exit removes only that pane unless `--hold` was selected. Empty split branches collapse; the last tab closes its window. Other windows remain running. `--list` prints session name, visibility and child PID; all panes in a window’s selected, presented tab are reported as visible; zero indicates a launch failure or an exited held command. A spawn failure stays visible with a Restart action.

For a taskittyUI-style launcher, point a desktop shortcut at a named command session:

```fish
./build/shadow-term --session tasks --toggle --hide-on-focus-loss -- /path/to/tasklineUI
```

Build the complete tasklineUI package once; do not compile it on every toggle. Identical launch options can be repeated to control an existing session. Conflicting launch options produce an error instead of silently replacing a running command. Hide-on-focus-loss is armed only after actual activation; an activation request denied by the compositor leaves the window visible. Focus moves into this application's transient dialogs do not hide the parent. Global shortcut registration is left to the desktop.

Initial sizing is constrained to available monitor geometry. User size is saved under the window’s first-session identity in `$XDG_STATE_HOME/shadow-term/geometry.ini` (normally `~/.local/state/shadow-term/geometry.ini`). X11 builds can center new windows and restore their position; native Wayland placement follows compositor policy. Showing an existing window preserves its geometry. Window-manager rules can override placement requests.

## Composer and terminal input

With the default `--input auto`, an interactive fish session opens Composer in Fish mode and focuses it at each prompt. `--input composer` opens Composer for any command; supported interactive fish uses exact-source submission and prompt suppression, while other consumers receive text plus Return through VTE. `--input terminal` starts with Composer hidden and native prompt editing active. The outer-fish adapter stays available so enabling Composer later can suppress the shell prompt and use normal Composer submission. Other shells, fish scripts and `fish -c` use ordinary VTE input. Markdown/Fish chooses presentation only; commands still follow fish syntax.

- Enter, Ctrl+Enter or Send submits the full draft to the active shell or program. Shift+Enter inserts a line. At the outer fish prompt, an incomplete Enter submission gains a line; Ctrl+Enter or the button retains it unchanged.
- An incomplete Enter submission stays editable and gains a line. Invalid syntax, a nonempty native fish buffer, cancellation or a three-second handoff timeout retain the draft. Cancel or Escape cancels a pending handoff; an accepted command has already been handed to fish.
- The unchanged submitted draft clears; edits made while fish acceptance was pending remain. Composer Options contains a collapsed, read-only Last Input disclosure. Recall Last Input or Ctrl+Shift+L restores the last submitted source into an empty draft. Foreground programs have no generic acceptance acknowledgement: their draft clears once the text and Return are queued to the live VTE, and Composer keeps focus for the next response. Empty Enter sends a bare Return to a foreground program. Stopped sessions and pending fish submissions retain the draft.
- Composer retains default input focus while visible, including ordinary foreground readers. Send delivers text plus Return; Ctrl+C interrupts the program and Ctrl+D with an empty draft sends EOF. Clicking the Pane still selects native terminal input. At the next fish prompt, Composer retains focus if visible. Composer collapses while VTE reports an alternate screen, preserving its draft and enabled preference. An explicit V Composer toggle can show it there until the next screen transition. Ordinary foreground readers, including CV, retain the editor. Composer keeps the same Send control and Enter/Shift+Enter behavior. Foreground delivery uses VTE’s ordinary paste handling for the source followed by a separate carriage return, outside any bracketed-paste markers, so the program receives a normal submission. Shell abbreviations and diagnostics pause outside shell-command readiness. This screen-state notification comes from the private VTE build below, without another escape-sequence parser.
- Up on the first logical line and Down on the last logical line browse history while fish is ready. The original draft is the prefix filter; returning past the newest match restores it and its caret. Multiline source, Unicode and trailing newlines remain intact. Completion owns these keys while its picker is active; ordinary multiline caret movement remains available. Navigation edits are undoable and never execute. History comes from this shell’s own namespace, including native-editor commands, bounded to 200 entries/128 KiB and 16 KiB per entry; oversized/incomplete entries are omitted. This is navigation, not a full history-search UI.
- V Composer or Ctrl+Shift+M toggles the editor. Hide it to use native fish editing, history or completions. A partial native command must be finished or cleared before Composer can submit.

The adapter is sourced through the launched fish process's `--init-command`; it changes no configuration files. It reserves Ctrl+Alt+O for source handoff and Ctrl+Alt+P for prompt presentation in that process's default and insert binding modes. It saves the existing left/right prompt functions and skips their drawing while Composer is active. Hiding Composer restores those functions, including their shell-status context, and repaints without changing a partial native input buffer. Prompt functions and their side effects do not run while suppressed. This intentionally replaces shell prompt emission; command source and program output are not filtered. Presentation changes wait for prompt readiness before sending any control binding, so foreground programs receive none of these control sequences. Nested fish sessions use native input. Code that later replaces the private bindings, prompt wrappers or event functions can disable the adapter; native terminal input remains available.

Composer retains canonical UTF-8 source, including hidden Markdown delimiters and trailing newlines. Each submission is limited to 65,536 bytes. `input-session.vala` tracks readiness and one pending handoff. A local D-Bus bridge and GIO-only `vcom-shell` helper transfer source with per-spawn identity and one-use retrieval. At a ready outer-fish prompt, the PTY carries only the binding's key sequence; fish sets its ordinary commandline buffer, validates syntax and invokes its native execute action. Transport code never evaluates or shell-quotes the source. Prompt and preexec events report state; no background polling is needed.

Last Input styles accepted source separately from VTE's terminal screen. Fish still echoes and executes its ordinary commandline, and program output is not rewritten. This adapter is one concrete Composer/Pane/shell arrangement; general routing and shell-independent submission remain separate design work.

When **Route Pane text input to active Composer** is enabled in Preferences (the default), typing, clipboard paste and middle-click Primary Selection insertion at the shell prompt go to Composer even if the Pane has focus. Insertion never submits. Pane selection/copying/scrolling remain available. The guard follows authenticated prompt readiness, not just alternate-screen state: interactive readers and TUIs retain native input. Busy commands retain native input because the adapter does not classify arbitrary programs by whether they will read stdin. Hiding Composer or disabling the option restores native shell editing. Clipboard delivery is discarded after session/foreground changes rather than retargeted.

## Workspace and contextual controls

The header contains a horizontally scrollable tab strip, + (New Tab) and Terminal Options. Each pane retains its own shell, current directory, terminal contents, Composer draft and input state. New tabs and splits start a fresh configured shell in the active pane’s directory; switching or moving sessions never restarts a shell. The selected tab scrolls into view when necessary. The header follows Pane styling when Inherit Pane Style is enabled, without a bottom separator. Search, Composer visibility, preferences, shortcut help and session actions live in Terminal Options. Composer grows from a compact prompt to a bounded multiline input. Its options menu contains presentation mode, Markdown source/formatting, suggestions, recall, search, explicit terminal paste and Last Input. Run appears for a nonempty shell draft; Cancel appears only during a pending submission. The status strip appears for pending input, errors and held exits rather than repeating prompt instructions. This follows the elementary HIG's guidance on [contextual controls](https://docs.elementary.io/hig/widgets/avoid-widgets-that-do-nothing) and [tool ordering](https://docs.elementary.io/hig/widgets/creating-layouts); visible menus and shortcut labels preserve discovery.

Tab captions and the active window title prefer the application’s terminal title, falling back to the current directory basename. Returning to an authenticated fish prompt clears the previous application title; a later terminal title can replace it. Other shells retain the launch-directory fallback unless they send a terminal title. `--title` supplies an initial title. Titles are bounded plain text, split tabs follow their active pane and show a pane count, and tab tooltips retain the full directory and session identity. Session names used by CLI controls remain unchanged.

Composer Options → Context Information and Preferences → Input → Composer Context contain saved, application-wide toggles for the whole context strip and each indicator. The compact icon/text indicators wrap in narrow panes, inherit Composer styling and expose details on hover. Available fields are:

- Working directory, abbreviated under the home directory.
- Git branch, detached commit or unborn branch; `↑`/`↓` show ahead/behind counts, `+` staged entries, `~` modified entries, `?` untracked entries and `!` conflicts. Stash count appears when nonzero. The tooltip spells out the counts and names the upstream. A file can be both staged and modified, and untracked directories may be one status entry. Counts are entries, not changed lines.
- Last command result: a nonzero exit status, or nonzero pipeline statuses when the overall command succeeded. Routine success stays quiet.
- Last command duration, shown for commands taking at least one second. Result and duration hide while another foreground command runs.
- Active Python virtual environment and Conda environment, shown only when their named shell variables are set; tooltips include the reported environment paths/names.
- User and host, with an SSH marker when the shell reports an SSH session. This indicator is opt-in.
- Background-job count, shown when nonzero. It is a snapshot at the last shell prompt.

The launched fish reports only these named fields through the authenticated bridge. Its post-execution event captures the result/pipeline/duration before prompt helper commands; repaints and completion queries do not replace the last command result. Environment and job fields refresh at prompt events. Native shell editing and other command sessions retain the context available from their adapter; live fish-only fields are absent without this integration. These displays are advisory and independent of command source and PTY output. No version probes, environment scans, network requests or idle polling run.

Git status refreshes at prompt/directory events, when Composer becomes visible, when its Git indicator is enabled, or through Refresh Repository. Hiding Composer or disabling Git cancels its query. It uses asynchronous literal argv without optional locks or external fsmonitor, ignores submodule contents, and is bounded to 1.5 seconds/64 KiB. NUL-framed porcelain records keep rename and newline-containing filenames from inflating counts. Nonrepositories, unavailable Git and failed/oversized/timed-out results leave the repository label empty; stale results are discarded. Existing same-directory status stays visible while a fresh query runs. Ahead/behind compares locally available refs; the provider never fetches.

Keyboard Shortcuts is available from Terminal Options, or F1 while editing Composer. Page Up/Page Down while editing Composer scroll the Pane; within suggestions they move selection by a page. Home/End, selection, word movement/deletion and undo retain GTK editor behavior. Ctrl+L clears the terminal at a shell prompt; Ctrl+C with no editor selection cancels its draft as an undoable edit and interrupts the empty shell prompt. Ctrl+C with a selection copies normally. Ctrl+D on an empty shell draft sends EOF. Bare F1/Page Up/Page Down in terminal input remain program keys, including in alternate-screen TUIs. Ctrl+C remains the terminal interrupt. Existing explicit application shortcuts retain their documented meaning.

Terminal controls and explicit source paste remain available in every mode. These are the default bindings; Preferences → Shortcuts changes host actions live:

- +, Ctrl+T or Ctrl+Shift+T creates a tab in the active pane’s directory. Ctrl+N uses the window’s initial directory; Ctrl+Shift+N creates a window.
- Ctrl+Shift+E splits side by side; Ctrl+Shift+O stacks a new pane. Drag the divider to resize. Ctrl+Alt+Left/Right cycles panes in layout order; clicking or focusing a pane selects it. Ctrl+Page Up/Down cycles tabs.
- Ctrl+W closes a pane; Ctrl+Shift+W closes the whole tab. A tab’s close button or middle-click also closes its whole layout. Ctrl+Shift+Q closes the window.
- Terminal Options and the command palette expose Move Pane to New Tab, Move Pane to New Window and Move Previous Tab into Split. Moving preserves the shell PID, screen, draft and pending input; it does not copy a stream or create a second PTY owner. Each session has one attached view; closing that view still ends the session.
- Ctrl+Shift+H hides the whole window; Ctrl+Shift+P opens the searchable command palette. The palette dispatches UI actions and never executes query text.
- Ctrl+Shift+C copies selected Pane text (or canonical selected Composer source); Ctrl+Shift+V pastes. Right-click highlights the word under the pointer when there is no native selection, then offers Copy/Paste and UI actions. Native selections and emulator mouse grabs retain precedence; the temporary word target clears on output/viewport/input changes.

[VTE's paste operation](https://gnome.pages.gitlab.gnome.org/vte/gtk4/method.Terminal.paste_text.html) uses bracketed paste when the child enables it. The running program determines paste semantics: multiline text can execute in shells without bracketed-paste support. Composer Options → Paste Draft without Return (Ctrl+Shift+Enter) remains an explicit insertion-only action and moves focus to the terminal. It is separate from Send and from the fish source handoff or ClaudeVassal’s prompt-to-argv/cache protocol. Send follows a foreground paste with a separate Return; arbitrary program input still follows that program’s terminal semantics rather than the outer-fish exact-source acknowledgement contract. Keyboard shortcuts work in the terminal and editor; GTK's normal clipboard and undo keys remain available in Composer.

## Appearance, search and suggestions

Preferences (Terminal Options or Ctrl+,) groups controls into scrollable Appearance, Input and Shortcuts pages. Appearance changes the terminal and Composer fonts, Pane background opacity (0–100%) and scrollback limit (100–100,000 lines). Font sizes accept 6–72 points/pixels. Pane bold, italic and bold-italic faces are independently selectable, following [Kitty’s separate style-face model](https://sw.kovidgoyal.net/kitty/conf/#fonts). Unchecked uses automatic matching from the regular font. Explicit face size is normalized to the regular size/zoom so the terminal grid stays stable; choose faces with compatible monospace metrics. These controls require the private VTE style-font hook and are disabled with an explanation when unavailable; saved choices survive switching builds. Composer retains its independent regular font and automatic style matching. Use System Colors follows desktop light/dark appearance; turn it off to edit the terminal colors below. Inherit Pane Style is on by default and applies Pane colors and background opacity to Composer and the header live. Turn it off to use desktop theme styling for both Composer and the header while keeping the Pane’s appearance. Header Opacity Boost is an optional live adjustment: 0% matches Pane opacity; 100% keeps the header opaque. Intermediate values fill that fraction of the remaining transparency, so the header stays at least as opaque as the Pane. Its default is 0%; the control is disabled when inheritance is off. Fonts remain independently configurable; menus/preferences keep their native opaque styling. Changes apply across open sessions and are saved under `$XDG_CONFIG_HOME/shadow-term/preferences.ini`; Restore Appearance Defaults resets appearance; Input/context choices and shortcut defaults have independent controls. Slider motion is coalesced before saving, and closing flushes pending changes. Text stays opaque; actual desktop blending depends on compositor support.

Appearance → Typography → Pane cursor shape offers Block (the default), I-beam and Underline. The choice is saved and applies live across sessions, independently of cursor colors and Composer's text caret. Applications can override it with DECSCUSR; restoring the terminal-default style returns to your saved choice. Restore Appearance Defaults selects Block again. Composer-time cursor hiding preserves the selected shape. Both private and system VTE support this setting.

Preferences → Appearance → Terminal color scheme → Import accepts XML `.itermcolors` presets from [iTerm2](https://iterm2.com/documentation-preferences-profiles-colors.html), including the downloadable presets in [iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes). Import applies the preset immediately, turns off Use System Colors and copies the values into preferences; the original file is no longer needed. It preserves fonts, opacity and other settings. Invalid presets leave the current colors intact. The importer accepts files up to 256 KiB with all 16 ANSI colors plus foreground/background, and sRGB RGB components between 0 and 1. Legacy RGB dictionaries without an explicit color-space field are accepted; other color spaces, binary plists and other terminal theme formats are unsupported. XML entities and external resources are not loaded; preset alpha does not replace the separate opacity setting.

The ANSI palette exposes each normal and bright color independently. Pane text/background and cursor, cursor text, selection background and selection text have individual native color choosers too. Optional cursor/selection roles offer Automatic; missing roles in imported presets restore Automatic. Edits apply across open sessions and persist alongside other appearance settings. Use System Colors temporarily bypasses custom colors while retaining them; Restore Appearance Defaults resets every color, including the ANSI palette and automatic roles. These are terminal colors: applications using explicit RGB colors retain their own choices, and indexed colors 16–255 retain VTE's extended palette. Composer/header inheritance follows Pane text/background rather than recoloring application-defined syntax.

Preferences → Shortcuts has a searchable action list. Select a binding and press the new combination; Escape cancels capture and Backspace disables it. Conflicting bindings are rejected with the owning action’s name. Each row can restore its default; Restore Shortcut Defaults resets the whole map. Bindings and menu/palette hints update live across windows. Core editing, submission and completion keys remain contextual and reserved; foreground TUIs still receive their ordinary unclaimed keys. Legacy Ctrl+Shift+T remains an alias for New Tab while that action uses its default binding.

Ctrl+Shift+F opens literal terminal search; Ctrl+F while editing searches Composer source, including hidden delimiters. The search bar also lets you choose the target. Enter finds the next match, Shift+Enter finds the previous one, and Escape closes the bar. Search is case insensitive and wraps. It never alters the source or sends search text to the child process.

In Markdown mode, Ctrl+B and Ctrl+I toggle bold and italic delimiters around the selection; Ctrl+grave toggles inline code. The formatting buttons expose the same actions. An empty selection inserts a delimiter pair with the cursor inside it. Each action is one undoable source edit. These actions are disabled in Fish mode so a formatting shortcut cannot silently rewrite a shell command. Preview support remains the [editor's documented Markdown subset](../rich-input/README.md#interaction).

Tab inserts a unique candidate only when the provider reports a complete relevant set, or opens suggestions; Ctrl+Space always opens the list. Suggestions float near the caret with labels and descriptions. Typing within the same argument refines the open session; cursor/context changes, editor scrolling, focus leaving both editor and popup, or Escape dismiss it. Ctrl+F inside the list filters labels/descriptions without changing the draft; prefix label matches precede substring matches. Up/Down and Shift+Tab select, Page Up/Page Down moves five entries, and the wheel scrolls. Enter, Tab or clicking inserts one undoable edit and never submits; Ctrl+Right inserts and continues when a candidate supports continuation, such as directory descent. Pending/partial/truncated queries cannot imply uniqueness or let Enter execute the draft. Batches publish as providers return and retain selected identities where available.

Selected suggestions load bounded previews after a short navigation-coalescing delay. Files show text excerpts, directories show at most 128 entries, and Git candidates can show commit/branch summaries. Binary and special files are identified; large results show truncation. Open Preview promotes the current text into a separate movable window. Preview work is cancelled when selection/context changes and never touches the command PTY. File previews are plain text; rich format renderers and wider desktop-specific layouts remain extensions.

The fish provider runs `complete --escape --do-complete` in a disposable, noninteractive `fish --no-config` worker using the shell-reported cwd, completion definitions, supported static abbreviations and completion/function search paths. It supports command/option completion and literal filenames, including unfinished quoted tokens, spaces, backslashes and Unicode. Definitions refresh at shell prompts through the authenticated bridge. The query source is an argv value; drafts with command substitutions are excluded. Completion functions can run their usual helper commands, but they run outside the interactive shell. Workers have bounded output, deadlines and their own process groups, including descendant cleanup. Shell configuration is not rerun for each request. Private session globals, dynamically defined functions and subsequent environment changes are not cloned into these workers, so this is not full fish-state parity.

Static `abbr` definitions expand on Space or before shell Send/Enter as one undoable source edit. Command/anywhere positions, command restrictions and cursor markers are supported; a candidate can also expose an abbreviation in the completion list. Quoted tokens are not abbreviation triggers. Regex and function-generated abbreviations are not expanded by this implementation. Expansion changes the visible canonical draft before the ordinary source handoff; no terminal styling becomes command text. Foreground program drafting does not apply shell abbreviations.

Fish highlighting updates as text changes. After each settled edit, a bounded `fish --no-config --no-execute` worker checks syntax; asynchronous metadata checks annotate existing literal paths and missing required inputs. Missing-path warnings cover literal command paths, input redirections and simple file arguments to `cat`, `less`, `more`, `head`, `tail`, `stat`, `file`, `source`, `cd` and `ls`. An unfinished final token remains provisional until a delimiter is inserted; existing literal paths may still be annotated. Ambiguous option values and variable/glob/substitution expressions are left unmarked. Output redirections and new destinations for unrelated commands are not treated as missing inputs. Diagnostics are advisory and do not block Run or create files. Source bytes remain unchanged. Work is limited to 16 KiB drafts, 32 path checks, bounded output and per-stage deadlines up to 1.5 s, and stops when the editor is hidden or shell input is busy. This combines Composer’s lexical tags with a host-owned provider; it does not reproduce fish’s full semantic highlighter.

Markdown suggestions and native GTK editing remain available independently of these fish services. The shared [provider interface](../rich-input/README.md#completion-providers) remains replaceable.

## Documentation and native completion definitions

Alt+H or Composer Options → Documentation opens a separate movable/resizable documentation window. Without a selection, lookup uses the caret's command scope: inside `echo (task list)` it targets `task`; outside it targets `echo`. Pipeline processes and incomplete nested substitutions are supported; quoted or escaped literal parentheses do not create scopes. Explicit selections are literal queries, with selected options resolved against their command. Lookup does not evaluate substitutions. It tries command-subcommand pages before the command page where appropriate.

The compact window has a draggable source strip, edge resize regions, per-source scrolling and Ctrl+F search. Escape or Close dismisses it independently of the command session. **Dismiss on focus loss** is a saved setting, off by default so the window can stay open. Available sources default to man, offline tldr and info; missing tools/pages show errors without suppressing the other sources. The default tldr adapter requires a client supporting `--offline`; configure another cached source if yours differs. Source changes load lazily and cancel obsolete workers. Window size and supported placement are saved; new X11 views start near the invoking window, while Wayland placement follows compositor policy. No source installs, updates or fetches occur automatically. Fish's installed manual directory takes precedence for man queries.

Configure `$XDG_CONFIG_HOME/shadow-term/documentation.json` with ordered sources and literal argument arrays. The placeholders `{query}`, `{command}`, `{token}` and `{subcommand}` substitute inside individual arguments; they are never shell code:

```json
{"sources": [{"name": "Manual", "argv": ["man", "--", "{query}"]}, {"name": "Info", "argv": ["info", "--output=-", "--", "{query}"]}]}
```

Optional native completion definitions live in `$XDG_CONFIG_HOME/shadow-term/completions/*.json`. A matching command definition owns its candidates, with ordinary fish definitions used for other commands. Version 1 supports option forms, descriptions, required arguments, file policy, subcommand conditions, preserved ordering and literal-argv dynamic candidates. Values can carry Composer-only kind/group/preview/continuation metadata:

```json
{"version": 1, "command": "example", "rules": [{"long": "color", "short": "c", "description": "Output color", "requires_argument": true, "files": "disable", "values": [{"value": "always", "description": "Always use color"}, {"value": "never", "description": "Plain output"}]}]}
```

Export reviewable fish definitions with `python3 completion-definitions.py --export /path/example.json > example.fish`. Static exports run independently; dynamic rules explicitly depend on the JSON definition and this headless helper, without a GUI or Composer session. Dynamic argv writes one value and optional tab-separated description per line. `when_subcommand` maps to fish's helper condition; `files` accepts `allow`, `disable` or `force`; `keep_order` maps to fish's ordering flag. Unsupported fields fail explicitly. Preview/group metadata stays out of fish exports. Configured dynamic providers can execute commands, just like fish completion functions, so definitions are trusted user configuration. Work is bounded to 32 definition files, 128 candidates, worker output/time limits and cancellable process groups.

## Private VTE presentation

[VTE 0.82.4](https://github.com/GNOME/vte/tree/0.82.4) hardcodes idle OSC 8 link decoration and exposes neither host cursor visibility nor alternate-screen state through its public GTK API. The [small presentation patch](patches/vte-0.82.4-hover-only-hyperlinks.patch) adds opt-in widget classes for hover-only links and Composer-time cursor hiding, plus a read-only alternate-screen property. Link destinations, explicit SGR underlines, emulator protocol handling and program cursor state are retained. The Pane does not implement another terminal parser.

To build these hooks privately after the normal Meson setup:

```fish
nice -n 19 ionice -c 3 python3 prepare-vte.py --configure
nice -n 15 meson compile -C build -j 1
```

The helper downloads GNOME’s pinned release, verifies its published SHA-256 and builds only the GTK4 library with one job. A C++ compiler and VTE’s build dependencies are needed. `--archive PATH` uses a local release tarball. Source and artifacts stay under `build/private-vte`; no system package is installed. Shadow Term’s runpath selects that library without exporting a library path into child programs. Keep this build directory in place. `meson configure build -Dvte-library-dir=` followed by a rebuild returns to system VTE. System VTE retains its idle link dots, has only an approximate background-colour cursor fallback, and cannot provide automatic alternate-screen hiding or independent style faces. VTE’s [public font setter](https://gnome.pages.gitlab.gnome.org/vte/gtk4/method.Terminal.set_font.html) accepts one base description; the private drawing hook supplies the additional faces without changing terminal semantics or PTY bytes. Future Pane presentation is intended to be independent of VT grid/style restrictions while retaining an established emulator for terminal semantics.

The private VTE still links to system libraries; it does not bundle dependencies such as simdutf. After a dependency changes its shared-library version, both an older retained build and the desktop build can fail at the dynamic loader before `--version` runs. Refresh the private build’s dependency discovery and rebuild it against the installed libraries. For the default source/build locations, from `shadow-terminal/`:

```fish
set vte_source (realpath build/private-vte/vte-0.82.4)
set vte_build (realpath build/private-vte/compile)
nice -n 19 meson setup --reconfigure --clearcache "$vte_build" "$vte_source"
nice -n 19 meson compile -C "$vte_build" -j 1 vte-2.91-gtk4
env LD_BIND_NOW=1 ./build/shadow-term --version
```

If a patch revision created a hash-named directory beneath `build/private-vte/`, use that revision’s source/build paths instead. The last command checks immediate symbol resolution without opening a window. `ldd ./build/shadow-term` shows which private VTE and system dependencies that executable resolves. Retained builds in another checkout have independent libraries and need their own refresh; rebuilding the current checkout does not repair them. [Verification and limits](#verification-and-limits) describes the isolated terminal check.

## Desktop identity

The generated desktop entry launches this build with `--input composer`. Registration changes files only and does not launch or restart the app. An existing entry is retained as `.desktop.previous` before replacement; an existing backup is never overwritten. The executable embeds an application icon and uses the stable application/WM-class identity `io.github.visrosa.Vibrant.ShadowTerm`. Register the existing build with the current user’s launcher, dock and task switcher:

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

The integration checks require Python, fish, Xvfb, xdotool, xprop, ImageMagick’s `import` and D-Bus; the frontend check also uses PyGObject with GTK4 for exact Unicode clipboard input. They use a private software-X11 display, synthetic fish configuration, temporary XDG configuration/data/cache/state directories, a synthetic GTK Compose table and a private bus with service activation disabled. An explicit test-only fish history namespace overrides inherited history settings; the harness verifies that interactive commands were recorded under the temporary data directory. The baseline checks shell input, argv/cwd/environment, interrupts, PTY resize, process reuse, source/clipboard paste, foreground Enter/Ctrl+Enter with Return outside bracketed paste, empty responses, consecutive reader prompts, focus/hide and child cleanup. The frontend check covers native-start Composer activation, Up/Down history, PID/draft-preserving split→tab→window moves, builtin/quoted-filename completion, literal terminal search, preferences access, command-palette activation, independent tab drafts/PTYs, cycling, whole-window cleanup, Unicode and multiline argv, shell status, pipelines, incomplete syntax, recall, occupied native buffers, foreground stdin/interrupt, nested fish, concurrent draft edits, cancellation and timeout recovery. Editor/appearance checks also exercise formatting undo, source-aware search, stale provider results, per-candidate descriptions, floating-popup geometry/focus, preference persistence, iTerm2 import/edit/reset and save failures, cursor-shape persistence/reset, three rendered shapes and application override precedence, all 16 live ANSI slots, selection colors and truecolor/extended-palette independence, actual shortcut remapping, independent styled-font pixels with stable cell metrics, nested split collapse/focus, live Composer/header colors and rendered alpha (including the relative header boost), unchanged source, alternate-screen Composer collapse/restore and ordinary-reader availability, Unicode word hit-testing, real secondary-click copying, transparent popover corners and narrow layouts. Private presentation checks compare rendered pixels for idle/hovered links and a hidden caret at partial opacity, and exercise middle-click tab closure plus actual suggestion-popup mouse scrolling and selection. The native program fixture checks bare Page Up/Page Down/F1; frontend checks include multiline/right-prompt restoration, shell-status preservation and shortcut discovery. The private presentation test writes previews to `/tmp/shadow-term-ui-wide.png` and `/tmp/shadow-term-ui-narrow.png`, with private popup captures in `/tmp/shadow-term-context-menu.png`, `/tmp/shadow-term-options-menu.png` and `/tmp/shadow-term-suggestions.png`; desktop compositor blending remains outside those rendered-alpha checks. They do not write real Taskwarrior data or use desktop windows. Test processes are cleaned up.

Context checks additionally cover actual fish pipeline/duration snapshots, Unicode environment activation/deactivation, background jobs, prompt repaint preservation, preference toggles and narrow wrapping. Git fixtures exercise unborn/detached branches, staged/worktree/untracked entries, newline-containing renames, conflicts, diverged tracking refs, stashes and cancellation. The narrow prompt-context preview is `/tmp/shadow-term-prompt-context.png`.

The existing [CV shadow client](../rich-input/README.md) remains available independently. Composer supplies the bounded fish services above; full live-shell state, dynamic/regex abbreviation expansion, advanced history search and semantic-highlighting parity remain outside this version. Native editing remains reachable. This version provides authoritative command sessions; it does not capture/reparent another emulator's window or clone a running external terminal. Simultaneous views of one PTY, unattached producer lifetimes, a public raw-stream subscription API, arbitrary programmatic overlays/modals, desktop docking and Kitty image/text-sizing parity are separate extensions. In particular, tasklineUI's Kitty OSC 66 labels need a rendering compatibility check before assuming identical appearance. Native Wayland focus/placement, IME and assistive-technology behavior require actual-desktop validation; isolated X11 checks do not establish those properties.

[gtk4-layer-shell](https://github.com/wmww/gtk4-layer-shell) is a possible optional panel backend for Wayland compositors implementing Layer Shell. It does not supply that protocol on unsupported compositors, GNOME Wayland or X11. Ordinary Shadow Term windows and dock identity do not depend on it.

[Compiler warning boundaries](docs/compiler-warnings.md) records the full-build warning inventory, corrected C binding contracts and remaining generator/toolkit diagnostics.
