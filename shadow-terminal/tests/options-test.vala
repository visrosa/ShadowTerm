int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/options/argv-roundtrip", () => {
        try {
            var r = Shadow.Request.parse ({"shadow-term", "--session", "test.1", "--size", "900x600",
                "--", "printf", "%s", "quotes ' \" and $shell\n日本語"});
            var decoded = Shadow.Request.decode (r.encode ());
            assert (decoded.command.length == 3);
            assert (decoded.command[2] == r.command[2]);
            assert (decoded.width == 900 && decoded.height == 600);
            assert (decoded.explicit_command);
        } catch (Error e) { Test.fail (); }
    });
    Test.add_func ("/options/invalid", () => {
        string[] invalid = {"--unknown", "--size", "--session"};
        foreach (string option in invalid) {
            try { Shadow.Request.parse ({"shadow-term", option}); Test.fail (); }
            catch (Error e) {}
        }
        try { Shadow.Request.parse ({"shadow-term", "--session", "../escape"}); Test.fail (); }
        catch (Error e) {}
        try { Shadow.Request.parse ({"shadow-term", "--show", "--hide"}); Test.fail (); }
        catch (Error e) {}
        try { Shadow.Request.parse ({"shadow-term", "--size", "2x4"}); Test.fail (); }
        catch (Error e) {}
    });
    Test.add_func ("/options/shell-and-cwd", () => {
        try {
            Environment.set_variable ("SHELL", "/bin/sh", true);
            var r = Shadow.Request.parse ({"shadow-term"});
            assert (r.argv ()[0] == "/bin/sh");
            assert (r.cwd == Environment.get_current_dir ());
            assert (!r.explicit_command);
        } catch (Error e) { Test.fail (); }
    });
    Test.add_func ("/options/composer-shell-selection", () => {
        try {
            var fish = Shadow.Request.parse ({"shadow-term", "--", "fish", "--login"});
            assert (fish.composer_enabled ());
            var classic = Shadow.Request.parse ({"shadow-term", "--input", "terminal", "--", "fish"});
            assert (!classic.composer_enabled ());
            var command = Shadow.Request.parse ({"shadow-term", "--", "fish", "-c", "echo hi"});
            assert (!command.composer_enabled ());
            var other = Shadow.Request.parse ({"shadow-term", "--input", "composer", "--", "sh"});
            assert (other.composer_enabled () && !other.supports_composer ());
        } catch (Error error) { Test.fail (); }
    });
    return Test.run ();
}
