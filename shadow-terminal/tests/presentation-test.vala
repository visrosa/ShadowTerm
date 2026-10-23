private void settle () {
    var loop = new MainLoop ();
    Timeout.add (100, () => { loop.quit (); return Source.REMOVE; });
    loop.run ();
}

private Gtk.Widget? find_surface (Gtk.Widget widget) {
    if (widget.has_css_class ("shadow-composer")) return widget;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var result = find_surface (child);
        if (result != null) return result;
    }
    return null;
}

private RichInput? find_editor (Gtk.Widget widget) {
    if (widget is RichInput) return (RichInput) widget;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var result = find_editor (child);
        if (result != null) return result;
    }
    return null;
}

private Gtk.Button? find_button (Gtk.Widget widget, string label) {
    if (widget is Gtk.Button && ((Gtk.Button) widget).label == label) return (Gtk.Button) widget;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var result = find_button (child, label);
        if (result != null) return result;
    }
    return null;
}

private string run_private (string[] command) throws Error {
    string output;
    int status;
    string[] private_env = Environ.unset_variable (Environ.get (), "DEBUG");
    Process.spawn_sync (null, command, private_env, SpawnFlags.SEARCH_PATH, null, out output, null, out status);
    Process.check_wait_status (status);
    return output.strip ();
}

private Gdk.Texture texture (Gtk.Widget widget, Gtk.Window window) {
    var snapshot = new Gtk.Snapshot ();
    var paintable = new Gtk.WidgetPaintable (widget);
    paintable.snapshot (snapshot, widget.get_width (), widget.get_height ());
    return ((Gtk.Native) window).get_renderer ().render_texture (snapshot.to_node (), null);
}

private uint8 background_alpha (Gtk.Widget widget, Gtk.Window window) {
    var image = texture (widget, window);
    var pixels = new uint8[image.get_width () * image.get_height () * 4];
    image.download (pixels, image.get_width () * 4);
    return pixels[((image.get_height () - 3) * image.get_width () + 3) * 4 + 3];
}

int main (string[] args) {
    // This executable opens synthetic windows; only the isolated harness opts in.
    if (Environment.get_variable ("SHADOW_TERM_PRIVATE_TEST") != "1") return 2;
    Gtk.init ();
    Test.init (ref args);
    // The private bus intentionally has no desktop portal/AccountsService.
    Log.set_always_fatal (LogLevelFlags.LEVEL_ERROR | LogLevelFlags.LEVEL_CRITICAL);
    Test.add_func ("/presentation/live-style-source-and-compact-layout", () => {
        try {
            var host = new Shadow.Host ();
            host.register ();
            var request = Shadow.Request.parse ({"shadow-term", "--input", "composer", "--", "fish"});
            request.session = "private-style-test";
            request.cwd = Environment.get_tmp_dir ();
            request.width = 920; request.height = 650;
            var window = new Shadow.WorkspaceWindow (host, request);
            var session = new Shadow.TerminalSession (host, window, request, Environ.get ());
            window.add_session (session);
            window.present_session (session);
            settle ();
            var surface = find_surface (window.child);
            assert (surface != null);
            var editor = find_editor (surface);
            assert (editor != null && surface.get_height () < 140);
            editor.buffer.text = "printf '%s' '日本語'";
            string source = editor.source ();
            host.preferences.apply ("Monospace 12", "Monospace 12", 0.5, 10000, true, false, "#ddeeff", "#123456");
            settle ();
            Gdk.RGBA expected = {};
            expected.parse ("#ddeeff");
            assert (editor.get_color ().equal (expected));
            assert (background_alpha (surface, window) >= 126 && background_alpha (surface, window) <= 129);
            assert (window.titlebar.get_color ().equal (expected));
            assert (background_alpha (window.titlebar, window) >= 126 && background_alpha (window.titlebar, window) <= 129);
            host.preferences.apply ("Monospace 12", "Monospace 12", 0.8, 10000, true, false, "#ffddaa", "#302010");
            settle ();
            expected.parse ("#ffddaa");
            assert (editor.get_color ().equal (expected));
            assert (background_alpha (surface, window) >= 202 && background_alpha (surface, window) <= 205);
            assert (window.titlebar.get_color ().equal (expected));
            assert (background_alpha (window.titlebar, window) >= 202 && background_alpha (window.titlebar, window) <= 205);
            host.preferences.apply ("Monospace 12", "Monospace 12", 0.5, 10000, true, false, "#ffddaa", "#302010", 0.5);
            settle ();
            assert (background_alpha (surface, window) >= 126 && background_alpha (surface, window) <= 129);
            assert (background_alpha (window.titlebar, window) >= 190 && background_alpha (window.titlebar, window) <= 193);
            assert (editor.source () == source);
            // Give the synthetic preview a running-session presentation without
            // launching a shell or connecting it to the real user environment.
            session.running = true;
            session.input_session.report (session.input_session.token, "ready", "");
            editor.buffer.text = "preserved draft";
            session.input_session.report (session.input_session.token, "busy", "");
            settle ();
            assert (!surface.get_mapped ());
            session.input_session.report (session.input_session.token, "ready", "");
            settle ();
            assert (surface.get_mapped () && editor.source () == "preserved draft");
            editor.buffer.text = "";
            host.preferences.apply ("Monospace 12", "Monospace 12", 1, 10000, true, false, "#f6f5f4", "#20242b");
            session.terminal.feed ("Shadow Term\r\n日本語 résumé.md\r\n\r\nA quieter workspace for commands and their output.\r\n".data);
            settle ();
            double cell_width = session.terminal.get_char_width ();
            double cell_height = session.terminal.get_char_height ();
            var word = Shadow.WordSelection.at (session.terminal, cell_width * 2.5, cell_height * 0.5);
            assert (word != null && word.text () == "Shadow");
            word = Shadow.WordSelection.at (session.terminal, cell_width * 1.5, cell_height * 1.5);
            assert (word != null && word.text () == "日本語");
            word = Shadow.WordSelection.at (session.terminal, cell_width * 9.5, cell_height * 1.5);
            assert (word != null && word.text () == "résumé.md");
            // Exercise the actual pointer event and clipboard path, including
            // VTE's conversion from widget padding to terminal coordinates.
            var padding = session.terminal.get_style_context ().get_padding ();
            Graphene.Point point = {}, target = {};
            point.x = (float) (padding.left + cell_width * 2.5);
            point.y = (float) (padding.top + cell_height * 0.5);
            assert (session.terminal.compute_point (window, point, out target));
            string wid = run_private ({"xdotool", "search", "--onlyvisible", "--name", " · private-style-test$"});
            run_private ({"xdotool", "mousemove", "--window", wid, ((int) target.x).to_string (), ((int) target.y).to_string (), "click", "3"});
            settle ();
            var popup = session.terminal.get_context_menu ();
            assert (popup != null && popup.get_mapped ());
            var copy = find_button (popup, "Copy");
            assert (copy != null && copy.sensitive);
            run_private ({"import", "-window", "root", "/tmp/shadow-term-context-menu.png"});
            copy.clicked ();
            string? copied = null;
            var clipboard_loop = new MainLoop ();
            session.terminal.get_clipboard ().read_text_async.begin (null, (obj, result) => {
                try { copied = session.terminal.get_clipboard ().read_text_async.end (result); }
                catch (Error error) { Test.message (error.message); }
                clipboard_loop.quit ();
            });
            clipboard_loop.run ();
            assert (copied == "Shadow");
            settle ();
            assert (texture (window, window).save_to_png ("/tmp/shadow-term-ui-wide.png"));
            session.menu.popup ();
            settle ();
            // Styling the outer popover node paints a square behind the
            // theme's rounded content. Its corner must remain transparent.
            assert (background_alpha (session.menu.popover, window) < 20);
            run_private ({"import", "-window", "root", "/tmp/shadow-term-options-menu.png"});
            session.menu.popdown ();
            host.preferences.apply ("Monospace 12", "Monospace 12", 0.5, 10000, false, false, "#ddeeff", "#123456");
            settle ();
            assert (!surface.has_css_class ("inherit-pane-style"));
            assert (background_alpha (surface, window) == 255);
            assert (background_alpha (window.titlebar, window) >= 126 && background_alpha (window.titlebar, window) <= 129);
            window.set_default_size (420, 420);
            settle ();
            assert (window.get_width () <= 440);
            assert (texture (window, window).save_to_png ("/tmp/shadow-term-ui-narrow.png"));
            session.running = false;
            session.end_session ();
            // This test has its own process and private XDG configuration.
            host.preferences.apply ("Monospace 12", "Monospace 12", 1, 10000);
        } catch (Error error) { Test.message (error.message); Test.fail (); }
    });
    return Test.run ();
}
