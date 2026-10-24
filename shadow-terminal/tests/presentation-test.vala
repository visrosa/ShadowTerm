private void settle () {
    var loop = new MainLoop ();
    Timeout.add (100, () => { loop.quit (); return Source.REMOVE; });
    loop.run ();
}

private Shadow.Host? shared_host;

private Shadow.Host test_host () throws Error {
    // Presentation fixtures share one application registration on their private
    // bus, just as ordinary windows share the process's application instance.
    if (shared_host == null) { shared_host = new Shadow.Host (); shared_host.register (); }
    return shared_host;
}

private Gtk.Widget? find_surface (Gtk.Widget widget) {
    if (widget.has_css_class ("shadow-composer")) return widget;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var result = find_surface (child);
        if (result != null) return result;
    }
    return null;
}

private Gtk.Widget? find_css (Gtk.Widget widget, string name) {
    if (widget.has_css_class (name)) return widget;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var found = find_css (child, name);
        if (found != null) return found;
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

private Gtk.ListBox? find_suggestions (Gtk.Widget widget) {
    if (widget is Gtk.ListBox) return (Gtk.ListBox) widget;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var result = find_suggestions (child);
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

private bool same_pixels (Gdk.Texture first, Gdk.Texture second) {
    if (first.get_width () != second.get_width () || first.get_height () != second.get_height ()) return false;
    int size = first.get_width () * first.get_height () * 4;
    var a = new uint8[size]; var b = new uint8[size];
    first.download (a, first.get_width () * 4); second.download (b, second.get_width () * 4);
    for (int i = 0; i < size; i++) if (a[i] != b[i]) return false;
    return true;
}

int main (string[] args) {
    // This executable opens synthetic windows; only the isolated harness opts in.
    if (Environment.get_variable ("SHADOW_TERM_PRIVATE_TEST") != "1") return 2;
    Gtk.init ();
    Test.init (ref args);
    // The private bus intentionally has no desktop portal/AccountsService.
    Log.set_always_fatal (LogLevelFlags.LEVEL_ERROR | LogLevelFlags.LEVEL_CRITICAL);
    Test.add_func ("/presentation/prompt-context-live-toggles-and-narrow-layout", () => {
        try {
            var host = test_host ();
            var request = Shadow.Request.parse ({"shadow-term", "--input", "composer", "--", "fish"});
            request.session = "private-prompt-context";
            request.cwd = Environment.get_tmp_dir ();
            request.width = 920; request.height = 650;
            var window = new Shadow.WorkspaceWindow (host, request);
            var session = new Shadow.TerminalSession (host, window, request, Environ.get ());
            window.add_session (session); window.present_session (session);
            settle ();
            var editor = find_editor (window.child);
            editor.buffer.text = "preserved draft";
            assert (session.shell_context ({"1", "7", "0,7", "2345", "/tmp/日本語", "science", "1", "2", "fixture", "host"}));
            session.input_session.report (session.input_session.token, "ready", "");
            host.preferences.set_context_visible ("identity", true);
            settle ();
            foreach (string name in new string[] {"directory", "result", "duration", "environment", "identity", "jobs"})
                assert (find_css (window.child, "context-" + name).visible);
            var context = (Shadow.ContextBar) find_css (window.child, "composer-context");
            var result = find_css (window.child, "context-result");
            assert (result.tooltip_text.contains ("exit: 7") && result.tooltip_text.contains ("0|7"));
            assert (find_css (window.child, "context-environment").tooltip_text.contains ("/tmp/日本語"));
            host.preferences.set_context_visible ("environment", false);
            assert (!find_css (window.child, "context-environment").visible);
            host.preferences.set_context_visible ("enabled", false);
            assert (!context.visible && !context.repository.enabled);
            host.preferences.set_context_visible ("enabled", true);
            assert (context.visible && !find_css (window.child, "context-environment").visible);
            host.preferences.set_context_visible ("environment", true);
            session.input_session.report (session.input_session.token, "busy", "");
            assert (!result.visible && !find_css (window.child, "context-duration").visible);
            session.input_session.report (session.input_session.token, "ready", "");
            window.set_default_size (380, 650);
            settle ();
            assert (window.get_width () <= 400 && context.get_width () <= window.get_width ());
            assert (context.get_height () < 180 && editor.source () == "preserved draft");
            run_private ({"import", "-window", "root", "/tmp/shadow-term-prompt-context.png"});
            assert (session.shell_context ({"1", "0", "0", "100", "", "", "0", "0", "fixture", "host"}));
            assert (!result.visible && !find_css (window.child, "context-duration").visible &&
                !find_css (window.child, "context-environment").visible && !find_css (window.child, "context-jobs").visible);
            host.preferences.reset_context ();
            window.close_workspace ();
            settle ();
        } catch (Error error) { Test.message (error.message); Test.fail (); }
    });
    Test.add_func ("/presentation/floating-completion-pointer-and-scroll", () => {
        try {
            var editor = new RichInput ();
            var assistance = new ComposerAssist (editor);
            var body = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            body.append (new Gtk.DrawingArea () {vexpand = true});
            body.append (new Gtk.ScrolledWindow () {child = editor, min_content_height = 56,
                max_content_height = 56, propagate_natural_height = true});
            var window = new Gtk.Window () {child = body, title = "Private floating completions",
                default_width = 640, default_height = 480};
            window.present ();
            settle ();
            string wid = run_private ({"xdotool", "search", "--onlyvisible", "--name", "^Private floating completions$"});
            run_private ({"xdotool", "windowfocus", "--sync", wid});
            editor.grab_focus ();
            assistance.request.begin ();
            settle ();
            var list = find_suggestions (assistance.panel);
            assert (list != null && list.get_row_at_index (5) != null);
            var popup = (Gdk.Popup) assistance.panel.get_surface ();
            assert (popup.get_parent () == window.get_surface ());
            Graphene.Point point = {}, target;
            point.x = 24; point.y = 10;
            assert (list.get_row_at_index (1).compute_point (assistance.panel, point, out target));
            double dx, dy;
            assistance.panel.get_surface_transform (out dx, out dy);
            string x = ((int) (popup.get_position_x () + target.x - dx)).to_string ();
            string y = ((int) (popup.get_position_y () + target.y - dy)).to_string ();
            var scroll = (Gtk.ScrolledWindow) list.get_ancestor (typeof (Gtk.ScrolledWindow));
            run_private ({"xdotool", "mousemove", "--window", wid, x, y, "click", "5"});
            settle ();
            assert (assistance.visible && scroll.vadjustment.value > 0);
            scroll.vadjustment.value = 0;
            settle ();
            run_private ({"import", "-window", "root", "/tmp/shadow-term-suggestions.png"});
            run_private ({"xdotool", "mousemove", "--window", wid, x, y, "click", "1"});
            settle ();
            assert (!assistance.visible && editor.source () == "`code`" && editor.has_focus);
            editor.buffer.undo ();
            assert (editor.source () == "");
            window.destroy ();
        } catch (Error error) { Test.message (error.message); Test.fail (); }
    });
    Test.add_func ("/presentation/live-style-source-and-compact-layout", () => {
        try {
            var host = test_host ();
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
            assert (surface.get_mapped ());
            if (Shadow.PRIVATE_VTE) {
                session.terminal.feed ("\x1b[?1049h".data);
                settle ();
                assert (!surface.get_mapped ());
                session.terminal.feed ("\x1b[?1049l".data);
                settle ();
                assert (surface.get_mapped ());
            }
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
            assert (background_alpha (window.titlebar, window) == 255);
            assert (!window.titlebar.get_color ().equal (expected));
            window.set_default_size (420, 420);
            settle ();
            assert (window.get_width () <= 440);
            assert (texture (window, window).save_to_png ("/tmp/shadow-term-ui-narrow.png"));
            var history = new StringBuilder ();
            for (int line = 0; line < 100; line++) history.append_printf ("\r\nHistory line %d", line);
            session.terminal.feed (history.str.data);
            settle ();
            var adjustment = session.terminal.vadjustment;
            adjustment.value = adjustment.upper - adjustment.page_size;
            settle ();
            double bottom = adjustment.value;
            editor.grab_focus ();
            run_private ({"xdotool", "windowfocus", "--sync", wid, "key", "Page_Up"});
            settle ();
            assert (adjustment.value < bottom && editor.source () == "");
            run_private ({"xdotool", "key", "Page_Down"});
            settle ();
            assert (adjustment.value == bottom && editor.source () == "");
            session.running = false;
            var second_request = Shadow.Request.parse ({"shadow-term", "--session", "middle-close-test"});
            var second = new Shadow.TerminalSession (host, window, second_request, Environ.get ());
            window.add_session (second); window.present_session (second);
            settle ();
            var first_tab = find_css (window.titlebar, "workspace-tab");
            point.x = first_tab.get_width () / 2.0f; point.y = first_tab.get_height () / 2.0f;
            assert (first_tab.compute_point (window, point, out target));
            run_private ({"xdotool", "mousemove", "--window", wid, ((int) target.x).to_string (), ((int) target.y).to_string (), "click", "2"});
            settle ();
            assert (session.closing && window.active_session == second && !second.closing);
            second.end_session ();
            // This test has its own process and private XDG configuration.
            host.preferences.apply ("Monospace 12", "Monospace 12", 1, 10000);
        } catch (Error error) { Test.message (error.message); Test.fail (); }
    });
    Test.add_func ("/presentation/live-analysis-paths-syntax-and-stale-drafts", () => {
        string? directory = null;
        try {
            directory = DirUtils.make_tmp ("vcom-analysis-XXXXXX");
            string existing = Path.build_filename (directory, "日本 existing.txt");
            FileUtils.set_contents (existing, "fixture");
            var editor = new RichInput () {fish_mode = true, working_directory = directory};
            var analysis = new Shadow.FishAnalysis (editor);
            var body = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            body.append (editor); body.append (analysis.status);
            var window = new Gtk.Window () {child = body};
            window.present ();
            editor.buffer.text = "cat '日本 existing.txt'";
            for (int i = 0; i < 6; i++) settle ();
            assert (!analysis.status.visible);
            Gtk.TextIter iter;
            editor.buffer.get_iter_at_offset (out iter, 6);
            assert (iter.has_tag (editor.buffer.tag_table.lookup ("path")));
            assert (editor.source () == "cat '日本 existing.txt'");
            editor.buffer.text = "cat missing.txt";
            for (int i = 0; i < 6; i++) settle ();
            assert (analysis.status.visible && analysis.status.label.contains ("does not exist"));
            editor.buffer.get_iter_at_offset (out iter, 6);
            assert (iter.has_tag (editor.buffer.tag_table.lookup ("diagnostic")));
            editor.buffer.text = "printf hello > new-output.txt";
            for (int i = 0; i < 6; i++) settle ();
            assert (!analysis.status.visible);
            assert (!FileUtils.test (Path.build_filename (directory, "new-output.txt"), FileTest.EXISTS));
            editor.buffer.text = "echo (";
            for (int i = 0; i < 6; i++) settle ();
            assert (analysis.status.visible && analysis.status.label == "Check fish syntax");
            editor.buffer.text = "cat missing.txt";
            settle ();
            editor.buffer.text = "echo retained";
            for (int i = 0; i < 6; i++) settle ();
            assert (!analysis.status.visible && editor.source () == "echo retained");
            editor.buffer.text = "cat '日本 existing.txt'";
            editor.working_directory = Path.build_filename (directory, "other");
            DirUtils.create (editor.working_directory, 0700);
            for (int i = 0; i < 6; i++) settle ();
            assert (analysis.status.visible && analysis.status.label.contains ("does not exist"));
            analysis.cancel ();
            window.destroy ();
            DirUtils.remove (editor.working_directory);
            FileUtils.unlink (existing);
        } catch (Error error) { Test.message (error.message); Test.fail (); }
        if (directory != null) DirUtils.remove (directory);
    });
    Test.add_func ("/presentation/private-vte-hover-links-and-cursor", () => {
        if (!Shadow.PRIVATE_VTE) { Test.skip ("Private VTE presentation hooks are not configured"); return; }
        try {
            var terminal = new Vte.Terminal ();
            terminal.set_allow_hyperlink (true);
            terminal.add_css_class ("shadow-hover-links");
            terminal.add_css_class ("shadow-composer-cursor");
            terminal.set_cursor_blink_mode (Vte.CursorBlinkMode.OFF);
            Gdk.RGBA fg = {}, bg = {};
            fg.parse ("#ddeeff"); bg.parse ("rgba(18,52,86,0.5)");
            terminal.set_colors (fg, bg, null);
            var window = new Gtk.Window () {title = "Private VTE hooks", child = terminal, default_width = 500, default_height = 260};
            window.present (); terminal.grab_focus ();
            settle ();
            string wid = run_private ({"xdotool", "search", "--onlyvisible", "--name", "^Private VTE hooks$"});
            run_private ({"xdotool", "mousemove", "--window", wid, "480", "240"});
            terminal.feed ("\x1b[2J\x1b[Hdirectory\r\n".data);
            settle ();
            var plain = texture (terminal, window);
            terminal.feed ("\x1b[2J\x1b[H\x1b]8;;file:///tmp\x1b\\directory\x1b]8;;\x1b\\\r\n".data);
            settle ();
            var linked = texture (terminal, window);
            assert (same_pixels (plain, linked));
            var padding = terminal.get_style_context ().get_padding ();
            int x = padding.left + (int) terminal.get_char_width () * 2;
            int y = padding.top + (int) terminal.get_char_height () / 2;
            run_private ({"xdotool", "mousemove", "--window", wid, x.to_string (), y.to_string ()});
            settle ();
            assert (terminal.hyperlink_hover_uri == "file:///tmp");
            assert (!same_pixels (linked, texture (terminal, window)));
            run_private ({"xdotool", "mousemove", "--window", wid, "480", "240"});
            settle ();
            assert (same_pixels (linked, texture (terminal, window)));
            terminal.feed ("\x1b[?25l".data);
            settle ();
            assert (same_pixels (linked, texture (terminal, window)));
            terminal.feed ("\x1b[?25h".data);
            terminal.remove_css_class ("shadow-composer-cursor");
            terminal.queue_draw ();
            settle ();
            assert (!same_pixels (linked, texture (terminal, window)));
            window.destroy ();
        } catch (Error error) { Test.message (error.message); Test.fail (); }
    });
    return Test.run ();
}
