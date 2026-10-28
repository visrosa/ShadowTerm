private void reject_preset (string text) {
    bool rejected = false;
    try { Shadow.TerminalColors.import_iterm (text); } catch (Error error) { rejected = true; }
    assert (rejected);
}

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
            settings.set_style_fonts ("DejaVu Sans Mono Bold 12", "Liberation Mono Italic 12", "Monospace Bold Italic 12");
            settings.set_shortcut ("split-horizontal", "<Control><Alt>e");
            settings.set_shortcut ("detach-pane", "<Control><Alt>d");
            settings.set_shortcut ("hide", "");
            settings.apply ("Monospace 14", "Sans 13", 0.65, 25000, false, false, "#112233", "#445566", 0.5);
            var loaded = new Shadow.Preferences (filename);
            assert (loaded.bold_font == "DejaVu Sans Mono Bold 12" && loaded.italic_font == "Liberation Mono Italic 12" && loaded.bold_italic_font == "Monospace Bold Italic 12");
            assert (loaded.shortcut_action (Gdk.Key.e, Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK) == "split-horizontal");
            assert (loaded.shortcut_action (Gdk.Key.h, Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK) == null);
            assert (loaded.shortcut_action (Gdk.Key.e, Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK) == null);
            bool conflict = false;
            try { loaded.set_shortcut ("split-vertical", "<Control><Alt>e"); } catch (IOError.EXISTS error) { conflict = true; }
            assert (conflict);
            bool reserved = false;
            try { loaded.set_shortcut ("split-vertical", "<Control>c"); } catch (IOError.INVALID_ARGUMENT error) { reserved = true; }
            assert (reserved);
            loaded.reset_shortcut ("split-horizontal");
            assert (loaded.shortcut_action (Gdk.Key.e, Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK) == "split-horizontal");
            loaded.reset_shortcuts ();
            assert (loaded.shortcut ("hide") == "<Control><Shift>h");
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
    Test.add_func ("/preferences/terminal-colors-import-and-persistence", () => {
        string? directory = null;
        try {
            var colors = Shadow.TerminalColors.import_iterm (theme_preset ());
            var palette = colors.palette ();
            for (int i = 0; i < 16; i++) {
                assert ((palette[i].red - i / 22.0).abs () < 0.003);
                assert ((palette[i].green - 0.25).abs () < 0.003);
            }
            assert (colors.special (16) != null && colors.special (19) != null);
            var minimal = Shadow.TerminalColors.import_iterm (theme_preset (false));
            for (int i = 16; i < 20; i++) assert (minimal.special (i) == null);
            directory = DirUtils.make_tmp ("shadow-theme-XXXXXX");
            string filename = Path.build_filename (directory, "preferences.ini");
            var settings = new Shadow.Preferences (filename);
            settings.apply ("Monospace 15", "Sans 14", 0.6, 20000);
            settings.import_colors (colors);
            var loaded = new Shadow.Preferences (filename);
            assert (!loaded.system_colors && loaded.opacity == 0.6 && loaded.terminal_font == "Monospace 15");
            assert (loaded.foreground == colors.foreground && loaded.background == colors.background);
            for (int i = 0; i < 20; i++) assert (loaded.colors.get_color (i) == colors.get_color (i));
            loaded.colors.set_color (3, "#123456"); loaded.colors.set_color (16, "");
            loaded.set_colors (loaded.colors);
            var edited = new Shadow.Preferences (filename);
            assert (edited.colors.get_color (3) == "rgb(18,52,86)" && edited.colors.special (16) == null);
            edited.apply ("Monospace 15", "Sans 14", 0.6, 20000);
            var system = new Shadow.Preferences (filename);
            assert (system.system_colors && system.colors.get_color (3) == "rgb(18,52,86)");
            FileUtils.unlink (filename);
        } catch (Error error) { Test.message (error.message); Test.fail (); }
        if (directory != null) DirUtils.remove (directory);
    });
    Test.add_func ("/preferences/terminal-colors-invalid-input", () => {
        reject_preset ("not XML");
        reject_preset ("<plist><dict/></plist>");
        reject_preset (theme_preset ().replace ("Ansi 15 Color", "Ansi 14 Color"));
        reject_preset (theme_preset ().replace ("Ansi 15 Color", "Unknown Color"));
        reject_preset (theme_preset ().replace ("<real>0.25</real>", "<real>nan</real>"));
        reject_preset (theme_preset ().replace ("<real>0.25</real>", "<real>1.01</real>"));
        reject_preset (theme_preset ().replace ("<real>0.25</real>", "<real>-0.1</real>"));
        reject_preset (theme_preset ().replace ("sRGB", "Display P3"));
        reject_preset (theme_preset ().replace ("Green Component", "Missing Component"));
        reject_preset (theme_preset ().replace ("<dict>", "<array>"));
        reject_preset ("<!DOCTYPE plist [<!ENTITY x SYSTEM 'file:///etc/passwd'>]>" + theme_preset ());
        reject_preset (string.nfill (262145, 'x'));
    });
    Test.add_func ("/preferences/terminal-colors-malformed-persistence", () => {
        var file = new KeyFile ();
        file.set_string ("terminal-colors", "ansi-0", "invalid");
        file.set_string ("terminal-colors", "ansi-1", "#123456");
        file.set_string ("terminal-colors", "cursor", "invalid");
        var colors = new Shadow.TerminalColors ();
        var defaults = new Shadow.TerminalColors ();
        colors.load (file);
        assert (colors.get_color (0) == defaults.get_color (0));
        assert (colors.get_color (1) == "rgb(18,52,86)");
        assert (colors.special (16) == null);
    });
    return Test.run ();
}
