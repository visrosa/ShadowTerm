private Gtk.Widget? find_control (Gtk.Widget widget, string name) {
    if (widget.has_css_class (name)) return widget;
    for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var found = find_control (child, name); if (found != null) return found;
    }
    return null;
}

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
            var capture_loop = new MainLoop ();
            Timeout.add (80, () => { capture_loop.quit (); return Source.REMOVE; }); capture_loop.run ();
            var snapshot = new Gtk.Snapshot ();
            new Gtk.WidgetPaintable (dialog).snapshot (snapshot, dialog.get_width (), dialog.get_height ());
            ((Gtk.Native) dialog).get_renderer ().render_texture (snapshot.to_node (), null).save_to_png ("/tmp/shadow-term-preferences.png");
            var font = (Gtk.FontDialogButton) find_control (dialog.child, "pref-terminal-font");
            var editor = (Gtk.FontDialogButton) find_control (dialog.child, "pref-editor-font");
            var opacity = (Gtk.Scale) find_control (dialog.child, "pref-opacity");
            var lines = (Gtk.SpinButton) find_control (dialog.child, "pref-scrollback");
            var inherit = (Gtk.Switch) find_control (dialog.child, "pref-inherit");
            var system = (Gtk.Switch) find_control (dialog.child, "pref-system-colors");
            var foreground = (Gtk.ColorDialogButton) find_control (dialog.child, "pref-foreground");
            var background = (Gtk.ColorDialogButton) find_control (dialog.child, "pref-background");
            assert (inherit.active && system.active && !foreground.sensitive && !background.sensitive);
            inherit.active = false; system.active = false;
            assert (foreground.sensitive && background.sensitive);
            Gdk.RGBA fg = {}, bg = {};
            fg.parse ("#ddeeff"); bg.parse ("#112233");
            foreground.rgba = fg; background.rgba = bg;
            ((Gtk.Scale) find_control (dialog.child, "pref-header-boost")).set_value (50);
            font.font_desc = Pango.FontDescription.from_string ("Monospace 16");
            editor.font_desc = Pango.FontDescription.from_string ("Sans Italic 14");
            opacity.set_value (70); lines.value = 17000;
            ((Gtk.Stack) ((Gtk.Box) dialog.child).get_first_child ()).visible_child_name = "input";
            var loop_map = new MainLoop ();
            Timeout.add (30, () => { loop_map.quit (); return Source.REMOVE; }); loop_map.run ();
            var options = find_control (dialog.child, "pref-context");
            var master = (Gtk.CheckButton) options.get_first_child ();
            var directory_toggle = (Gtk.CheckButton) master.get_next_sibling ();
            var git_toggle = (Gtk.CheckButton) directory_toggle.get_next_sibling ();
            master.active = false;
            assert (!git_toggle.sensitive && !settings.context_visible ("enabled"));
            master.active = true;
            git_toggle.active = false;
            // Closing must flush the coalesced write even before its timer fires.
            dialog.close ();
            var loop = new MainLoop ();
            Timeout.add (30, () => { loop.quit (); return Source.REMOVE; });
            loop.run ();
            var loaded = new Shadow.Preferences (filename);
            assert (loaded.terminal_font == "Monospace 16" && loaded.editor_font == "Sans Italic 14");
            assert (loaded.opacity == 0.7 && loaded.scrollback == 17000);
            assert (!loaded.inherit_style && !loaded.system_colors);
            assert (loaded.header_opacity_boost == 0.5);
            assert (loaded.context_visible ("enabled") && !loaded.context_visible ("git"));
            assert (loaded.foreground == fg.to_string () && loaded.background == bg.to_string ());
            parent.destroy ();
            FileUtils.unlink (filename);
        } catch (Error error) { Test.message (error.message); Test.fail (); }
        if (directory != null) DirUtils.remove (directory);
    });
    return Test.run ();
}
