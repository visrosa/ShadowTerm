namespace Shadow {
    // The liner belongs to the host strip and leaves the selected tab open to
    // its content, including when the tabs sit inside a scrolling container.
    public class PaneTabStrip : Gtk.Box {
        public PaneTabStrip () {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0, hexpand: true);
            add_css_class ("pane-tab-strip");
        }

        private PaneTab? active_tab (Gtk.Widget widget) {
            if (widget is PaneTab && ((PaneTab) widget).selected) return (PaneTab) widget;
            for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
                var found = active_tab (child); if (found != null) return found;
            }
            return null;
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            Graphene.Rect bounds = {}; bounds.init (0, 0, get_width (), get_height ());
            var context = snapshot.append_cairo (bounds);
            var color = get_color ();
            context.set_source_rgba (color.red, color.green, color.blue, 0.3);
            context.set_line_width (1);
            var active = active_tab (this);
            Graphene.Rect tab = {};
            if (active != null && active.compute_bounds (this, out tab)) {
                context.move_to (0, get_height () - 0.5); context.line_to (tab.origin.x, get_height () - 0.5);
                context.move_to (tab.origin.x + tab.size.width, get_height () - 0.5); context.line_to (get_width (), get_height () - 0.5);
            } else {
                context.move_to (0, get_height () - 0.5); context.line_to (get_width (), get_height () - 0.5);
            }
            context.stroke ();
            base.snapshot (snapshot);
        }
    }

    // This widget owns presentation and gestures, never the hosted content or
    // its lifetime. Terminal and documentation hosts interpret these signals.
    public class PaneTab : Gtk.Box {
        public Gtk.ToggleButton selector;
        private Gtk.Label label;
        public signal void activated ();
        public signal void closed ();
        public string caption { set { label.label = value; } }
        public bool selected {
            get { return selector.active; }
            set {
                selector.active = value;
                if (value) add_css_class ("selected"); else remove_css_class ("selected");
                queue_draw ();
            }
        }

        public PaneTab (string caption, string close_description = "Close Tab", bool closable = true) {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0, hexpand: true, width_request: 90);
            add_css_class ("workspace-tab");
            selector = new Gtk.ToggleButton () {has_frame = false, hexpand = true};
            label = new Gtk.Label (caption) {ellipsize = Pango.EllipsizeMode.MIDDLE, max_width_chars = 26, xalign = 0.5f};
            selector.child = label;
            selector.clicked.connect (() => activated ());
            selector.notify["active"].connect (() => queue_draw ());
            append (selector);
            if (closable) {
                var close = new Gtk.Button.from_icon_name ("window-close-symbolic") {has_frame = false, tooltip_text = close_description};
                close.clicked.connect (() => closed ()); append (close);
                var middle = new Gtk.GestureClick () {button = 2, propagation_phase = Gtk.PropagationPhase.CAPTURE};
                middle.pressed.connect (() => { middle.set_state (Gtk.EventSequenceState.CLAIMED); closed (); });
                add_controller (middle);
            }
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            Graphene.Rect bounds = {}; bounds.init (0, 0, get_width (), get_height ());
            var context = snapshot.append_cairo (bounds);
            var color = get_color ();
            double width = get_width (), height = get_height ();
            double slope = double.min (12, height / 3);
            double radius = double.min (8, height / 4);
            context.move_to (0, height - 0.5);
            context.line_to (slope, 1);
            context.line_to (width - radius - 1, 1);
            context.arc (width - radius - 1, radius + 1, radius, -Math.PI / 2, 0);
            context.line_to (width - 1, height - 0.5);
            if (selected) {
                context.set_source_rgba (color.red, color.green, color.blue, 0.3);
                context.set_line_width (1); context.stroke ();
            }
            base.snapshot (snapshot);
        }
    }
}
