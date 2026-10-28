namespace Shadow {
    public class Preferences : Object {
        public const string[] ACTIONS = {"new-tab", "default-tab", "new-window", "close-pane", "close-tab", "close-window",
            "previous-tab", "next-tab", "split-horizontal", "split-vertical", "next-pane", "previous-pane",
            "detach-pane", "pane-to-tab", "join-tab", "palette", "preferences", "composer", "hide", "copy", "paste", "find-terminal", "find-composer", "documentation", "recall", "paste-draft", "zoom-in", "zoom-out", "zoom-reset", "shortcuts", "previous-session", "next-session"};
        public const string[] ACTION_LABELS = {"New Tab", "New Tab in Default Directory", "New Window", "Close Pane", "Close Tab", "Close Window",
            "Previous Tab", "Next Tab", "Split Side by Side", "Split Stacked", "Next Pane", "Previous Pane",
            "Move Pane to New Window", "Move Pane to New Tab", "Move Previous Tab into Split", "Command Palette…", "Preferences…", "Toggle Composer", "Hide Window", "Copy", "Paste", "Find in Terminal", "Find in Composer", "Documentation", "Recall Last Input", "Paste Draft without Return", "Zoom In", "Zoom Out", "Reset Zoom", "Keyboard Shortcuts", "Previous Session", "Next Session"};
        public const string[] DEFAULT_KEYS = {"<Control>t", "<Control>n", "<Control><Shift>n", "<Control>w", "<Control><Shift>w", "<Control><Shift>q",
            "<Control>Page_Up", "<Control>Page_Down", "<Control><Shift>e", "<Control><Shift>o", "<Control><Alt>Right", "<Control><Alt>Left",
            "", "", "", "<Control><Shift>p", "<Control>comma", "<Control><Shift>m", "<Control><Shift>h", "<Control><Shift>c", "<Control><Shift>v", "<Control><Shift>f", "<Control>f", "<Alt>h", "<Control><Shift>l", "<Control><Shift>Return", "<Control><Shift>plus", "<Control><Shift>minus", "<Control><Shift>0", "F1", "<Control>Tab", "<Control><Shift>Tab"};
        private HashTable<string, string> shortcuts = new HashTable<string, string> (str_hash, str_equal);

        public string shortcut (string action) {
            var custom = shortcuts.lookup (action);
            if (custom != null) return custom;
            for (int i = 0; i < ACTIONS.length; i++) if (ACTIONS[i] == action) return DEFAULT_KEYS[i];
            return "";
        }

        public string shortcut_label (string action) {
            uint key = 0; Gdk.ModifierType modifiers = 0;
            var value = shortcut (action);
            if (value == "" || !Gtk.accelerator_parse (value, out key, out modifiers)) return "";
            return Gtk.accelerator_get_label (key, modifiers);
        }

        public string? shortcut_action (uint key, Gdk.ModifierType modifiers) {
            modifiers &= Gtk.accelerator_get_default_mod_mask ();
            if (key == Gdk.Key.ISO_Left_Tab) { key = Gdk.Key.Tab; modifiers |= Gdk.ModifierType.SHIFT_MASK; }
            key = Gdk.keyval_to_lower (key);
            foreach (var action in ACTIONS) {
                uint expected = 0; Gdk.ModifierType mods = 0;
                if (Gtk.accelerator_parse (shortcut (action), out expected, out mods) && expected != 0 &&
                    key == Gdk.keyval_to_lower (expected) && modifiers == mods) return action;
            }
            // Shifted printable keyvals differ by keyboard layout. Accept the
            // established terminal zoom aliases after explicit assignments.
            if ((modifiers & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) == (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) {
                if (key == Gdk.Key.equal && shortcut ("zoom-in") == DEFAULT_KEYS[26]) return "zoom-in";
                if (key == Gdk.Key.underscore && shortcut ("zoom-out") == DEFAULT_KEYS[27]) return "zoom-out";
                if (key == Gdk.Key.parenright && shortcut ("zoom-reset") == DEFAULT_KEYS[28]) return "zoom-reset";
                if (key == Gdk.Key.t && shortcut ("new-tab") == DEFAULT_KEYS[0]) return "new-tab";
            }
            return null;
        }

        public static string canonical_shortcut (string value) throws Error {
            if (value.strip () == "") return "";
            uint key = 0; Gdk.ModifierType mods = 0;
            if (value.length > 128 || !Gtk.accelerator_parse (value, out key, out mods) || (!Gtk.accelerator_valid (key, mods) && key != Gdk.Key.Tab && key != Gdk.Key.ISO_Left_Tab))
                throw new IOError.INVALID_ARGUMENT ("Use a valid shortcut, such as <Control><Shift>e");
            mods &= Gtk.accelerator_get_default_mod_mask ();
            if (key == Gdk.Key.ISO_Left_Tab) { key = Gdk.Key.Tab; mods |= Gdk.ModifierType.SHIFT_MASK; }
            key = Gdk.keyval_to_lower (key);
            // Bare text/caret keys remain editor/program input. Enter and Tab
            // also carry submission/completion semantics in Composer.
            if ((mods & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SUPER_MASK)) == 0 && !(key >= Gdk.Key.F1 && key <= Gdk.Key.F35))
                throw new IOError.INVALID_ARGUMENT ("Use Ctrl, Alt or Super with text/navigation keys");
            if (key == Gdk.Key.Return || key == Gdk.Key.Escape || key == Gdk.Key.space ||
                (key == Gdk.Key.Right && mods == Gdk.ModifierType.CONTROL_MASK) ||
                (mods == Gdk.ModifierType.CONTROL_MASK && ("acdxvzbif".index_of_char (key) >= 0)))
                throw new IOError.INVALID_ARGUMENT ("This shortcut is reserved for editing or completion");
            return Gtk.accelerator_name (key, mods);
        }

        public void set_shortcut (string action, string value) throws Error {
            if (index_of_action (action) < 0) throw new IOError.INVALID_ARGUMENT ("Unknown action");
            string normalized;
            if (value == DEFAULT_KEYS[index_of_action (action)]) {
                uint key = 0; Gdk.ModifierType mods = 0;
                Gtk.accelerator_parse (value, out key, out mods);
                normalized = value == "" ? "" : Gtk.accelerator_name (Gdk.keyval_to_lower (key), mods);
            } else normalized = canonical_shortcut (value);
            foreach (var other in ACTIONS) {
                if (other == action || normalized == "") continue;
                uint key = 0; Gdk.ModifierType mods = 0;
                if (Gtk.accelerator_parse (shortcut (other), out key, out mods) &&
                    Gtk.accelerator_name (Gdk.keyval_to_lower (key), mods) == normalized)
                    throw new IOError.EXISTS ("Already assigned to " + ACTION_LABELS[index_of_action (other)]);
            }
            shortcuts.insert (action, normalized); changed (); save ();
        }

        public static int index_of_action (string action) {
            for (int i = 0; i < ACTIONS.length; i++) if (ACTIONS[i] == action) return i;
            return -1;
        }

        public void reset_shortcut (string action) throws Error {
            if (index_of_action (action) < 0) throw new IOError.INVALID_ARGUMENT ("Unknown action");
            // Restore through conflict validation, allowing the action's own
            // reserved default while keeping other assignments unambiguous.
            set_shortcut (action, DEFAULT_KEYS[index_of_action (action)]);
        }

        public void reset_shortcuts () throws Error { shortcuts.remove_all (); changed (); save (); }

        public string terminal_font = "Monospace 12";
        public string bold_font = "";
        public string italic_font = "";
        public string bold_italic_font = "";
        public string editor_font = "Monospace 12";
        public const string[] CURSOR_SHAPES = {"block", "ibeam", "underline"};
        public string cursor_shape = "block";
        public double opacity = 1;
        public int64 scrollback = 10000;
        public bool inherit_style = true;
        public bool guard_pane_input = true;
        public bool docs_dismiss = false;
        public bool system_colors = true;
        public string foreground = "#eeeeec";
        public string background = "#20242b";
        public TerminalColors colors = new TerminalColors ();
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
            colors.load (file);
            try { cursor_shape = valid_cursor_shape (file.get_string ("appearance", "cursor-shape")); } catch (Error error) {}
            try { terminal_font = valid_font (file.get_string ("appearance", "terminal-font"), terminal_font); } catch (Error error) {}
            try { bold_font = optional_font (file.get_string ("appearance", "bold-font")); } catch (Error error) {}
            try { italic_font = optional_font (file.get_string ("appearance", "italic-font")); } catch (Error error) {}
            try { bold_italic_font = optional_font (file.get_string ("appearance", "bold-italic-font")); } catch (Error error) {}
            try { editor_font = valid_font (file.get_string ("appearance", "editor-font"), editor_font); } catch (Error error) {}
            try {
                double value = file.get_double ("appearance", "opacity");
                if (value.is_finite ()) opacity = double.max (0, double.min (1, value));
            } catch (Error error) {}
            try { scrollback = int64.max (100, int64.min (100000, file.get_int64 ("terminal", "scrollback"))); } catch (Error error) {}
            try { docs_dismiss = file.get_boolean ("documentation", "dismiss-on-focus-loss"); } catch (Error error) {}
            try { guard_pane_input = file.get_boolean ("terminal", "guard-pane-input"); } catch (Error error) {}
            try { inherit_style = file.get_boolean ("appearance", "inherit-pane-style"); } catch (Error error) {}
            try { system_colors = file.get_boolean ("appearance", "system-colors"); } catch (Error error) {}
            try { foreground = valid_color (file.get_string ("appearance", "foreground"), foreground); } catch (Error error) {}
            try { background = valid_color (file.get_string ("appearance", "background"), background); } catch (Error error) {}
            try {
                double value = file.get_double ("appearance", "header-opacity-boost");
                if (value.is_finite ()) header_opacity_boost = double.max (0, double.min (1, value));
            } catch (Error error) {}
            foreach (var action in ACTIONS) {
                try {
                    string value = file.get_string ("shortcuts", action);
                    // Defaults include core UI chords which users may disable
                    // and restore; validate stored syntax without remapping them.
                    uint key = 0; Gdk.ModifierType mods = 0;
                    if (value == "" || (value.length < 128 && Gtk.accelerator_parse (value, out key, out mods) && Gtk.accelerator_valid (key, mods)))
                        shortcuts.insert (action, value);
                } catch (Error error) {}
            }
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

        private static string optional_font (string value) { return value == "" ? "" : valid_font (value, ""); }

        public void set_style_fonts (string bold, string italic, string bold_italic) throws Error {
            bold_font = optional_font (bold); italic_font = optional_font (italic); bold_italic_font = optional_font (bold_italic);
            changed (); save ();
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
                           string foreground = "#eeeeec", string background = "#20242b", double header_opacity_boost = 0, TerminalColors? colors = null) throws Error {
            terminal_font = valid_font (terminal, terminal_font);
            editor_font = valid_font (editor, editor_font);
            this.opacity = opacity.is_finite () ? double.max (0, double.min (1, opacity)) : 1;
            this.scrollback = int64.max (100, int64.min (100000, scrollback));
            if (colors != null) this.colors = colors;
            this.inherit_style = inherit_style;
            this.system_colors = system_colors;
            this.foreground = valid_color (foreground, this.foreground);
            this.background = valid_color (background, this.background);
            this.header_opacity_boost = header_opacity_boost.is_finite () ? double.max (0, double.min (1, header_opacity_boost)) : 0;
            changed ();
            save ();
        }

        public void set_docs_dismiss (bool enabled) throws Error {
            docs_dismiss = enabled; changed (); save ();
        }

        private static string valid_cursor_shape (string value) {
            foreach (var shape in CURSOR_SHAPES) if (value == shape) return value;
            return "block";
        }

        public void set_cursor_shape (string value) throws Error {
            cursor_shape = valid_cursor_shape (value);
            changed (); save ();
        }

        public void set_input_guard (bool enabled) throws Error {
            guard_pane_input = enabled;
            changed ();
            save ();
        }

        public void set_colors (TerminalColors colors) throws Error {
            this.colors = colors;
            changed (); save ();
        }

        public void import_colors (TerminalColors colors) throws Error {
            this.colors = colors;
            foreground = colors.foreground; background = colors.background;
            system_colors = false;
            changed (); save ();
        }

        private void save () throws Error {
            var file = new KeyFile ();
            colors.save (file);
            foreach (var action in shortcuts.get_keys ())
                file.set_string ("shortcuts", action, shortcuts.lookup (action));
            file.set_string ("appearance", "terminal-font", terminal_font);
            file.set_string ("appearance", "bold-font", bold_font);
            file.set_string ("appearance", "italic-font", italic_font);
            file.set_string ("appearance", "bold-italic-font", bold_italic_font);
            file.set_string ("appearance", "editor-font", editor_font);
            file.set_string ("appearance", "cursor-shape", cursor_shape);
            file.set_double ("appearance", "opacity", this.opacity);
            file.set_int64 ("terminal", "scrollback", this.scrollback);
            file.set_boolean ("terminal", "guard-pane-input", guard_pane_input);
            file.set_boolean ("documentation", "dismiss-on-focus-loss", docs_dismiss);
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
        private Gtk.FontDialogButton[] faces = {};
        private Gtk.CheckButton[] custom_faces = {};
        private Gtk.Scale pane_opacity;
        private Gtk.SpinButton lines;
        private Gtk.DropDown cursor_shape;
        private Gtk.Switch inherit_style;
        private Gtk.Switch system_colors;
        private Gtk.ColorDialogButton foreground;
        private Gtk.ColorDialogButton background;
        private Gtk.ColorDialogButton[] color_controls = {};
        private Gtk.CheckButton[] automatic_colors = {};
        private Cancellable import_cancel = new Cancellable ();
        private uint import_generation = 0;
        private Gtk.Scale header_boost;
        private Gtk.Label status;
        private bool updating = false;
        private uint save_timeout = 0;

        private Gtk.Box page () {
            return new Gtk.Box (Gtk.Orientation.VERTICAL, 18) {margin_start = 24, margin_end = 24, margin_top = 24, margin_bottom = 24};
        }
        private Gtk.ListBox group (Gtk.Box page, string title) {
            var heading = new Gtk.Label (title) {xalign = 0}; heading.add_css_class ("heading");
            var list = new Gtk.ListBox () {selection_mode = Gtk.SelectionMode.NONE}; list.add_css_class ("boxed-list");
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8); box.append (heading); box.append (list); page.append (box);
            return list;
        }
        private Gtk.Label description (string text) {
            var label = new Gtk.Label (text) {xalign = 0, wrap = true};
            label.add_css_class ("dim-label");
            // Relative scaling preserves the desktop font and accessibility sizing.
            var attributes = new Pango.AttrList ();
            attributes.insert (Pango.attr_scale_new (Pango.Scale.SMALL));
            label.attributes = attributes;
            return label;
        }
        private void row (Gtk.ListBox list, string title, string detail, Gtk.Widget control, string? name = null) {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 18) {margin_start = 14, margin_end = 14, margin_top = 12, margin_bottom = 12};
            var labels = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) {hexpand = true, valign = Gtk.Align.CENTER};
            labels.append (new Gtk.Label (title) {xalign = 0, wrap = true});
            if (detail != "") {
                var hint = description (detail); hint.max_width_chars = 38; labels.append (hint);
            }
            control.valign = Gtk.Align.CENTER;
            if (name != null) control.add_css_class (name);
            box.append (labels); box.append (control); list.append (box);
        }
        private void add_page (Gtk.Stack stack, Gtk.Box box, string id, string title) {
            var scroll = new Gtk.ScrolledWindow () {child = box, hscrollbar_policy = Gtk.PolicyType.NEVER, vexpand = true};
            stack.add_titled (scroll, id, title);
        }

        public PreferencesWindow (Gtk.Window parent, Preferences settings, bool style_fonts_available = false) {
            Object (title: "Preferences", transient_for: parent, application: parent.application, modal: false, destroy_with_parent: true,
                default_width: 700, default_height: 680);
            this.settings = settings;
            var stack = new Gtk.Stack () {hhomogeneous = false, vhomogeneous = false, vexpand = true};
            var header = new Gtk.HeaderBar ();
            header.title_widget = new Gtk.StackSwitcher () {stack = stack}; titlebar = header;
            var root = new Gtk.Box (Gtk.Orientation.VERTICAL, 0); root.append (stack);
            status = new Gtk.Label ("") {xalign = 0, wrap = true, margin_start = 24, margin_end = 24, margin_bottom = 8};
            status.add_css_class ("pref-status");
            root.append (status); child = root;

            var appearance = page ();
            var fonts = group (appearance, "Typography");
            terminal = new Gtk.FontDialogButton (new Gtk.FontDialog () {title = "Pane Font"}) {font_desc = Pango.FontDescription.from_string (settings.terminal_font)};
            editor = new Gtk.FontDialogButton (new Gtk.FontDialog () {title = "Composer Font"}) {font_desc = Pango.FontDescription.from_string (settings.editor_font)};
            row (fonts, "Pane font", "The regular face determines terminal cell size.", terminal, "pref-terminal-font");
            row (fonts, "Composer font", "Independent text size and family.", editor, "pref-editor-font");
            cursor_shape = (Gtk.DropDown) Native.drop_down ({"Block", "I-beam", "Underline"});
            for (int i = 0; i < Preferences.CURSOR_SHAPES.length; i++)
                if (Preferences.CURSOR_SHAPES[i] == settings.cursor_shape) cursor_shape.selected = i;
            row (fonts, "Pane cursor shape", "Applications can request their own cursor shape.", cursor_shape, "pref-cursor-shape");
            cursor_shape.notify["selected"].connect (schedule_apply);
            string[] names = {"Bold", "Italic", "Bold italic"};
            string[] values = {settings.bold_font, settings.italic_font, settings.bold_italic_font};
            for (int i = 0; i < names.length; i++) {
                var controls = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                var custom = new Gtk.CheckButton () {active = values[i] != "", tooltip_text = "Choose a separate face; unchecked uses automatic matching", sensitive = style_fonts_available};
                var face = new Gtk.FontDialogButton (new Gtk.FontDialog () {title = names[i] + " Pane Font"}) {
                    font_desc = Pango.FontDescription.from_string (values[i] != "" ? values[i] : settings.terminal_font), sensitive = custom.active && style_fonts_available};
                custom.toggled.connect (() => { face.sensitive = custom.active && style_fonts_available; schedule_apply (); });
                face.notify["font-desc"].connect (schedule_apply);
                controls.append (custom); controls.append (face); faces += face; custom_faces += custom;
                row (fonts, names[i] + " face", "Automatic when unchecked; uses the regular cell size.", controls);
            }
            if (!style_fonts_available) {
                appearance.append (description ("Separate Pane faces require the private VTE style-font hook. Saved choices are retained with system VTE."));
            }
            var colors = group (appearance, "Colors and transparency");
            system_colors = new Gtk.Switch () {active = settings.system_colors};
            inherit_style = new Gtk.Switch () {active = settings.inherit_style};
            Gdk.RGBA fg = {}, bg = {}; fg.parse (settings.foreground); bg.parse (settings.background);
            foreground = new Gtk.ColorDialogButton (new Gtk.ColorDialog () {title = "Pane Text", with_alpha = false}) {rgba = fg, sensitive = !settings.system_colors};
            background = new Gtk.ColorDialogButton (new Gtk.ColorDialog () {title = "Pane Background", with_alpha = false}) {rgba = bg, sensitive = !settings.system_colors};
            pane_opacity = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, 100, 1) {draw_value = true, digits = 0, width_request = 170}; pane_opacity.set_value (settings.opacity * 100);
            header_boost = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, 100, 1) {draw_value = true, digits = 0, width_request = 170, sensitive = settings.inherit_style}; header_boost.set_value (settings.header_opacity_boost * 100);
            row (colors, "Use system colors", "Follow the desktop light or dark appearance.", system_colors, "pref-system-colors");
            row (colors, "Pane text", "", foreground, "pref-foreground"); row (colors, "Pane background", "", background, "pref-background");
            row (colors, "Background opacity", "Transparency depends on the compositor.", pane_opacity, "pref-opacity");
            row (colors, "Inherit Pane Style", "Unify Composer, header and documentation colors and opacity.", inherit_style, "pref-inherit");
            row (colors, "Header opacity boost", "0% matches the Pane; 100% makes the header opaque.", header_boost, "pref-header-boost");
            var theme_group = group (appearance, "Terminal color scheme");
            var import_button = new Gtk.Button.with_label ("Import…");
            row (theme_group, "Import iTerm2 theme", "Load an .itermcolors file, then customize any color below.", import_button, "pref-import-theme");
            import_button.clicked.connect (() => {
                var filter = new Gtk.FileFilter () {name = "iTerm2 color schemes"}; filter.add_pattern ("*.itermcolors");
                var filters = new ListStore (typeof (Gtk.FileFilter)); filters.append (filter);
                var chooser = new Gtk.FileDialog () {title = "Import Terminal Color Scheme", filters = filters, default_filter = filter};
                chooser.open.begin (this, import_cancel, (obj, result) => {
                    try { import_theme_file.begin (chooser.open.end (result)); }
                    catch (Error error) {
                        if (!(error is Gtk.DialogError.DISMISSED) && !(error is Gtk.DialogError.CANCELLED) && !import_cancel.is_cancelled ()) status.label = error.message;
                    }
                });
            });
            var palette_group = group (appearance, "ANSI palette");
            var special_group = group (appearance, "Cursor and selection");
            for (int i = 0; i < TerminalColors.KEYS.length; i++) {
                int index = i;
                Gdk.RGBA color = {}; color.parse (settings.colors.get_color (i) != "" ? settings.colors.get_color (i) : settings.foreground);
                var button = new Gtk.ColorDialogButton (new Gtk.ColorDialog () {title = TerminalColors.LABELS[i], with_alpha = false}) {rgba = color};
                var automatic = new Gtk.CheckButton.with_label ("Automatic") {active = i >= 16 && settings.colors.get_color (i) == ""};
                color_controls += button; automatic_colors += automatic;
                var controls = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                if (i >= 16) controls.append (automatic);
                controls.append (button);
                button.add_css_class ("pref-color-" + TerminalColors.KEYS[i]);
                automatic.add_css_class ("pref-auto-" + TerminalColors.KEYS[i]);
                row (i < 16 ? palette_group : special_group, TerminalColors.LABELS[i], i < 16 ? "ANSI %d".printf (i) : "", controls);
                button.notify["rgba"].connect (schedule_apply);
                automatic.toggled.connect (() => { color_controls[index].sensitive = !system_colors.active && !automatic.active; schedule_apply (); });
            }
            update_color_sensitivity ();
            add_page (stack, appearance, "appearance", "Appearance");

            var input = page ();
            var behavior = group (input, "Input and terminal");
            lines = new Gtk.SpinButton.with_range (100, 100000, 1000) {value = settings.scrollback}; row (behavior, "Scrollback lines", "Retained per session.", lines, "pref-scrollback");
            var guard = new Gtk.Switch () {active = settings.guard_pane_input};
            row (behavior, "Route Pane input to Composer", "At ready fish prompts, typing and paste go into the draft.", guard);
            guard.notify["active"].connect (() => { try { settings.set_input_guard (guard.active); } catch (Error error) { status.label = error.message; } });
            var dismiss = new Gtk.Switch () {active = settings.docs_dismiss};
            row (behavior, "Dismiss documentation on focus loss", "Owned dialogs remain part of the documentation pane.", dismiss);
            dismiss.notify["active"].connect (() => { try { settings.set_docs_dismiss (dismiss.active); } catch (Error error) { status.label = error.message; } });
            var context = group (input, "Composer context");
            var context_controls = new ContextOptions (settings) {margin_start = 14, margin_end = 14, margin_top = 12, margin_bottom = 12};
            context_controls.add_css_class ("pref-context"); context.append (context_controls);
            add_page (stack, input, "input", "Input");

            var shortcuts = page ();
            var shortcut_view = new ShortcutSettings (settings);
            shortcut_view.feedback.connect ((message) => status.label = message);
            shortcuts.append (shortcut_view);
            add_page (stack, shortcuts, "shortcuts", "Shortcuts");

            terminal.notify["font-desc"].connect (schedule_apply); editor.notify["font-desc"].connect (schedule_apply);
            pane_opacity.value_changed.connect (schedule_apply); lines.value_changed.connect (schedule_apply);
            inherit_style.notify["active"].connect (() => { header_boost.sensitive = inherit_style.active; schedule_apply (); });
            system_colors.notify["active"].connect (() => { update_color_sensitivity (); schedule_apply (); });
            foreground.notify["rgba"].connect (schedule_apply); background.notify["rgba"].connect (schedule_apply); header_boost.value_changed.connect (schedule_apply);
            var reset = new Gtk.Button.with_label ("Restore Appearance Defaults") {halign = Gtk.Align.START}; appearance.append (reset); reset.add_css_class ("pref-appearance-reset");
            reset.clicked.connect (() => {
                updating = true;
                terminal.font_desc = Pango.FontDescription.from_string ("Monospace 12"); editor.font_desc = Pango.FontDescription.from_string ("Monospace 12");
                foreach (var custom in custom_faces) custom.active = false;
                pane_opacity.set_value (100); lines.value = 10000; inherit_style.active = system_colors.active = true;
                cursor_shape.selected = 0;
                Gdk.RGBA reset_fg = {}, reset_bg = {}; reset_fg.parse ("#eeeeec"); reset_bg.parse ("#20242b"); foreground.rgba = reset_fg; background.rgba = reset_bg; header_boost.set_value (0);
                load_color_controls (new TerminalColors ());
                update_color_sensitivity ();
                updating = false; schedule_apply ();
            });
            ((Gtk.Widget) this).unrealize.connect (() => import_cancel.cancel ());
            unmap.connect (flush);
            var keys = new Gtk.EventControllerKey () {propagation_phase = Gtk.PropagationPhase.CAPTURE};
            keys.key_pressed.connect ((key, code, state) => {
                if (shortcut_view.handle_key (key, state)) return true;
                if (key == Gdk.Key.Escape) { close (); return true; }
                return false;
            }); ((Gtk.Widget) this).add_controller (keys);
        }

        private void update_color_sensitivity () {
            foreground.sensitive = background.sensitive = !system_colors.active;
            for (int i = 0; i < color_controls.length; i++) {
                automatic_colors[i].sensitive = !system_colors.active;
                color_controls[i].sensitive = !system_colors.active && !automatic_colors[i].active;
            }
        }
        private void load_color_controls (TerminalColors colors) {
            for (int i = 0; i < color_controls.length; i++) {
                var value = colors.get_color (i);
                automatic_colors[i].active = i >= 16 && value == "";
                Gdk.RGBA color = {}; color.parse (value == "" ? settings.foreground : value);
                color_controls[i].rgba = color;
            }
        }
        public async void import_theme_file (File file) {
            uint generation = ++import_generation;
            try {
                var info = yield file.query_info_async (FileAttribute.STANDARD_TYPE, FileQueryInfoFlags.NONE, Priority.DEFAULT, import_cancel);
                if (info.get_file_type () != FileType.REGULAR) throw new IOError.INVALID_DATA ("Choose a regular theme file");
                var stream = yield file.read_async (Priority.DEFAULT, import_cancel);
                var data = new ByteArray ();
                try {
                    while (data.len <= 262144) {
                        var bytes = yield stream.read_bytes_async (16384, Priority.DEFAULT, import_cancel);
                        if (bytes.get_size () == 0) break;
                        data.append (bytes.get_data ());
                    }
                } finally { try { stream.close (null); } catch (Error error) {} }
                if (import_cancel.is_cancelled () || generation != import_generation) return;
                uint length = data.len;
                data.append ({0});
                if (length > 262144 || length == 0 || ((string) data.data).length != length)
                    throw new IOError.INVALID_DATA ("Choose an XML iTerm2 preset under 256 KiB without NUL bytes");
                string text = (string) data.data;
                var colors = TerminalColors.import_iterm (text);
                flush ();
                string? save_error = null;
                try { settings.import_colors (colors); } catch (Error error) { save_error = error.message; }
                updating = true;
                system_colors.active = false;
                Gdk.RGBA fg = {}, bg = {}; fg.parse (settings.foreground); bg.parse (settings.background);
                foreground.rgba = fg; background.rgba = bg;
                load_color_controls (colors); update_color_sensitivity ();
                updating = false;
                status.label = save_error == null ? "Imported " + file.get_basename () : "Imported; could not save: " + save_error;
            } catch (Error error) {
                if (!import_cancel.is_cancelled () && generation == import_generation) status.label = "Could not import theme: " + error.message;
            }
        }

        private void schedule_apply () {
            if (updating) return;
            if (save_timeout != 0) Source.remove (save_timeout);
            save_timeout = Timeout.add (200, () => { save_timeout = 0; apply_controls (); return Source.REMOVE; });
        }
        private void flush () {
            if (save_timeout == 0) return;
            Source.remove (save_timeout); save_timeout = 0; apply_controls ();
        }
        private void apply_controls () {
            try {
                var colors = new TerminalColors ();
                for (int i = 0; i < color_controls.length; i++)
                    colors.set_color (i, i >= 16 && automatic_colors[i].active ? "" : color_controls[i].get_rgba ().to_string ());
                settings.apply (terminal.font_desc.to_string (), editor.font_desc.to_string (), pane_opacity.get_value () / 100,
                    (int64) lines.value, inherit_style.active, system_colors.active, foreground.get_rgba ().to_string (), background.get_rgba ().to_string (), header_boost.get_value () / 100, colors);
                settings.set_style_fonts (custom_faces[0].active ? faces[0].font_desc.to_string () : "",
                    custom_faces[1].active ? faces[1].font_desc.to_string () : "", custom_faces[2].active ? faces[2].font_desc.to_string () : "");
                settings.set_cursor_shape (Preferences.CURSOR_SHAPES[cursor_shape.selected]);
                status.label = "";
            } catch (Error error) { status.label = "Applied; could not save: " + error.message; }
        }
    }
}
