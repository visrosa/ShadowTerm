namespace Shadow {
    // Capture and discovery belong to this view; the registry remains the sole
    // authority for validation, conflicts, persistence and dispatch bindings.
    public class ShortcutSettings : Gtk.Box {
        private Preferences settings;
        private HashTable<string, Gtk.Button> buttons = new HashTable<string, Gtk.Button> (str_hash, str_equal);
        private string? recording;
        private ulong changed_handler;
        public signal void feedback (string message);

        private static string category (string action) {
            if (action == "palette" || action == "preferences" || action == "shortcuts" || action == "hide") return "Application";
            if (action == "composer" || action == "find-composer" || action == "documentation" || action == "recall" || action == "paste-draft") return "Composer";
            if (action == "copy" || action == "paste" || action == "find-terminal" || action.has_prefix ("zoom-")) return "Terminal";
            return "Workspace";
        }

        public ShortcutSettings (Preferences settings) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 12);
            this.settings = settings;
            add_css_class ("pref-shortcuts");
            var search = new Gtk.SearchEntry () {placeholder_text = "Find a shortcut…"}; append (search);
            var stack = new Gtk.Stack () {hexpand = true, hhomogeneous = false, vhomogeneous = false};
            var navigation = new Gtk.StackSidebar () {stack = stack, valign = Gtk.Align.START};
            var content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            content.append (navigation); content.append (stack); append (content);
            foreach (var group in new string[] {"All", "Workspace", "Composer", "Terminal", "Application"}) {
                var list = new Gtk.ListBox () {selection_mode = Gtk.SelectionMode.NONE}; list.add_css_class ("boxed-list");
                for (int i = 0; i < Preferences.ACTIONS.length; i++) {
                    string action = Preferences.ACTIONS[i];
                    if (group != "All" && category (action) != group) continue;
                    var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {margin_start = 10, margin_end = 8, margin_top = 6, margin_bottom = 6};
                    var label = new Gtk.Label (Preferences.ACTION_LABELS[i]) {xalign = 0, wrap = true, hexpand = true, max_width_chars = 26};
                    var capture = new Gtk.Button () {has_frame = false, tooltip_text = "Change " + label.label};
                    capture.clicked.connect (() => begin_capture (action));
                    // All and category pages have separate views of the same action.
                    buttons.insert (group + ":" + action, capture);
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
                list.set_filter_func ((candidate) => ((Gtk.Label) candidate.child.get_first_child ()).label.down ().contains (search.text.down ()));
                search.search_changed.connect (() => list.invalidate_filter ());
                stack.add_titled (list, group, group);
            }
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
        private void refresh () {
            foreach (var identity in buttons.get_keys ()) {
                string action = identity.substring (identity.index_of_char (':') + 1);
                var button = buttons.lookup (identity);
                string shortcut = settings.shortcut (action);
                uint key = 0; Gdk.ModifierType modifiers = 0;
                string label = shortcut != "" && Gtk.accelerator_parse (shortcut, out key, out modifiers) ?
                    Gtk.accelerator_get_label (key, modifiers) : "Disabled";
                button.child = new Gtk.Label (action == recording ? "Press shortcut…" : label);
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
