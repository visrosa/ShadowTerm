int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/preferences/round-trip-and-bounds", () => {
        string? directory = null;
        try {
            directory = DirUtils.make_tmp ("shadow-preferences-XXXXXX");
            string filename = Path.build_filename (directory, "preferences.ini");
            var settings = new Shadow.Preferences (filename);
            settings.apply ("Monospace 14", "Sans 13", 0.65, 25000);
            var loaded = new Shadow.Preferences (filename);
            assert (loaded.terminal_font == "Monospace 14" && loaded.editor_font == "Sans 13");
            assert (loaded.opacity == 0.65 && loaded.scrollback == 25000);
            loaded.apply ("bad\nCSS", "Sans 5000", -1, -1);
            assert (loaded.terminal_font == "Monospace 14" && loaded.editor_font == "Sans 13");
            assert (loaded.opacity == 0 && loaded.scrollback == 100);
            FileUtils.unlink (filename);
        } catch (Error error) { Test.message (error.message); Test.fail (); }
        if (directory != null) DirUtils.remove (directory);
    });
    Test.add_func ("/preferences/independent-malformed-fields", () => {
        string? directory = null;
        try {
            directory = DirUtils.make_tmp ("shadow-preferences-XXXXXX");
            string filename = Path.build_filename (directory, "preferences.ini");
            FileUtils.set_contents (filename, "[appearance]\nterminal-font=Monospace 15\neditor-font=Sans 1000\nopacity=nan\n[terminal]\nscrollback=oops\n");
            var settings = new Shadow.Preferences (filename);
            assert (settings.terminal_font == "Monospace 15" && settings.editor_font == "Monospace 12");
            assert (settings.opacity == 1 && settings.scrollback == 10000);
            FileUtils.unlink (filename);
        } catch (Error error) { Test.message (error.message); Test.fail (); }
        if (directory != null) DirUtils.remove (directory);
    });
    return Test.run ();
}
