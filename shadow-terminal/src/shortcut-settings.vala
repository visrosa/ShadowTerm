namespace Shadow {
    // Capture and discovery belong to this view; the registry remains the sole
    // authority for validation, conflicts, persistence and dispatch bindings.
    public class ShortcutSettings : Gtk.Box {
        private Preferences settings;
        private HashTable<string, Gtk.Button> buttons = new HashTable<string, Gtk.Button> (str_hash, str_equal);
        private string? recording;
        private ulong changed_handler;
        public signal void feedback (string message);

        public ShortcutSettings (Preferences settings) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 12);
            this.settings = settings;
            add_css_class ("pref-shortcuts");
            var search = new Gtk.SearchEntry () {placeholder_text = "Find a shortcut…"}; append (search);
            var list = new Gtk.ListBox () {selection_mode = Gtk.SelectionMode.NONE};
            list.add_css_class ("boxed-list"); append (list);
            for (int i = 0; i < Preferences.ACTIONS.length; i++) {
                string action = Preferences.ACTIONS[i];
                var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {margin_start = 10, margin_end = 8, margin_top = 6, margin_bottom = 6};
                var label = new Gtk.Label (Preferences.ACTION_LABELS[i]) {xalign = 0, wrap = true, hexpand = true, max_width_chars = 26};
                var capture = new Gtk.Button () {has_frame = false, tooltip_text = "Change " + label.label};
                capture.clicked.connect (() => begin_capture (action));
                buttons.insert (action, capture);
                var menu = new Gtk.MenuButton () {icon_name = "emblem-system-symbolic", has_frame = false, tooltip_text = "Options for " + label.label};
                var popover = new Gtk.Popover ();
                var choices = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {margin_start = 6, margin_end = 6, margin_top = 6, margin_bottom = 6};
                var change = new Gtk.Button.with_label ("Change Shortcut…") {has_frame = false};
                var disable = new Gtk.Button.with_label ("Disable") {has_frame = false};
                var reset = new Gtk.Button.with_label ("Restore Default") {has_frame = false};
                change.clicked.connect (() => { popover.popdown (); begin_capture (action); });
                disable.clicked.connect (() => { popover.popdown (); apply (action, "", false); });
                reset.clicked.connect (() => { popover.popdown (); apply (action, "", true); });
                choices.append (change); choices.append (disable); choices.append (reset);
                popover.child = choices; Native.menu_popover (menu, popover);
                row.append (label); row.append (capture); row.append (menu); list.append (row);
            }
            list.set_filter_func ((candidate) => ((Gtk.Label) candidate.child.get_first_child ()).label.down ().contains (search.text.strip ().down ()));
            search.search_changed.connect (() => {
                if (recording != null && !Preferences.ACTION_LABELS[Preferences.index_of_action (recording)].down ().contains (search.text.strip ().down ())) {
                    recording = null; feedback (""); refresh ();
                }
                list.invalidate_filter ();
            });
            var help = new Gtk.Label ("Select a shortcut and press a new combination. Escape cancels; Backspace disables it.") {xalign = 0, wrap = true};
            help.add_css_class ("dim-label"); var attributes = new Pango.AttrList ();
            attributes.insert (Pango.attr_scale_new (Pango.Scale.SMALL)); help.attributes = attributes; append (help);
            var reset_all = new Gtk.Button.with_label ("Restore Shortcut Defaults") {halign = Gtk.Align.START};
            reset_all.clicked.connect (() => {
                recording = null;
                try { settings.reset_shortcuts (); feedback (""); } catch (Error error) { feedback (error.message); }
            }); append (reset_all);
            changed_handler = settings.changed.connect (refresh);
            unrealize.connect (() => { if (changed_handler != 0) { settings.disconnect (changed_handler); changed_handler = 0; } });
            unmap.connect (() => { recording = null; refresh (); });
            refresh ();
        }

        private void begin_capture (string action) {
            recording = action; refresh ();
            feedback ("Press the new shortcut, Escape to cancel, or Backspace to disable.");
        }
        private void apply (string action, string value, bool reset) {
            try {
                if (reset) settings.reset_shortcut (action); else settings.set_shortcut (action, value);
                recording = null; feedback (""); refresh ();
            } catch (Error error) { feedback (error.message); }
        }
        private static Gtk.Widget keycaps (string accelerator) {
            uint key = 0; Gdk.ModifierType modifiers = 0;
            Gtk.accelerator_parse (accelerator, out key, out modifiers);
            var keys = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 3) {halign = Gtk.Align.END};
            foreach (var modifier in new Gdk.ModifierType[] {Gdk.ModifierType.SHIFT_MASK, Gdk.ModifierType.CONTROL_MASK,
                Gdk.ModifierType.ALT_MASK, Gdk.ModifierType.SUPER_MASK, Gdk.ModifierType.HYPER_MASK, Gdk.ModifierType.META_MASK}) {
                if ((modifiers & modifier) == 0) continue;
                var cap = new Gtk.Label (Gtk.accelerator_get_label (0, modifier));
                cap.add_css_class ("keycap"); keys.append (cap);
            }
            // Keep the key separate: a literal plus key is not a separator.
            var cap = new Gtk.Label (Gtk.accelerator_get_label (key, 0));
            cap.add_css_class ("keycap"); keys.append (cap);
            return keys;
        }

        private void refresh () {
            foreach (var action in buttons.get_keys ()) {
                var button = buttons.lookup (action);
                string shortcut = settings.shortcut (action);
                string label = action == recording ? "Press shortcut…" : settings.shortcut_label (action);
                if (action == recording || shortcut == "")
                    button.child = new Gtk.Label (action == recording ? label : "Disabled");
                else
                    button.child = keycaps (shortcut);
                button.update_property (Gtk.AccessibleProperty.LABEL,
                    Preferences.ACTION_LABELS[Preferences.index_of_action (action)] + ": " + (label == "" ? "Disabled" : label), -1);
            }
        }

        public bool handle_key (uint key, Gdk.ModifierType state) {
            if (recording == null) return false;
            if (key == Gdk.Key.Escape) { recording = null; feedback (""); refresh (); return true; }
            if (key == Gdk.Key.Shift_L || key == Gdk.Key.Shift_R || key == Gdk.Key.Control_L || key == Gdk.Key.Control_R || key == Gdk.Key.Alt_L || key == Gdk.Key.Alt_R || key == Gdk.Key.Super_L || key == Gdk.Key.Super_R) return true;
            apply (recording, key == Gdk.Key.BackSpace ? "" : Gtk.accelerator_name (key, state & Gtk.accelerator_get_default_mod_mask ()), false);
            return true;
        }
    }
}
