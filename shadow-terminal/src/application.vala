namespace Shadow {
    internal delegate void MenuAction ();
    [CCode (cname = "shadow_position", cheader_filename = "placement.h")]
    extern bool position (Gtk.Window window, int x, int y, bool restore);
    [CCode (cname = "shadow_get_position", cheader_filename = "placement.h")]
    extern bool get_position (Gtk.Window window, out int x, out int y);

    public class TerminalSession : Gtk.Box {
        public Request request;
        public Pid child_pid = 0;
        public bool closing = false;
        public bool running = false;
        public Vte.Terminal terminal;
        private RichInput editor;
        private Gtk.Label feedback;
        private Gtk.Revealer composer;
        private Gtk.Button restart;
        private Cancellable spawn_cancel = new Cancellable ();
        private bool spawning = false;
        private uint kill_timeout = 0;
        private string[] environment;
        private weak Host host;
        private Gtk.DropDown mode;
        private Gtk.ToggleButton compose_button;
        public InputSession input_session = new InputSession ();
        private bool shell_editor;
        private Gtk.Button submit_button;
        private Gtk.Button cancel_button;
        private Gtk.Button recall_button;
        private RichInput preview;
        private Gtk.Revealer preview_card;
        private string submitted_source = "";
        private string last_source = "";
        private bool enter_submission = false;
        private bool previous_ready = false;
        private bool alternate_screen = false;
        private bool alternate_composer_override = false;
        private bool adjusting_composer_toggle = false;
        private string shell_cwd;
        private ComposerAssist assistance;
        private FishProvider fish_provider = new FishProvider ();
        private FishAnalysis analysis;
        private Gtk.Revealer search;
        private Gtk.SearchEntry search_entry;
        private Gtk.DropDown search_target;
        private Gtk.Label search_status;
        private Gtk.Window? preferences_window;
        private ulong preferences_handler;
        private bool presentation_dirty = false;
        private Gtk.Box feedback_bar;
        private Gtk.Box compose_box;
        private ContextBar context_bar;
        private Gtk.Window? shortcuts_window;
        private Granite.Settings desktop_settings;
        private ulong theme_handler;
        private List<UiCommand> commands = new List<UiCommand> ();
        private Gtk.Window? palette_window;
        private TerminalContext terminal_context;
        public weak WorkspaceWindow window;
        public Gtk.MenuButton menu;
        public string title { get; set; }
        public bool is_active { get { return window.is_active && window.active_session == this; } }
        public bool is_presented { get { return window.visible && window.active_session == this; } }
        public string directory { get { return shell_cwd; } }
        public signal void ended ();

        public TerminalSession (Host owner, WorkspaceWindow workspace, Request config, string[] environment) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0, hexpand: true, vexpand: true);
            window = workspace;
            this.host = owner;
            this.request = config;
            shell_cwd = config.cwd;
            shell_editor = request.composer_enabled ();
            this.environment = environment;
            add_css_class ("shadow-terminal");
            title = "%s · %s".printf (request.title, request.session);

            terminal = new Vte.Terminal () {hexpand = true, vexpand = true};
            terminal.set_font (Pango.FontDescription.from_string ("monospace 12"));
            terminal.set_scrollback_lines (10000);
            terminal.set_audible_bell (false);
            terminal.set_allow_hyperlink (true);
            terminal.add_css_class ("shadow-hover-links");
            terminal.set_scroll_on_keystroke (true);
            terminal.set_scroll_on_output (false);
            var scroll = new Gtk.ScrolledWindow () {child = terminal, vexpand = true};
            var terminal_overlay = new Gtk.Overlay () {child = scroll, vexpand = true};
            terminal_context = new TerminalContext (this, terminal_overlay);
            editor = new RichInput ();
            editor.add_css_class ("composer-input");
            editor.fish_mode = shell_editor;
            editor.working_directory = shell_cwd;
            assistance = new ComposerAssist (editor);
            if (shell_editor) assistance.set_provider (fish_provider);
            analysis = new FishAnalysis (editor) {enabled = false};
            fish_provider.enabled = false;
            desktop_settings = Granite.Settings.get_default ();
            theme_handler = desktop_settings.notify["prefers-color-scheme"].connect (update_colors);

            menu = create_menu ();
            var root = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            root.add_css_class ("shadow-pane");
            root.append (create_search ());
            scroll.add_css_class ("terminal-scroll");
            root.append (terminal_overlay);
            root.append (create_composer ());
            feedback = new Gtk.Label ("Starting…") {hexpand = true, xalign = 0, wrap = true};
            restart = new Gtk.Button.with_label ("Restart") {visible = false};
            restart.clicked.connect (() => { terminal.reset (true, true); start (); });
            feedback_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            feedback_bar.add_css_class ("shadow-chrome");
            feedback_bar.add_css_class ("shadow-padding");
            feedback_bar.append (feedback); feedback_bar.append (restart);
            root.append (feedback_bar);
            append (root);
            apply_preferences ();
            preferences_handler = host.preferences.changed.connect (apply_preferences);
            if (PRIVATE_VTE) terminal.notify["shadow-alternate-screen"].connect (() => {
                terminal.get ("shadow-alternate-screen", out alternate_screen);
                alternate_composer_override = false;
                update_composer_visibility ();
                if (alternate_screen && editor.has_focus) terminal.grab_focus ();
            });
            editor.notify["has-focus"].connect (update_terminal_cursor);

            var keys = new Gtk.EventControllerKey () {propagation_phase = Gtk.PropagationPhase.CAPTURE};
            keys.key_pressed.connect ((key, code, state) => {
                if (editor.has_focus && assistance.handle_key (key, state)) return true;
                if (editor.has_focus && key == Gdk.Key.Return &&
                    (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK | Gdk.ModifierType.ALT_MASK)) == Gdk.ModifierType.CONTROL_MASK &&
                    !input_session.pending && (!shell_editor || !input_session.ready)) { paste_draft (); return true; }
                if (editor.has_focus && (key == Gdk.Key.Page_Up || key == Gdk.Key.Page_Down) &&
                    (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK)) == 0) {
                    var adjustment = terminal.vadjustment;
                    adjustment.value += (key == Gdk.Key.Page_Up ? -1 : 1) * adjustment.page_increment;
                    return true;
                }
                if (shell_editor && editor.has_focus && input_session.ready &&
                    (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK | Gdk.ModifierType.ALT_MASK)) == Gdk.ModifierType.CONTROL_MASK) {
                    uint lower = Gdk.keyval_to_lower (key);
                    if (lower == Gdk.Key.l && !input_session.pending) { terminal.feed_child ("\x0c".data); return true; }
                    if (lower == Gdk.Key.c && !editor.buffer.has_selection) {
                        if (input_session.pending) input_session.reject ("Submission cancelled; draft retained");
                        else {
                            Gtk.TextIter start, end;
                            editor.buffer.get_bounds (out start, out end);
                            editor.buffer.begin_user_action ();
                            editor.buffer.delete (ref start, ref end);
                            editor.buffer.end_user_action ();
                            terminal.feed_child ("\x03".data);
                        }
                        return true;
                    }
                    if (lower == Gdk.Key.d && editor.source () == "" && !input_session.pending) { terminal.feed_child ("\x04".data); return true; }
                }
                if (key == Gdk.Key.F1 && editor.has_focus) { show_shortcuts (); return true; }
                if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 && key == Gdk.Key.comma) {
                    show_preferences (); return true;
                }
                if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 && Gdk.keyval_to_lower (key) == Gdk.Key.f &&
                    (editor.has_focus || (state & Gdk.ModifierType.SHIFT_MASK) != 0)) {
                    open_search (editor.has_focus && (state & Gdk.ModifierType.SHIFT_MASK) == 0); return true;
                }
                if (key == Gdk.Key.Escape && editor.has_focus && input_session.pending) {
                    input_session.reject ("Submission cancelled; draft retained");
                    return true;
                }
                if (shell_editor && editor.has_focus && key == Gdk.Key.Return &&
                    (state & Gdk.ModifierType.SHIFT_MASK) == 0 && input_session.pending) return true;
                if (shell_editor && editor.has_focus && key == Gdk.Key.Return &&
                    (state & Gdk.ModifierType.SHIFT_MASK) == 0 && input_session.ready && !input_session.pending) {
                    submit_command ((state & Gdk.ModifierType.CONTROL_MASK) == 0);
                    return true;
                }
                if ((state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) !=
                    (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) return false;
                switch (Gdk.keyval_to_lower (key)) {
                case Gdk.Key.c:
                    if (editor.has_focus) {
                        Gtk.TextIter start, end;
                        if (editor.buffer.get_selection_bounds (out start, out end))
                            get_clipboard ().set_text (editor.buffer.get_text (start, end, true));
                    } else terminal_context.copy_selection ();
                    return true;
                case Gdk.Key.v: terminal.paste_clipboard (); return true;
                case Gdk.Key.n: host.new_terminal (shell_cwd); return true;
                case Gdk.Key.w: end_session (); return true;
                case Gdk.Key.h: hide_session (); return true;
                case Gdk.Key.m: compose_button.active = !compose_button.active; return true;
                case Gdk.Key.Return: paste_draft (); return true;
                case Gdk.Key.l:
                    if (editor.source () == "") editor.buffer.text = last_source;
                    compose_button.active = true; editor.grab_focus (); return true;
                case Gdk.Key.plus: case Gdk.Key.equal:
                    terminal.font_scale = double.min (3, terminal.font_scale + 0.1); return true;
                case Gdk.Key.minus: case Gdk.Key.underscore:
                    terminal.font_scale = double.max (0.5, terminal.font_scale - 0.1); return true;
                case Gdk.Key.@0: case Gdk.Key.parenright: terminal.font_scale = 1; return true;
                }
                return false;
            });
            ((Gtk.Widget) this).add_controller (keys);
            notify["title"].connect (() => window.update_session (this));
            terminal.termprop_changed.connect ((prop) => {
                if (prop != Vte.TERMPROP_XTERM_TITLE) return;
                size_t title_size;
                var child_title = terminal.get_termprop_string (prop, out title_size);
                if (child_title != null && child_title != "")
                    title = "%s · %s".printf (child_title, request.session);
            });
            terminal.child_exited.connect ((status) => {
                input_session.reset ();
                child_pid = 0; running = false;
                if (kill_timeout != 0) { Source.remove (kill_timeout); kill_timeout = 0; }
                if (closing || !request.hold) finish ();
                else {
                    string result = Process.if_exited (status) ? "exit %d".printf (Process.exit_status (status)) :
                        "signal %d".printf ((int) Process.term_sig (status));
                    feedback.label = "Process ended (%s) · %s".printf (result, request.session);
                    restart.visible = true;
                    feedback_bar.visible = true;
                }
            });
            editor.buffer.changed.connect (refresh_input);
            input_session.changed.connect (refresh_input);
            input_session.accepted.connect ((source_text) => {
                last_source = source_text;
                preview.fish_mode = editor.fish_mode;
                preview.dark = desktop_settings.prefers_color_scheme == Granite.Settings.ColorScheme.DARK;
                preview.buffer.text = source_text;
                preview_card.reveal_child = true;
                if (editor.source () == source_text) editor.buffer.text = "";
                refresh_input ();
            });
            input_session.rejected.connect ((reason) => {
                feedback.label = reason;
                feedback_bar.visible = true;
                if (enter_submission && reason.has_prefix ("Incomplete") && editor.source () == submitted_source)
                    editor.buffer.insert_at_cursor ("\n", -1);
                if (is_active && composer.reveal_child) editor.grab_focus ();
            });
        }

        private Gtk.Button menu_item (Gtk.Box box, Gtk.Popover popover, string label, string shortcut, owned MenuAction action) {
            var button = new Gtk.Button () {has_frame = false};
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 24);
            row.append (new Gtk.Label (label) {hexpand = true, xalign = 0});
            var hint = new Gtk.Label (shortcut) {xalign = 1};
            hint.add_css_class ("dim-label");
            row.append (hint);
            button.child = row;
            var command = new UiCommand (label, shortcut, (owned) action, button);
            commands.append (command);
            weak Gtk.Popover popup = popover;
            button.clicked.connect (() => { popup.popdown (); command.run (); });
            box.append (button);
            return button;
        }

        private Gtk.MenuButton create_menu () {
            var menu = new Gtk.MenuButton () {icon_name = "open-menu-symbolic", tooltip_text = "Terminal Options"};
            menu.add_css_class ("header-action");
            var popover = new Gtk.Popover ();
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {margin_start = 6, margin_end = 6, margin_top = 6, margin_bottom = 6};
            menu_item (box, popover, "New Tab", "Ctrl+T", () => host.new_tab (window, shell_cwd));
            menu_item (box, popover, "New Tab in Default Directory", "Ctrl+N", () => window.new_default_tab ());
            menu_item (box, popover, "New Window", "Ctrl+Shift+N", () => host.new_terminal (shell_cwd));
            menu_item (box, popover, "Command Palette…", "Ctrl+Shift+P", show_palette);
            menu_item (box, popover, "Find in Terminal", "Ctrl+Shift+F", () => open_search (false));
            compose_button = new Gtk.ToggleButton.with_label ("V Composer") {active = shell_editor,
                tooltip_text = "Show Composer or use native terminal input (Ctrl+Shift+M)", has_frame = false};
            box.append (compose_button);
            weak Gtk.Popover header_popup = popover;
            compose_button.toggled.connect (() => { if (header_popup != null) header_popup.popdown (); });
            commands.append (new UiCommand ("Toggle Composer", "Ctrl+Shift+M", () => { compose_button.active = !compose_button.active; }));
            box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            menu_item (box, popover, "Preferences…", "Ctrl+,", show_preferences);
            menu_item (box, popover, "Keyboard Shortcuts", "F1", show_shortcuts);
            box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            menu_item (box, popover, "Hide Window", "Ctrl+Shift+H", hide_session);
            menu_item (box, popover, "Close Tab", "Ctrl+W", end_session);
            menu_item (box, popover, "Close Window", "Ctrl+Shift+Q", () => window.close_workspace ());
            popover.child = box; menu.popover = popover;
            return menu;
        }

        private Gtk.Revealer create_composer () {
            compose_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            compose_box.add_css_class ("shadow-composer");
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            var prompt = new Gtk.Image.from_icon_name ("go-next-symbolic") {margin_start = 14, margin_end = 0};
            prompt.add_css_class ("dim-label");
            row.append (prompt);
            editor.left_margin = 10;
            editor.right_margin = 10;
            var editor_overlay = new Gtk.Overlay ();
            editor_overlay.child = editor;
            var placeholder = new Gtk.Label (shell_editor ? "Type a command…" : "Write something…") {
                xalign = 0, valign = Gtk.Align.START, margin_start = 10, margin_top = 12, can_target = false};
            placeholder.add_css_class ("dim-label");
            editor_overlay.add_overlay (placeholder);
            weak Gtk.Label empty_hint = placeholder;
            weak Gtk.TextBuffer draft_buffer = editor.buffer;
            editor.buffer.changed.connect (() => { if (empty_hint != null) empty_hint.visible = draft_buffer.get_char_count () == 0; });
            row.append (new Gtk.ScrolledWindow () {child = editor_overlay, hexpand = true,
                min_content_height = 48, max_content_height = 190, propagate_natural_height = true});
            cancel_button = new Gtk.Button.from_icon_name ("process-stop-symbolic") {
                visible = false, tooltip_text = "Cancel Submission (Escape)", valign = Gtk.Align.CENTER, has_frame = false};
            cancel_button.clicked.connect (() => input_session.reject ("Submission cancelled; draft retained"));
            submit_button = new Gtk.Button.from_icon_name ("go-up-symbolic") {
                visible = false, sensitive = false, tooltip_text = "Run Command (Enter; Shift+Enter adds a line)", valign = Gtk.Align.CENTER};
            submit_button.add_css_class ("suggested-action");
            submit_button.add_css_class ("circular");
            submit_button.clicked.connect (() => {
                if (shell_editor && input_session.ready) submit_command (false);
                else paste_draft ();
            });
            var options = new Gtk.MenuButton () {icon_name = "view-more-symbolic", tooltip_text = "Composer Options",
                valign = Gtk.Align.CENTER, margin_start = 4, margin_end = 10, has_frame = false};
            var popover = new Gtk.Popover ();
            var tools = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {margin_start = 12, margin_end = 12, margin_top = 12, margin_bottom = 12};
            var style_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            style_row.append (new Gtk.Label ("Presentation") {hexpand = true, xalign = 0});
            mode = new Gtk.DropDown.from_strings ({"Markdown", "Fish"});
            mode.selected = shell_editor ? 1 : 0;
            mode.notify["selected"].connect (() => { editor.fish_mode = mode.selected == 1; });
            style_row.append (mode); tools.append (style_row);
            var source = new Gtk.CheckButton.with_label ("Show Markdown Source");
            source.bind_property ("active", editor, "source-mode", BindingFlags.SYNC_CREATE);
            tools.append (source);
            editor.bind_property ("fish-mode", source, "visible", BindingFlags.SYNC_CREATE | BindingFlags.INVERT_BOOLEAN);
            tools.append (editor.formatting_toolbar ());
            menu_item (tools, popover, "Suggestions", "Ctrl+Space", () => { editor.grab_focus (); assistance.request.begin (); });
            recall_button = menu_item (tools, popover, "Recall Last Input", "Ctrl+Shift+L", () => {
                if (editor.source () == "") editor.buffer.text = last_source;
                editor.grab_focus ();
            });
            recall_button.sensitive = false;
            menu_item (tools, popover, "Find in Composer", "Ctrl+F", () => open_search (true));
            menu_item (tools, popover, "Paste into Terminal", "Ctrl+Shift+Enter", paste_draft);
            var context_options = new Gtk.Expander ("Context Information") {child = new ContextOptions (host.preferences)};
            tools.append (context_options);
            menu_item (tools, popover, "Refresh Repository", "", () => context_bar.refresh_repository ());
            preview = new RichInput () {editable = false, cursor_visible = false, reveal_active_line = false};
            var last_input = new Gtk.Expander ("Last Input") {child = new Gtk.ScrolledWindow () {
                child = preview, max_content_height = 140, max_content_width = 480, propagate_natural_height = true}};
            preview_card = new Gtk.Revealer () {child = last_input, transition_duration = 0};
            tools.append (preview_card);
            popover.child = tools; options.popover = popover;
            row.append (cancel_button); row.append (submit_button); row.append (options);
            compose_box.append (row);
            analysis.status.margin_start = 42;
            analysis.status.margin_end = 14;
            compose_box.append (analysis.status);
            context_bar = new ContextBar (host.preferences, shell_cwd);
            compose_box.append (context_bar);
            compose_box.map.connect (context_bar.refresh_repository);
            compose_box.unmap.connect (context_bar.cancel);
            composer = new Gtk.Revealer () {child = compose_box, transition_duration = 0};
            composer.reveal_child = compose_button.active;
            compose_button.toggled.connect (() => {
                if (adjusting_composer_toggle) return;
                if (alternate_screen && !alternate_composer_override && !compose_button.active) {
                    // An enabled but automatically hidden editor should appear
                    // on the first explicit toggle, without a disable/enable pair.
                    alternate_composer_override = true;
                    adjusting_composer_toggle = true;
                    compose_button.active = true;
                    adjusting_composer_toggle = false;
                } else if (alternate_screen) alternate_composer_override = compose_button.active;
                update_composer_visibility ();
                presentation_dirty = true;
                sync_presentation ();
                if (compose_button.active) editor.grab_focus (); else terminal.grab_focus ();
            });
            return composer;
        }

        private void show_shortcuts () {
            if (shortcuts_window == null) {
                shortcuts_window = new Gtk.Window () {title = "Keyboard Shortcuts", transient_for = window, application = host,
                    modal = true, destroy_with_parent = true, resizable = false};
                shortcuts_window.titlebar = new Gtk.HeaderBar ();
                var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {margin_start = 24, margin_end = 24, margin_top = 18, margin_bottom = 24};
                var grid = new Gtk.Grid () {column_spacing = 36, row_spacing = 10};
                string[] actions = {"Run command / New line", "Run without adding a line", "Suggestions", "Composer / Native input",
                    "Recall last input", "Find in Composer / Terminal", "Copy / Paste terminal text", "Paste Composer source into terminal",
                    "New tab / Tab in default directory", "New window", "Close tab / Close window", "Previous / Next tab", "Command palette", "Hide window", "Preferences", "Bold / Italic / Code (Markdown)", "Zoom in / Out / Reset"};
                string[] shortcuts = {"Enter / Shift+Enter", "Ctrl+Enter", "Ctrl+Space", "Ctrl+Shift+M", "Ctrl+Shift+L",
                    "Ctrl+F / Ctrl+Shift+F", "Ctrl+Shift+C / V", "Ctrl+Shift+Enter", "Ctrl+T / N", "Ctrl+Shift+N", "Ctrl+W / Ctrl+Shift+Q",
                    "Ctrl+Page Up / Down", "Ctrl+Shift+P", "Ctrl+Shift+H",
                    "Ctrl+,", "Ctrl+B / I / `", "Ctrl+Shift+Plus / Minus / 0"};
                for (int i = 0; i < actions.length; i++) {
                    grid.attach (new Gtk.Label (actions[i]) {xalign = 0}, 0, i);
                    grid.attach (new Gtk.Label (shortcuts[i]) {xalign = 1}, 1, i);
                }
                box.append (grid);
                box.append (new Gtk.Label ("Foreground programs receive terminal input.\nSuggestions edit the draft; accepting one never runs it.") {xalign = 0});
                shortcuts_window.child = box;
                var keys = new Gtk.EventControllerKey ();
                keys.key_pressed.connect ((key) => { if (key == Gdk.Key.Escape) { shortcuts_window.close (); return true; } return false; });
                ((Gtk.Widget) shortcuts_window).add_controller (keys);
                shortcuts_window.close_request.connect (() => { shortcuts_window = null; return false; });
            }
            shortcuts_window.present ();
        }

        public void show_palette () {
            if (palette_window == null) {
                var available = new List<UiCommand> ();
                foreach (var command in commands) if (command.label != "Command Palette…") available.append (command);
                palette_window = new CommandPalette (window, (owned) available);
                palette_window.close_request.connect (() => { palette_window = null; return false; });
            }
            palette_window.present ();
        }

        private void refresh_input () {
            update_composer_visibility ();
            context_bar.set_ready (input_session.ready);
            bool command_input = shell_editor && input_session.ready;
            fish_provider.enabled = command_input;
            if (analysis.enabled != command_input) analysis.enabled = command_input;
            submit_button.sensitive = running && !input_session.pending && editor.source () != "";
            submit_button.visible = editor.source () != "" && !input_session.pending;
            submit_button.icon_name = command_input ? "go-up-symbolic" : "edit-paste-symbolic";
            submit_button.tooltip_text = command_input ? "Run Command (Enter; Shift+Enter adds a line)" : "Paste into Program (Ctrl+Enter; Enter adds a line)";
            cancel_button.visible = input_session.pending;
            recall_button.sensitive = last_source != "" && editor.source () == "";
            bool became_ready = input_session.ready && !previous_ready;
            bool became_busy = !input_session.ready && previous_ready;
            previous_ready = input_session.ready;
            if (became_ready || became_busy) assistance.dismiss ();
            sync_presentation ();
            if (shell_editor) {
                if (running) feedback_bar.visible = input_session.pending;
                if (input_session.pending) feedback.label = "Waiting for fish to accept input…";
                if (is_active) {
                    if (became_ready && composer.reveal_child) editor.grab_focus ();
                    else if (became_busy) terminal.grab_focus ();
                }
            }
        }

        private void update_composer_visibility () {
            // Screen state comes from VTE itself. Ordinary foreground readers
            // can still consume explicitly pasted Composer source.
            composer.reveal_child = compose_button.active && (!alternate_screen || alternate_composer_override);
            update_terminal_cursor ();
        }

        private void update_terminal_cursor () {
            // VTE has no host cursor-visibility API. At the empty suppressed
            // prompt, matching its colours hides the idle outline without
            // injecting terminal control sequences or changing emulator state.
            bool hidden = composer.reveal_child && (input_session.ready || editor.has_focus);
            if (hidden) terminal.add_css_class ("shadow-composer-cursor");
            else terminal.remove_css_class ("shadow-composer-cursor");
            terminal.queue_draw ();
            if (PRIVATE_VTE) return;
            bool dark = desktop_settings.prefers_color_scheme == Granite.Settings.ColorScheme.DARK;
            Gdk.RGBA background = host.preferences.pane_background (dark);
            Gdk.RGBA foreground = host.preferences.pane_foreground (dark);
            if (hidden) {
                terminal.set_color_cursor (background);
                terminal.set_color_cursor_foreground (foreground);
            } else {
                terminal.set_color_cursor (null);
                terminal.set_color_cursor_foreground (null);
            }
            terminal.set_cursor_blink_mode (hidden ? Vte.CursorBlinkMode.OFF : Vte.CursorBlinkMode.SYSTEM);
        }

        public bool composer_active () {
            return shell_editor && compose_button.active;
        }

        private void sync_presentation () {
            // Never send a prompt-control binding to a foreground program.
            if (!presentation_dirty || !shell_editor || !input_session.ready || input_session.pending) return;
            presentation_dirty = false;
            terminal.feed_child ("\x1b\x10".data);
        }

        private void submit_command (bool from_enter) {
            if (!shell_editor || !running || !input_session.ready || input_session.pending || editor.source () == "") return;
            assistance.expand_abbreviation ();
            try {
                submitted_source = editor.source ();
                enter_submission = from_enter;
                input_session.prepare (submitted_source);
                // fish's binding retrieves source over the bridge. No source,
                // markup, quoting or terminal paste conversion occurs here.
                terminal.feed_child ("\x1b\x0f".data);
            } catch (IOError error) { feedback.label = error.message; feedback_bar.visible = true; }
        }

        public void shell_directory (string directory) {
            shell_cwd = directory;
            window.update_session (this);
            editor.working_directory = directory;
            context_bar.set_directory (directory);
            refresh_input ();
        }

        public bool shell_context (string[] fields) { return context_bar.prompt.update (fields); }

        public void shell_metadata (string abbreviations, string completions, string paths, string functions) {
            assistance.dismiss ();
            fish_provider.configure (abbreviations, completions, paths, functions);
        }

        private Gtk.Revealer create_search () {
            search_entry = new Gtk.SearchEntry () {hexpand = true, placeholder_text = "Find literal text"};
            search_target = new Gtk.DropDown.from_strings ({"Terminal", "Composer"});
            var previous = new Gtk.Button.from_icon_name ("go-up-symbolic") {tooltip_text = "Previous Match (Shift+Enter)"};
            var next = new Gtk.Button.from_icon_name ("go-down-symbolic") {tooltip_text = "Next Match (Enter)"};
            var close = new Gtk.Button.from_icon_name ("window-close-symbolic") {tooltip_text = "Close Search (Escape)"};
            search_status = new Gtk.Label ("");
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            box.add_css_class ("shadow-chrome");
            box.add_css_class ("shadow-padding");
            box.append (search_target); box.append (search_entry); box.append (search_status);
            box.append (previous); box.append (next); box.append (close);
            search = new Gtk.Revealer () {child = box, transition_duration = 0};
            next.clicked.connect (() => find_next (false));
            previous.clicked.connect (() => find_next (true));
            close.clicked.connect (close_search);
            search_entry.stop_search.connect (close_search);
            var keys = new Gtk.EventControllerKey () {propagation_phase = Gtk.PropagationPhase.CAPTURE};
            keys.key_pressed.connect ((key, code, state) => {
                if (key == Gdk.Key.Return) { find_next ((state & Gdk.ModifierType.SHIFT_MASK) != 0); return true; }
                return false;
            });
            search_entry.add_controller (keys);
            return search;
        }

        private void open_search (bool in_composer) {
            assistance.dismiss ();
            search_target.selected = in_composer ? 1 : 0;
            search.reveal_child = true;
            search_entry.grab_focus ();
        }

        private void close_search () {
            search.reveal_child = false;
            terminal.search_set_regex (null, 0);
            if (search_target.selected == 1 && composer.reveal_child) editor.grab_focus ();
            else terminal.grab_focus ();
        }

        private void find_next (bool previous) {
            string query = search_entry.text;
            if (query == "") { search_status.label = ""; return; }
            bool found = false;
            if (search_target.selected == 1) found = editor.find_text (query, previous);
            else {
                try {
                    // VTE takes PCRE2 flags, not GLib.RegexCompileFlags.
                    var regex = new Vte.Regex.for_search ("(?mi)" + Regex.escape_string (query), -1, (uint32) Vte.REGEX_FLAGS_DEFAULT);
                    if (terminal.search_get_regex () == null || last_search != query) {
                        terminal.search_set_regex (regex, 0); last_search = query;
                    }
                    terminal.search_set_wrap_around (true);
                    found = previous ? terminal.search_find_previous () : terminal.search_find_next ();
                } catch (Error error) { search_status.label = error.message; return; }
            }
            search_status.label = found ? "Match" : "No match";
        }
        private string last_search = "";

        private void show_preferences () {
            if (preferences_window == null) {
                preferences_window = new PreferencesWindow (window, host.preferences);
                preferences_window.close_request.connect (() => { preferences_window = null; return false; });
            }
            preferences_window.present ();
        }

        private void apply_preferences () {
            terminal.set_font (Pango.FontDescription.from_string (host.preferences.terminal_font));
            terminal.set_scrollback_lines ((long) host.preferences.scrollback);
            editor.set_editor_font (host.preferences.editor_font);
            preview.set_editor_font (host.preferences.editor_font);
            context_bar.apply_preferences ();
            update_colors ();
        }

        private void update_colors () {
            bool dark = Granite.Settings.get_default ().prefers_color_scheme == Granite.Settings.ColorScheme.DARK;
            editor.dark = dark;
            if (preview != null) preview.dark = dark;
            var background = host.preferences.pane_background (dark);
            var foreground = host.preferences.pane_foreground (dark);
            bool editor_dark = host.preferences.inherit_style ?
                background.red * 0.2126 + background.green * 0.7152 + background.blue * 0.0722 < 0.5 : dark;
            editor.dark = editor_dark;
            if (preview != null) preview.dark = dark;
            terminal.set_colors (foreground, background, null);
            update_terminal_cursor ();
            if (compose_box != null) {
                if (host.preferences.inherit_style) compose_box.add_css_class ("inherit-pane-style");
                else compose_box.remove_css_class ("inherit-pane-style");
            }
        }

        private void paste_draft () {
            if (!running) return;
            terminal.paste_text (editor.source ());
            terminal.grab_focus ();
        }

        public void start () {
            if (spawning || running || closing) return;
            spawning = true;
            restart.visible = false;
            feedback.label = "Starting…";
            feedback_bar.visible = true;
            spawn_cancel = new Cancellable ();
            input_session.reset ();
            // A restarted shell must not inherit the previous process's result
            // or environment snapshot before it reports its own prompt.
            context_bar.prompt.update ({"0", "0", "0", "0", "", "", "0", "0", "", ""});
            // Remove parent-terminal identity so children discover this VTE,
            // rather than sending Kitty-specific control to the outer terminal.
            string[] env = environment;
            foreach (string key in new string[] {"KITTY_WINDOW_ID", "KITTY_PID", "KITTY_LISTEN_ON", "WINDOWID"})
                env = Environ.unset_variable (env, key);
            env = Environ.set_variable (env, "TERM", "xterm-256color", true);
            env = Environ.set_variable (env, "COLORTERM", "truecolor", true);
            env = Environ.set_variable (env, "TERM_PROGRAM", "shadow-term", true);
            env = Environ.set_variable (env, "TERM_PROGRAM_VERSION", VERSION, true);
            string[] command = request.command;
            if (shell_editor) {
                env = Environ.set_variable (env, "SHADOW_TERM_HELPER", SHELL_HELPER_PATH, true);
                env = Environ.set_variable (env, "SHADOW_TERM_SESSION", request.session, true);
                env = Environ.set_variable (env, "SHADOW_TERM_TOKEN", input_session.token, true);
                env = Environ.set_variable (env, "SHADOW_TERM_INTEGRATION", FISH_INTEGRATION_PATH, true);
                command = {request.command[0], "--init-command", "source \"$SHADOW_TERM_INTEGRATION\""};
                foreach (string arg in request.command[1:request.command.length]) command += arg;
            }
            terminal.spawn_async (Vte.PtyFlags.DEFAULT, request.cwd, command, env,
                SpawnFlags.SEARCH_PATH_FROM_ENVP, null, -1, spawn_cancel, (widget, pid, error) => {
                    spawning = false;
                    if (error != null) {
                        if (closing) finish ();
                        else { feedback.label = "Launch failed: " + error.message; restart.visible = true; feedback_bar.visible = true; }
                        return;
                    }
                    child_pid = pid; running = true;
                    if (closing) { stop_child (); return; }
                    feedback_bar.visible = false;
                    refresh_input ();
                });
        }

        public void show_session () {
            if (!closing) window.present_session (this);
        }

        public void focus_input () {
            if (shell_editor && input_session.ready && composer.reveal_child) editor.grab_focus ();
            else terminal.grab_focus ();
        }

        public void hide_session () {
            if (!closing) window.hide_workspace ();
        }

        private void signal_child (int signum) {
            if (child_pid <= 0) return;
            var pty = terminal.get_pty ();
            int foreground = pty == null ? -1 : Posix.tcgetpgrp (pty.get_fd ());
            if (foreground > 0) Posix.kill (-foreground, signum);
            Posix.kill (-child_pid, signum);
            Posix.kill (child_pid, signum);
        }

        private void stop_child () {
            signal_child (Posix.Signal.HUP);
            signal_child (Posix.Signal.TERM);
            kill_timeout = Timeout.add (800, () => {
                kill_timeout = 0;
                if (running) signal_child (Posix.Signal.KILL);
                return Source.REMOVE;
            });
        }

        public void end_session () {
            if (closing) return;
            closing = true;
            window.session_closing (this);
            assistance.dismiss ();
            context_bar.cancel ();
            analysis.cancel ();
            input_session.reset ();
            visible = false;
            if (spawning) spawn_cancel.cancel ();
            else if (running) stop_child ();
            else finish ();
        }

        private void finish () {
            context_bar.cancel ();
            analysis.cancel ();
            terminal_context.close ();
            if (theme_handler != 0) { desktop_settings.disconnect (theme_handler); theme_handler = 0; }
            if (shortcuts_window != null) { shortcuts_window.destroy (); shortcuts_window = null; }
            if (palette_window != null) { palette_window.destroy (); palette_window = null; }
            if (preferences_window != null) { preferences_window.destroy (); preferences_window = null; }
            if (preferences_handler != 0) { host.preferences.disconnect (preferences_handler); preferences_handler = 0; }
            closing = true;
            window.remove_session (this);
            menu = null;
            commands = new List<UiCommand> ();
            ended ();
        }
    }

    public class Host : Gtk.Application {
        private HashTable<string, TerminalSession> sessions = new HashTable<string, TerminalSession> (str_hash, str_equal);
        private ShellBridge bridge;
        public Preferences preferences;
        private Gtk.CssProvider appearance_css = new Gtk.CssProvider ();

        public Host () {
            Object (application_id: "io.github.visrosa.Vibrant.ShadowTerm",
                flags: ApplicationFlags.HANDLES_COMMAND_LINE | ApplicationFlags.SEND_ENVIRONMENT);
        }

        protected override void startup () {
            base.startup ();
            Granite.init ();
            Gtk.Window.set_default_icon_name ("io.github.visrosa.Vibrant.ShadowTerm");
            Gtk.IconTheme.get_for_display (Gdk.Display.get_default ()).add_resource_path ("/io/github/visrosa/Vibrant/ShadowTerm/icons");
            preferences = new Preferences ();
            Gtk.StyleContext.add_provider_for_display (Gdk.Display.get_default (), appearance_css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            update_style ();
            preferences.changed.connect (update_style);
            Granite.Settings.get_default ().notify["prefers-color-scheme"].connect (update_style);
            bridge = new ShellBridge (this);
            try { get_dbus_connection ().register_object<ShellBridge> ("/io/github/visrosa/Vibrant/Shell", bridge); }
            catch (IOError error) { warning ("Shell integration unavailable: %s", error.message); }
            Unix.signal_add (Posix.Signal.TERM, () => { end_all (); return Source.CONTINUE; });
            Unix.signal_add (Posix.Signal.INT, () => { end_all (); return Source.CONTINUE; });
        }

        private void update_style () {
            bool dark = Granite.Settings.get_default ().prefers_color_scheme == Granite.Settings.ColorScheme.DARK;
            string foreground = preferences.pane_foreground (dark).to_string ();
            string header_foreground = preferences.inherit_style ? foreground : "@theme_fg_color";
            string background = preferences.pane_background (dark).to_string ();
            string header_background = preferences.inherit_style ? preferences.header_background (dark).to_string () : "@theme_bg_color";
            appearance_css.load_from_string ("""
                window.shadow-terminal { background-color: transparent; }
                vte-terminal { padding: 10px 14px; }
                .shadow-chrome { background-color: @theme_bg_color; color: @theme_fg_color; }
                .shadow-padding { padding: 8px 14px; }
                headerbar.shadow-header { background-image: none; background-color: %s; color: %s;
                    box-shadow: none; border: none; }
                headerbar.shadow-header button.header-action,
                headerbar.shadow-header .header-action > button,
                headerbar.shadow-header windowcontrols button { color: %s; }
                .workspace-tab { border-radius: 8px; }
                .workspace-tab.selected { background-color: alpha(currentColor, 0.12); }
                .workspace-tab > button { color: inherit; }
                .workspace-tab > button:checked { background: transparent; box-shadow: none; }
                .shadow-composer { background-color: @theme_bg_color; color: @theme_fg_color;
                    border-top: 1px solid alpha(@theme_fg_color, 0.12); }
                .shadow-composer textview, .shadow-composer textview text { background-color: transparent; }
                .composer-context { font-size: 0.85em; }
                .shadow-composer.inherit-pane-style { background-color: %s; color: %s; }
                .shadow-composer.inherit-pane-style textview.composer-input,
                .shadow-composer.inherit-pane-style textview.composer-input text { color: %s; caret-color: %s; }
            """.printf (header_background, header_foreground, header_foreground, background, foreground, foreground, foreground));
        }

        public TerminalSession shell_window (string session, int pid) throws IOError {
            var window = sessions.lookup (session);
            if (window == null || window.closing || pid <= 0 || pid != window.child_pid)
                throw new IOError.PERMISSION_DENIED ("Shell process is not attached to this session");
            return window;
        }

        public string input_status (string session) throws IOError {
            var window = sessions.lookup (session);
            if (window == null || window.closing) throw new IOError.NOT_FOUND ("Session not found");
            return window.input_session.pending ? "pending" : window.input_session.ready ? "ready" : "busy";
        }

        private void end_all () {
            foreach (var window in sessions.get_values ()) window.end_session ();
        }

        public void new_terminal (string cwd) {
            var r = new Request ();
            r.session = "terminal-" + Uuid.string_random ().substring (0, 8);
            r.cwd = cwd;
            r.command = r.argv ();
            open_session (r, Environ.get ());
        }

        public void new_tab (WorkspaceWindow window, string cwd) {
            var r = new Request ();
            r.session = "tab-" + Uuid.string_random ().substring (0, 8);
            r.cwd = cwd;
            r.command = r.argv ();
            open_session (r, Environ.get (), window);
        }

        private void open_session (Request r, string[] environment, WorkspaceWindow? target = null) {
            hold ();
            var window = target ?? new WorkspaceWindow (this, r);
            var session = new TerminalSession (this, window, r, environment);
            window.add_session (session);
            sessions.insert (r.session, session);
            session.ended.connect (() => { sessions.remove (r.session); release (); });
            window.present_session (session);
            session.start ();
        }

        protected override int command_line (ApplicationCommandLine invocation) {
            try {
                string[] args = invocation.get_arguments ();
                var r = Request.decode (args[1]);
                if (r.action == "list") {
                    foreach (var window in sessions.get_values ())
                        invocation.print ("%s\t%s\t%d\n", window.request.session,
                            window.is_presented ? "visible" : "hidden", (int) window.child_pid);
                    return 0;
                }
                var existing = sessions.lookup (r.session);
                if (existing != null) {
                    if (r.configured && !r.compatible (existing.request)) {
                        invocation.printerr ("Session already exists with different launch options; use a new name.\n");
                        return 2;
                    }
                    if (r.action == "quit") existing.end_session ();
                    else if (r.action == "hide" || (r.action == "toggle" && existing.is_presented && existing.is_active))
                        existing.hide_session ();
                    else existing.show_session ();
                    return 0;
                }
                if (r.action == "hide" || r.action == "quit") {
                    invocation.printerr ("Session not found: %s\n", r.session);
                    return 1;
                }
                open_session (r, invocation.get_environ ());
                return 0;
            } catch (Error error) {
                invocation.printerr ("%s\n", error.message);
                return 2;
            }
        }
    }
}

#if !PRESENTATION_TEST
int main (string[] args) {
    Environment.set_prgname ("io.github.visrosa.Vibrant.ShadowTerm");
    Environment.set_application_name ("Shadow Term");
    if (args.length == 2 && args[1] == "--version") {
        stdout.printf ("Shadow Term %s\n", Shadow.VERSION); return 0;
    }
    if (args.length == 2 && (args[1] == "--help" || args[1] == "-h")) {
        stdout.printf ("""Shadow Term 0.0.6 — interactive shell and command windows
Usage: shadow-term [OPTIONS] [-- COMMAND ARG...]
  --session NAME           Named session (default: default)
  --cwd DIRECTORY          Initial working directory (default: invoking directory)
  --title TITLE            Initial window title
  --size WIDTHxHEIGHT      Preferred initial size in logical pixels
  --input MODE             auto (Composer for fish), composer, or terminal
  --hide-on-focus-loss     Hide after activated window loses focus
  --hold                   Keep output after the command exits; offer Restart
  --show | --hide | --toggle | --quit | --list
                           Control sessions without launching another child
  --help | --version
Without a command, launch $SHELL or /bin/sh. A session's launch options are set
only on its first invocation. Use a new name for an independent terminal.
""");
        return 0;
    }
    try {
        var request = Shadow.Request.parse (args);
        var host = new Shadow.Host ();
        return host.run ({args[0], request.encode ()});
    } catch (Error error) {
        stderr.printf ("shadow-term: %s\n", error.message); return 2;
    }
}

#endif
