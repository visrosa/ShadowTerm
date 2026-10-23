private void spin (uint milliseconds) {
    var loop = new MainLoop ();
    Timeout.add (milliseconds, () => { loop.quit (); return Source.REMOVE; });
    loop.run ();
}

private class DelayedProvider : VCom.CompletionProvider {
    public override async VCom.CompletionItem[] complete (VCom.CompletionContext context, Cancellable cancel) throws Error {
        Timeout.add (40, () => { complete.callback (); return Source.REMOVE; });
        yield;
        // Deliberately ignore cancellation: the consumer must reject stale data.
        return {new VCom.CompletionItem (context, "zebra", "zebra", "Test provider")};
    }
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
    Test.add_func ("/editor/assistance-stale-results-and-undo", () => {
        var editor = new RichInput () {fish_mode = true};
        var assistance = new ComposerAssist (editor);
        assistance.add_provider (new DelayedProvider ());
        var body = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        body.append (editor); body.append (assistance.panel);
        var window = new Gtk.Window () {child = body, title = "Isolated editor test"};
        window.present ();
        spin (20);
        editor.buffer.text = "z";
        assistance.request.begin ();
        editor.buffer.insert_at_cursor ("changed", -1);
        spin (80);
        assert (!assistance.visible && editor.source () == "zchanged");
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
    Test.run ();
}
