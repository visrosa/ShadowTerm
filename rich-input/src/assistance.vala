// The controller is consumer-neutral: providers receive snapshots, never a PTY
// or permission to submit commands. Accepting a candidate is one undoable edit.
public class ComposerAssist : Object {
    public Gtk.Revealer panel;
    private weak RichInput editor;
    private Gtk.ListBox list;
    private Gtk.Label detail;
    private Gtk.ScrolledWindow scroll;
    private VCom.CompletionProvider[] providers = {};
    private VCom.CompletionItem[] items = {};
    private VCom.CompletionContext? snapshot;
    private Cancellable? pending;
    private uint generation = 0;
    public bool visible { get { return panel.reveal_child; } }

    public ComposerAssist (RichInput editor) {
        this.editor = editor;
        providers += new VCom.BuiltinProvider ();
        providers += new VCom.LocalFilesProvider ();
        list = new Gtk.ListBox () {selection_mode = Gtk.SelectionMode.SINGLE, focusable = false};
        list.row_selected.connect ((row) => {
            if (row != null && row.get_index () < items.length) detail.label = items[row.get_index ()].detail;
        });
        list.row_activated.connect ((row) => accept (row.get_index ()));
        detail = new Gtk.Label ("") {xalign = 0, wrap = true, margin_start = 12, margin_end = 12, margin_bottom = 6};
        var body = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
        body.append (new Gtk.Label ("Suggestions · Enter/Tab inserts · Escape closes") {xalign = 0, margin_start = 12});
        scroll = new Gtk.ScrolledWindow () {child = list, max_content_height = 120, propagate_natural_height = true};
        body.append (scroll);
        body.append (detail);
        panel = new Gtk.Revealer () {child = body, transition_duration = 0};
        editor.buffer.changed.connect (dismiss);
        editor.buffer.mark_set.connect ((iter, mark) => {
            if (mark == editor.buffer.get_insert () && snapshot != null && iter.get_offset () != snapshot.cursor) dismiss ();
        });
        editor.notify["fish-mode"].connect (dismiss);
        editor.notify["working-directory"].connect (dismiss);
        editor.unmap.connect (dismiss);
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
        panel.reveal_child = false;
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
        if (!editor.editable || editor.buffer.has_selection) return;
        Gtk.TextIter cursor;
        editor.buffer.get_iter_at_mark (out cursor, editor.buffer.get_insert ());
        var context = new VCom.CompletionContext (editor.source (), cursor.get_offset (), editor.fish_mode, editor.working_directory);
        snapshot = context;
        var cancel = new Cancellable ();
        pending = cancel;
        items = {};
        while (list.get_first_child () != null) list.remove (list.get_first_child ());
        detail.label = "Looking for suggestions…";
        panel.reveal_child = true;
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
            row.child = new Gtk.Label (item.label) {xalign = 0, margin_start = 12, margin_end = 12,
                ellipsize = Pango.EllipsizeMode.END};
            list.append (row);
        }
        detail.label = items.length == 0 ? "No suggestions for this context" : "";
        if (items.length > 0) list.select_row (list.get_row_at_index (0));
        panel.reveal_child = true;
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
