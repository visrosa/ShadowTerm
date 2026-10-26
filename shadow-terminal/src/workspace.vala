namespace Shadow {
    // Layout nodes contain live widgets, never another terminal stream. Moving
    // a leaf therefore preserves its emulator, PTY, pending input and draft.
    public class SessionTab : Gtk.Box {
        public TerminalSession? active;
        public SessionTab (TerminalSession session) {
            Object (orientation: Gtk.Orientation.VERTICAL, hexpand: true, vexpand: true);
            append (session); active = session;
        }

        private void collect (Gtk.Widget node, ref List<TerminalSession> leaves) {
            if (node is TerminalSession) leaves.append ((TerminalSession) node);
            else if (node is Gtk.Paned) {
                var pane = (Gtk.Paned) node;
                if (pane.start_child != null) collect (pane.start_child, ref leaves);
                if (pane.end_child != null) collect (pane.end_child, ref leaves);
            }
        }
        public List<TerminalSession> members () {
            var leaves = new List<TerminalSession> ();
            if (get_first_child () != null) collect (get_first_child (), ref leaves);
            return leaves;
        }

        private void replace (Gtk.Widget parent, Gtk.Widget old, Gtk.Widget? replacement) {
            if (parent == this) { remove (old); if (replacement != null) append (replacement); }
            else {
                var pane = (Gtk.Paned) parent;
                if (pane.start_child == old) pane.start_child = replacement;
                else pane.end_child = replacement;
            }
        }

        public void split (TerminalSession relative, TerminalSession session, Gtk.Orientation orientation) {
            var parent = relative.get_parent ();
            var pane = new Gtk.Paned (orientation) {hexpand = true, vexpand = true,
                resize_start_child = true, resize_end_child = true,
                shrink_start_child = false, shrink_end_child = false, wide_handle = true};
            int size = orientation == Gtk.Orientation.HORIZONTAL ? relative.get_width () : relative.get_height ();
            replace (parent, relative, pane);
            pane.start_child = relative; pane.end_child = session;
            pane.position = int.max (100, size / 2);
            active = session;
            add_css_class ("split-layout");
        }

        public void take (TerminalSession session) {
            var parent = session.get_parent ();
            if (parent == this) remove (session);
            else {
                var pane = (Gtk.Paned) parent;
                var grand = pane.get_parent ();
                Gtk.Widget sibling = pane.start_child == session ? pane.end_child : pane.start_child;
                pane.start_child = null; pane.end_child = null;
                replace (grand, pane, sibling);
            }
            if (active == session) active = members ().nth_data (0);
            if (members ().length () < 2) remove_css_class ("split-layout");
        }
    }

    // A window arranges sessions; each session retains its own PTY, draft and
    // lifecycle. Switching tabs never reconnects or restarts a shell.
    public class WorkspaceWindow : Gtk.ApplicationWindow {
        private weak Host host;
        private Gtk.Stack pages = new Gtk.Stack ();
        private Gtk.Stack menus = new Gtk.Stack ();
        private Gtk.Box tabs = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
        private Gtk.ScrolledWindow tab_scroll;
        private List<TerminalSession> sessions = new List<TerminalSession> ();
        private HashTable<SessionTab, Gtk.Box> tab_widgets = new HashTable<SessionTab, Gtk.Box> (direct_hash, direct_equal);
        private List<SessionTab> layouts = new List<SessionTab> ();
        private HashTable<TerminalSession, SessionTab> session_tabs = new HashTable<TerminalSession, SessionTab> (direct_hash, direct_equal);
        private Geometry geometry;
        private string geometry_name;
        private bool placed = false;
        private bool was_active = false;
        private bool closing = false;
        private string default_directory;
        private uint blur_idle = 0;
        private ulong preferences_handler = 0;
        public TerminalSession? active_session { get { return (pages.visible_child as SessionTab) == null ? null : ((SessionTab) pages.visible_child).active; } }

        public WorkspaceWindow (Host host, Request request) {
            Object (application: host);
            this.host = host;
            default_directory = request.cwd;
            geometry_name = request.session;
            geometry = new Geometry (geometry_name);
            int width = request.width > 0 ? request.width : geometry.width;
            int height = request.height > 0 ? request.height : geometry.height;
            var monitors = get_display ().get_monitors ();
            if (monitors.get_n_items () > 0) {
                var bounds = ((Gdk.Monitor) monitors.get_item (0)).get_geometry ();
                width = int.min (width, int.max (320, bounds.width - 60));
                height = int.min (height, int.max (200, bounds.height - 80));
            }
            set_default_size (width, height);
            add_css_class ("shadow-terminal");
            var header = new Gtk.HeaderBar ();
            header.add_css_class ("shadow-header");
            var create = new Gtk.Button.from_icon_name ("tab-new-symbolic") {tooltip_text = "New Tab (Ctrl+T)"};
            string new_tab_key = host.preferences.shortcut_label ("new-tab");
            create.tooltip_text = "New Tab" + (new_tab_key == "" ? "" : " (" + new_tab_key + ")");
            create.add_css_class ("header-action");
            preferences_handler = host.preferences.changed.connect (() => {
                string binding = host.preferences.shortcut_label ("new-tab");
                create.tooltip_text = "New Tab" + (binding == "" ? "" : " (" + binding + ")");
            });
            ((Gtk.Widget) this).unrealize.connect (() => {
                if (preferences_handler != 0) { host.preferences.disconnect (preferences_handler); preferences_handler = 0; }
            });
            create.clicked.connect (() => host.new_tab (this, active_session == null ? request.cwd : active_session.directory));
            header.pack_start (create);
            tabs.hexpand = true;
            tab_scroll = new Gtk.ScrolledWindow () {child = tabs, hexpand = true,
                hscrollbar_policy = Gtk.PolicyType.EXTERNAL, vscrollbar_policy = Gtk.PolicyType.NEVER,
                propagate_natural_width = true};
            header.title_widget = tab_scroll;
            header.pack_end (menus);
            titlebar = header;
            pages.vexpand = true;
            pages.hexpand = true;
            pages.transition_type = Gtk.StackTransitionType.NONE;
            pages.hhomogeneous = false; pages.vhomogeneous = false;
            child = pages;
            close_request.connect (() => { close_workspace (); return true; });
            map.connect (() => {
                if (placed) return;
                placed = true;
                Idle.add (() => { if (!closing && visible) position (this, geometry.x, geometry.y, geometry.positioned); return Source.REMOVE; });
            });
            notify["is-active"].connect (() => {
                if (is_active) {
                    was_active = true;
                    if (active_session != null) active_session.focus_input ();
                } else if (was_active && visible && active_session != null && active_session.request.hide_on_blur && blur_idle == 0) {
                    blur_idle = Idle.add (() => {
                        blur_idle = 0;
                        if (!closing && !is_active && visible && !owned_dialog_active ()) hide_workspace ();
                        return Source.REMOVE;
                    });
                }
            });
            var keys = new Gtk.EventControllerKey () {propagation_phase = Gtk.PropagationPhase.CAPTURE};
            keys.key_pressed.connect ((key, code, state) => {
                var action = host.preferences.shortcut_action (key, state);
                return action != null && dispatch_action (action);
            });
            ((Gtk.Widget) this).add_controller (keys);
        }

        public void add_session (TerminalSession session, TerminalSession? relative = null, Gtk.Orientation orientation = Gtk.Orientation.HORIZONTAL) {
            sessions.append (session);
            SessionTab tab;
            if (relative != null && session_tabs.lookup (relative) != null) {
                tab = session_tabs.lookup (relative);
                tab.split (relative, session, orientation);
            } else {
                tab = new SessionTab (session);
                layouts.append (tab);
                pages.add_named (tab, session.request.session);
                var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {hexpand = true};
                row.add_css_class ("workspace-tab");
                var select = new Gtk.ToggleButton () {has_frame = false, hexpand = true};
                select.child = new Gtk.Label (session.request.session) {ellipsize = Pango.EllipsizeMode.MIDDLE,
                    max_width_chars = 26, width_chars = 8};
                select.clicked.connect (() => { if (tab.active != null) select_session (tab.active); });
                var close = new Gtk.Button.from_icon_name ("window-close-symbolic") {has_frame = false, tooltip_text = "Close Tab"};
                close.clicked.connect (() => close_tab (tab));
                row.append (select); row.append (close);
                var middle = new Gtk.GestureClick () {button = 2, propagation_phase = Gtk.PropagationPhase.CAPTURE};
                weak Gtk.GestureClick middle_click = middle;
                middle.pressed.connect (() => { middle_click.set_state (Gtk.EventSequenceState.CLAIMED); close_tab (tab); });
                row.add_controller (middle);
                tabs.append (row); tab_widgets.insert (tab, row);
            }
            session_tabs.insert (session, tab);
            menus.add_named (session.menu, session.request.session);
            update_session (session);
        }

        public bool contains_visible (TerminalSession session) {
            return visible && pages.visible_child == session_tabs.lookup (session);
        }

        public void update_session (TerminalSession session) {
            var tab = session_tabs.lookup (session);
            if (tab == null) return;
            var row = tab_widgets.lookup (tab);
            var current = tab.active ?? session;
            if (row != null) {
                var select = (Gtk.ToggleButton) row.get_first_child ();
                string caption = current.directory == "/" ? "/" : Path.get_basename (current.directory);
                int count = (int) tab.members ().length ();
                ((Gtk.Label) select.child).label = caption + (count > 1 ? " · %d".printf (count) : "");
                select.tooltip_text = current.title + "\n" + current.directory;
            }
            if (active_session == session) title = session.title;
        }

        public void activate_session (TerminalSession session) { select_session (session, false); }

        private void select_session (TerminalSession session, bool focus = true) {
            if (session.closing) return;
            var tab = session_tabs.lookup (session);
            if (tab == null) return;
            tab.active = session;
            pages.visible_child = tab;
            menus.visible_child = session.menu;
            foreach (var item in layouts) {
                var row = tab_widgets.lookup (item);
                ((Gtk.ToggleButton) row.get_first_child ()).active = item == tab;
                if (item == tab) row.add_css_class ("selected"); else row.remove_css_class ("selected");
            }
            foreach (var item in sessions) {
                if (item == session) item.add_css_class ("active-pane"); else item.remove_css_class ("active-pane");
            }
            update_session (session);
            if (focus) session.focus_input ();
            Idle.add (() => {
                var row = tab_widgets.lookup (tab);
                Graphene.Rect bounds = {};
                if (row != null && row.compute_bounds (tabs, out bounds)) {
                    var adjustment = tab_scroll.hadjustment;
                    if (bounds.origin.x < adjustment.value) adjustment.value = bounds.origin.x;
                    else if (bounds.origin.x + bounds.size.width > adjustment.value + adjustment.page_size)
                        adjustment.value = bounds.origin.x + bounds.size.width - adjustment.page_size;
                }
                return Source.REMOVE;
            });
        }

        public void present_session (TerminalSession session) {
            if (closing || session.closing) return;
            if (!visible) was_active = false;
            select_session (session); present (); session.focus_input ();
        }

        public void cycle (int step) {
            int index = layouts.index ((SessionTab) pages.visible_child);
            int count = (int) layouts.length ();
            for (int i = 1; i <= count; i++) {
                var tab = layouts.nth_data ((index + step * i + count * 2) % count);
                foreach (var session in tab.members ())
                    if (!session.closing) { select_session (tab.active != null && !tab.active.closing ? tab.active : session); return; }
            }
        }

        public void cycle_pane (int step) {
            var tab = pages.visible_child as SessionTab;
            if (tab == null) return;
            var leaves = tab.members ();
            int count = (int) leaves.length ();
            int index = leaves.index (active_session);
            for (int i = 1; i <= count; i++) {
                var session = leaves.nth_data ((index + step * i + count * 2) % count);
                if (!session.closing) { select_session (session); return; }
            }
        }

        public void close_tab (SessionTab? tab = null) {
            tab = tab ?? pages.visible_child as SessionTab;
            if (tab == null) return;
            foreach (var session in tab.members ()) session.end_session ();
        }

        public void session_closing (TerminalSession session) {
            save_geometry ();
            if (active_session != session) return;
            var tab = session_tabs.lookup (session);
            foreach (var candidate in tab.members ()) {
                if (candidate != session && !candidate.closing) { select_session (candidate); return; }
            }
            foreach (var candidate in sessions) {
                if (candidate != session && !candidate.closing) { select_session (candidate); return; }
            }
            visible = false;
        }

        // Removing an attachment does not end a session. Only the caller's
        // explicit close action terminates the PTY; transfers use this path too.
        public void take_session (TerminalSession session) {
            var previous_active = active_session;
            var tab = session_tabs.lookup (session);
            if (tab == null) return;
            tab.take (session);
            sessions.remove (session); session_tabs.remove (session);
            menus.remove (session.menu);
            if (tab.members ().length () == 0) {
                pages.remove (tab); layouts.remove (tab);
                var row = tab_widgets.lookup (tab);
                if (row != null) tabs.remove (row);
                tab_widgets.remove (tab);
            }
            if (sessions.length () == 0) {
                save_geometry ();
                if (blur_idle != 0) { Source.remove (blur_idle); blur_idle = 0; }
                destroy ();
            } else {
                TerminalSession? next = previous_active != session && previous_active != null && !previous_active.closing ? previous_active : tab.active;
                if (next == null || next.closing) {
                    next = null;
                    foreach (var candidate in sessions) if (!candidate.closing) { next = candidate; break; }
                }
                if (next != null) select_session (next);
                foreach (var item in sessions) update_session (item);
            }
        }

        public void remove_session (TerminalSession session) { take_session (session); }

        public void move_to_tab (TerminalSession session) {
            if (session_tabs.lookup (session).members ().length () < 2) return;
            take_session (session); add_session (session); select_session (session);
        }

        public void join_previous_tab () {
            if (layouts.length () < 2 || active_session == null) return;
            var target = active_session;
            int index = layouts.index ((SessionTab) pages.visible_child);
            var previous = layouts.nth_data ((index + layouts.length () - 1) % layouts.length ());
            var session = previous.active;
            if (session == null || session.closing) return;
            take_session (session);
            add_session (session, target); select_session (session);
        }

        private void save_geometry () {
            get_default_size (out geometry.width, out geometry.height);
            if (visible && !is_maximized () && !is_fullscreen ())
                geometry.positioned = get_position (this, out geometry.x, out geometry.y);
            geometry.save (geometry_name);
        }

        public void hide_workspace () {
            save_geometry ();
            was_active = false;
            visible = false;
        }

        public void close_workspace () {
            if (closing) return;
            closing = true;
            save_geometry ();
            visible = false;
            // Closing an idle session removes it immediately from this list.
            var copy = sessions.copy ();
            foreach (var session in copy) session.end_session ();
        }

        private bool owned_dialog_active () {
            foreach (var candidate in host.get_windows ()) {
                if (candidate == this || !candidate.is_active) continue;
                for (var parent = candidate.transient_for; parent != null; parent = parent.transient_for)
                    if (parent == this) return true;
            }
            return false;
        }

        public void show_palette () {
            if (active_session != null) active_session.show_palette ();
        }

        public bool dispatch_action (string action) {
            var current = active_session;
            switch (action) {
            case "new-tab": if (current != null) host.new_tab (this, current.directory); return true;
            case "default-tab": new_default_tab (); return true;
            case "new-window": if (current != null) host.new_terminal (current.directory); return true;
            case "close-pane": if (current != null) current.end_session (); return true;
            case "close-tab": close_tab (); return true;
            case "close-window": close_workspace (); return true;
            case "previous-tab": cycle (-1); return true;
            case "next-tab": cycle (1); return true;
            case "next-pane": cycle_pane (1); return true;
            case "previous-pane": cycle_pane (-1); return true;
            case "split-horizontal": host.split_session (this, Gtk.Orientation.HORIZONTAL); return true;
            case "split-vertical": host.split_session (this, Gtk.Orientation.VERTICAL); return true;
            case "detach-pane": if (current != null) host.detach_session (current); return true;
            case "pane-to-tab": if (current != null) move_to_tab (current); return true;
            case "join-tab": join_previous_tab (); return true;
            default: return current != null && current.dispatch_action (action);
            }
        }

        public void new_default_tab () { host.new_tab (this, default_directory); }
    }
}
