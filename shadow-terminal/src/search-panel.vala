namespace Shadow {
    // A height-for-width surface with a bounded preferred width. Overlays do
    // not contribute this minimum to the terminal's grid allocation.
    internal class SearchPanel : Gtk.Widget {
        private Gtk.Widget content;

        public SearchPanel (Gtk.Widget content) {
            this.content = content;
            content.set_parent (this);
            add_css_class ("session-search");
        }

        public override Gtk.SizeRequestMode get_request_mode () {
            return Gtk.SizeRequestMode.HEIGHT_FOR_WIDTH;
        }

        public override void measure (Gtk.Orientation orientation, int for_size,
                                      out int minimum, out int natural,
                                      out int minimum_baseline, out int natural_baseline) {
            content.measure (orientation, for_size, out minimum, out natural,
                out minimum_baseline, out natural_baseline);
            if (orientation == Gtk.Orientation.HORIZONTAL) {
                int width, height;
                create_pango_layout ("M").get_pixel_size (out width, out height);
                natural = int.max (minimum, int.min (natural, width * 44));
            }
        }

        public override void size_allocate (int width, int height, int baseline) {
            content.allocate (width, height, baseline, null);
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            snapshot_child (content, snapshot);
        }

        protected override void dispose () {
            if (content != null) { content.unparent (); content = null; }
            base.dispose ();
        }
    }
}
