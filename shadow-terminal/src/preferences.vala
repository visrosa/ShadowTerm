namespace Shadow {
    public class Preferences : Object {
        public string terminal_font = "Monospace 12";
        public string editor_font = "Monospace 12";
        public double opacity = 1;
        public int64 scrollback = 10000;
        public bool inherit_style = true;
        public bool system_colors = true;
        public string foreground = "#eeeeec";
        public string background = "#20242b";
        public double header_opacity_boost = 0;
        public const string[] CONTEXT_KEYS = {"enabled", "directory", "git", "result", "duration", "environment", "identity", "jobs"};
        public const string[] CONTEXT_LABELS = {"Show context information", "Working directory", "Git branch and changes",
            "Last command result", "Command duration", "Python / Conda environment", "User and host", "Background jobs"};
        private bool[] context_flags = {true, true, true, true, true, true, false, true};
        public signal void changed ();
        private string filename;

        public Preferences (string? filename = null) {
            this.filename = filename ?? Path.build_filename (Environment.get_user_config_dir (), "shadow-term", "preferences.ini");
            var file = new KeyFile ();
            try { file.load_from_file (this.filename, KeyFileFlags.NONE); } catch (Error error) { return; }
            try { terminal_font = valid_font (file.get_string ("appearance", "terminal-font"), terminal_font); } catch (Error error) {}
            try { editor_font = valid_font (file.get_string ("appearance", "editor-font"), editor_font); } catch (Error error) {}
            try {
                double value = file.get_double ("appearance", "opacity");
                if (value.is_finite ()) opacity = double.max (0, double.min (1, value));
            } catch (Error error) {}
            try { scrollback = int64.max (100, int64.min (100000, file.get_int64 ("terminal", "scrollback"))); } catch (Error error) {}
            try { inherit_style = file.get_boolean ("appearance", "inherit-pane-style"); } catch (Error error) {}
            try { system_colors = file.get_boolean ("appearance", "system-colors"); } catch (Error error) {}
            try { foreground = valid_color (file.get_string ("appearance", "foreground"), foreground); } catch (Error error) {}
            try { background = valid_color (file.get_string ("appearance", "background"), background); } catch (Error error) {}
            try {
                double value = file.get_double ("appearance", "header-opacity-boost");
                if (value.is_finite ()) header_opacity_boost = double.max (0, double.min (1, value));
            } catch (Error error) {}
            for (int i = 0; i < CONTEXT_KEYS.length; i++) {
                try { context_flags[i] = file.get_boolean ("context", CONTEXT_KEYS[i]); } catch (Error error) {}
            }
        }

        public bool context_visible (string key) {
            for (int i = 0; i < CONTEXT_KEYS.length; i++) if (CONTEXT_KEYS[i] == key) return context_flags[i];
            return false;
        }

        public void set_context_visible (string key, bool visible) throws Error {
            for (int i = 0; i < CONTEXT_KEYS.length; i++) {
                if (CONTEXT_KEYS[i] != key) continue;
                if (context_flags[i] == visible) return;
                context_flags[i] = visible;
                changed ();
                save ();
                return;
            }
            throw new IOError.INVALID_ARGUMENT ("Unknown context item");
        }

        public void reset_context () throws Error {
            context_flags = {true, true, true, true, true, true, false, true};
            changed ();
            save ();
        }

        private static string valid_color (string value, string fallback) {
            Gdk.RGBA color = {};
            if (value.length > 128 || !color.parse (value)) return fallback;
            color.alpha = 1;
            return color.to_string ();
        }

        public Gdk.RGBA pane_foreground (bool dark) {
            Gdk.RGBA color = {};
            color.parse (system_colors ? (dark ? "#f6f5f4" : "#242424") : foreground);
            return color;
        }

        public Gdk.RGBA pane_background (bool dark) {
            Gdk.RGBA color = {};
            color.parse (system_colors ? (dark ? "#20242b" : "#ffffff") : background);
            color.alpha = (float) opacity;
            return color;
        }

        public Gdk.RGBA header_background (bool dark) {
            var color = pane_background (dark);
            color.alpha = (float) (opacity + (1 - opacity) * header_opacity_boost);
            return color;
        }

        private static string valid_font (string value, string fallback) {
            if (value == "" || value.length > 512 || value.contains ("\n") || value.contains ("\r")) return fallback;
            var font = Pango.FontDescription.from_string (value);
            double size = font.get_size () / (double) Pango.SCALE;
            if (font.get_family () == null || size < 6 || size > 72) return fallback;
            return font.to_string ();
        }

        public void apply (string terminal, string editor, double opacity, int64 scrollback,
                           bool inherit_style = true, bool system_colors = true,
                           string foreground = "#eeeeec", string background = "#20242b", double header_opacity_boost = 0) throws Error {
            terminal_font = valid_font (terminal, terminal_font);
            editor_font = valid_font (editor, editor_font);
            this.opacity = opacity.is_finite () ? double.max (0, double.min (1, opacity)) : 1;
            this.scrollback = int64.max (100, int64.min (100000, scrollback));
            this.inherit_style = inherit_style;
            this.system_colors = system_colors;
            this.foreground = valid_color (foreground, this.foreground);
            this.background = valid_color (background, this.background);
            this.header_opacity_boost = header_opacity_boost.is_finite () ? double.max (0, double.min (1, header_opacity_boost)) : 0;
            changed ();
            save ();
        }

        private void save () throws Error {
            var file = new KeyFile ();
            file.set_string ("appearance", "terminal-font", terminal_font);
            file.set_string ("appearance", "editor-font", editor_font);
            file.set_double ("appearance", "opacity", this.opacity);
            file.set_int64 ("terminal", "scrollback", this.scrollback);
            file.set_boolean ("appearance", "inherit-pane-style", inherit_style);
            file.set_boolean ("appearance", "system-colors", system_colors);
            file.set_string ("appearance", "foreground", this.foreground);
            file.set_string ("appearance", "background", this.background);
            file.set_double ("appearance", "header-opacity-boost", this.header_opacity_boost);
            for (int i = 0; i < CONTEXT_KEYS.length; i++) file.set_boolean ("context", CONTEXT_KEYS[i], context_flags[i]);
            if (DirUtils.create_with_parents (Path.get_dirname (filename), 0700) != 0)
                throw new IOError.FAILED ("Could not create the preferences directory");
            FileUtils.set_contents (filename, file.to_data ());
        }
    }

    // Menus and Preferences share the same persisted options. Subscribe only
    // while mapped so hidden/closed option views do not retain session widgets.
    public class ContextOptions : Gtk.Box {
        private weak Preferences settings;
        private Gtk.CheckButton[] controls = {};
        private Gtk.Label status;
        private bool updating = false;
        private ulong handler = 0;

        public ContextOptions (Preferences settings) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 6);
            this.settings = settings;
            for (int i = 0; i < Preferences.CONTEXT_KEYS.length; i++) {
                string key = Preferences.CONTEXT_KEYS[i];
                var control = new Gtk.CheckButton.with_label (Preferences.CONTEXT_LABELS[i]);
                control.toggled.connect (() => {
                    if (updating) return;
                    try { settings.set_context_visible (key, control.active); status.label = ""; }
                    catch (Error error) { status.label = "Applied; could not save: " + error.message; }
                });
                controls += control;
                append (control);
            }
            status = new Gtk.Label ("") {xalign = 0, wrap = true};
            append (status);
            sync ();
            map.connect (() => { if (handler == 0) handler = settings.changed.connect (sync); sync (); });
            unmap.connect (() => { if (handler != 0) { settings.disconnect (handler); handler = 0; } });
        }

        private void sync () {
            updating = true;
            for (int i = 0; i < controls.length; i++) {
                controls[i].active = settings.context_visible (Preferences.CONTEXT_KEYS[i]);
                controls[i].sensitive = i == 0 || settings.context_visible ("enabled");
            }
            updating = false;
        }
    }

    public class PreferencesWindow : Gtk.Window {
        private Preferences settings;
        private Gtk.FontDialogButton terminal;
        private Gtk.FontDialogButton editor;
        private Gtk.Scale opacity;
        private Gtk.SpinButton lines;
        private Gtk.Switch inherit_style;
        private Gtk.Switch system_colors;
        private Gtk.ColorDialogButton foreground;
        private Gtk.ColorDialogButton background;
        private Gtk.Scale header_boost;
        private Gtk.Label status;
        private bool updating = false;
        private uint save_timeout = 0;

        public PreferencesWindow (Gtk.Window parent, Preferences settings) {
            Object (title: "Preferences", transient_for: parent, application: parent.application, modal: true, destroy_with_parent: true,
                default_width: 480, resizable: false);
            this.settings = settings;
            var header = new Gtk.HeaderBar ();
            set_titlebar (header);
            var grid = new Gtk.Grid () {column_spacing = 18, row_spacing = 14,
                margin_start = 24, margin_end = 24, margin_top = 18, margin_bottom = 24};
            terminal = new Gtk.FontDialogButton (new Gtk.FontDialog () {title = "Terminal Font"}) {
                font_desc = Pango.FontDescription.from_string (settings.terminal_font), hexpand = true};
            editor = new Gtk.FontDialogButton (new Gtk.FontDialog () {title = "Composer Font"}) {
                font_desc = Pango.FontDescription.from_string (settings.editor_font), hexpand = true};
            opacity = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, 100, 1) {draw_value = true, digits = 0, hexpand = true};
            opacity.set_value (settings.opacity * 100);
            lines = new Gtk.SpinButton.with_range (100, 100000, 1000) {value = settings.scrollback};
            inherit_style = new Gtk.Switch () {active = settings.inherit_style, halign = Gtk.Align.START,
                tooltip_text = "Apply Pane colors and background opacity to Composer and the headerbar"};
            system_colors = new Gtk.Switch () {active = settings.system_colors, halign = Gtk.Align.START};
            Gdk.RGBA fg = {}, bg = {};
            fg.parse (settings.foreground); bg.parse (settings.background);
            foreground = new Gtk.ColorDialogButton (new Gtk.ColorDialog () {title = "Pane Text Color", with_alpha = false}) {
                rgba = fg, halign = Gtk.Align.START, sensitive = !settings.system_colors};
            background = new Gtk.ColorDialogButton (new Gtk.ColorDialog () {title = "Pane Background Color", with_alpha = false}) {
                rgba = bg, halign = Gtk.Align.START, sensitive = !settings.system_colors};
            header_boost = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, 100, 1) {
                draw_value = true, digits = 0, hexpand = true, tooltip_text = "0% matches Pane opacity; 100% keeps the header opaque"};
            header_boost.set_value (settings.header_opacity_boost * 100);
            header_boost.sensitive = settings.inherit_style;
            status = new Gtk.Label ("") {xalign = 0, wrap = true};
            Gtk.Widget[] controls = {terminal, editor, opacity, lines, inherit_style, system_colors, foreground, background, header_boost};
            string[] labels = {"Terminal font", "Composer font", "Background opacity (%)", "Scrollback lines",
                "Inherit Pane Style", "Use system colors", "Pane text", "Pane background", "Header opacity boost (%)"};
            for (int i = 0; i < labels.length; i++) {
                var label = new Gtk.Label (labels[i]) {xalign = 0};
                label.set_mnemonic_widget (controls[i]);
                grid.attach (label, 0, i); grid.attach (controls[i], 1, i);
            }
            grid.attach (new Gtk.Label ("Transparency depends on compositor support.") {xalign = 0, wrap = true}, 0, 9, 2);
            grid.attach (new Gtk.Expander ("Composer Context") {child = new ContextOptions (settings)}, 0, 10, 2);
            grid.attach (status, 0, 11, 2);
            var reset = new Gtk.Button.with_label ("Restore Defaults") {halign = Gtk.Align.START};
            grid.attach (reset, 0, 12, 2);
            set_child (grid);
            terminal.notify["font-desc"].connect (schedule_apply);
            editor.notify["font-desc"].connect (schedule_apply);
            opacity.value_changed.connect (schedule_apply);
            lines.value_changed.connect (schedule_apply);
            inherit_style.notify["active"].connect (() => {
                header_boost.sensitive = inherit_style.active;
                schedule_apply ();
            });
            system_colors.notify["active"].connect (() => {
                foreground.sensitive = background.sensitive = !system_colors.active;
                schedule_apply ();
            });
            foreground.notify["rgba"].connect (schedule_apply);
            background.notify["rgba"].connect (schedule_apply);
            header_boost.value_changed.connect (schedule_apply);
            reset.clicked.connect (() => {
                updating = true;
                terminal.font_desc = Pango.FontDescription.from_string ("Monospace 12");
                editor.font_desc = Pango.FontDescription.from_string ("Monospace 12");
                opacity.set_value (100); lines.value = 10000;
                inherit_style.active = system_colors.active = true;
                Gdk.RGBA reset_fg = {}, reset_bg = {};
                reset_fg.parse ("#eeeeec"); reset_bg.parse ("#20242b");
                foreground.rgba = reset_fg; background.rgba = reset_bg;
                header_boost.set_value (0);
                try { settings.reset_context (); } catch (Error error) { status.label = error.message; }
                updating = false;
                schedule_apply ();
            });
            unmap.connect (flush);
            var keys = new Gtk.EventControllerKey ();
            keys.key_pressed.connect ((key) => {
                if (key == Gdk.Key.Escape) { close (); return true; }
                return false;
            });
            ((Gtk.Widget) this).add_controller (keys);
        }

        private void schedule_apply () {
            if (updating) return;
            if (save_timeout != 0) Source.remove (save_timeout);
            // Slider motion is coalesced into one write after a short pause.
            save_timeout = Timeout.add (200, () => {
                save_timeout = 0;
                apply_controls ();
                return Source.REMOVE;
            });
        }

        private void flush () {
            if (save_timeout == 0) return;
            Source.remove (save_timeout); save_timeout = 0;
            apply_controls ();
        }

        private void apply_controls () {
            try {
                settings.apply (terminal.font_desc.to_string (), editor.font_desc.to_string (), opacity.get_value () / 100,
                    (int64) lines.value, inherit_style.active, system_colors.active,
                    foreground.get_rgba ().to_string (), background.get_rgba ().to_string (), header_boost.get_value () / 100);
                status.label = "";
            } catch (Error error) { status.label = "Applied for this session; could not save: " + error.message; }
        }
    }
}
