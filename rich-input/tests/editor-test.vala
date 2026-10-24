private void spin (uint milliseconds) {
    var loop = new MainLoop ();
    Timeout.add (milliseconds, () => { loop.quit (); return Source.REMOVE; });
    loop.run ();
}

private class DelayedProvider : VCom.CompletionProvider {
    public int simultaneous = 0;
    public int maximum = 0;
    public override async VCom.CompletionItem[] complete (VCom.CompletionContext context, Cancellable cancel) throws Error {
        simultaneous++; maximum = int.max (maximum, simultaneous);
        Timeout.add (40, () => { complete.callback (); return Source.REMOVE; });
        yield;
        simultaneous--;
        // Deliberately ignore cancellation: the consumer must reject stale data.
        return {new VCom.CompletionItem (context, "zebra", "zebra", "Test provider")};
    }
}

private class DescribedProvider : VCom.CompletionProvider {
    public override async VCom.CompletionItem[] complete (VCom.CompletionContext context, Cancellable cancel) throws Error {
        VCom.CompletionItem[] items = {};
        for (int i = 0; i < 12; i++) {
            items += new VCom.CompletionItem (context, "candidate-%d".printf (i), "value-%d".printf (i),
                "Description %d · 日本語 · <literal markup> ".printf (i) + string.nfill (100, 'x'));
        }
        return items;
    }
}

private class CompleteProvider : VCom.CompletionProvider {
    public bool truncated = false;
    public override async VCom.CompletionItem[] complete (VCom.CompletionContext context, Cancellable cancel) throws Error {
        VCom.CompletionItem[] items = {};
        foreach (string value in new string[] {"alpha", "beta"})
            if (value.has_prefix (context.prefix)) items += new VCom.CompletionItem (context, value, value, value == "beta" ? "Second description" : "First description") {id = value, continue_after = true};
        return items;
    }
    public override async VCom.CompletionBatch complete_batch (VCom.CompletionContext context, Cancellable cancel) throws Error {
        return new VCom.CompletionBatch (yield complete (context, cancel), truncated ? VCom.CompletionState.TRUNCATED : VCom.CompletionState.COMPLETE);
    }
}

private Gtk.SearchEntry? suggestion_filter (Gtk.Widget widget) {
    if (widget is Gtk.SearchEntry) return (Gtk.SearchEntry) widget;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var entry = suggestion_filter (child); if (entry != null) return entry;
    }
    return null;
}

private Gtk.ListBox? suggestion_list (Gtk.Widget widget) {
    if (widget is Gtk.ListBox) return (Gtk.ListBox) widget;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var list = suggestion_list (child);
        if (list != null) return list;
    }
    return null;
}

void main (string[] args) {
    Gtk.init ();
    Test.init (ref args);
    Test.add_func ("/editor/source-and-undo", () => {
        var editor = new RichInput ();
        string source = "# Olá\ne\u0301 **bold** and `fish`\n終\t'quoted'\n\n";
        editor.buffer.text = source;
        assert (editor.source () == source);
        Gtk.TextIter start, end;
        editor.buffer.get_bounds (out start, out end);
        assert (!editor.buffer.get_text (start, end, false).contains ("**"));
        editor.source_mode = true;
        assert (editor.buffer.get_text (start, end, false) == source);
        editor.fish_mode = true;
        assert (editor.source () == source);
        editor.buffer.insert_at_cursor ("more", -1);
        editor.buffer.undo ();
        assert (editor.source () == source);
    });
    Test.add_func ("/editor/code-is-opaque", () => {
        var spans = RichInput.parse ("`**literal**`\n```fish\n# code\n```\n", false);
        foreach (var span in spans) assert (span.tag != "bold" && span.tag != "heading");
    });
    Test.add_func ("/editor/fish-spans", () => {
        var spans = RichInput.parse ("set name 'Vivian' # $not_variable\necho $name --help", true);
        assert (spans.length == 5);
        assert (spans[0].tag == "keyword");
        assert (spans[1].tag == "string");
        assert (spans[2].tag == "comment");
        assert (spans[3].tag == "variable");
        assert (spans[4].tag == "option");
    });
    Test.add_func ("/editor/readonly-presentation", () => {
        var preview = new RichInput () {editable = false, reveal_active_line = false};
        string source = "# Heading\n**strong** and `code`\n\n";
        preview.buffer.text = source;
        Gtk.TextIter start, end;
        preview.buffer.get_bounds (out start, out end);
        assert (preview.source () == source);
        assert (preview.buffer.get_text (start, end, false) == "Heading\nstrong and code\n\n");
        assert (preview.buffer.get_text (start, end, true) == source);
    });
    Test.add_func ("/editor/formatting-unicode-and-undo", () => {
        var editor = new RichInput ();
        string source = "日本 e\u0301";
        editor.buffer.text = source;
        Gtk.TextIter start, end;
        editor.buffer.get_bounds (out start, out end);
        editor.buffer.select_range (end, start);
        assert (editor.toggle_format ("**"));
        assert (editor.source () == "**" + source + "**");
        assert (editor.toggle_format ("**"));
        assert (editor.source () == source);
        editor.buffer.undo ();
        assert (editor.source () == "**" + source + "**");
        editor.buffer.undo ();
        assert (editor.source () == source);
        editor.fish_mode = true;
        assert (!editor.toggle_format ("*"));
        assert (editor.source () == source);
    });
    Test.add_func ("/editor/empty-format-and-source-search", () => {
        var editor = new RichInput ();
        assert (editor.toggle_format ("*"));
        assert (editor.source () == "**");
        assert (editor.toggle_format ("*"));
        assert (editor.source () == "");
        string source = "alpha **日本** alpha";
        editor.buffer.text = source;
        assert (editor.find_text ("**日本**"));
        Gtk.TextIter start, end;
        assert (editor.buffer.get_selection_bounds (out start, out end));
        assert (editor.buffer.get_text (start, end, true) == "**日本**");
        assert (editor.find_text ("ALPHA"));
        assert (editor.find_text ("alpha", true));
        assert (!editor.find_text ("missing"));
        editor.set_editor_font ("Monospace 13");
        assert (editor.source () == source);
    });
    Test.add_func ("/editor/refinement-filter-and-truncated-uniqueness", () => {
        var editor = new RichInput () {fish_mode = true};
        var assist = new ComposerAssist (editor);
        var provider = new CompleteProvider (); assist.set_provider (provider);
        var window = new Gtk.Window () {child = editor}; window.present (); spin (30);
        editor.buffer.text = "a"; assist.request.begin (); spin (20);
        editor.buffer.insert_at_cursor ("l", -1); spin (40);
        assert (assist.visible && editor.source () == "al");
        assist.handle_key (Gdk.Key.Tab, 0); assert (editor.source () == "alpha");
        editor.buffer.undo (); assert (editor.source () == "al");
        provider.truncated = true;
        assist.request.begin (true); spin (20);
        assert (editor.source () == "al" && assist.visible);
        assist.dismiss (); editor.buffer.text = "";
        assist.request.begin (); spin (20);
        assist.handle_key (Gdk.Key.f, Gdk.ModifierType.CONTROL_MASK);
        var filter = suggestion_filter (assist.panel); filter.text = "Second description"; spin (200);
        assert (editor.source () == "" && assist.visible);
        assert (suggestion_list (assist.panel).get_row_at_index (1) == null);
        assert (suggestion_list (assist.panel).get_selected_row () == null);
        assist.handle_key (Gdk.Key.Down, 0);
        assist.handle_key (Gdk.Key.Return, 0); assert (editor.source () == "beta");
        editor.buffer.undo (); assert (editor.source () == "");
        window.destroy ();
    });
    Test.add_func ("/editor/assistance-stale-results-and-undo", () => {
        var editor = new RichInput () {fish_mode = true};
        var assistance = new ComposerAssist (editor);
        var slow = new DelayedProvider ();
        assistance.add_provider (slow);
        var body = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        body.append (editor);
        var window = new Gtk.Window () {child = body, title = "Isolated editor test"};
        window.present ();
        spin (20);
        editor.buffer.text = "z";
        assistance.request.begin ();
        editor.buffer.insert_at_cursor ("changed", -1);
        spin (80);
        assert (assistance.visible && editor.source () == "zchanged" && slow.maximum == 1);
        assistance.dismiss ();
        editor.buffer.text = "z";
        assistance.request.begin ();
        Gtk.TextIter start;
        editor.buffer.get_start_iter (out start);
        editor.buffer.place_cursor (start);
        spin (80);
        assert (!assistance.visible && editor.source () == "z");
        editor.buffer.get_end_iter (out start);
        editor.buffer.place_cursor (start);
        assistance.request.begin ();
        assert (assistance.visible);
        assert (assistance.handle_key (Gdk.Key.Return, 0));
        assert (editor.source () == "z");
        spin (80);
        assert (assistance.visible);
        assert (assistance.handle_key (Gdk.Key.Tab, 0));
        assert (editor.source () == "zebra");
        editor.buffer.undo ();
        assert (editor.source () == "z");
        window.destroy ();
    });
    Test.add_func ("/editor/floating-descriptions-layout-focus-and-selection", () => {
        var editor = new RichInput () {fish_mode = true};
        var assistance = new ComposerAssist (editor);
        assistance.set_provider (new DescribedProvider ());
        var body = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        var output = new Gtk.DrawingArea () {vexpand = true};
        body.append (output);
        body.append (new Gtk.ScrolledWindow () {child = editor, min_content_height = 56,
            max_content_height = 56, propagate_natural_height = true});
        var other = new Gtk.Button.with_label ("Other focus target");
        body.append (other);
        var window = new Gtk.Window () {child = body, default_width = 380, default_height = 480};
        window.present ();
        editor.grab_focus ();
        editor.buffer.text = "draft";
        spin (30);
        int editor_height = editor.get_height (), output_height = output.get_height ();
        assistance.request.begin ();
        spin (80);
        assert (assistance.visible && assistance.panel.get_mapped () && editor.has_focus);
        assert (assistance.panel.get_parent () == editor);
        assert (editor.get_height () == editor_height && output.get_height () == output_height);
        assert (assistance.panel.get_width () <= window.get_width ());
        var list = suggestion_list (assistance.panel);
        assert (list != null);
        for (int i = 0; i < 12; i++) {
            var content = list.get_row_at_index (i).child;
            var label = (Gtk.Label) content.get_first_child ();
            var description = (Gtk.Label) label.get_next_sibling ();
            assert (label.label == "candidate-%d".printf (i));
            assert (description.visible && description.label.has_prefix ("Description %d · 日本語 · <literal markup>".printf (i)));
            assert (!description.use_markup && description.tooltip_text == description.label);
        }
        assert (assistance.handle_key (Gdk.Key.Page_Down, 0));
        assert (list.get_selected_row ().get_index () == 5);
        assert (assistance.handle_key (Gdk.Key.Tab, 0));
        assert (editor.source () == "value-5" && !assistance.visible);
        editor.buffer.undo ();
        assert (editor.source () == "draft");
        assistance.request.begin ();
        spin (30);
        assert (assistance.handle_key (Gdk.Key.Escape, 0));
        assert (!assistance.visible && editor.has_focus && editor.source () == "draft");
        assistance.request.begin ();
        spin (30);
        other.grab_focus ();
        spin (30);
        assert (!assistance.visible && editor.source () == "draft");
        window.destroy ();
    });
    Test.run ();
}
