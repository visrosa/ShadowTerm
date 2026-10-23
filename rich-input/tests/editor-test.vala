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
    Test.run ();
}
