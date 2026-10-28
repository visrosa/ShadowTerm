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
            assert (!dialog.modal && dialog.transient_for == parent);
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
    Test.add_func ("/appearance/shortcut-capture-categories-and-cancellation", () => {
        string? directory = null;
        try {
            directory = DirUtils.make_tmp ("shadow-shortcut-ui-XXXXXX");
            var settings = new Shadow.Preferences (Path.build_filename (directory, "preferences.ini"));
            var parent = new Gtk.Window ();
            var dialog = new Shadow.PreferencesWindow (parent, settings);
            var pages = (Gtk.Stack) ((Gtk.Box) dialog.child).get_first_child ();
            pages.visible_child_name = "shortcuts"; parent.present (); dialog.present ();
            var loop = new MainLoop ();
            Timeout.add (100, () => { loop.quit (); return Source.REMOVE; }); loop.run ();
            var view = (Shadow.ShortcutSettings) find_control (dialog.child, "pref-shortcuts");
            var content = view.get_first_child ().get_next_sibling ();
            assert (content.get_first_child () is Gtk.StackSidebar);
            var categories = (Gtk.Stack) content.get_last_child ();
            assert (categories.get_pages ().get_n_items () == 5);
            var row = (Gtk.ListBoxRow) ((Gtk.ListBox) categories.visible_child).get_first_child ();
            var capture = (Gtk.Button) row.child.get_first_child ().get_next_sibling ();
            assert (capture.child is Gtk.ShortcutLabel);
            string original = settings.shortcut ("new-tab");
            capture.clicked ();
            assert (view.handle_key (Gdk.Key.Escape, 0) && settings.shortcut ("new-tab") == original);
            capture.clicked (); assert (view.handle_key (Gdk.Key.q, Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK));
            assert (settings.shortcut ("new-tab") == original);
            assert (((Gtk.Label) find_control (dialog.child, "pref-status")).label.has_prefix ("Already assigned"));
            assert (view.handle_key (Gdk.Key.BackSpace, 0) && settings.shortcut ("new-tab") == "");
            capture.clicked (); pages.visible_child_name = "input";
            assert (!view.handle_key (Gdk.Key.x, Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK));
            settings.reset_shortcut ("new-tab");
            dialog.close (); parent.destroy ();
            FileUtils.unlink (Path.build_filename (directory, "preferences.ini"));
        } catch (Error error) { Test.message (error.message); Test.fail (); }
        if (directory != null) DirUtils.remove (directory);
    });
    Test.add_func ("/appearance/theme-import-edit-reset", () => {
        string? directory = null;
        try {
            directory = DirUtils.make_tmp ("shadow-theme-ui-XXXXXX");
            string filename = Path.build_filename (directory, "preferences.ini");
            string theme = Path.build_filename (directory, "theme.itermcolors");
            FileUtils.set_contents (theme, theme_preset ());
            var settings = new Shadow.Preferences (filename);
            settings.apply ("Monospace 12", "Monospace 12", 0.7, 10000);
            var parent = new Gtk.Window ();
            var dialog = new Shadow.PreferencesWindow (parent, settings);
            parent.present (); dialog.present ();
            var loop = new MainLoop ();
            dialog.import_theme_file.begin (File.new_for_path (theme), (obj, result) => {
                dialog.import_theme_file.end (result); loop.quit ();
            }); loop.run ();
            assert (!settings.system_colors && settings.opacity == 0.7);
            assert (((Gtk.Label) find_control (dialog.child, "pref-status")).label == "Imported theme.itermcolors");
            for (int i = 0; i < 20; i++) {
                var control = (Gtk.ColorDialogButton) find_control (dialog.child, "pref-color-" + Shadow.TerminalColors.KEYS[i]);
                Gdk.RGBA expected = {}; expected.parse (settings.colors.get_color (i));
                assert (control.sensitive && control.get_rgba ().equal (expected));
            }
            var red = (Gtk.ColorDialogButton) find_control (dialog.child, "pref-color-ansi-1");
            Gdk.RGBA edited = {}; edited.parse ("#123456"); red.rgba = edited;
            ((Gtk.CheckButton) find_control (dialog.child, "pref-auto-cursor")).active = true;
            assert (!find_control (dialog.child, "pref-color-cursor").sensitive);
            // A failed import leaves pending edits and the current theme intact.
            FileUtils.set_contents (theme, "<plist><dict/></plist>");
            dialog.import_theme_file.begin (File.new_for_path (theme), (obj, result) => {
                dialog.import_theme_file.end (result); loop.quit ();
            }); loop.run ();
            assert (((Gtk.Label) find_control (dialog.child, "pref-status")).label.has_prefix ("Could not import theme:"));
            dialog.close ();
            var loaded = new Shadow.Preferences (filename);
            assert (loaded.colors.get_color (1) == edited.to_string () && loaded.colors.special (16) == null);
            var reset_dialog = new Shadow.PreferencesWindow (parent, loaded);
            reset_dialog.present ();
            ((Gtk.Button) find_control (reset_dialog.child, "pref-appearance-reset")).clicked ();
            reset_dialog.close ();
            var defaults = new Shadow.Preferences (filename);
            var default_colors = new Shadow.TerminalColors ();
            assert (defaults.system_colors && defaults.opacity == 1);
            for (int i = 0; i < 20; i++) assert (defaults.colors.get_color (i) == default_colors.get_color (i));
            FileUtils.set_contents (theme, theme_preset ());
            var unsaved = new Shadow.Preferences (directory);
            var unsaved_dialog = new Shadow.PreferencesWindow (parent, unsaved);
            unsaved_dialog.present ();
            unsaved_dialog.import_theme_file.begin (File.new_for_path (theme), (obj, result) => {
                unsaved_dialog.import_theme_file.end (result); loop.quit ();
            }); loop.run ();
            assert (!unsaved.system_colors);
            assert (((Gtk.Label) find_control (unsaved_dialog.child, "pref-status")).label.has_prefix ("Imported; could not save:"));
            var imported_red = (Gtk.ColorDialogButton) find_control (unsaved_dialog.child, "pref-color-ansi-1");
            Gdk.RGBA expected_red = {}; expected_red.parse (unsaved.colors.get_color (1));
            assert (imported_red.get_rgba ().equal (expected_red));
            unsaved_dialog.close ();
            parent.destroy ();
            FileUtils.unlink (theme); FileUtils.unlink (filename);
        } catch (Error error) { Test.message (error.message); Test.fail (); }
        if (directory != null) DirUtils.remove (directory);
    });
    return Test.run ();
}
