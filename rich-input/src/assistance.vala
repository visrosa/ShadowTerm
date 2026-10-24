// The controller is consumer-neutral: providers receive snapshots, never a PTY
// or permission to submit commands. Accepting a candidate is one undoable edit.
public class ComposerAssist : Object {
    public Gtk.Popover panel;
    private weak RichInput editor;
    private Gtk.ListBox list;
    private Gtk.Label detail;
    private Gtk.ScrolledWindow scroll;
    private VCom.CompletionProvider[] providers = {};
    private VCom.CompletionItem[] items = {};
    private VCom.CompletionContext? snapshot;
    private Cancellable? pending;
    private uint generation = 0;
    public bool visible { get { return panel.visible; } }

    public ComposerAssist (RichInput editor) {
        this.editor = editor;
        providers += new VCom.BuiltinProvider ();
        providers += new VCom.LocalFilesProvider ();
        list = new Gtk.ListBox () {selection_mode = Gtk.SelectionMode.SINGLE, focusable = false};
        list.row_activated.connect ((row) => accept (row.get_index ()));
        detail = new Gtk.Label ("") {xalign = 0, wrap = true, margin_start = 12, margin_end = 12, margin_bottom = 6};
        var body = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
        var hint = new Gtk.Label ("Enter/Tab inserts · Escape closes") {
            xalign = 0, margin_start = 12, margin_end = 12, ellipsize = Pango.EllipsizeMode.END};
        hint.add_css_class ("dim-label");
        body.append (hint);
        scroll = new Gtk.ScrolledWindow () {child = list, max_content_height = 240,
            propagate_natural_height = true, hscrollbar_policy = Gtk.PolicyType.NEVER, focusable = false};
        body.append (scroll);
        body.append (detail);
        // A nonmodal native popup leaves typing and IME ownership in the editor.
        // It is parented for coordinates/lifetime, never appended to host layout.
        panel = new Gtk.Popover () {child = body, autohide = false, has_arrow = false,
            position = Gtk.PositionType.TOP, halign = Gtk.Align.START, focusable = false};
        panel.add_css_class ("composer-suggestions");
        panel.set_parent (editor);
        var focus = new Gtk.EventControllerFocus ();
        focus.leave.connect (dismiss);
        editor.add_controller (focus);
        var scrolling = new Gtk.EventControllerScroll (Gtk.EventControllerScrollFlags.BOTH_AXES);
        scrolling.scroll.connect (() => { dismiss (); return false; });
        editor.add_controller (scrolling);
        editor.buffer.changed.connect (dismiss);
        editor.buffer.mark_set.connect ((iter, mark) => {
            if (mark == editor.buffer.get_insert () && snapshot != null && iter.get_offset () != snapshot.cursor) dismiss ();
        });
        editor.notify["fish-mode"].connect (dismiss);
        editor.notify["working-directory"].connect (dismiss);
        editor.unmap.connect (dismiss);
    }

    private void show () {
        if (!editor.get_mapped ()) return;
        Gtk.TextIter cursor;
        editor.buffer.get_iter_at_mark (out cursor, editor.buffer.get_insert ());
        Gdk.Rectangle location;
        editor.get_iter_location (cursor, out location);
        editor.buffer_to_window_coords (Gtk.TextWindowType.WIDGET, location.x, location.y,
            out location.x, out location.y);
        panel.set_pointing_to (location);
        // Bound long candidates to the host rather than their natural text width.
        int width = int.min (560, int.max (160, ((Gtk.Widget) editor.get_root ()).get_width () - 32));
        panel.child.width_request = width;
        panel.popup ();
        editor.grab_focus ();
    }

    public void add_provider (VCom.CompletionProvider provider) { providers += provider; }

    public void set_provider (VCom.CompletionProvider provider) {
        dismiss ();
        providers = {provider};
    }

    public bool expand_abbreviation () {
        if (!editor.editable || editor.buffer.has_selection) return false;
        Gtk.TextIter cursor;
        editor.buffer.get_iter_at_mark (out cursor, editor.buffer.get_insert ());
        var context = new VCom.CompletionContext (editor.source (), cursor.get_offset (), editor.fish_mode, editor.working_directory);
        foreach (var provider in providers) {
            var item = provider.expand (context);
            if (item == null) continue;
            snapshot = context; items = {item}; accept (0);
            return true;
        }
        return false;
    }

    public void dismiss () {
        generation++;
        if (pending != null) pending.cancel ();
        pending = null; snapshot = null;
        panel.popdown ();
    }

    public bool handle_key (uint key, Gdk.ModifierType state) {
        if (!editor.editable) return false;
        if (key == Gdk.Key.space && (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
            request.begin (); return true;
        }
        if (!visible) {
            if (editor.fish_mode && key == Gdk.Key.Tab && (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK)) == 0) {
                request.begin (true); return true;
            }
            if (key == Gdk.Key.space &&
                (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK)) == 0 && !editor.buffer.has_selection) {
                expand_abbreviation ();
            }
            return false;
        }
        if (key == Gdk.Key.Escape) { dismiss (); return true; }
        if (key == Gdk.Key.Return || (key == Gdk.Key.Tab && (state & Gdk.ModifierType.SHIFT_MASK) == 0)) {
            var row = list.get_selected_row ();
            if (row != null) accept (row.get_index ());
            return true;
        }
        if (key == Gdk.Key.Up || key == Gdk.Key.Down || key == Gdk.Key.Page_Up || key == Gdk.Key.Page_Down || key == Gdk.Key.ISO_Left_Tab ||
            (key == Gdk.Key.Tab && (state & Gdk.ModifierType.SHIFT_MASK) != 0)) {
            if (items.length == 0) return true;
            var row = list.get_selected_row ();
            int index = row == null ? 0 : row.get_index ();
            int step = key == Gdk.Key.Page_Down ? 5 : key == Gdk.Key.Page_Up ? -5 : key == Gdk.Key.Down ? 1 : -1;
            index = int.max (0, int.min (items.length - 1, index + step));
            list.select_row (list.get_row_at_index (index));
            Graphene.Rect bounds;
            if (list.get_row_at_index (index).compute_bounds (list, out bounds)) {
                var adjustment = scroll.vadjustment;
                double top = bounds.origin.y, bottom = top + bounds.size.height;
                if (top < adjustment.value) adjustment.value = top;
                else if (bottom > adjustment.value + adjustment.page_size) adjustment.value = bottom - adjustment.page_size;
            }
            return true;
        }
        // Typing dismisses a snapshot; it never accepts a suggestion implicitly.
        return false;
    }

    public async void request (bool insert_unique = false) {
        dismiss ();
        if (!editor.editable || editor.buffer.has_selection || !editor.get_mapped ()) return;
        Gtk.TextIter cursor;
        editor.buffer.get_iter_at_mark (out cursor, editor.buffer.get_insert ());
        var context = new VCom.CompletionContext (editor.source (), cursor.get_offset (), editor.fish_mode, editor.working_directory);
        snapshot = context;
        var cancel = new Cancellable ();
        pending = cancel;
        items = {};
        while (list.get_first_child () != null) list.remove (list.get_first_child ());
        detail.label = "Looking for suggestions…";
        detail.visible = true;
        show ();
        uint version = generation;
        uint deadline = Timeout.add (1500, () => { cancel.cancel (); return Source.REMOVE; });
        VCom.CompletionItem[] results = {};
        foreach (var provider in providers) {
            try {
                foreach (var item in yield provider.complete (context, cancel)) {
                    if (results.length < 128) results += item;
                }
            } catch (Error error) {
                // A missing/unreadable directory should not suppress builtin help.
                if (error is IOError.CANCELLED) break;
            }
            if (cancel.is_cancelled ()) break;
        }
        if (MainContext.default ().find_source_by_id (deadline) != null) Source.remove (deadline);
        if (version != generation || !editor.get_mapped ()) return;
        pending = null;
        if (cancel.is_cancelled ()) { detail.label = "Suggestions timed out · Escape closes"; return; }
        items = results; snapshot = context;
        foreach (var item in items) {
            var row = new Gtk.ListBoxRow () {focusable = false};
            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
                margin_start = 12, margin_end = 12, margin_top = 5, margin_bottom = 5};
            content.append (new Gtk.Label (item.label) {xalign = 0, ellipsize = Pango.EllipsizeMode.END,
                tooltip_text = item.label});
            var description = new Gtk.Label (item.detail) {xalign = 0, ellipsize = Pango.EllipsizeMode.END,
                visible = item.detail != "", tooltip_text = item.detail};
            description.add_css_class ("dim-label");
            description.add_css_class ("caption");
            content.append (description);
            row.child = content;
            list.append (row);
        }
        detail.label = items.length == 0 ? "No suggestions for this context" : "";
        detail.visible = items.length == 0;
        if (items.length > 0) list.select_row (list.get_row_at_index (0));
        show ();
        if (insert_unique && items.length == 1) accept (0);
    }

    private void accept (int index) {
        if (snapshot == null || index < 0 || index >= items.length) return;
        Gtk.TextIter cursor;
        editor.buffer.get_iter_at_mark (out cursor, editor.buffer.get_insert ());
        if (editor.source () != snapshot.source || cursor.get_offset () != snapshot.cursor ||
            editor.fish_mode != snapshot.fish || editor.working_directory != snapshot.directory) { dismiss (); return; }
        var item = items[index];
        if (item.start < 0 || item.end < item.start || item.end > snapshot.source.char_count () ||
            item.cursor > item.insertion.char_count () ||
            !item.insertion.validate () || item.insertion.length > 65536) { dismiss (); return; }
        dismiss ();
        Gtk.TextIter start, end;
        editor.buffer.get_iter_at_offset (out start, item.start);
        editor.buffer.get_iter_at_offset (out end, item.end);
        editor.buffer.begin_user_action ();
        editor.buffer.delete (ref start, ref end);
        editor.buffer.insert (ref start, item.insertion, -1);
        if (item.cursor >= 0) editor.buffer.get_iter_at_offset (out start, item.start + item.cursor);
        editor.buffer.place_cursor (start);
        editor.buffer.end_user_action ();
        editor.grab_focus ();
    }
}
