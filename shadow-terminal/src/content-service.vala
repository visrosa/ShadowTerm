namespace Shadow {
    public class DocumentationWindow : Gtk.Window {
        private Json.Node? context;
        private string directory;
        private weak Preferences settings;
        private Cancellable? pending;
        private uint generation;
        private bool activated = false;
        private bool passive_dismissal = false;
        private uint blur_idle = 0;
        private ulong active_handler = 0;
        private Geometry geometry;
        private Gtk.Stack documents = new Gtk.Stack ();
        private Gtk.Box tabs = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {hexpand = true, homogeneous = true};
        private PaneTab[] tab_views = {};
        private Gtk.CssProvider appearance_css = new Gtk.CssProvider ();
        private ulong settings_handler;
        private ulong theme_handler;
        private bool stopped;

        private Gtk.SearchEntry search = new Gtk.SearchEntry () {placeholder_text = "Find in document…"};
        private RichInput[] views = {};
        private bool[] loaded = {};
        private Gtk.Label status = new Gtk.Label ("Finding documentation…") {xalign = 0, wrap = true};

        public DocumentationWindow (Gtk.Window origin, Preferences settings, string source, int cursor, string selection, string directory) {
            Object (title: "Documentation", application: origin.application, transient_for: origin, destroy_with_parent: true,
                decorated: false, resizable: true, default_width: 760, default_height: 540);
            this.directory = directory; this.settings = settings;
            add_css_class ("shadow-documentation");
            Gtk.StyleContext.add_provider_for_display (get_display (), appearance_css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            settings_handler = settings.changed.connect (update_appearance);
            theme_handler = Granite.Settings.get_default ().notify["prefers-color-scheme"].connect (update_appearance);
            geometry = new Geometry ("documentation", 760, 540);
            set_default_size (geometry.width, geometry.height);
            ((Gtk.Widget) this).map.connect (() => {
                Idle.add (() => {
                    if (!visible) return Source.REMOVE;
                    int x, y;
                    if (geometry.positioned) position (this, geometry.x, geometry.y, true);
                    else if (get_position (origin, out x, out y)) position (this, x + 36, y + 36, true);
                    return Source.REMOVE;
                });
            });
            var body = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {margin_start = 8, margin_end = 8, margin_top = 8, margin_bottom = 8};
            var bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var scroll_tabs = new Gtk.ScrolledWindow () {child = tabs, hexpand = true, hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                vscrollbar_policy = Gtk.PolicyType.NEVER, propagate_natural_width = false};
            var handle = new Gtk.WindowHandle () {child = scroll_tabs, hexpand = true};
            bar.append (handle);
            var dismiss = new Gtk.CheckButton.with_label ("Dismiss on focus loss") {active = settings.docs_dismiss};
            dismiss.toggled.connect (() => {
                try { settings.set_docs_dismiss (dismiss.active); } catch (Error error) { status.label = error.message; }
            });
            bar.append (dismiss);
            var close = new Gtk.Button.from_icon_name ("window-close-symbolic") {has_frame = false, tooltip_text = "Close documentation (Escape)"};
            close.clicked.connect (() => this.close ()); bar.append (close);
            body.append (bar); body.append (search); body.append (documents); body.append (status);
            documents.vexpand = true;
            child = body; body.add_css_class ("documentation-surface");
            update_appearance ();
            documents.notify["visible-child-name"].connect (() => {
                for (int i = 0; i < tab_views.length; i++) tab_views[i].selected = documents.visible_child_name == i.to_string ();
                load_document.begin ();
            });
            search.search_changed.connect (() => {
                if (documents.visible_child_name != null) views[int.parse (documents.visible_child_name)].find_text (search.text, false);
            });
            search.activate.connect (() => {
                if (documents.visible_child_name != null) views[int.parse (documents.visible_child_name)].find_text (search.text, false);
            });
            var keys = new Gtk.EventControllerKey ();
            keys.key_pressed.connect ((key, code, state) => {
                if (key == Gdk.Key.Escape) { this.close (); return true; }
                if (key == Gdk.Key.f && (state & Gdk.ModifierType.CONTROL_MASK) != 0) { search.grab_focus (); return true; }
                return false;
            });
            ((Gtk.Widget) this).add_controller (keys);
            notify["is-active"].connect (() => {
                if (is_active) activated = true;
                else check_focus ();
            });
            active_handler = application.notify["active-window"].connect (check_focus);
            close_request.connect (() => {
                get_default_size (out geometry.width, out geometry.height);
                geometry.positioned = get_position (this, out geometry.x, out geometry.y);
                geometry.save ("documentation");
                stop ();
                if (!passive_dismissal && is_active) origin.present ();
                return false;
            });
            ((Gtk.Widget) this).unrealize.connect (stop);
            // Undecorated windows need explicit resize hit regions. Movement is
            // provided by WindowHandle without depending on global placement.
            var resize = new Gtk.GestureClick () {button = 1, propagation_phase = Gtk.PropagationPhase.CAPTURE};
            resize.pressed.connect ((count, x, y) => {
                bool left = x < 7, right = x > get_width () - 7, top = y < 7, bottom = y > get_height () - 7;
                if (!(left || right || top || bottom)) return;
                var edge = top ? (left ? Gdk.SurfaceEdge.NORTH_WEST : right ? Gdk.SurfaceEdge.NORTH_EAST : Gdk.SurfaceEdge.NORTH) :
                    bottom ? (left ? Gdk.SurfaceEdge.SOUTH_WEST : right ? Gdk.SurfaceEdge.SOUTH_EAST : Gdk.SurfaceEdge.SOUTH) :
                    left ? Gdk.SurfaceEdge.WEST : Gdk.SurfaceEdge.EAST;
                var event = resize.get_current_event ();
                ((Gdk.Toplevel) get_surface ()).begin_resize (edge, event.get_device (), 1, x, y, event.get_time ());
                resize.set_state (Gtk.EventSequenceState.CLAIMED);
            });
            ((Gtk.Widget) this).add_controller (resize);
            initialize.begin (source, cursor, selection);
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            Graphene.Rect bounds = {}; bounds.init (0, 0, get_width (), get_height ());
            Gsk.RoundedRect clip = {}; clip.init_from_rect (bounds, 12);
            snapshot.push_rounded_clip (clip); base.snapshot (snapshot); snapshot.pop ();
        }

        private void update_appearance () {
            bool dark = Granite.Settings.get_default ().prefers_color_scheme == Granite.Settings.ColorScheme.DARK;
            string background = settings.inherit_style ? settings.pane_background (dark).to_string () : "@theme_bg_color";
            string foreground = settings.inherit_style ? settings.pane_foreground (dark).to_string () : "@theme_fg_color";
            appearance_css.load_from_string ("""
                window.shadow-documentation { background: transparent; }
                .shadow-documentation .documentation-surface { background: %s; color: %s;
                    border: 1px solid alpha(currentColor, 0.2); border-radius: 12px; padding: 5px; }
                .shadow-documentation textview, .shadow-documentation textview text { background: transparent; color: %s; }
            """.printf (background, foreground, foreground));
            foreach (var view in views) { view.set_editor_font (settings.editor_font); view.dark = dark; }
        }

        private void check_focus () {
            if (!activated || !settings.docs_dismiss || blur_idle != 0) return;
            // Deactivation can arrive before the owned child's activation.
            // Evaluate the whole focus family after both notifications settle.
            blur_idle = Idle.add (() => {
                blur_idle = 0;
                if (!is_active && settings.docs_dismiss && !owns_active_transient ()) {
                    passive_dismissal = true; close ();
                }
                return Source.REMOVE;
            });
        }

        private bool owns_active_transient () {
            foreach (var candidate in application.get_windows ()) {
                if (!candidate.is_active) continue;
                var owner = candidate.transient_for;
                for (int depth = 0; owner != null && depth < 16; depth++, owner = owner.transient_for)
                    if (owner == this) return true;
            }
            return false;
        }

        private void cancel_load () {
            generation++;
            if (pending != null) pending.cancel ();
        }

        private void stop () {
            if (stopped) return;
            stopped = true;
            cancel_load ();
            if (settings_handler != 0) { settings.disconnect (settings_handler); settings_handler = 0; }
            if (theme_handler != 0) { Granite.Settings.get_default ().disconnect (theme_handler); theme_handler = 0; }
            Gtk.StyleContext.remove_provider_for_display (get_display (), appearance_css);
            if (blur_idle != 0) { Source.remove (blur_idle); blur_idle = 0; }
            if (active_handler != 0) { application.disconnect (active_handler); active_handler = 0; }
        }

        private async void initialize (string source, int cursor, string selection) {
            var cancel = new Cancellable (); pending = cancel;
            try {
                var request = ContentService.make_request ("lookup");
                request.set_string_member ("source", source); request.set_int_member ("cursor", cursor); request.set_string_member ("selection", selection);
                context = yield ContentService.request (request, directory, cancel);
                cancel.set_error_if_cancelled ();
                title = "Documentation · " + context.get_object ().get_string_member ("query");
                request = ContentService.make_request ("sources"); request.set_string_member ("config", ContentService.configuration ());
                var specs = (yield ContentService.request (request, directory, cancel)).get_array ();
                cancel.set_error_if_cancelled ();
                for (uint i = 0; i < specs.get_length (); i++) {
                    var view = new RichInput () {editable = false, cursor_visible = false, source_mode = true, wrap_mode = Gtk.WrapMode.WORD_CHAR};
                    view.set_editor_font (settings.editor_font);
                    view.dark = Granite.Settings.get_default ().prefers_color_scheme == Granite.Settings.ColorScheme.DARK;
                    views += view; loaded += false;
                    string id = i.to_string ();
                    var tab = new PaneTab (specs.get_object_element (i).get_string_member ("name"), "", false);
                    tab_views += tab; tabs.append (tab);
                    tab.activated.connect (() => { documents.visible_child_name = id; tab.selected = true; });
                    documents.add_titled (new Gtk.ScrolledWindow () {child = view, vexpand = true}, i.to_string (), specs.get_object_element (i).get_string_member ("name"));
                }
                update_appearance ();
                load_document.begin ();
            } catch (Error error) { if (!cancel.is_cancelled ()) status.label = error.message; }
        }

        private async void load_document () {
            if (context == null || documents.visible_child_name == null) return;
            int index = int.parse (documents.visible_child_name);
            if (index >= views.length) return;
            cancel_load ();
            if (loaded[index]) { status.label = ""; return; }
            uint version = generation;
            var cancel = new Cancellable (); pending = cancel;
            status.label = "Loading documentation…";
            try {
                var request = ContentService.make_request ("document"); request.set_member ("context", context.copy ());
                request.set_int_member ("index", index); request.set_string_member ("cwd", directory);
                request.set_string_member ("config", ContentService.configuration ());
                string text = (yield ContentService.request (request, directory, cancel)).get_string ();
                if (version != generation || cancel.is_cancelled ()) return;
                views[index].buffer.text = text; loaded[index] = true; status.label = "";
            } catch (Error error) { if (version == generation && !cancel.is_cancelled ()) status.label = error.message; }
        }
    }
}
