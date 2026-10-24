namespace Shadow {
    internal class UiCommand : Object {
        public string label;
        public string shortcut;
        public weak Gtk.Widget? source;
        private MenuAction action;
        public bool available { get { return source == null || (source.sensitive && source.visible); } }

        public UiCommand (string label, string shortcut, owned MenuAction action, Gtk.Widget? source = null) {
            this.label = label; this.shortcut = shortcut; this.action = (owned) action; this.source = source;
        }

        public void run () { if (available) action (); }
    }

    internal class CommandPalette : Gtk.Window {
        private Gtk.SearchEntry entry;
        private Gtk.ListBox list;
        private Gtk.ScrolledWindow scroll;
        private List<UiCommand> commands;

        public CommandPalette (Gtk.Window parent, owned List<UiCommand> commands) {
            Object (title: "Command Palette", transient_for: parent, application: parent.application,
                modal: true, destroy_with_parent: true, default_width: 540, default_height: 420);
            this.commands = (owned) commands;
            titlebar = new Gtk.HeaderBar ();
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {margin_start = 12, margin_end = 12, margin_top = 12, margin_bottom = 12};
            entry = new Gtk.SearchEntry () {placeholder_text = "Search actions…"};
            list = new Gtk.ListBox () {selection_mode = Gtk.SelectionMode.SINGLE};
            list.add_css_class ("boxed-list");
            foreach (var command in this.commands) {
                var row = new Gtk.ListBoxRow ();
                var content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 24) {margin_start = 12, margin_end = 12, margin_top = 10, margin_bottom = 10};
                content.append (new Gtk.Label (command.label) {xalign = 0, hexpand = true});
                var hint = new Gtk.Label (command.shortcut);
                hint.add_css_class ("dim-label");
                content.append (hint); row.child = content; list.append (row);
            }
            list.set_filter_func ((row) => {
                var command = this.commands.nth_data (row.get_index ());
                if (!command.available) return false;
                string text = (command.label + " " + command.shortcut).casefold ();
                foreach (var word in entry.text.casefold ().split (" ")) if (!text.contains (word)) return false;
                return true;
            });
            entry.notify["text"].connect (() => { list.invalidate_filter (); select_first (); });
            list.row_activated.connect ((row) => activate_row (row));
            entry.activate.connect (() => activate_row (list.get_selected_row ()));
            entry.stop_search.connect (() => close ());
            var keys = new Gtk.EventControllerKey () {propagation_phase = Gtk.PropagationPhase.CAPTURE};
            keys.key_pressed.connect ((key) => {
                if (key == Gdk.Key.Escape) { close (); return true; }
                if (key == Gdk.Key.Down || key == Gdk.Key.Up) {
                    int step = key == Gdk.Key.Down ? 1 : -1;
                    var selected = list.get_selected_row ();
                    int index = selected == null ? (step > 0 ? -1 : (int) this.commands.length ()) : selected.get_index ();
                    for (int i = index + step; i >= 0 && i < this.commands.length (); i += step) {
                        var row = list.get_row_at_index (i);
                        if (row.get_child_visible ()) { select_row (row); break; }
                    }
                    return true;
                }
                return false;
            });
            ((Gtk.Widget) this).add_controller (keys);
            box.append (entry);
            scroll = new Gtk.ScrolledWindow () {child = list, vexpand = true, hscrollbar_policy = Gtk.PolicyType.NEVER};
            box.append (scroll);
            child = box;
            select_first ();
            map.connect (() => entry.grab_focus ());
            unmap.connect (() => list.set_filter_func (null));
        }

        private void select_first () {
            list.unselect_all ();
            for (int i = 0; i < commands.length (); i++) {
                var row = list.get_row_at_index (i);
                if (row.get_child_visible ()) { select_row (row); break; }
            }
        }

        private void select_row (Gtk.ListBoxRow row) {
            list.select_row (row);
            Idle.add (() => {
                Graphene.Rect bounds = {};
                if (row.compute_bounds (list, out bounds)) {
                    var adjustment = scroll.vadjustment;
                    if (bounds.origin.y < adjustment.value) adjustment.value = bounds.origin.y;
                    else if (bounds.origin.y + bounds.size.height > adjustment.value + adjustment.page_size)
                        adjustment.value = bounds.origin.y + bounds.size.height - adjustment.page_size;
                }
                return Source.REMOVE;
            });
        }

        private void activate_row (Gtk.ListBoxRow? row) {
            if (row == null || !row.get_child_visible ()) return;
            var command = commands.nth_data (row.get_index ());
            close ();
            // Wait for the modal to release focus before running a UI action.
            Idle.add (() => { command.run (); return Source.REMOVE; });
        }
    }
}
