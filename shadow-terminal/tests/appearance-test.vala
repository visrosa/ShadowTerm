int main (string[] args) {
    Gtk.init ();
    Test.init (ref args);
    Test.add_func ("/appearance/preferences-controls-and-persistence", () => {
        string? directory = null;
        try {
            directory = DirUtils.make_tmp ("shadow-appearance-XXXXXX");
            string filename = Path.build_filename (directory, "preferences.ini");
            var settings = new Shadow.Preferences (filename);
            var parent = new Gtk.Window () {title = "Isolated appearance test"};
            var dialog = new Shadow.PreferencesWindow (parent, settings);
            parent.present (); dialog.present ();
            var grid = (Gtk.Grid) dialog.child;
            var font = (Gtk.FontDialogButton) grid.get_child_at (1, 0);
            var editor = (Gtk.FontDialogButton) grid.get_child_at (1, 1);
            var opacity = (Gtk.Scale) grid.get_child_at (1, 2);
            var lines = (Gtk.SpinButton) grid.get_child_at (1, 3);
            var inherit = (Gtk.Switch) grid.get_child_at (1, 4);
            var system = (Gtk.Switch) grid.get_child_at (1, 5);
            var foreground = (Gtk.ColorDialogButton) grid.get_child_at (1, 6);
            var background = (Gtk.ColorDialogButton) grid.get_child_at (1, 7);
            assert (inherit.active && system.active && !foreground.sensitive && !background.sensitive);
            inherit.active = false; system.active = false;
            assert (foreground.sensitive && background.sensitive);
            Gdk.RGBA fg = {}, bg = {};
            fg.parse ("#ddeeff"); bg.parse ("#112233");
            foreground.rgba = fg; background.rgba = bg;
            font.font_desc = Pango.FontDescription.from_string ("Monospace 16");
            editor.font_desc = Pango.FontDescription.from_string ("Sans Italic 14");
            opacity.set_value (70); lines.value = 17000;
            // Closing must flush the coalesced write even before its timer fires.
            dialog.close ();
            var loop = new MainLoop ();
            Timeout.add (30, () => { loop.quit (); return Source.REMOVE; });
            loop.run ();
            var loaded = new Shadow.Preferences (filename);
            assert (loaded.terminal_font == "Monospace 16" && loaded.editor_font == "Sans Italic 14");
            assert (loaded.opacity == 0.7 && loaded.scrollback == 17000);
            assert (!loaded.inherit_style && !loaded.system_colors);
            assert (loaded.foreground == fg.to_string () && loaded.background == bg.to_string ());
            parent.destroy ();
            FileUtils.unlink (filename);
        } catch (Error error) { Test.message (error.message); Test.fail (); }
        if (directory != null) DirUtils.remove (directory);
    });
    return Test.run ();
}
