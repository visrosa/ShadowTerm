namespace Shadow {
    // A zero minimum lets Gtk.Box give up decoration before displacing controls.
    internal class LinerTail : Gtk.Widget {
        public LinerTail () {
            Object (can_target: false, accessible_role: Gtk.AccessibleRole.PRESENTATION);
            add_css_class ("tab-liner-tail");
        }

        public override void measure (Gtk.Orientation orientation, int for_size,
                                      out int minimum, out int natural,
                                      out int minimum_baseline, out int natural_baseline) {
            minimum = natural = 0;
            minimum_baseline = natural_baseline = -1;
            if (orientation != Gtk.Orientation.HORIZONTAL) return;
            var context = get_pango_context ();
            var font = context.get_font_description ();
            double size = (double) font.get_size () / Pango.SCALE;
            double resolution = Pango.cairo_context_get_resolution (context);
            if (!font.get_size_is_absolute ()) size *= (resolution > 0 ? resolution : 96) / 72;
            natural = (int) (size * 1.5 + 0.5);
        }
    }

    // The liner belongs to the host strip and leaves the selected tab open to
    // its content, including when the tabs sit inside a scrolling container.
    public class PaneTabStrip : Gtk.Box {
        public bool draw_liner { get; set; default = true; }
        private LinerTail tail = new LinerTail ();
        public PaneTabStrip () {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0, hexpand: true);
            add_css_class ("pane-tab-strip");
            append (tail);
        }

        public void append_content (Gtk.Widget child) {
            insert_child_after (child, tail.get_prev_sibling ());
        }

        private PaneTab? active_tab (Gtk.Widget widget) {
            if (widget is PaneTab && ((PaneTab) widget).selected) return (PaneTab) widget;
            for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
                var found = active_tab (child); if (found != null) return found;
            }
            return null;
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            if (!draw_liner) { base.snapshot (snapshot); return; }
            Graphene.Rect bounds = {}; bounds.init (0, 0, get_width (), get_height ());
            var context = snapshot.append_cairo (bounds);
            var color = get_color ();
            context.set_source_rgba (color.red, color.green, color.blue, 0.3);
            context.set_line_width (1);
            var active = active_tab (this);
            Graphene.Rect tab = {}, viewport = {};
            if (active != null && active.compute_bounds (this, out tab)) {
                double start = tab.origin.x, end = tab.origin.x + tab.size.width;
                for (var parent = active.get_parent (); parent != null && parent != this; parent = parent.get_parent ()) {
                    if (parent is Gtk.ScrolledWindow && parent.compute_bounds (this, out viewport)) {
                        start = double.max (start, viewport.origin.x);
                        end = double.min (end, viewport.origin.x + viewport.size.width);
                    }
                }
                if (end <= start) start = end = 0;
                context.move_to (0, get_height () - 0.5); context.line_to (start, get_height () - 0.5);
                context.move_to (end, get_height () - 0.5); context.line_to (get_width (), get_height () - 0.5);
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
        public bool draw_outline { get; set; default = true; }
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

        public static void outline (Cairo.Context context, double x, double y, double width, double height) {
            double slope = double.min (12, height / 3);
            double radius = double.min (8, height / 4);
            context.move_to (x, y + height - 0.5);
            context.line_to (x + slope, y + 1);
            context.line_to (x + width - radius - 1, y + 1);
            context.arc (x + width - radius - 1, y + radius + 1, radius, -Math.PI / 2, 0);
            context.line_to (x + width - 1, y + height - 0.5);
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            if (selected && draw_outline) {
                Graphene.Rect bounds = {}; bounds.init (0, 0, get_width (), get_height ());
                var context = snapshot.append_cairo (bounds);
                var color = get_color ();
                outline (context, 0, 0, get_width (), get_height ());
                context.set_source_rgba (color.red, color.green, color.blue, 0.3);
                context.set_line_width (1); context.stroke ();
            }
            base.snapshot (snapshot);
        }
    }
}
