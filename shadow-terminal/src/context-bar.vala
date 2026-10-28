namespace Shadow {
    // Prompt chips belong to the host, not the source editor or PTY stream.
    // Flow layout keeps contextual information usable in narrow panes.
    public class ContextBar : Gtk.Box {
        private weak Preferences settings;
        public RepositoryContext repository = new RepositoryContext ();
        public PromptContext prompt = new PromptContext ();
        private string directory = "";
        private bool ready = false;
        private ContextDetailsPopover[] details = {};
        public signal bool action_requested (ContextAction action, string origin_directory);
        public signal void context_dismissed ();
        private Gtk.FlowBoxChild[] chips = {};
        private Gtk.Label[] labels = {};
        private const string[] KEYS = {"directory", "git", "result", "duration", "environment", "identity", "jobs"};
        private const string[] ICONS = {"folder-symbolic", "shadow-branch-symbolic", "dialog-error-symbolic",
            "preferences-system-time-symbolic", "applications-science-symbolic", "network-server-symbolic", "view-list-symbolic"};

        public ContextBar (Preferences settings, string directory) {
            Object (orientation: Gtk.Orientation.VERTICAL,
                margin_start: 38, margin_end: 14, margin_bottom: 8, focusable: false);
            this.settings = settings; this.directory = directory;
            add_css_class ("composer-context");
            var flow = new Gtk.FlowBox () {selection_mode = Gtk.SelectionMode.NONE, homogeneous = false,
                min_children_per_line = 1, max_children_per_line = 7, column_spacing = 12, row_spacing = 4, focusable = false};
            append (flow);
            for (int i = 0; i < KEYS.length; i++) {
                var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 5);
                box.append (new Gtk.Image.from_icon_name (ICONS[i]) {pixel_size = 14});
                var label = new Gtk.Label ("") {xalign = 0, ellipsize = Pango.EllipsizeMode.MIDDLE,
                    max_width_chars = i == 1 ? 48 : 28};
                box.append (label);
                Gtk.Widget content = box;
                if (i < 2) {
                    var menu = new Gtk.MenuButton () {child = box, has_frame = false, direction = Gtk.ArrowType.NONE};
                    var popup = new ContextDetailsPopover (i == 0 ? ContextDetailsKind.DIRECTORY : ContextDetailsKind.GIT);
                    menu.tooltip_text = i == 0 ? "Browse directories" : "Inspect repository";
                    popup.closed.connect (() => context_dismissed ());
                    popup.action_requested.connect ((action, origin) => action_requested (action, origin));
                    popup.map.connect (() => popup.load.begin (this.directory, ready));
                    Native.menu_popover (menu, popup); details += popup; content = menu;
                }
                var chip = new Gtk.FlowBoxChild () {child = content, focusable = false};
                chip.add_css_class ("context-" + KEYS[i]);
                if (i == 2) chip.add_css_class ("error"); else chip.add_css_class ("dim-label");
                flow.append (chip);
                chips += chip; labels += label;
            }
            prompt.changed.connect (update);
            repository.notify["summary"].connect (update);
            repository.notify["detail"].connect (update);
            apply_preferences ();
        }

        public void apply_preferences () {
            bool wanted = settings.context_visible ("enabled") && settings.context_visible ("git");
            bool newly_enabled = wanted && !repository.enabled;
            repository.enabled = wanted;
            close_details ();
            update ();
            if (newly_enabled) refresh_repository ();
        }

        private void close_details () { foreach (var popup in details) { popup.cancel (); popup.popdown (); } }
        public void set_ready (bool ready) { if (this.ready != ready) close_details (); this.ready = ready; update (); }

        public void set_directory (string directory) {
            if (this.directory != directory) close_details ();
            this.directory = directory;
            update ();
            refresh_repository ();
        }

        public void refresh_repository () {
            if (get_parent () != null && get_parent ().get_mapped () && repository.enabled && directory != "") repository.refresh.begin (directory);
        }

        public void cancel () { repository.cancel (); close_details (); }

        private void update () {
            string home = Environment.get_home_dir ();
            string short_dir = directory == home ? "~" : directory.has_prefix (home + "/") ? "~" + directory.substring (home.length) : directory;
            string[] text = {PromptContext.display_text (short_dir), repository.summary, ready ? prompt.result_summary () : "",
                ready ? prompt.duration_summary () : "", prompt.environment_summary (), prompt.identity_summary (),
                prompt.jobs > 0 ? "%d %s".printf (prompt.jobs, prompt.jobs == 1 ? "job" : "jobs") : ""};
            string[] detail = {directory, repository.detail, "Last command exit: %d · pipeline: %s".printf (prompt.exit_status, prompt.pipeline),
                ("Last command duration: %" + int64.FORMAT + " ms").printf (prompt.duration_ms),
                "Python environment: %s\nConda environment: %s".printf (prompt.virtual_env, prompt.conda_env),
                prompt.ssh ? "SSH session · " + prompt.identity_summary () : "Local session · " + prompt.identity_summary (),
                "Background jobs at the last shell prompt"};
            bool any = false;
            for (int i = 0; i < KEYS.length; i++) {
                labels[i].label = text[i];
                chips[i].tooltip_text = detail[i];
                chips[i].visible = settings.context_visible ("enabled") && settings.context_visible (KEYS[i]) && text[i] != "";
                any = any || chips[i].visible;
            }
            visible = any;
        }
    }
}
