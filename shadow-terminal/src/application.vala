namespace Shadow {
    [CCode (cname = "shadow_position", cheader_filename = "placement.h")]
    extern bool position (Gtk.Window window, int x, int y, bool restore);
    [CCode (cname = "shadow_get_position", cheader_filename = "placement.h")]
    extern bool get_position (Gtk.Window window, out int x, out int y);

    public class TerminalWindow : Gtk.ApplicationWindow {
        public Request request;
        public Pid child_pid = 0;
        public bool closing = false;
        public bool running = false;
        public Vte.Terminal terminal;
        private RichInput editor;
        private Gtk.Label feedback;
        private Gtk.Revealer composer;
        private Gtk.Button restart;
        private Geometry geometry;
        private Cancellable spawn_cancel = new Cancellable ();
        private bool spawning = false;
        private bool was_active = false;
        private bool placed = false;
        private uint blur_idle = 0;
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
        private string shell_cwd;
        private ComposerAssist assistance;
        private Gtk.Revealer search;
        private Gtk.SearchEntry search_entry;
        private Gtk.DropDown search_target;
        private Gtk.Label search_status;
        private Gtk.Window? preferences_window;
        private ulong preferences_handler;
        public signal void ended ();

        public TerminalWindow (Host owner, Request config, string[] environment) {
            Object (application: owner);
            this.host = owner;
            this.request = config;
            shell_cwd = config.cwd;
            shell_editor = request.composer_enabled ();
            this.environment = environment;
            add_css_class ("shadow-terminal");
            geometry = new Geometry (request.session);
            int width = request.width > 0 ? request.width : geometry.width;
            int height = request.height > 0 ? request.height : geometry.height;
            // Size is a preference, not a minimum: users can still shrink it.
            var monitors = get_display ().get_monitors ();
            if (monitors.get_n_items () > 0) {
                var monitor = (Gdk.Monitor) monitors.get_item (0);
                var bounds = monitor.get_geometry ();
                width = int.min (width, int.max (320, bounds.width - 60));
                height = int.min (height, int.max (200, bounds.height - 80));
            }
            set_default_size (width, height);
            title = "%s · %s".printf (request.title, request.session);

            terminal = new Vte.Terminal () {hexpand = true, vexpand = true};
            terminal.set_font (Pango.FontDescription.from_string ("monospace 12"));
            terminal.set_scrollback_lines (10000);
            terminal.set_audible_bell (false);
            terminal.set_allow_hyperlink (true);
            terminal.set_scroll_on_keystroke (true);
            terminal.set_scroll_on_output (false);
            var scroll = new Gtk.ScrolledWindow () {child = terminal, vexpand = true};
            editor = new RichInput ();
            editor.fish_mode = shell_editor;
            editor.working_directory = shell_cwd;
            assistance = new ComposerAssist (editor);
            var settings = Granite.Settings.get_default ();
            settings.notify["prefers-color-scheme"].connect (update_colors);
            update_colors ();

            var header = new Gtk.HeaderBar ();
            var new_button = new Gtk.Button.from_icon_name ("tab-new-symbolic") {tooltip_text = "New Terminal (Ctrl+Shift+N)"};
            new_button.clicked.connect (() => host.new_terminal (shell_cwd));
            header.pack_start (new_button);
            var find_button = new Gtk.Button.from_icon_name ("edit-find-symbolic") {tooltip_text = "Find in Terminal (Ctrl+Shift+F)"};
            find_button.clicked.connect (() => open_search (false));
            header.pack_start (find_button);
            var preferences_button = new Gtk.Button.from_icon_name ("preferences-system-symbolic") {tooltip_text = "Preferences (Ctrl+,)"};
            preferences_button.clicked.connect (show_preferences);
            header.pack_end (preferences_button);
            var hide_button = new Gtk.Button.from_icon_name ("window-minimize-symbolic") {tooltip_text = "Hide Session (Ctrl+Shift+H)"};
            hide_button.clicked.connect (hide_session);
            header.pack_end (hide_button);
            compose_button = new Gtk.ToggleButton.with_label ("V Composer") {tooltip_text = "Show input editor (Ctrl+Shift+M)", active = shell_editor};
            header.pack_end (compose_button);
            set_titlebar (header);

            var tools = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                margin_start = 12, margin_end = 12, margin_top = 8, margin_bottom = 8
            };
            mode = new Gtk.DropDown.from_strings ({"Markdown", "Fish"});
            mode.selected = shell_editor ? 1 : 0;
            mode.notify["selected"].connect (() => { editor.fish_mode = mode.selected == 1; });
            var source = new Gtk.ToggleButton.with_label ("Show Source");
            source.bind_property ("active", editor, "source-mode", BindingFlags.SYNC_CREATE);
            var paste = new Gtk.Button.from_icon_name ("edit-paste-symbolic") {
                tooltip_text = "Paste into Terminal (Ctrl+Shift+Enter)", hexpand = true, halign = Gtk.Align.END};
            paste.clicked.connect (() => {
                paste_draft ();
            });
            recall_button = new Gtk.Button.with_label ("Recall Last") {sensitive = false};
            recall_button.clicked.connect (() => {
                if (editor.source () == "") editor.buffer.text = last_source;
                editor.grab_focus ();
            });
            submit_button = new Gtk.Button.with_label ("Run") {visible = shell_editor, sensitive = false};
            submit_button.add_css_class ("suggested-action");
            submit_button.clicked.connect (() => submit_command (false));
            cancel_button = new Gtk.Button.with_label ("Cancel") {visible = false};
            cancel_button.clicked.connect (() => input_session.reject ("Submission cancelled; draft retained"));
            var suggest = new Gtk.Button.from_icon_name ("insert-text-symbolic") {tooltip_text = "Suggestions (Ctrl+Space)", focus_on_click = false};
            suggest.clicked.connect (() => { editor.grab_focus (); assistance.request.begin (); });
            tools.append (mode); tools.append (source); tools.append (editor.formatting_toolbar ());
            tools.append (suggest); tools.append (recall_button);
            tools.append (paste); tools.append (cancel_button); tools.append (submit_button);
            var compose_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            compose_box.add_css_class ("shadow-chrome");
            compose_box.append (tools);
            compose_box.append (new Gtk.ScrolledWindow () {child = editor, min_content_height = 140});
            compose_box.append (assistance.panel);
            composer = new Gtk.Revealer () {child = compose_box, transition_duration = 0};
            compose_button.bind_property ("active", composer, "reveal-child", BindingFlags.SYNC_CREATE);
            compose_button.toggled.connect (() => {
                if (compose_button.active) editor.grab_focus (); else terminal.grab_focus ();
            });

            feedback = new Gtk.Label ("Starting…") {hexpand = true, xalign = 0, ellipsize = Pango.EllipsizeMode.MIDDLE};
            restart = new Gtk.Button.with_label ("Restart") {visible = false};
            restart.clicked.connect (() => { terminal.reset (true, true); start (); });
            var footer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                margin_start = 0, margin_end = 0, margin_top = 0, margin_bottom = 0
            };
            footer.add_css_class ("shadow-chrome");
            footer.add_css_class ("shadow-padding");
            footer.append (feedback); footer.append (restart);
            var root = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            root.append (create_search ());
            preview = new RichInput () {editable = false, cursor_visible = false, reveal_active_line = false};
            var preview_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            preview_box.add_css_class ("shadow-chrome");
            preview_box.append (new Gtk.Label ("Last input") {xalign = 0, margin_start = 12, margin_top = 6});
            preview_box.append (new Gtk.ScrolledWindow () {child = preview, max_content_height = 110,
                propagate_natural_height = true});
            preview_card = new Gtk.Revealer () {child = preview_box, transition_duration = 0};
            root.append (preview_card);
            root.append (scroll); root.append (composer); root.append (footer);
            set_child (root);
            apply_preferences ();
            preferences_handler = host.preferences.changed.connect (apply_preferences);

            var keys = new Gtk.EventControllerKey () {propagation_phase = Gtk.PropagationPhase.CAPTURE};
            keys.key_pressed.connect ((key, code, state) => {
                if (editor.has_focus && assistance.handle_key (key, state)) return true;
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
                    } else terminal.copy_clipboard_format (Vte.Format.TEXT);
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
            close_request.connect (() => { end_session (); return true; });
            map.connect (() => {
                if (!placed) {
                    placed = true;
                    // Allocate before computing the optional X11 position.
                    Idle.add (() => {
                        if (!closing && visible) position (this, geometry.x, geometry.y, geometry.positioned);
                        return Source.REMOVE;
                    });
                }
            });
            notify["is-active"].connect (() => {
                if (is_active) {
                    was_active = true;
                    if (shell_editor && input_session.ready && composer.reveal_child) editor.grab_focus ();
                }
                else if (was_active && visible && request.hide_on_blur && blur_idle == 0) {
                    blur_idle = Idle.add (() => {
                        blur_idle = 0;
                        if (!closing && !is_active && visible && !owned_dialog_active (host)) hide_session ();
                        return Source.REMOVE;
                    });
                }
            });
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
                }
            });
            editor.buffer.changed.connect (refresh_input);
            input_session.changed.connect (refresh_input);
            input_session.accepted.connect ((source_text) => {
                last_source = source_text;
                preview.fish_mode = editor.fish_mode;
                preview.dark = editor.dark;
                preview.buffer.text = source_text;
                preview_card.reveal_child = true;
                if (editor.source () == source_text) editor.buffer.text = "";
                refresh_input ();
            });
            input_session.rejected.connect ((reason) => {
                feedback.label = reason;
                if (enter_submission && reason.has_prefix ("Incomplete") && editor.source () == submitted_source)
                    editor.buffer.insert_at_cursor ("\n", -1);
                if (is_active && composer.reveal_child) editor.grab_focus ();
            });
        }

        private void refresh_input () {
            submit_button.sensitive = shell_editor && running && input_session.ready && !input_session.pending && editor.source () != "";
            cancel_button.visible = input_session.pending;
            recall_button.sensitive = last_source != "" && editor.source () == "";
            bool became_ready = input_session.ready && !previous_ready;
            bool became_busy = !input_session.ready && previous_ready;
            previous_ready = input_session.ready;
            if (shell_editor) {
                if (input_session.pending) feedback.label = "Waiting for fish to accept input…";
                else if (input_session.ready) feedback.label = "fish ready · Enter runs · Shift+Enter adds a line · " + shell_cwd;
                else if (running) feedback.label = "Program input uses the terminal · draft remains editable";
                if (is_active) {
                    if (became_ready && composer.reveal_child) editor.grab_focus ();
                    else if (became_busy) terminal.grab_focus ();
                }
            }
        }

        private void submit_command (bool from_enter) {
            if (!shell_editor || !running || !input_session.ready || input_session.pending || editor.source () == "") return;
            try {
                submitted_source = editor.source ();
                enter_submission = from_enter;
                input_session.prepare (submitted_source);
                // fish's binding retrieves source over the bridge. No source,
                // markup, quoting or terminal paste conversion occurs here.
                terminal.feed_child ("\x1b\x0f".data);
            } catch (IOError error) { feedback.label = error.message; }
        }

        public void shell_directory (string directory) {
            shell_cwd = directory;
            editor.working_directory = directory;
            refresh_input ();
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
                preferences_window = new PreferencesWindow (this, host.preferences);
                preferences_window.close_request.connect (() => { preferences_window = null; return false; });
            }
            preferences_window.present ();
        }

        private void apply_preferences () {
            terminal.set_font (Pango.FontDescription.from_string (host.preferences.terminal_font));
            terminal.set_scrollback_lines ((long) host.preferences.scrollback);
            editor.set_editor_font (host.preferences.editor_font);
            preview.set_editor_font (host.preferences.editor_font);
            update_colors ();
        }

        private bool owned_dialog_active (Host host) {
            foreach (var window in host.get_windows ()) {
                if (window == this || !window.is_active) continue;
                Gtk.Window? parent = window.transient_for;
                while (parent != null) {
                    if (parent == this) return true;
                    parent = parent.transient_for;
                }
            }
            return false;
        }

        private void update_colors () {
            bool dark = Granite.Settings.get_default ().prefers_color_scheme == Granite.Settings.ColorScheme.DARK;
            editor.dark = dark;
            if (preview != null) preview.dark = dark;
            Gdk.RGBA foreground = {}, background = {};
            foreground.parse (dark ? "#f6f5f4" : "#242424");
            background.parse (dark ? "#1e1e1e" : "#ffffff");
            background.alpha = (float) host.preferences.opacity;
            terminal.set_colors (foreground, background, null);
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
            spawn_cancel = new Cancellable ();
            input_session.reset ();
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
                        else { feedback.label = "Launch failed: " + error.message; restart.visible = true; }
                        return;
                    }
                    child_pid = pid; running = true;
                    if (closing) { stop_child (); return; }
                    feedback.label = "%s · %s".printf (request.session, request.cwd);
                    refresh_input ();
                });
        }

        private void save_geometry () {
            get_default_size (out geometry.width, out geometry.height);
            if (visible && !is_maximized () && !is_fullscreen ())
                geometry.positioned = get_position (this, out geometry.x, out geometry.y);
            geometry.save (request.session);
        }

        public void show_session () {
            if (closing) return;
            if (!visible) was_active = false;
            present ();
            if (shell_editor && input_session.ready && composer.reveal_child) editor.grab_focus ();
            else terminal.grab_focus ();
        }

        public void hide_session () {
            if (closing) return;
            save_geometry ();
            was_active = false;
            visible = false;
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
            save_geometry ();
            closing = true;
            assistance.dismiss ();
            input_session.reset ();
            visible = false;
            if (blur_idle != 0) { Source.remove (blur_idle); blur_idle = 0; }
            if (spawning) spawn_cancel.cancel ();
            else if (running) stop_child ();
            else finish ();
        }

        private void finish () {
            if (preferences_window != null) { preferences_window.destroy (); preferences_window = null; }
            if (preferences_handler != 0) { host.preferences.disconnect (preferences_handler); preferences_handler = 0; }
            if (blur_idle != 0) { Source.remove (blur_idle); blur_idle = 0; }
            destroy ();
            ended ();
        }
    }

    public class Host : Gtk.Application {
        private HashTable<string, TerminalWindow> sessions = new HashTable<string, TerminalWindow> (str_hash, str_equal);
        private ShellBridge bridge;
        public Preferences preferences;

        public Host () {
            Object (application_id: "io.github.visrosa.Vibrant.ShadowTerm",
                flags: ApplicationFlags.HANDLES_COMMAND_LINE | ApplicationFlags.SEND_ENVIRONMENT);
        }

        protected override void startup () {
            base.startup ();
            Granite.init ();
            preferences = new Preferences ();
            var css = new Gtk.CssProvider ();
            css.load_from_string ("window.shadow-terminal { background-color: transparent; } .shadow-chrome { background-color: @theme_bg_color; } .shadow-padding { padding: 6px 12px; }");
            Gtk.StyleContext.add_provider_for_display (Gdk.Display.get_default (), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            bridge = new ShellBridge (this);
            try { get_dbus_connection ().register_object<ShellBridge> ("/io/github/visrosa/Vibrant/Shell", bridge); }
            catch (IOError error) { warning ("Shell integration unavailable: %s", error.message); }
            Unix.signal_add (Posix.Signal.TERM, () => { end_all (); return Source.CONTINUE; });
            Unix.signal_add (Posix.Signal.INT, () => { end_all (); return Source.CONTINUE; });
        }

        public TerminalWindow shell_window (string session, int pid) throws IOError {
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

        private void open_session (Request r, string[] environment) {
            hold ();
            var window = new TerminalWindow (this, r, environment);
            sessions.insert (r.session, window);
            window.ended.connect (() => { sessions.remove (r.session); release (); });
            window.show_session ();
            window.start ();
        }

        protected override int command_line (ApplicationCommandLine invocation) {
            try {
                string[] args = invocation.get_arguments ();
                var r = Request.decode (args[1]);
                if (r.action == "list") {
                    foreach (var window in sessions.get_values ())
                        invocation.print ("%s\t%s\t%d\n", window.request.session,
                            window.visible ? "visible" : "hidden", (int) window.child_pid);
                    return 0;
                }
                var existing = sessions.lookup (r.session);
                if (existing != null) {
                    if (r.configured && !r.compatible (existing.request)) {
                        invocation.printerr ("Session already exists with different launch options; use a new name.\n");
                        return 2;
                    }
                    if (r.action == "quit") existing.end_session ();
                    else if (r.action == "hide" || (r.action == "toggle" && existing.visible && existing.is_active))
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

int main (string[] args) {
    if (args.length == 2 && args[1] == "--version") {
        stdout.printf ("Shadow Term %s\n", Shadow.VERSION); return 0;
    }
    if (args.length == 2 && (args[1] == "--help" || args[1] == "-h")) {
        stdout.printf ("""Shadow Term 0.0.3 — interactive shell and command windows
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
