int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/preferences/round-trip-and-bounds", () => {
        string? directory = null;
        try {
            directory = DirUtils.make_tmp ("shadow-preferences-XXXXXX");
            string filename = Path.build_filename (directory, "preferences.ini");
            var settings = new Shadow.Preferences (filename);
            assert (settings.context_visible ("enabled") && settings.context_visible ("git") && !settings.context_visible ("identity"));
            settings.set_context_visible ("git", false);
            settings.set_input_guard (false);
            settings.set_docs_dismiss (true);
            settings.set_context_visible ("identity", true);
            settings.apply ("Monospace 14", "Sans 13", 0.65, 25000, false, false, "#112233", "#445566", 0.5);
            var loaded = new Shadow.Preferences (filename);
            assert (!loaded.guard_pane_input && loaded.docs_dismiss);
            assert (!loaded.context_visible ("git") && loaded.context_visible ("identity"));
            assert (loaded.terminal_font == "Monospace 14" && loaded.editor_font == "Sans 13");
            assert (loaded.opacity == 0.65 && loaded.scrollback == 25000);
            assert (!loaded.inherit_style && !loaded.system_colors);
            assert (loaded.foreground == "rgb(17,34,51)" && loaded.background == "rgb(68,85,102)");
            assert ((loaded.pane_background (false).alpha - 0.65).abs () < 0.001);
            assert (loaded.header_opacity_boost == 0.5 && (loaded.header_background (false).alpha - 0.825).abs () < 0.001);
            assert ((loaded.pane_foreground (true).red - 17.0 / 255).abs () < 0.001);
            loaded.apply ("bad\nCSS", "Sans 5000", -1, -1);
            assert (loaded.terminal_font == "Monospace 14" && loaded.editor_font == "Sans 13");
            assert (loaded.opacity == 0 && loaded.scrollback == 100);
            loaded.reset_context ();
            assert (loaded.context_visible ("git") && !loaded.context_visible ("identity"));
            FileUtils.unlink (filename);
        } catch (Error error) { Test.message (error.message); Test.fail (); }
        if (directory != null) DirUtils.remove (directory);
    });
    Test.add_func ("/preferences/independent-malformed-fields", () => {
        string? directory = null;
        try {
            directory = DirUtils.make_tmp ("shadow-preferences-XXXXXX");
            string filename = Path.build_filename (directory, "preferences.ini");
            FileUtils.set_contents (filename, "[appearance]\nterminal-font=Monospace 15\neditor-font=Sans 1000\nopacity=nan\ninherit-pane-style=false\nsystem-colors=oops\nforeground=red; } * { background: pink\nbackground=#aabbcc\n[terminal]\nscrollback=oops\n");
            var settings = new Shadow.Preferences (filename);
            assert (settings.terminal_font == "Monospace 15" && settings.editor_font == "Monospace 12");
            assert (settings.opacity == 1 && settings.scrollback == 10000);
            assert (!settings.inherit_style && settings.system_colors);
            assert (settings.foreground == "#eeeeec" && settings.background == "rgb(170,187,204)");
            FileUtils.unlink (filename);
        } catch (Error error) { Test.message (error.message); Test.fail (); }
        if (directory != null) DirUtils.remove (directory);
    });
    return Test.run ();
}
