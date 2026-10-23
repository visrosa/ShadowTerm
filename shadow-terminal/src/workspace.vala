namespace Shadow {
    // A window arranges sessions; each session retains its own PTY, draft and
    // lifecycle. Switching tabs never reconnects or restarts a shell.
    public class WorkspaceWindow : Gtk.ApplicationWindow {
        private weak Host host;
        private Gtk.Stack pages = new Gtk.Stack ();
        private Gtk.Stack menus = new Gtk.Stack ();
        private Gtk.Box tabs = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
        private Gtk.ScrolledWindow tab_scroll;
        private List<TerminalSession> sessions = new List<TerminalSession> ();
        private HashTable<TerminalSession, Gtk.Box> tab_widgets = new HashTable<TerminalSession, Gtk.Box> (direct_hash, direct_equal);
        private Geometry geometry;
        private string geometry_name;
        private bool placed = false;
        private bool was_active = false;
        private bool closing = false;
        private uint blur_idle = 0;
        public TerminalSession? active_session { get { return pages.visible_child as TerminalSession; } }

        public WorkspaceWindow (Host host, Request request) {
            Object (application: host);
            this.host = host;
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
            var create = new Gtk.Button.from_icon_name ("tab-new-symbolic") {tooltip_text = "New Tab (Ctrl+Shift+T)"};
            create.add_css_class ("header-action");
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
                if ((state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) ==
                    (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) {
                    switch (Gdk.keyval_to_lower (key)) {
                    case Gdk.Key.t:
                        if (active_session != null) host.new_tab (this, active_session.directory);
                        return true;
                    case Gdk.Key.n:
                        if (active_session != null) host.new_terminal (active_session.directory);
                        return true;
                    case Gdk.Key.w:
                        if (active_session != null) active_session.end_session ();
                        return true;
                    case Gdk.Key.p: show_palette (); return true;
                    case Gdk.Key.q: close_workspace (); return true;
                    }
                }
                if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 && (key == Gdk.Key.Page_Down || key == Gdk.Key.Page_Up)) {
                    cycle (key == Gdk.Key.Page_Down ? 1 : -1); return true;
                }
                return false;
            });
            ((Gtk.Widget) this).add_controller (keys);
        }

        public void add_session (TerminalSession session) {
            sessions.append (session);
            pages.add_named (session, session.request.session);
            menus.add_named (session.menu, session.request.session);
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {hexpand = true};
            row.add_css_class ("workspace-tab");
            var select = new Gtk.ToggleButton () {has_frame = false, hexpand = true,
                tooltip_text = session.title};
            select.child = new Gtk.Label (session.request.session) {ellipsize = Pango.EllipsizeMode.MIDDLE,
                max_width_chars = 26, width_chars = 8};
            select.clicked.connect (() => { if (!session.closing) select_session (session); });
            var close = new Gtk.Button.from_icon_name ("window-close-symbolic") {has_frame = false, tooltip_text = "Close Tab"};
            close.clicked.connect (() => session.end_session ());
            row.append (select); row.append (close);
            tabs.append (row); tab_widgets.insert (session, row);
            update_session (session);
        }

        public void update_session (TerminalSession session) {
            var row = tab_widgets.lookup (session);
            if (row != null) {
                var select = (Gtk.ToggleButton) row.get_first_child ();
                string caption = session.directory == "/" ? "/" : Path.get_basename (session.directory);
                ((Gtk.Label) select.child).label = caption;
                select.tooltip_text = session.title + "\n" + session.directory;
            }
            if (active_session == session) title = session.title;
        }

        private void select_session (TerminalSession session) {
            if (session.closing) return;
            pages.visible_child = session;
            menus.visible_child = session.menu;
            foreach (var item in sessions) {
                var row = tab_widgets.lookup (item);
                ((Gtk.ToggleButton) row.get_first_child ()).active = item == session;
                if (item == session) row.add_css_class ("selected"); else row.remove_css_class ("selected");
            }
            update_session (session);
            session.focus_input ();
            Idle.add (() => {
                var row = tab_widgets.lookup (session);
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
            select_session (session);
            present ();
            session.focus_input ();
        }

        public void cycle (int step) {
            int index = sessions.index (active_session);
            int count = (int) sessions.length ();
            if (count < 2) return;
            for (int i = 1; i <= count; i++) {
                var candidate = sessions.nth_data ((index + step * i + count * 2) % count);
                if (!candidate.closing) { select_session (candidate); break; }
            }
        }

        public void session_closing (TerminalSession session) {
            save_geometry ();
            var row = tab_widgets.lookup (session);
            if (row != null) row.sensitive = false;
            if (active_session != session) return;
            foreach (var candidate in sessions) {
                if (candidate != session && !candidate.closing) { select_session (candidate); return; }
            }
            visible = false;
        }

        public void remove_session (TerminalSession session) {
            session_closing (session);
            sessions.remove (session);
            pages.remove (session);
            menus.remove (session.menu);
            var row = tab_widgets.lookup (session);
            if (row != null) tabs.remove (row);
            tab_widgets.remove (session);
            if (sessions.length () == 0) {
                if (blur_idle != 0) { Source.remove (blur_idle); blur_idle = 0; }
                destroy ();
            } else if (active_session != null) active_session.focus_input ();
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
    }
}
