// Providers edit immutable source snapshots. Popup interaction, filtering and
// previews never have access to the consumer's submission channel.
public class ComposerAssist : Object {
    public Gtk.Popover panel;
    private weak RichInput editor;
    private Gtk.ListBox list;
    private Gtk.Label detail;
    private Gtk.SearchEntry filter;
    private Gtk.TextView preview;
    private Gtk.Button promote;
    private Gtk.ScrolledWindow preview_scroll;
    private Gtk.ScrolledWindow popup_frame;
    private Gtk.ScrolledWindow scroll;
    private VCom.CompletionProvider[] providers = {};
    private VCom.CompletionItem[] items = {};
    private VCom.CompletionItem[] shown = {};
    private VCom.CompletionContext? snapshot;
    private Cancellable? pending;
    private Cancellable? preview_pending;
    private uint generation = 0;
    private uint preview_generation = 0;
    private uint refresh_idle = 0;
    private uint preview_timer = 0;
    private bool active = false;
    private bool worker_running = false;
    private bool request_queued = false;
    private bool queued_unique = false;
    private bool editing = false;
    private bool rendering = false;
    private bool complete_set = false;
    private string selected_id = "";
    public bool visible { get { return panel.visible; } }
    public signal void open_preview (string title, string text);

    public ComposerAssist (RichInput editor) {
        this.editor = editor;
        providers += new VCom.BuiltinProvider ();
        providers += new VCom.LocalFilesProvider ();
        list = new Gtk.ListBox () {selection_mode = Gtk.SelectionMode.SINGLE, focusable = false};
        list.row_activated.connect ((row) => accept (row.get_index (), false));
        list.row_selected.connect (() => { if (!rendering) schedule_preview (); });
        detail = new Gtk.Label ("") {xalign = 0, wrap = true, margin_start = 12, margin_end = 12, margin_bottom = 6};
        var body = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
        var hint = new Gtk.Label ("Enter/Tab inserts · Ctrl+Right continues · Ctrl+F filters · Escape closes") {
            xalign = 0, margin_start = 12, margin_end = 12, ellipsize = Pango.EllipsizeMode.END};
        hint.add_css_class ("dim-label"); body.append (hint);
        filter = new Gtk.SearchEntry () {placeholder_text = "Filter labels and descriptions…", visible = false};
        filter.search_changed.connect (render);
        filter.stop_search.connect (() => { filter.text = ""; filter.visible = false; editor.grab_focus (); });
        var filter_keys = new Gtk.EventControllerKey () {propagation_phase = Gtk.PropagationPhase.CAPTURE};
        filter_keys.key_pressed.connect ((key, code, state) => handle_key (key, state));
        filter.add_controller (filter_keys); body.append (filter);
        scroll = new Gtk.ScrolledWindow () {child = list, max_content_height = 240,
            propagate_natural_height = true, hscrollbar_policy = Gtk.PolicyType.NEVER, focusable = false};
        body.append (scroll); body.append (detail);
        preview = new Gtk.TextView () {editable = false, cursor_visible = false, wrap_mode = Gtk.WrapMode.WORD_CHAR,
            left_margin = 12, right_margin = 12, monospace = true, focusable = false};
        preview_scroll = new Gtk.ScrolledWindow () {child = preview, min_content_height = 90, max_content_height = 160, hscrollbar_policy = Gtk.PolicyType.NEVER,
            propagate_natural_height = true, visible = false};
        body.append (preview_scroll);
        promote = new Gtk.Button.with_label ("Open preview") {halign = Gtk.Align.END, has_frame = false, focusable = false};
        promote.clicked.connect (() => {
            var row = list.get_selected_row ();
            if (row != null && row.get_index () < shown.length) open_preview (shown[row.get_index ()].label, preview.buffer.text);
        });
        body.append (promote);
        popup_frame = new Gtk.ScrolledWindow () {child = body, hscrollbar_policy = Gtk.PolicyType.EXTERNAL,
            vscrollbar_policy = Gtk.PolicyType.NEVER, propagate_natural_width = true, propagate_natural_height = true};
        panel = new Gtk.Popover () {child = popup_frame, autohide = false, has_arrow = false,
            position = Gtk.PositionType.TOP, halign = Gtk.Align.START, focusable = false};
        panel.add_css_class ("composer-suggestions"); panel.set_parent (editor);
        var focus = new Gtk.EventControllerFocus ();
        var popup_focus = new Gtk.EventControllerFocus ();
        focus.leave.connect (() => {
            Idle.add (() => {
                if (active && !focus.contains_focus && !popup_focus.contains_focus) dismiss ();
                return Source.REMOVE;
            });
        });
        popup_focus.leave.connect (() => {
            Idle.add (() => {
                if (active && !focus.contains_focus && !popup_focus.contains_focus) dismiss ();
                return Source.REMOVE;
            });
        });
        ((Gtk.Widget) panel).add_controller (popup_focus);
        editor.add_controller (focus);
        var scrolling = new Gtk.EventControllerScroll (Gtk.EventControllerScrollFlags.BOTH_AXES);
        scrolling.scroll.connect (() => { dismiss (); return false; }); editor.add_controller (scrolling);
        editor.buffer.changed.connect (() => {
            if (!active) return;
            editing = true;
            invalidate_results ();
            queue_refresh ();
        });
        editor.buffer.mark_set.connect ((iter, mark) => {
            if (mark != editor.buffer.get_insert () || !active || snapshot == null || iter.get_offset () == snapshot.cursor) return;
            if (editing) queue_refresh (); else dismiss ();
        });
        editor.notify["fish-mode"].connect (dismiss);
        editor.notify["working-directory"].connect (dismiss);
        editor.unmap.connect (dismiss);
    }

    private VCom.CompletionContext context () {
        Gtk.TextIter cursor; editor.buffer.get_iter_at_mark (out cursor, editor.buffer.get_insert ());
        return new VCom.CompletionContext (editor.source (), cursor.get_offset (), editor.fish_mode, editor.working_directory);
    }

    private void queue_refresh () {
        if (refresh_idle != 0) return;
        refresh_idle = Idle.add (() => {
            refresh_idle = 0;
            var next = context ();
            bool same = snapshot != null && next.start == snapshot.start && next.command_prefix == snapshot.command_prefix &&
                next.directory == snapshot.directory && next.fish == snapshot.fish;
            editing = false;
            if (same && !editor.buffer.has_selection) request.begin (); else dismiss ();
            return Source.REMOVE;
        });
    }

    private void show () {
        if (!editor.get_mapped ()) return;
        Gtk.TextIter cursor; editor.buffer.get_iter_at_mark (out cursor, editor.buffer.get_insert ());
        Gdk.Rectangle location; editor.get_iter_location (cursor, out location);
        editor.buffer_to_window_coords (Gtk.TextWindowType.WIDGET, location.x, location.y, out location.x, out location.y);
        panel.set_pointing_to (location);
        var root = (Gtk.Widget) editor.get_root ();
        int width = int.min (600, int.max (160, root.get_width () - 32));
        scroll.max_content_height = int.min (240, int.max (80, (root.get_height () - 200) / 2));
        popup_frame.min_content_width = -1;
        popup_frame.max_content_width = width;
        popup_frame.min_content_width = width;
        panel.popup ();
        var focused = ((Gtk.Window) editor.get_root ()).get_focus ();
        if (focused == null || !focused.is_ancestor (filter)) editor.grab_focus ();
    }

    public void add_provider (VCom.CompletionProvider provider) { providers += provider; }
    public void set_provider (VCom.CompletionProvider provider) { dismiss (); providers = {provider}; }

    public bool expand_abbreviation () {
        if (!editor.editable || editor.buffer.has_selection) return false;
        var current = context ();
        foreach (var provider in providers) {
            var item = provider.expand (current);
            if (item == null) continue;
            snapshot = current; shown = {item}; accept (0, false); return true;
        }
        return false;
    }

    private void invalidate_results () {
        generation++;
        if (pending != null) pending.cancel ();
        pending = null; items = {}; shown = {}; complete_set = false;
        render ();
    }

    public void dismiss () {
        active = false; editing = false; request_queued = false; selected_id = "";
        if (refresh_idle != 0) { Source.remove (refresh_idle); refresh_idle = 0; }
        invalidate_results (); snapshot = null;
        filter.text = ""; filter.visible = false;
        panel.popdown ();
    }

    public bool handle_key (uint key, Gdk.ModifierType state) {
        if (!editor.editable) return false;
        if (key == Gdk.Key.space && (state & Gdk.ModifierType.CONTROL_MASK) != 0) { request.begin (); return true; }
        if (!visible) {
            if (editor.fish_mode && key == Gdk.Key.Tab && (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK)) == 0) {
                request.begin (true); return true;
            }
            if (key == Gdk.Key.space && (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK)) == 0 && !editor.buffer.has_selection)
                expand_abbreviation ();
            return false;
        }
        if (key == Gdk.Key.Escape) { dismiss (); editor.grab_focus (); return true; }
        if (key == Gdk.Key.f && (state & Gdk.ModifierType.CONTROL_MASK) != 0) { filter.visible = true; panel.present (); filter.grab_focus (); return true; }
        bool continuation = key == Gdk.Key.Right && (state & Gdk.ModifierType.CONTROL_MASK) != 0;
        if (continuation || key == Gdk.Key.Return || (key == Gdk.Key.Tab && (state & Gdk.ModifierType.SHIFT_MASK) == 0)) {
            var row = list.get_selected_row (); if (row != null) accept (row.get_index (), continuation);
            return true;
        }
        if (key == Gdk.Key.Up || key == Gdk.Key.Down || key == Gdk.Key.Page_Up || key == Gdk.Key.Page_Down || key == Gdk.Key.ISO_Left_Tab ||
            (key == Gdk.Key.Tab && (state & Gdk.ModifierType.SHIFT_MASK) != 0)) {
            if (shown.length == 0) return true;
            var row = list.get_selected_row ();
            int index = row == null ? 0 : row.get_index ();
            int step = key == Gdk.Key.Page_Down ? 5 : key == Gdk.Key.Page_Up ? -5 : key == Gdk.Key.Down ? 1 : -1;
            index = int.max (0, int.min (shown.length - 1, index + step));
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
        return false;
    }

    public async void request (bool insert_unique = false) {
        if (refresh_idle != 0) { Source.remove (refresh_idle); refresh_idle = 0; }
        editing = false;
        invalidate_results ();
        if (!editor.editable || editor.buffer.has_selection || !editor.get_mapped ()) { dismiss (); return; }
        active = true;
        var current = context (); snapshot = current;
        if (worker_running) {
            request_queued = true; queued_unique = insert_unique;
            detail.label = "Looking for suggestions…"; detail.visible = true; show ();
            return;
        }
        worker_running = true;
        var cancel = new Cancellable (); pending = cancel;
        detail.label = "Looking for suggestions…"; detail.visible = true; show ();
        uint version = generation;
        uint deadline = Timeout.add (1500, () => { cancel.cancel (); return Source.REMOVE; });
        bool all_complete = true;
        string problems = "";
        var seen = new HashTable<string, bool> (str_hash, str_equal);
        foreach (var provider in providers) {
            try {
                var batch = yield provider.complete_batch (current, cancel);
                if (version != generation || !active) break;
                if (batch.message != "") problems += (problems == "" ? "" : "\n") + batch.message;
                all_complete = all_complete && batch.state == VCom.CompletionState.COMPLETE;
                foreach (var item in batch.items) {
                    string identity = "%d:%d:%d:%s:%s".printf (item.start, item.end, item.cursor, item.continue_after.to_string (), item.insertion);
                    if (seen.contains (identity)) continue;
                    seen[identity] = true;
                    if (items.length >= 128) { all_complete = false; continue; }
                    item.provider = provider; items += item;
                }
                // Publish each provider immediately; later results do not hide
                // an already usable set or silently authorize unique insertion.
                render (); show ();
                if (batch.authoritative) break;
            } catch (Error error) {
                all_complete = false;
                if (version == generation) problems += (problems == "" ? "" : "\n") + error.message;
                if (error is IOError.CANCELLED) break;
            }
            if (cancel.is_cancelled ()) break;
        }
        if (MainContext.default ().find_source_by_id (deadline) != null) Source.remove (deadline);
        worker_running = false;
        if (request_queued && active) {
            request_queued = false;
            bool unique = queued_unique;
            Idle.add (() => { if (active) request.begin (unique); return Source.REMOVE; });
        }
        if (version != generation || !active || !editor.get_mapped ()) return;
        pending = null; complete_set = all_complete && !cancel.is_cancelled ();
        detail.label = problems != "" ? problems : cancel.is_cancelled () ? "Suggestions timed out" : !complete_set ? "Partial suggestions · refine your query" : items.length == 0 ? "No suggestions for this context" : "";
        if (shown.length > 0 && list.get_selected_row () == null) detail.label = (problems != "" ? problems + "\n" : "") + "Previous selection unavailable · choose a candidate";
        detail.visible = detail.label != "";
        if (insert_unique && complete_set && items.length == 1 && filter.text == "") accept (0, false);
    }

    private void render () {
        string selected = selected_id;
        rendering = true;
        while (list.get_first_child () != null) list.remove (list.get_first_child ());
        shown = {};
        string query = filter.text.casefold ();
        // Prefix label matches precede label/description substring matches.
        for (int rank = 0; rank < 2; rank++) foreach (var item in items) {
            bool prefix = item.label.casefold ().has_prefix (query);
            if ((rank == 0) != prefix || (!prefix && !item.label.casefold ().contains (query) && !item.detail.casefold ().contains (query))) continue;
            shown += item;
            var row = new Gtk.ListBoxRow () {focusable = false};
            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {margin_start = 12, margin_end = 12, margin_top = 5, margin_bottom = 5};
            content.append (new Gtk.Label (item.label) {xalign = 0, ellipsize = Pango.EllipsizeMode.END, tooltip_text = item.label});
            var description = new Gtk.Label (item.detail) {xalign = 0, ellipsize = Pango.EllipsizeMode.END, visible = item.detail != "", tooltip_text = item.detail};
            description.add_css_class ("dim-label"); description.add_css_class ("caption"); content.append (description);
            if (item.group != "") content.append (new Gtk.Label (item.group) {xalign = 0, tooltip_text = item.provenance});
            row.child = content; list.append (row);
        }
        int selection = selected == "" ? 0 : -1;
        for (int i = 0; i < shown.length; i++) if (selected != "" && shown[i].id == selected) selection = i;
        if (shown.length > 0 && selection >= 0) list.select_row (list.get_row_at_index (selection));
        else if (shown.length > 0) { detail.label = "Previous selection unavailable · choose a candidate"; detail.visible = true; }
        rendering = false;
        schedule_preview ();
    }

    private void schedule_preview () {
        preview_generation++;
        if (preview_pending != null) preview_pending.cancel ();
        if (preview_timer != 0) { Source.remove (preview_timer); preview_timer = 0; }
        preview_scroll.visible = false;
        promote.sensitive = false;
        if (!active || shown.length == 0 || snapshot == null) return;
        var selected = list.get_selected_row ();
        if (selected != null && selected.get_index () < shown.length) selected_id = shown[selected.get_index ()].id;
        preview_timer = Timeout.add (60, () => { preview_timer = 0; load_preview.begin (); return Source.REMOVE; });
    }

    private async void load_preview () {
        var row = list.get_selected_row ();
        if (row == null || row.get_index () >= shown.length || snapshot == null) return;
        var item = shown[row.get_index ()];
        if (item.provider == null) return;
        var current = snapshot;
        uint version = preview_generation;
        var cancel = new Cancellable (); preview_pending = cancel;
        uint deadline = Timeout.add (1500, () => { cancel.cancel (); return Source.REMOVE; });
        string text;
        try { text = yield item.provider.preview (current, item, cancel); }
        catch (Error error) { text = (error is IOError.CANCELLED) ? "" : "Preview unavailable: " + error.message; }
        if (MainContext.default ().find_source_by_id (deadline) != null) Source.remove (deadline);
        if (version != preview_generation || cancel.is_cancelled () || !active) return;
        preview_pending = null;
        promote.sensitive = text != "";
        preview.buffer.text = text; preview_scroll.visible = text != ""; panel.present ();
    }

    private void accept (int index, bool continuation) {
        if (snapshot == null || index < 0 || index >= shown.length) return;
        var current = context ();
        if (current.source != snapshot.source || current.cursor != snapshot.cursor || current.fish != snapshot.fish || current.directory != snapshot.directory) { dismiss (); return; }
        var item = shown[index];
        if (item.start < 0 || item.end < item.start || item.end > snapshot.source.char_count () || item.cursor > item.insertion.char_count () || !item.insertion.validate () || item.insertion.length > 65536) { dismiss (); return; }
        bool keep = continuation && item.continue_after;
        dismiss ();
        Gtk.TextIter start, end;
        editor.buffer.get_iter_at_offset (out start, item.start); editor.buffer.get_iter_at_offset (out end, item.end);
        editor.buffer.begin_user_action (); editor.buffer.delete (ref start, ref end); editor.buffer.insert (ref start, item.insertion, -1);
        if (item.cursor >= 0) editor.buffer.get_iter_at_offset (out start, item.start + item.cursor);
        editor.buffer.place_cursor (start); editor.buffer.end_user_action (); editor.grab_focus ();
        if (keep) request.begin ();
    }
}
