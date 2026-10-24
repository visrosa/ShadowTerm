namespace Shadow {
    [CCode (cname = "shadow_event_coordinates", cheader_filename = "word-selection.h")]
    private extern bool event_coordinates (Vte.EventContext context, out double x, out double y);

    public class TerminalContext : Object {
        private Vte.Terminal terminal;
        private Gtk.DrawingArea highlight;
        private WordSelection? word;
        private weak TerminalSession session;

        public TerminalContext (TerminalSession session, Gtk.Overlay overlay) {
            this.session = session;
            terminal = session.terminal;
            highlight = new Gtk.DrawingArea () {can_target = false, hexpand = true, vexpand = true};
            highlight.set_draw_func ((area, context) => { if (word != null) word.draw (context); });
            overlay.add_overlay (highlight);
            terminal.setup_context_menu.connect ((context) => {
                if (context == null) return;
                clear ();
                if (!terminal.get_has_selection () && context != null) {
                    double x, y;
                    if (event_coordinates (context, out x, out y)) {
                        // Context events include CSS padding; VTE's regex
                        // hit-testing coordinates start at the cell grid.
                        var padding = terminal.get_style_context ().get_padding ();
                        word = WordSelection.at (terminal, x - padding.left, y - padding.top);
                    }
                }
                highlight.queue_draw ();
                var menu = new Gtk.Popover ();
                weak Gtk.Popover popup = menu;
                var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {margin_start = 6, margin_end = 6, margin_top = 6, margin_bottom = 6};
                var copy = new Gtk.Button.with_label ("Copy") {has_frame = false, sensitive = terminal.get_has_selection () || word != null};
                copy.clicked.connect (() => { copy_selection (); popup.popdown (); });
                var paste = new Gtk.Button.with_label ("Paste") {has_frame = false};
                paste.clicked.connect (() => { this.session.paste_clipboard (); popup.popdown (); });
                var palette = new Gtk.Button.with_label ("Command Palette…") {has_frame = false};
                palette.clicked.connect (() => { popup.popdown (); this.session.show_palette (); });
                box.append (copy); box.append (paste); box.append (palette);
                menu.child = box;
                terminal.set_context_menu (menu);
            });
            terminal.contents_changed.connect (clear);
            terminal.vadjustment.value_changed.connect (clear);
            var clicks = new Gtk.GestureClick () {button = 1, propagation_phase = Gtk.PropagationPhase.CAPTURE};
            clicks.pressed.connect (() => clear ());
            terminal.add_controller (clicks);
            var primary = new Gtk.GestureClick () {button = 2, propagation_phase = Gtk.PropagationPhase.CAPTURE};
            primary.pressed.connect (() => {
                if (!this.session.guard_pane_input ()) return;
                primary.set_state (Gtk.EventSequenceState.CLAIMED);
                this.session.paste_clipboard (true);
            });
            terminal.add_controller (primary);
            var keys = new Gtk.EventControllerKey ();
            keys.key_pressed.connect (() => { clear (); return false; });
            terminal.add_controller (keys);
        }

        private void clear () { word = null; highlight.queue_draw (); }

        public void close () {
            clear ();
            highlight.set_draw_func (null);
            // VTE retains the context widget. Drop its callbacks so it cannot
            // retain this controller and the terminal after a tab closes.
            var popup = terminal.get_context_menu () as Gtk.Popover;
            if (popup != null) { popup.popdown (); popup.child = null; }
        }

        public void copy_selection () {
            if (terminal.get_has_selection ()) terminal.copy_clipboard_format (Vte.Format.TEXT);
            else if (word != null) terminal.get_clipboard ().set_text (word.text ());
        }
    }
}
