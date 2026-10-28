namespace Shadow {
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
            context.move_to (0, height - 0.5);
            context.line_to (slope, 1);
            context.line_to (width - slope, 1);
            context.line_to (width, height - 0.5);
            if (!selected) {
                context.close_path ();
                context.set_source_rgba (color.red, color.green, color.blue, 0.035);
                context.fill_preserve ();
            }
            context.set_source_rgba (color.red, color.green, color.blue, selected ? 0.3 : 0.16);
            context.set_line_width (1); context.stroke ();
            base.snapshot (snapshot);
        }
    }
}
