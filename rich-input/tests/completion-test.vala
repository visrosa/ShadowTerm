int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/completion/unicode-offsets-and-complex-tokens", () => {
        var context = new VCom.CompletionContext ("echo 日本 ./fi-tail", 12, true, "/tmp");
        assert (context.simple && context.prefix == "./fi");
        assert (context.start == 8 && context.end == 17);
        assert (!new VCom.CompletionContext ("echo 'a b", 9, true, "/tmp").simple);
        assert (!new VCom.CompletionContext ("echo $HOME", 10, true, "/tmp").simple);
        assert (!new VCom.CompletionContext ("echo a\\ b", 9, true, "/tmp").simple);
        var quoted = new VCom.CompletionContext ("cat '日本 file-tail' rest", 12, true, "/tmp");
        assert (!quoted.simple && quoted.literal && quoted.start == 4 && quoted.end == 18);
        assert (!new VCom.CompletionContext ("echo (touch bad) ./fi", 21, true, "/tmp").query_safe);
    });
    Test.add_func ("/completion/local-files-and-fish-literals", () => {
        string? directory = null;
        try {
            directory = DirUtils.make_tmp ("vcom-provider-XXXXXX");
            string name = "file 'quote\\ 日本.txt";
            string filename = Path.build_filename (directory, name);
            FileUtils.set_contents (filename, "");
            var context = new VCom.CompletionContext ("cat ./fi", 8, true, directory);
            var loop = new MainLoop ();
            new VCom.LocalFilesProvider ().complete.begin (context, new Cancellable (), (obj, res) => {
                try {
                    var items = ((VCom.LocalFilesProvider) obj).complete.end (res);
                    assert (items.length == 1 && items[0].label == name);
                    string output, errors;
                    int status;
                    Process.spawn_sync (null, {"fish", "--no-config", "-c", "printf '%s' " + items[0].insertion}, null,
                        SpawnFlags.SEARCH_PATH, null, out output, out errors, out status);
                    assert (status == 0 && output == "./" + name);
                } catch (Error error) { Test.message (error.message); Test.fail (); }
                loop.quit ();
            });
            loop.run ();
            FileUtils.unlink (filename);
        } catch (Error error) { Test.message (error.message); Test.fail (); }
        if (directory != null) DirUtils.remove (directory);
    });
    Test.add_func ("/completion/provider-cancellation", () => {
        var cancel = new Cancellable ();
        cancel.cancel ();
        var loop = new MainLoop ();
        new VCom.BuiltinProvider ().complete.begin (new VCom.CompletionContext ("fo", 2, true, ""), cancel, (obj, res) => {
            try { ((VCom.BuiltinProvider) obj).complete.end (res); Test.fail (); }
            catch (Error error) { assert (error is IOError.CANCELLED); }
            loop.quit ();
        });
        loop.run ();
    });
    return Test.run ();
}
