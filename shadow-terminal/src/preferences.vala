namespace Shadow {
    public class Preferences : Object {
        public string terminal_font = "Monospace 12";
        public string editor_font = "Monospace 12";
        public double opacity = 1;
        public int64 scrollback = 10000;
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
        }

        private static string valid_font (string value, string fallback) {
            if (value == "" || value.length > 512 || value.contains ("\n") || value.contains ("\r")) return fallback;
            var font = Pango.FontDescription.from_string (value);
            double size = font.get_size () / (double) Pango.SCALE;
            if (font.get_family () == null || size < 6 || size > 72) return fallback;
            return font.to_string ();
        }

        public void apply (string terminal, string editor, double opacity, int64 scrollback) throws Error {
            terminal_font = valid_font (terminal, terminal_font);
            editor_font = valid_font (editor, editor_font);
            this.opacity = opacity.is_finite () ? double.max (0, double.min (1, opacity)) : 1;
            this.scrollback = int64.max (100, int64.min (100000, scrollback));
            changed ();
            var file = new KeyFile ();
            file.set_string ("appearance", "terminal-font", terminal_font);
            file.set_string ("appearance", "editor-font", editor_font);
            file.set_double ("appearance", "opacity", this.opacity);
            file.set_int64 ("terminal", "scrollback", this.scrollback);
            if (DirUtils.create_with_parents (Path.get_dirname (filename), 0700) != 0)
                throw new IOError.FAILED ("Could not create the preferences directory");
            FileUtils.set_contents (filename, file.to_data ());
        }
    }

    public class PreferencesWindow : Gtk.Window {
        private Preferences settings;
        private Gtk.FontDialogButton terminal;
        private Gtk.FontDialogButton editor;
        private Gtk.Scale opacity;
        private Gtk.SpinButton lines;
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
            status = new Gtk.Label ("") {xalign = 0, wrap = true};
            Gtk.Widget[] controls = {terminal, editor, opacity, lines};
            string[] labels = {"Terminal font", "Composer font", "Background opacity (%)", "Scrollback lines"};
            for (int i = 0; i < labels.length; i++) {
                var label = new Gtk.Label (labels[i]) {xalign = 0};
                label.set_mnemonic_widget (controls[i]);
                grid.attach (label, 0, i); grid.attach (controls[i], 1, i);
            }
            grid.attach (new Gtk.Label ("Transparency depends on compositor support.") {xalign = 0, wrap = true}, 0, 4, 2);
            grid.attach (status, 0, 5, 2);
            var reset = new Gtk.Button.with_label ("Restore Defaults") {halign = Gtk.Align.START};
            grid.attach (reset, 0, 6, 2);
            set_child (grid);
            terminal.notify["font-desc"].connect (schedule_apply);
            editor.notify["font-desc"].connect (schedule_apply);
            opacity.value_changed.connect (schedule_apply);
            lines.value_changed.connect (schedule_apply);
            reset.clicked.connect (() => {
                updating = true;
                terminal.font_desc = Pango.FontDescription.from_string ("Monospace 12");
                editor.font_desc = Pango.FontDescription.from_string ("Monospace 12");
                opacity.set_value (100); lines.value = 10000;
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
                settings.apply (terminal.font_desc.to_string (), editor.font_desc.to_string (), opacity.get_value () / 100, (int64) lines.value);
                status.label = "";
            } catch (Error error) { status.label = "Applied for this session; could not save: " + error.message; }
        }
    }
}
