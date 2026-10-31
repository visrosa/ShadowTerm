private void settle () {
    var loop = new MainLoop ();
    Timeout.add (100, () => { loop.quit (); return Source.REMOVE; });
    loop.run ();
}

private class SlowAnalysis : Shadow.FishAnalysis {
    public int starts = 0;
    public int simultaneous = 0;
    public int maximum = 0;
    public string latest = "";
    public SlowAnalysis (RichInput editor) { base (editor); }
    public override async string check_syntax (string text, string directory, Cancellable cancel) throws Error {
        starts++; simultaneous++; maximum = int.max (maximum, simultaneous); latest = text;
        Timeout.add (110, () => { check_syntax.callback (); return Source.REMOVE; });
        yield;
        simultaneous--;
        cancel.set_error_if_cancelled ();
        return "fixture syntax";
    }
    public override async void check_path (File file, Cancellable cancel) throws Error {
        Timeout.add (300, () => { check_path.callback (); return Source.REMOVE; });
        yield;
        cancel.set_error_if_cancelled ();
    }
}

private class SlowContextDetails : Shadow.ContextDetailsProvider {
    public override async Json.Object query (Shadow.ContextDetailsKind kind, string directory, Cancellable cancel) throws Error {
        Timeout.add (directory == "/old" ? 160 : 30, () => { query.callback (); return Source.REMOVE; });
        yield;
        // Ignore cancellation to verify that the view also rejects generations.
        var entry = new Json.Object (); entry.set_string_member ("path", directory + "/child"); entry.set_string_member ("group", "Children");
        var entries = new Json.Array (); entries.add_object_element (entry);
        var result = new Json.Object (); result.set_array_member ("entries", entries);
        result.set_boolean_member ("truncated", false); result.set_string_member ("notice", "Fixture");
        return result;
    }
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

private Gdk.Rectangle changed_ink (Gdk.Texture before, Gdk.Texture after) {
    int width = after.get_width (), height = after.get_height ();
    var a = new uint8[width * height * 4]; var b = new uint8[a.length];
    before.download (a, width * 4); after.download (b, width * 4);
    int left = width, top = height, right = -1, bottom = -1;
    for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) {
        int i = (y * width + x) * 4;
        if (int.max (int.max (((int) a[i] - b[i]).abs (), ((int) a[i + 1] - b[i + 1]).abs ()), ((int) a[i + 2] - b[i + 2]).abs ()) < 32) continue;
        left = int.min (left, x); right = int.max (right, x);
        top = int.min (top, y); bottom = int.max (bottom, y);
    }
    return {left, top, int.max (0, right - left + 1), int.max (0, bottom - top + 1)};
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

private uint8 alpha_at (Gdk.Texture image, int x, int y) {
    assert (x >= 0 && x < image.get_width () && y >= 0 && y < image.get_height ());
    var pixels = new uint8[image.get_width () * image.get_height () * 4];
    image.download (pixels, image.get_width () * 4);
    return pixels[(y * image.get_width () + x) * 4 + 3];
}

int main (string[] args) {
    // This executable opens synthetic windows; only the isolated harness opts in.
    if (Environment.get_variable ("SHADOW_TERM_PRIVATE_TEST") != "1") return 2;
    Gtk.init ();
    Test.init (ref args);
    // The private bus intentionally has no desktop portal/AccountsService.
    Log.set_always_fatal (LogLevelFlags.LEVEL_ERROR | LogLevelFlags.LEVEL_CRITICAL);
    Test.add_func ("/presentation/continuous-workspace-frame", () => {
        try {
            var host = test_host ();
            var request = Shadow.Request.parse ({"shadow-term", "--session", "frame-fixture", "--input", "composer"});
            request.width = 920; request.height = 600;
            var window = new Shadow.WorkspaceWindow (host, request);
            var session = new Shadow.TerminalSession (host, window, request, Environ.get ());
            window.add_session (session); window.present_session (session); settle ();
            var editor = find_editor (session);
            editor.buffer.text = "preserved 日本語 draft";
            var body = find_css (window.child, "pane-liner");
            var strip = (Shadow.PaneTabStrip) find_css (window.titlebar, "pane-tab-strip");
            assert (body is Shadow.PaneBody && !strip.draw_liner);
            var create = (Gtk.Button) find_css (strip, "new-tab-action");
            var divider = find_css (strip, "new-tab-divider");
            assert (!divider.focusable && !divider.can_target && ((Gtk.Accessible) divider).get_accessible_role () == Gtk.AccessibleRole.PRESENTATION);
            host.preferences.set_shortcut ("new-tab", "<Control><Shift>t");
            assert (create.tooltip_text == "New Tab (" + host.preferences.shortcut_label ("new-tab") + ")");
            host.preferences.reset_shortcut ("new-tab");
            for (int pass = 0; pass < 4; pass++) {
                host.preferences.apply ("Monospace 12", "Monospace 12", pass == 0 ? 0.25 : pass == 1 ? 0.75 : 1,
                    10000, pass != 3, false, "#ffeecc", "#102030", 0.5);
                window.set_default_size (pass < 2 ? 920 : 380, 600);
                settle ();
                Graphene.Rect frame = {}, bar = {};
                assert (body.compute_bounds (window, out frame));
                assert (strip.compute_bounds (window, out bar));
                Graphene.Rect button = {}, separator = {}, viewport = {};
                assert (create.compute_bounds (window, out button) && divider.compute_bounds (window, out separator));
                assert (strip.get_last_child ().compute_bounds (window, out viewport));
                assert (separator.origin.x >= button.origin.x + button.size.width + 6);
                assert (viewport.origin.x >= separator.origin.x + separator.size.width + 6);
                assert (separator.size.width == 1 && separator.size.height > 0 && separator.size.height < bar.size.height);
                var decoration = texture (divider, window);
                assert (alpha_at (decoration, 0, decoration.get_height () / 2) >= 50);
                assert (alpha_at (decoration, 0, decoration.get_height () / 2) <= 52);
                var image = texture (window, window);
                int left = (int) frame.origin.x, right = left + (int) frame.size.width - 1;
                int bottom = (int) (frame.origin.y + frame.size.height) - 1;
                int join = (int) (bar.origin.y + bar.size.height) - 1;
                int start = (int) frame.origin.y;
                // Border allocation stays transparent beneath the single
                // stroke; corners clip content instead of leaving square ink.
                for (int y = start + 12; y < bottom - 12; y += 23) {
                    assert (alpha_at (image, left, y) >= 75 && alpha_at (image, left, y) <= 78);
                    assert (alpha_at (image, right, y) >= 75 && alpha_at (image, right, y) <= 78);
                }
                assert (alpha_at (image, (left + right) / 2, bottom) >= 75);
                assert (alpha_at (image, (left + right) / 2, bottom) <= 78);
                assert (alpha_at (image, left, bottom) == 0 && alpha_at (image, right, bottom) == 0);
                // The same contour continues above the body into the native
                // header, composited over its independently boosted opacity.
                for (int y = join; y < start; y++) {
                    int underlying = alpha_at (image, left - 2, y);
                    int expected = (int) (77 + underlying * 0.7);
                    assert ((alpha_at (image, left, y) - expected).abs () <= 2);
                }
                assert (editor.source () == "preserved 日本語 draft");
                assert (!session.input_session.pending && session.child_pid == 0);
                assert (image.save_to_png ("/tmp/shadow-term-frame-%d.png".printf (pass)));
            }
            int columns = (int) session.terminal.get_column_count (), rows = (int) session.terminal.get_row_count ();
            session.dispatch_action ("find-terminal"); settle ();
            assert (session.terminal.get_column_count () == columns && session.terminal.get_row_count () == rows);
            assert (editor.source () == "preserved 日本語 draft");
            var extras = new List<Shadow.TerminalSession> ();
            for (int i = 0; i < 6; i++) {
                var extra_request = Shadow.Request.parse ({"shadow-term", "--session", "frame-tab-%d".printf (i)});
                var extra = new Shadow.TerminalSession (host, window, extra_request, Environ.get ());
                extras.append (extra); window.add_session (extra);
            }
            host.preferences.apply ("Monospace 12", "Monospace 12", 0.25, 10000, true, false, "#ffeecc", "#102030", 0.5);
            window.present_session (session); settle ();
            var scroll = (Gtk.ScrolledWindow) strip.get_last_child ();
            assert (scroll.hadjustment.upper > scroll.hadjustment.page_size);
            // Scroll the selected tab completely outside the viewport. Its
            // hidden outline must not leave an opening through visible tabs.
            scroll.hadjustment.value = scroll.hadjustment.upper - scroll.hadjustment.page_size;
            settle ();
            Graphene.Rect viewport = {}, bar = {};
            assert (scroll.compute_bounds (window, out viewport));
            assert (strip.compute_bounds (window, out bar));
            var overflow_image = texture (window, window);
            int baseline = (int) (bar.origin.y + bar.size.height) - 1;
            for (int x = (int) viewport.origin.x + 3; x < viewport.origin.x + viewport.size.width - 3; x += 17) {
                assert (alpha_at (overflow_image, x, baseline) >= 186 && alpha_at (overflow_image, x, baseline) <= 190);
            }
            assert (overflow_image.save_to_png ("/tmp/shadow-term-frame-overflow.png"));
            window.present_session (extras.last ().data); settle ();
            var split_request = Shadow.Request.parse ({"shadow-term", "--session", "frame-split"});
            var split = new Shadow.TerminalSession (host, window, split_request, Environ.get ());
            window.add_session (split, session); window.present_session (split); settle ();
            assert (editor.source () == "preserved 日本語 draft" && session.child_pid == 0 && split.child_pid == 0);
            assert (texture (window, window).save_to_png ("/tmp/shadow-term-frame-split.png"));
            split.end_session ();
            foreach (var extra in extras) extra.end_session ();
            session.end_session (); window.destroy ();
            host.preferences.apply ("Monospace 12", "Monospace 12", 1, 10000, true, true); settle ();
        } catch (Error error) { Test.fail_printf ("%s", error.message); }
    });
    Test.add_func ("/presentation/pane-extraction-fixture", () => {
        try {
            var host = test_host ();
            var request = Shadow.Request.parse ({"shadow-term", "--session", "extraction", "--cwd", "/tmp"});
            var window = new Shadow.WorkspaceWindow (host, request);
            var session = new Shadow.TerminalSession (host, window, request, Environ.get ());
            window.add_session (session); window.present_session (session); settle ();
            string source = "TITLE\r\n  child 日本語 e\u0301\r\nprogress 000\rprogress 100\r\n";
            VCom.TerminalBytes.feed (session.terminal, (char[]) source.data); settle ();
            string snapshot = session.terminal.get_text_format (Vte.Format.TEXT) ?? "";
            assert (snapshot.contains ("TITLE\n  child 日本語 e\u0301\nprogress 100"));
            assert (!snapshot.contains ("progress 000") && !snapshot.contains ("\r"));
            size_t bytes;
            string row = session.terminal.get_text_range_format (Vte.Format.TEXT, 1, 0, 1, session.terminal.get_column_count (), out bytes) ?? "";
            assert (row.contains ("child 日本語 e\u0301") && bytes == row.length);
            // An alternate screen is a separate live grid, not a command scope.
            VCom.TerminalBytes.feed (session.terminal, (char[]) "\x1b[?1049hALT\r\n".data); settle ();
            assert ((session.terminal.get_text_format (Vte.Format.TEXT) ?? "").contains ("ALT"));
            VCom.TerminalBytes.feed (session.terminal, (char[]) "\x1b[?1049l".data); settle ();
            assert (session.terminal.get_text_format (Vte.Format.TEXT) == snapshot);
            window.set_default_size (420, 360); settle ();
            assert ((session.terminal.get_text_format (Vte.Format.TEXT) ?? "").contains ("child 日本語"));
            assert (source.contains ("progress 000\r") && find_editor (session).source () == "");
            window.close_workspace (); settle ();
        } catch (Error error) { Test.message (error.message); Test.fail (); }
    });
    Test.add_func ("/presentation/taskline-persistent-consumer", () => {
        string? binary = Environment.get_variable ("SHADOWTERM_TASKLINE_FIXTURE");
        if (binary == null) { Test.skip ("Set SHADOWTERM_TASKLINE_FIXTURE to a complete tasklineUI binary"); return; }
        try {
            string directory = Path.build_filename (Environment.get_user_data_dir (), "taskline-fixture");
            DirUtils.create_with_parents (directory, 0700);
            string db = Path.build_filename (directory, "taskchampion.sqlite3");
            string fixture = "import sqlite3,json,sys\nc=sqlite3.connect(sys.argv[1])\nc.executescript('CREATE TABLE tasks(uuid TEXT, data TEXT); CREATE TABLE working_set(id INTEGER, uuid TEXT)')\nfor i in range(1,41):\n u='fixture-'+str(i); c.execute('INSERT INTO working_set VALUES(?,?)',(i,u)); c.execute('INSERT INTO tasks VALUES(?,?)',(u,json.dumps({'status':'pending','project':'Fixture','description':'Synthetic task '+str(i)})))\nc.commit()";
            Process.spawn_sync (null, {"python3", "-c", fixture, db}, null, SpawnFlags.SEARCH_PATH, null);
            var host = test_host ();
            var request = Shadow.Request.parse ({"shadow-term", "--session", "taskline", "--input", "terminal", "--cwd", directory, "--", binary});
            var window = new Shadow.WorkspaceWindow (host, request);
            string[] env = Environ.set_variable (Environ.get (), "TASKDATA", directory, true);
            var session = new Shadow.TerminalSession (host, window, request, env);
            window.add_session (session); window.present_session (session); session.start ();
            for (int i = 0; i < 30 && !(session.terminal.get_text_format (Vte.Format.TEXT) ?? "").contains ("Synthetic task"); i++) settle ();
            string text = session.terminal.get_text_format (Vte.Format.TEXT) ?? "";
            assert (session.running && text.contains ("Fixture") && text.contains ("Synthetic task 1") && text.contains (" 1 "));
            int pid = session.child_pid;
            VCom.TerminalBytes.feed_child (session.terminal, (char[]) "t".data); settle ();
            VCom.TerminalBytes.feed_child (session.terminal, (char[]) "unsent-fixture".data); settle ();
            string draft_screen = session.terminal.get_text_format (Vte.Format.TEXT) ?? "";
            assert (draft_screen.contains ("unsent-fixture"));
            window.hide_workspace (); settle ();
            window.present_session (session); settle ();
            assert (session.child_pid == pid && session.running);
            assert (session.terminal.get_text_format (Vte.Format.TEXT) == draft_screen);
            long columns = session.terminal.get_column_count ();
            window.set_default_size (420, 360); settle (); settle ();
            assert (session.terminal.get_column_count () != columns);
            assert ((session.terminal.get_text_format (Vte.Format.TEXT) ?? "").contains ("unsent-fixture"));
            window.close_workspace ();
            for (int i = 0; i < 20 && session.running; i++) settle ();
            assert (!session.running);
            FileUtils.remove (db); DirUtils.remove (directory);
        } catch (Error error) { Test.message (error.message); Test.fail (); }
    });
    Test.add_func ("/presentation/session-display-titles", () => {
        try {
            var host = test_host ();
            var request = Shadow.Request.parse ({"shadow-term", "--session", "title-a", "--cwd", "/tmp"});
            var window = new Shadow.WorkspaceWindow (host, request);
            var first = new Shadow.TerminalSession (host, window, request, Environ.get ());
            window.add_session (first); window.present_session (first); settle ();
            assert (first.display_title == "tmp" && window.title == "tmp · title-a");
            var draft = find_editor (first); draft.buffer.text = "unsubmitted 日本語";
            var emulator = first.terminal;
            var token = first.input_session.token;
            VCom.TerminalBytes.feed (first.terminal, (char[]) "\x1b]2;Editor 日本語 <b>literal</b>\x07".data); settle ();
            assert (first.display_title == "Editor 日本語 <b>literal</b>");
            var tab = (Gtk.ToggleButton) find_css (window.titlebar, "workspace-tab").get_first_child ();
            assert (((Gtk.Label) tab.child).label == first.display_title);
            assert (!((Gtk.Label) tab.child).use_markup);
            assert (tab.tooltip_text == first.title + "\n/tmp");
            assert (window.title == first.title);
            VCom.TerminalBytes.feed (first.terminal, (char[]) "\x1b]2;\x07".data); settle ();
            assert (first.display_title == "tmp");
            VCom.TerminalBytes.feed (first.terminal, (char[]) "\x1b]2;Stale program\x07".data); settle ();
            first.shell_directory ("/tmp/日本語");
            assert (first.display_title == "日本語" && window.title == "日本語 · title-a");
            first.shell_directory ("/");
            assert (first.display_title == "/");
            VCom.TerminalBytes.feed (first.terminal, (char[]) "\x1b]2;New title\x07".data); settle ();
            assert (first.display_title == "New title");
            string long_title = string.nfill (300, 'x') + "日本語";
            VCom.TerminalBytes.feed (first.terminal, (char[]) ("\x1b]2;" + long_title + "\x07").data); settle ();
            assert (first.display_title.char_count () == 160 && first.display_title.validate ());
            VCom.TerminalBytes.feed (first.terminal, (char[]) "\x1b]2;left\u202eright\x07".data); settle ();
            assert (first.display_title == "leftright");

            var second_request = Shadow.Request.parse ({"shadow-term", "--session", "title-b", "--cwd", "/tmp", "--title", "Initial"});
            var second = new Shadow.TerminalSession (host, window, second_request, Environ.get ());
            window.add_session (second); window.present_session (second); settle ();
            assert (second.display_title == "Initial" && window.title == "Initial · title-b");
            VCom.TerminalBytes.feed (first.terminal, (char[]) "\x1b]2;Background\x07".data); settle ();
            assert (first.display_title == "Background" && window.title == second.title);
            window.move_to_tab (first); window.join_previous_tab (); settle ();
            window.present_session (second);
            VCom.TerminalBytes.feed (first.terminal, (char[]) "\x1b]2;Inactive split\x07".data); settle ();
            assert (window.title == second.title);
            window.present_session (first); settle ();
            assert (window.title == first.title);
            tab = (Gtk.ToggleButton) find_css (window.titlebar, "workspace-tab").get_first_child ();
            assert (((Gtk.Label) tab.child).label == "Inactive split · 2");
            host.detach_session (first); settle ();
            assert (first.window != window && first.window.title == first.title);
            assert (first.terminal == emulator && first.input_session.token == token && first.child_pid == 0);
            assert (draft.source () == "unsubmitted 日本語");
            first.window.close_workspace (); window.close_workspace (); settle ();
        } catch (Error error) { Test.message (error.message); Test.fail (); }
    });
    Test.add_func ("/presentation/session-layout-transfer-and-focus", () => {
        try {
            var host = test_host ();
            var request = Shadow.Request.parse ({"shadow-term", "--session", "layout-a", "--cwd", "/tmp"});
            var window = new Shadow.WorkspaceWindow (host, request);
            var first = new Shadow.TerminalSession (host, window, request, Environ.get ());
            window.add_session (first); window.present_session (first); settle ();
            var draft = find_editor (first); draft.buffer.text = "printf '日本語\n'";
            var emulator = first.terminal;
            var token = first.input_session.token;
            var second_request = Shadow.Request.parse ({"shadow-term", "--session", "layout-b", "--cwd", "/tmp"});
            var second = new Shadow.TerminalSession (host, window, second_request, Environ.get ());
            window.add_session (second, first); window.present_session (second); settle ();
            assert (window.active_session == second && first.is_presented && second.is_presented);
            assert (first.get_parent () is Gtk.Paned && second.get_parent () == first.get_parent ());
            var third_request = Shadow.Request.parse ({"shadow-term", "--session", "layout-c", "--cwd", "/tmp"});
            var third = new Shadow.TerminalSession (host, window, third_request, Environ.get ());
            window.add_session (third, second, Gtk.Orientation.VERTICAL); window.present_session (third); settle ();
            assert (((Gtk.Paned) third.get_parent ()).orientation == Gtk.Orientation.VERTICAL);
            window.cycle_pane (1); assert (window.active_session == first);
            window.cycle_pane (-1); assert (window.active_session == third);
            window.move_to_tab (first); settle ();
            assert (first.is_presented && !second.is_presented && !third.is_presented);
            window.join_previous_tab (); settle ();
            assert (third.is_presented && first.is_presented && !second.is_presented);
            window.present_session (first);
            host.detach_session (first); settle ();
            var detached = first.window;
            assert (detached != window && first.terminal == emulator && first.input_session.token == token);
            assert (draft.source () == "printf '日本語\n'");
            assert (third.is_presented && !third.closing && !second.closing);
            var fourth_request = Shadow.Request.parse ({"shadow-term", "--session", "layout-d", "--cwd", "/tmp"});
            var fourth = new Shadow.TerminalSession (host, window, fourth_request, Environ.get ());
            window.add_session (fourth); window.present_session (fourth); settle ();
            second.end_session (); settle ();
            assert (window.active_session == fourth && fourth.is_presented);
            detached.close_workspace (); window.close_workspace (); settle ();
            assert (first.closing && second.closing && third.closing && fourth.closing);
        } catch (Error error) { Test.message (error.message); Test.fail (); }
    });
    Test.add_func ("/presentation/history-boundaries-and-draft-restoration", () => {
        try {
            var host = test_host ();
            var request = Shadow.Request.parse ({"shadow-term", "--session", "history", "--cwd", "/tmp"});
            var window = new Shadow.WorkspaceWindow (host, request);
            var session = new Shadow.TerminalSession (host, window, request, Environ.get ());
            window.add_session (session); window.present_session (session); settle ();
            session.input_session.report (session.input_session.token, "ready", "/tmp");
            host.preferences.set_shortcut ("composer", "<Control><Alt>m");
            session.shell_history ({"echo '日本語\nlast\n'", "echo older", "printf unrelated"});
            var editor = find_editor (session);
            editor.buffer.text = "echo "; editor.grab_focus (); settle ();
            string wid = run_private ({"xdotool", "search", "--onlyvisible", "--name", " · history$"});
            run_private ({"xdotool", "windowfocus", "--sync", wid}); settle ();
            var reveal = (Gtk.Revealer) find_surface (session).get_parent ();
            assert (reveal.reveal_child);
            run_private ({"xdotool", "key", "ctrl+shift+m"}); settle ();
            assert (reveal.reveal_child);
            run_private ({"xdotool", "key", "ctrl+alt+m"}); settle ();
            assert (!reveal.reveal_child);
            run_private ({"xdotool", "key", "ctrl+alt+m"}); settle ();
            assert (reveal.reveal_child);
            host.preferences.reset_shortcut ("composer");
            run_private ({"xdotool", "key", "Up"}); settle ();
            assert (editor.source () == "echo '日本語\nlast\n'");
            run_private ({"xdotool", "key", "Down"}); settle ();
            assert (editor.source () == "echo ");
            run_private ({"xdotool", "key", "Up"}); settle ();
            run_private ({"xdotool", "key", "ctrl+Home", "Up"}); settle ();
            assert (editor.source () == "echo older");
            run_private ({"xdotool", "type", " edited"}); settle ();
            string edited = editor.source ();
            run_private ({"xdotool", "key", "Down"}); settle ();
            assert (editor.source () == edited);
            editor.buffer.text = "first\nsecond";
            Gtk.TextIter cursor; editor.buffer.get_start_iter (out cursor); editor.buffer.place_cursor (cursor);
            run_private ({"xdotool", "key", "Down"}); settle ();
            editor.buffer.get_iter_at_mark (out cursor, editor.buffer.get_insert ());
            assert (cursor.get_line () == 1 && editor.source () == "first\nsecond");
            window.close_workspace ();
        } catch (Error error) { Test.message (error.message); Test.fail (); }
    });
    Test.add_func ("/presentation/style-font-hook-grid-and-live-switch", () => {
        try {
            var host = test_host ();
            var request = Shadow.Request.parse ({"shadow-term", "--session", "font-faces", "--cwd", "/tmp"});
            var window = new Shadow.WorkspaceWindow (host, request);
            var session = new Shadow.TerminalSession (host, window, request, Environ.get ());
            window.add_session (session); window.present_session (session); settle ();
            if (!session.style_fonts_available ()) Test.skip ("Private style-font hook unavailable");
            else {
                VCom.TerminalBytes.feed (session.terminal, (char[]) "Regular\r\n\x1b[1mBold\x1b[0m\r\n\x1b[3mItalic\x1b[0m\r\n\x1b[1;3mBoth\x1b[0m".data); settle ();
                int width = (int) session.terminal.get_char_width (), height = (int) session.terminal.get_char_height ();
                var before_fonts = texture (session.terminal, window);
                host.preferences.set_style_fonts ("DejaVu Sans Mono Bold 12", "Liberation Mono Italic 12", "Liberation Mono Bold Italic 12"); settle ();
                assert (!same_pixels (before_fonts, texture (session.terminal, window)));
                assert (session.terminal.get_char_width () == width && session.terminal.get_char_height () == height);
                assert (session.terminal.get_data<string> ("shadow-bold-font") == "DejaVu Sans Mono Bold 12");
                session.terminal.font_scale = 1.3; settle ();
                assert (session.terminal.get_char_height () > height);
                host.preferences.set_style_fonts ("", "", ""); settle ();
            }
            window.close_workspace ();
        } catch (Error error) { Test.message (error.message); Test.fail (); }
    });
    Test.add_func ("/presentation/analysis-prompt-newest-only-and-independent-paths", () => {
        var editor = new RichInput () {fish_mode = true, working_directory = "/tmp"};
        var window = new Gtk.Window () {child = editor}; window.present (); settle ();
        var analysis = new SlowAnalysis (editor);
        editor.buffer.text = "cat ./missing ";
        var loop = new MainLoop ();
        Timeout.add (20, () => { loop.quit (); return Source.REMOVE; }); loop.run ();
        assert (analysis.starts == 1);
        for (int i = 0; i < 10; i++) editor.buffer.insert_at_cursor ("x", -1);
        settle ();
        assert (analysis.starts == 2 && analysis.maximum == 1);
        settle (); settle ();
        assert (analysis.latest == editor.source () && analysis.status.visible && analysis.status.label == "Check fish syntax");
        analysis.enabled = false;
        settle ();
        assert (analysis.starts == 2);
        window.destroy ();
    });
    Test.add_func ("/presentation/context-details-stale-results-and-draft-authority", () => {
        try {
            var host = test_host ();
            var request = Shadow.Request.parse ({"shadow-term", "--session", "context-actions", "--cwd", "/tmp", "--input", "composer", "--", "fish"});
            var window = new Shadow.WorkspaceWindow (host, request);
            var session = new Shadow.TerminalSession (host, window, request, Environ.get ());
            window.add_session (session); window.present_session (session); settle ();
            string wid = run_private ({"xdotool", "search", "--onlyvisible", "--name", " · context-actions$"});
            run_private ({"xdotool", "windowfocus", "--sync", wid}); settle ();
            session.running = true;
            session.input_session.report (session.input_session.token, "ready", "/tmp");
            var context = (Shadow.ContextBar) find_css (session, "composer-context");
            var editor = find_editor (session);
            var action = new Shadow.ContextAction (Shadow.ContextActionKind.DIRECTORY, "/tmp", "/tmp/日本語 ' literal");
            editor.buffer.text = "unsubmitted draft";
            assert (!context.action_requested (action, "/tmp")); assert (editor.source () == "unsubmitted draft");
            editor.buffer.text = "";
            assert (!context.action_requested (action, "/stale")); assert (editor.source () == "");
            assert (context.action_requested (action, "/tmp"));
            assert (editor.source () == action.command () && session.child_pid == 0);
            string fixture = DirUtils.make_tmp ("shadow-context-action-XXXXXX");
            string destination = Path.build_filename (fixture, "日本語 ' literal");
            DirUtils.create (destination, 0700);
            var literal_action = new Shadow.ContextAction (Shadow.ContextActionKind.DIRECTORY, fixture, destination);
            assert (run_private ({"fish", "--no-config", "-c", literal_action.command () + "; pwd"}) == destination);
            DirUtils.remove (destination); DirUtils.remove (fixture);

            editor.buffer.undo (); assert (editor.source () == "");
            session.input_session.report (session.input_session.token, "busy", "/tmp");
            assert (!context.action_requested (action, "/tmp")); assert (editor.source () == "");
            session.running = false;
            var menu = new Gtk.MenuButton ();
            var popup = new Shadow.ContextDetailsPopover (Shadow.ContextDetailsKind.DIRECTORY, new SlowContextDetails ());
            Shadow.Native.menu_popover (menu, popup);
            var parent = new Gtk.Window () {application = host, child = menu}; parent.present (); settle ();
            menu.popup (); settle ();
            popup.load.begin ("/old", true); popup.load.begin ("/new", true);
            for (int i = 0; i < 3; i++) settle ();
            var prepare = (Gtk.Button) find_css (popup, "context-prepare");
            assert (((Gtk.Label) prepare.child).label == "/new/child");
            string target = "";
            popup.action_requested.connect ((chosen, origin) => { target = chosen.target; return true; });
            prepare.clicked (); assert (target == "/new/child");
            menu.popup (); popup.load.begin ("/old", true); menu.popdown ();
            for (int i = 0; i < 2; i++) settle ();
            assert (target == "/new/child");
            parent.destroy (); window.close_workspace ();
        } catch (Error error) { Test.message (error.message); Test.fail (); }
    });
    Test.add_func ("/presentation/private-use-icons-proportional-spans", () => {
        try {
            var host = test_host ();
            var request = Shadow.Request.parse ({"shadow-term", "--session", "icon-cells", "--cwd", "/tmp", "--input", "terminal"});
            var window = new Shadow.WorkspaceWindow (host, request);
            var session = new Shadow.TerminalSession (host, window, request, Environ.get ());
            window.add_session (session); window.present_session (session); settle ();
            if (!session.style_fonts_available ()) Test.skip ("Private VTE drawing hook unavailable");
            else {
                var terminal = session.terminal;
                var face = Pango.FontDescription.from_string ("DejaVu Sans Mono, Symbols Nerd Font 24");
                terminal.set_font (face);
                terminal.set_color_foreground ({1, 1, 1, 1}); terminal.set_color_background ({0, 0, 0, 1});
                foreach (string glyph in new string[] {"\uf07c", ((unichar) 0xf0001).to_string ()}) {
                    foreach (double zoom in new double[] {1, 1.4}) {
                        terminal.font_scale = zoom;
                        Gdk.Rectangle single = {}, reserved = {};
                        foreach (string suffix in new string[] {"", " ", "  ", "\u2002"}) {
                            VCom.TerminalBytes.feed (terminal, (char[]) "\x1b[2J\x1b[H\x1b[?25l".data); settle ();
                            long initial_col, initial_row; terminal.get_cursor_position (out initial_col, out initial_row);
                            var empty = texture (terminal, window);
                            VCom.TerminalBytes.feed (terminal, (char[]) (glyph + suffix).data); settle ();
                            var image = texture (terminal, window);
                            var ink = changed_ink (empty, image);
                            var layout = terminal.create_pango_layout (glyph);
                            var scaled_face = face.copy (); scaled_face.set_size ((int) (face.get_size () * zoom));
                            layout.set_font_description (scaled_face);
                            Pango.Rectangle natural, logical; layout.get_pixel_extents (out natural, out logical);
                            double ratio = (double) ink.width / ink.height;
                            double expected = (double) natural.width / natural.height;
                            Test.message ("Icon %dx%d natural %dx%d zoom %.1f suffix bytes %u", ink.width, ink.height, natural.width, natural.height, zoom, suffix.length);
                            assert (ink.width > 5 && ink.height > 5);
                            assert ((ratio / expected - 1).abs () < 0.18);
                            long col, row; terminal.get_cursor_position (out col, out row);
                            assert (col == initial_col + 1 + suffix.char_count () && row == initial_row);
                            VCom.TerminalBytes.feed (terminal, (char[]) "Z".data); settle ();
                            assert ((terminal.get_text_format (Vte.Format.TEXT) ?? "").contains (glyph + suffix + "Z"));
                            if (suffix == "") single = ink;
                            else {
                                assert (ink.width > single.width && ink.height > single.height);
                                if (suffix == " ") reserved = ink;
                                else assert ((ink.width - reserved.width).abs () <= 1 && (ink.height - reserved.height).abs () <= 1);
                            }
                        }
                        VCom.TerminalBytes.feed (terminal, (char[]) ("\x1b[2J\x1b[1;%ldH".printf (terminal.get_column_count ())).data); settle ();
                        var edge_empty = texture (terminal, window);
                        VCom.TerminalBytes.feed (terminal, (char[]) glyph.data); settle ();
                        var edge = changed_ink (edge_empty, texture (terminal, window));
                        assert ((edge.width - single.width).abs () <= 1 && (edge.height - single.height).abs () <= 1);
                        // Repainting a borrowed space must remove the former wide ink.
                        VCom.TerminalBytes.feed (terminal, (char[]) "\x1b[2J\x1b[H\uf07c  ".data); settle ();
                        VCom.TerminalBytes.feed (terminal, (char[]) "\x1b[1;2HX".data); settle ();
                        var overwritten = texture (terminal, window);
                        VCom.TerminalBytes.feed (terminal, (char[]) "\x1b[2J\x1b[H\uf07cX ".data); settle ();
                        assert (same_pixels (overwritten, texture (terminal, window)));
                        // Attribute mismatch and a cursor on the space forbid borrowing.
                        VCom.TerminalBytes.feed (terminal, (char[]) "\x1b[2J\x1b[H\uf07c\x1b[31m \x1b[0m".data); settle ();
                        var different = texture (terminal, window);
                        VCom.TerminalBytes.feed (terminal, (char[]) "\x1b[2J\x1b[H\uf07c".data); settle ();
                        assert (same_pixels (different, texture (terminal, window)));
                        terminal.cursor_blink_mode = Vte.CursorBlinkMode.OFF;
                        VCom.TerminalBytes.feed (terminal, (char[]) "\x1b[2J\x1b[H\x1b[?25h \x1b[1;2H".data); settle ();
                        var cursor_empty = texture (terminal, window);
                        VCom.TerminalBytes.feed (terminal, (char[]) ("\x1b[H" + glyph + " \x1b[1;2H").data); settle ();
                        var cursor_ink = changed_ink (cursor_empty, texture (terminal, window));
                        assert ((cursor_ink.width - single.width).abs () <= 1 && (cursor_ink.height - single.height).abs () <= 1);
                        VCom.TerminalBytes.feed (terminal, (char[]) "\x1b[?25l".data); settle ();
                        texture (terminal, window).save_to_png ("/tmp/shadow-term-icon-cells.png");
                    }
                }
            }
            window.close_workspace ();
        } catch (Error error) { Test.message (error.message); Test.fail (); }
    });
    Test.add_func ("/presentation/documentation-source-navigation-and-source-preservation", () => {
        try {
            var host = test_host ();
            var parent = new Gtk.Window () {application = host, title = "Documentation origin"}; parent.present ();
            string config = Shadow.ContentService.configuration ();
            DirUtils.create_with_parents (Path.get_dirname (config), 0700);
            FileUtils.set_contents (config, "{\"sources\":[{\"name\":\"First\",\"argv\":[\"printf\",\"%s\",\"{query}\"]},{\"name\":\"Unavailable\",\"argv\":[\"/missing/vcom-documentation\"]},{\"name\":\"Third\",\"argv\":[\"printf\",\"%s\",\"{command}\"]}]}");
            var docs = new Shadow.DocumentationWindow (parent, host.preferences, "echo (task list)", 9, "", "/tmp");
            docs.present ();
            for (int i = 0; i < 8; i++) settle ();
            assert (docs.title == "Documentation · task");
            var stack = (Gtk.Stack) ((Gtk.Widget) docs.child).get_first_child ().get_next_sibling ().get_next_sibling ();
            assert (stack is Gtk.Stack);
            var view = find_editor (stack);
            assert (view.source () == "task-list" && !view.editable);
            var source_tab = (Shadow.PaneTab) find_css (docs.child, "workspace-tab");
            assert (source_tab.get_first_child () == source_tab.get_last_child ());
            assert (source_tab.selected);
            host.preferences.apply ("Monospace 12", "Monospace 14", 0.5, 10000, true, false, "#ddeeff", "#123456");
            settle ();
            Gdk.RGBA expected = {}; expected.parse ("#ddeeff");
            assert (view.get_color ().equal (expected));
            var image = texture (docs, docs);
            var pixels = new uint8[image.get_width () * image.get_height () * 4];
            image.download (pixels, image.get_width () * 4);
            assert (pixels[3] == 0);
            image.save_to_png ("/tmp/shadow-term-documentation.png");
            host.preferences.apply ("Monospace 12", "Monospace 12", 1, 10000, false, true);
            settle (); assert (view.source () == "task-list");

            stack.visible_child_name = "1";
            for (int i = 0; i < 3; i++) settle ();
            stack.visible_child_name = "2";
            for (int i = 0; i < 3; i++) settle ();
            var third = (RichInput) ((Gtk.ScrolledWindow) stack.visible_child).child;
            assert (third.source () == "task");
            stack.visible_child_name = "0";
            assert (view.source () == "task-list");
            var source_name = (Gtk.Entry) find_css (docs.child, "documentation-source-name");
            var source_command = (Gtk.Entry) find_css (docs.child, "documentation-source-command");
            source_name.text = "Custom source";
            source_command.text = "printf '\\033]2;Generated title\\007%s' '{query}'";
            find_button (docs.child, "Save Source").clicked ();
            for (int i = 0; i < 4; i++) settle ();
            assert (view.source () == "task-list");
            assert (((Gtk.Label) source_tab.selector.child).label == "Generated title");
            var saved_config = new Json.Parser (); saved_config.load_from_file (config);
            assert (saved_config.get_root ().get_object ().get_array_member ("sources").get_object_element (0).get_string_member ("name") == "Custom source");
            source_command.text = "'unterminated";
            find_button (docs.child, "Save Source").clicked ();
            settle (); assert (view.source () == "task-list");
            string doc_id = run_private ({"xdotool", "search", "--onlyvisible", "--name", "^Documentation · task$"});
            string origin_id = run_private ({"xdotool", "search", "--onlyvisible", "--name", "^Documentation origin$"});
            host.preferences.set_docs_dismiss (false);
            run_private ({"xdotool", "windowfocus", "--sync", doc_id}); settle ();
            run_private ({"xdotool", "windowfocus", "--sync", origin_id}); settle ();
            assert (docs.visible);
            host.preferences.set_docs_dismiss (true);
            run_private ({"xdotool", "windowfocus", "--sync", doc_id}); settle ();
            var owned_window = new Gtk.Window () {application = host, transient_for = docs, title = "Documentation owned", destroy_with_parent = true};
            owned_window.present (); settle ();
            string owned_id = run_private ({"xdotool", "search", "--onlyvisible", "--name", "^Documentation owned$"});
            run_private ({"xdotool", "windowfocus", "--sync", owned_id}); settle ();
            assert (docs.visible);
            docs.set_default_size (880, 580); settle ();
            run_private ({"xdotool", "windowfocus", "--sync", origin_id}); settle ();
            assert (!docs.visible && run_private ({"xdotool", "getwindowfocus"}) == origin_id);
            var saved = new Shadow.Geometry ("documentation");
            assert (saved.width == 880 && saved.height == 580);
            owned_window.destroy (); host.preferences.set_docs_dismiss (false);
            parent.destroy (); FileUtils.unlink (config);
        } catch (Error error) { Test.message (error.message); Test.fail (); }
    });
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
    Test.add_func ("/presentation/cursor-shape-live-precedence-and-reset", () => {
        try {
            var host = test_host ();
            host.preferences.set_cursor_shape ("block");
            var request = Shadow.Request.parse ({"shadow-term", "--input", "terminal", "--", "fish"});
            request.session = "private-cursor-test";
            var window = new Shadow.WorkspaceWindow (host, request);
            var session = new Shadow.TerminalSession (host, window, request, Environ.get ());
            window.add_session (session); window.present_session (session); settle ();
            session.terminal.grab_focus ();
            session.terminal.set_cursor_blink_mode (Vte.CursorBlinkMode.OFF);
            VCom.TerminalBytes.feed (session.terminal, (char[]) "\x1b[2J\x1b[H\x1b[?25h".data); settle ();
            var block = texture (session.terminal, window);
            host.preferences.set_cursor_shape ("ibeam"); settle ();
            var ibeam = texture (session.terminal, window);
            host.preferences.set_cursor_shape ("underline"); settle ();
            var underline = texture (session.terminal, window);
            assert (!same_pixels (block, ibeam) && !same_pixels (block, underline) && !same_pixels (ibeam, underline));

            // A newly constructed session picks up the saved shape without
            // requiring a subsequent preference notification.
            request.session = "private-cursor-second";
            var second = new Shadow.TerminalSession (host, window, request, Environ.get ());
            window.add_session (second);
            assert (second.terminal.get_cursor_shape () == Vte.CursorShape.UNDERLINE);
            host.preferences.set_cursor_shape ("block");
            assert (session.terminal.get_cursor_shape () == Vte.CursorShape.BLOCK && second.terminal.get_cursor_shape () == Vte.CursorShape.BLOCK);
            window.present_session (session); session.terminal.grab_focus (); settle ();

            // The getter reports the API default, so compare pixels to verify
            // the effective application override as well.
            VCom.TerminalBytes.feed (session.terminal, (char[]) "\x1b[6 q".data); settle ();
            var application = texture (session.terminal, window);
            assert (same_pixels (application, ibeam));
            host.preferences.set_cursor_shape ("underline"); settle ();
            assert (same_pixels (application, texture (session.terminal, window)));
            VCom.TerminalBytes.feed (session.terminal, (char[]) "\x1b[0 q".data);
            session.terminal.set_cursor_blink_mode (Vte.CursorBlinkMode.OFF); settle ();
            assert (same_pixels (underline, texture (session.terminal, window)));

            var preferences = new Shadow.PreferencesWindow (window, host.preferences);
            var chooser = (Gtk.DropDown) find_css (preferences.child, "pref-cursor-shape");
            assert (chooser != null && chooser.selected == 2);
            chooser.selected = 1; settle (); settle ();
            assert (host.preferences.cursor_shape == "ibeam" && second.terminal.get_cursor_shape () == Vte.CursorShape.IBEAM);
            var reset = find_button (preferences.child, "Restore Appearance Defaults");
            assert (reset != null); reset.clicked (); settle (); settle ();
            assert (chooser.selected == 0 && host.preferences.cursor_shape == "block");
            assert (session.terminal.get_cursor_shape () == Vte.CursorShape.BLOCK && second.terminal.get_cursor_shape () == Vte.CursorShape.BLOCK);
            preferences.destroy ();
            session.dispatch_action ("composer");
            session.input_session.report (session.input_session.token, "ready", "");
            var editor = find_editor (find_surface (session));
            editor.buffer.text = "preserved cursor draft"; editor.grab_focus (); settle ();
            assert (session.terminal.has_css_class ("shadow-composer-cursor"));
            host.preferences.set_cursor_shape ("underline"); settle ();
            assert (session.terminal.has_css_class ("shadow-composer-cursor"));
            session.dispatch_action ("composer"); settle ();
            assert (!session.terminal.has_css_class ("shadow-composer-cursor"));
            assert (session.terminal.get_cursor_shape () == Vte.CursorShape.UNDERLINE && editor.source () == "preserved cursor draft");
            host.preferences.set_cursor_shape ("block");
            window.destroy ();
        } catch (Error error) { Test.message (error.message); Test.fail (); }
    });
    Test.add_func ("/presentation/floating-session-search", () => {
        try {
            var host = test_host ();
            var request = Shadow.Request.parse ({"shadow-term", "--session", "search-overlay", "--cwd", "/tmp"});
            request.width = 920; request.height = 650;
            var window = new Shadow.WorkspaceWindow (host, request);
            var session = new Shadow.TerminalSession (host, window, request, Environ.get ());
            window.add_session (session); window.present_session (session); settle ();
            string wid = run_private ({"xdotool", "search", "--onlyvisible", "--name", " · search-overlay$"});
            run_private ({"xdotool", "windowfocus", "--sync", wid}); settle ();
            var editor = find_editor (session);
            string source = "**literal [a.*]** and 日本語";
            editor.buffer.text = source;
            VCom.TerminalBytes.feed (session.terminal, (char[]) "literal [a.*] first\r\nliteral [a.*] second\r\n".data);
            settle ();
            int64 columns = session.terminal.get_column_count (), rows = session.terminal.get_row_count ();
            string contents = session.terminal.get_text_format (Vte.Format.TEXT) ?? "";
            editor.grab_focus ();
            session.dispatch_action ("find-terminal"); settle ();
            var panel = find_css (session, "session-search");
            var entry = (Gtk.SearchEntry) find_css (session, "session-search-entry");
            var scope = (Gtk.DropDown) find_css (session, "search-target");
            var status = (Gtk.Label) find_css (session, "search-status");
            var revealer = (Gtk.Revealer) panel.get_parent ();
            assert (revealer.get_parent () is Gtk.Overlay);
            assert (!((Gtk.Overlay) revealer.get_parent ()).get_measure_overlay (revealer));
            assert (session.terminal.get_column_count () == columns && session.terminal.get_row_count () == rows);
            assert (window.get_focus ().is_ancestor (entry));
            session.focus_input (); assert (window.get_focus ().is_ancestor (entry));
            var picked = session.pick (30, 160, Gtk.PickFlags.DEFAULT);
            assert (picked == session.terminal || picked.is_ancestor (session.terminal));
            entry.text = "[a.*]";
            run_private ({"xdotool", "key", "Return"}); settle ();
            assert (status.label == "Match");
            assert (session.terminal.get_has_selection ());
            run_private ({"xdotool", "key", "shift+Return"}); settle ();
            assert (status.label == "Match");
            entry.text = "absent"; run_private ({"xdotool", "key", "Return"}); settle ();
            assert (status.label == "No match");
            scope.selected = 1; entry.text = "**";
            run_private ({"xdotool", "key", "Return"}); settle ();
            assert (status.label == "Match" && editor.source () == source);
            assert (session.terminal.search_get_regex () == null);
            run_private ({"xdotool", "key", "Escape"}); settle ();
            assert (!revealer.reveal_child && editor.has_focus);
            // Restore the initiating input, independently of the search scope.
            session.terminal.grab_focus (); session.dispatch_action ("find-terminal"); settle ();
            scope.selected = 1;
            // Return on a control retains its native activation semantics.
            var close_search_button = (Gtk.Button) entry.get_parent ().get_last_child ();
            close_search_button.grab_focus ();
            run_private ({"xdotool", "key", "Return"}); settle ();
            assert (!revealer.reveal_child && session.terminal.has_focus);
            assert (session.terminal.get_column_count () == columns && session.terminal.get_row_count () == rows);
            editor.grab_focus (); session.dispatch_action ("find-composer"); settle ();
            session.dispatch_action ("composer"); settle ();
            assert (scope.selected == 0 && window.get_focus ().is_ancestor (entry));
            run_private ({"xdotool", "key", "Escape"}); settle ();
            assert (session.terminal.has_focus);
            session.dispatch_action ("composer");
            session.dispatch_action ("find-terminal"); settle ();
            host.preferences.apply ("Monospace 12", "Monospace 12", 0.5, 10000, true, false, "#ffeecc", "#302010", 0.5);
            settle ();
            assert (panel.has_css_class ("inherit-pane-style"));
            // The panel paints its own boosted alpha, above terminal content.
            uint8 alpha = background_alpha (panel, window);
            assert (alpha >= 190 && alpha <= 193);
            texture (window, window).save_to_png ("/tmp/shadow-term-search-wide.png");
            host.preferences.apply ("Monospace 12", "Monospace 12", 1, 10000, false, true);
            settle (); assert (!panel.has_css_class ("inherit-pane-style"));
            window.set_default_size (360, 440); settle ();
            Graphene.Rect bounds = {};
            assert (panel.compute_bounds (session, out bounds));
            assert (bounds.origin.x >= 0 && bounds.origin.x + bounds.size.width <= session.get_width ());
            texture (window, window).save_to_png ("/tmp/shadow-term-search-narrow.png");
            var gtk_settings = Gtk.Settings.get_default ();
            string previous_font = gtk_settings.gtk_font_name;
            gtk_settings.gtk_font_name = "Sans 20";
            window.set_default_size (620, 550); settle ();
            assert (panel.compute_bounds (session, out bounds));
            assert (bounds.origin.x >= 0 && bounds.origin.x + bounds.size.width <= session.get_width ());
            texture (window, window).save_to_png ("/tmp/shadow-term-search-large.png");
            gtk_settings.gtk_font_name = previous_font; settle ();
            assert (editor.source () == source && session.child_pid == 0 && !session.input_session.pending);
            assert ((session.terminal.get_text_format (Vte.Format.TEXT) ?? "").strip () == contents.strip ());
            // A different tab must retain focus when the old search unmaps.
            var other_request = Shadow.Request.parse ({"shadow-term", "--session", "search-other", "--cwd", "/tmp"});
            var other = new Shadow.TerminalSession (host, window, other_request, Environ.get ());
            window.add_session (other); window.present_session (other); settle ();
            assert (!revealer.reveal_child && find_editor (other).has_focus);
            window.present_session (session); settle ();
            assert (editor.has_focus);
            session.dispatch_action ("find-terminal"); settle ();
            session.end_session (); settle ();
            assert (!revealer.reveal_child && window.active_session == other && find_editor (other).has_focus);
            window.close_workspace (); settle ();
        } catch (Error error) { Test.message (error.message); Test.fail (); }
    });
    Test.add_func ("/presentation/live-terminal-palette", () => {
        try {
            var host = test_host ();
            var request = Shadow.Request.parse ({"shadow-term", "--input", "terminal", "--", "fish"});
            request.session = "private-palette-test";
            request.width = 920; request.height = 650;
            var window = new Shadow.WorkspaceWindow (host, request);
            var session = new Shadow.TerminalSession (host, window, request, Environ.get ());
            window.add_session (session); window.present_session (session);
            var colors = new Shadow.TerminalColors ();
            host.preferences.apply ("Monospace 12", "Monospace 12", 1, 10000, true, false, "#eeeeec", "#20242b", 0, colors);
            var blocks = new StringBuilder ("\x1b[?25l\x1b[2J\x1b[H");
            for (int i = 0; i < 16; i++) blocks.append ("\x1b[48;5;%dm  ".printf (i));
            blocks.append ("\x1b[0m");
            VCom.TerminalBytes.feed (session.terminal, (char[]) blocks.str.data); settle ();
            for (int i = 0; i < 16; i++) {
                var before = texture (session.terminal, window);
                colors.set_color (i, "#123456"); host.preferences.set_colors (colors); settle ();
                assert (!same_pixels (before, texture (session.terminal, window)));
            }
            // Explicit truecolor and the extended indexed cube are independent
            // of the user's 16 ANSI overrides.
            VCom.TerminalBytes.feed (session.terminal, (char[]) "\x1b[2J\x1b[H\x1b[48;2;11;22;33m      \x1b[48;5;123m      \x1b[0m".data); settle ();
            var direct = texture (session.terminal, window);
            host.preferences.set_colors (new Shadow.TerminalColors ()); settle ();
            assert (same_pixels (direct, texture (session.terminal, window)));
            session.terminal.select_all (); settle ();
            var selected = texture (session.terminal, window);
            colors.set_color (18, "#884422"); colors.set_color (19, "#ffeecc");
            host.preferences.set_colors (colors); settle ();
            assert (!same_pixels (selected, texture (session.terminal, window)));
            session.terminal.unselect_all ();
            host.preferences.apply ("Monospace 12", "Monospace 12", 1, 10000, true, true, "#eeeeec", "#20242b", 0, new Shadow.TerminalColors ());
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
                VCom.TerminalBytes.feed (session.terminal, (char[]) "\x1b[?1049h".data);
                settle ();
                assert (!surface.get_mapped ());
                VCom.TerminalBytes.feed (session.terminal, (char[]) "\x1b[?1049l".data);
                settle ();
                assert (surface.get_mapped ());
            }
            session.input_session.report (session.input_session.token, "ready", "");
            settle ();
            assert (surface.get_mapped () && editor.source () == "preserved draft");
            editor.buffer.text = "";
            host.preferences.apply ("Monospace 12", "Monospace 12", 1, 10000, true, false, "#f6f5f4", "#20242b");
            VCom.TerminalBytes.feed (session.terminal, (char[]) "Shadow Term\r\n日本語 résumé.md\r\n\r\nA quieter workspace for commands and their output.\r\n".data);
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
            VCom.TerminalBytes.feed (session.terminal, (char[]) history.str.data);
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
            settle ();
            assert (!analysis.status.visible);
            editor.buffer.insert_at_cursor (" ", -1);
            for (int i = 0; i < 3; i++) settle ();
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
            editor.buffer.insert_at_cursor (" ", -1);
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
            VCom.TerminalBytes.feed (terminal, (char[]) "\x1b[2J\x1b[Hdirectory\r\n".data);
            settle ();
            var plain = texture (terminal, window);
            VCom.TerminalBytes.feed (terminal, (char[]) "\x1b[2J\x1b[H\x1b]8;;file:///tmp\x1b\\directory\x1b]8;;\x1b\\\r\n".data);
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
            VCom.TerminalBytes.feed (terminal, (char[]) "\x1b[?25l".data);
            settle ();
            assert (same_pixels (linked, texture (terminal, window)));
            VCom.TerminalBytes.feed (terminal, (char[]) "\x1b[?25h".data);
            terminal.remove_css_class ("shadow-composer-cursor");
            terminal.queue_draw ();
            settle ();
            assert (!same_pixels (linked, texture (terminal, window)));
            window.destroy ();
        } catch (Error error) { Test.message (error.message); Test.fail (); }
    });
    return Test.run ();
}
