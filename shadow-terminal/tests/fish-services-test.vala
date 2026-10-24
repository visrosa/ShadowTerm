private VCom.CompletionItem[] complete (Shadow.FishProvider provider, string source, string directory) {
    var loop = new MainLoop ();
    VCom.CompletionItem[] items = {};
    provider.complete.begin (new VCom.CompletionContext (source, source.char_count (), true, directory), new Cancellable (), (obj, result) => {
        try { items = provider.complete.end (result); }
        catch (Error error) { Test.message (error.message); Test.fail (); }
        loop.quit ();
    });
    loop.run ();
    return items;
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/fish-services/live-completion-definitions-and-literal-source", () => {
        var provider = new Shadow.FishProvider ();
        provider.configure ("", "complete -c vcomfixture -f -l feature -d 'Fixture option'\n" +
            "complete -c vcomfixture -f -l feedback -d '日本語 <literal description>'\n" +
            "complete -c vcomfixture -f -l plain\n", "", "");
        var items = complete (provider, "vcomfixture --featu", "/tmp");
        assert (items.length == 1 && items[0].insertion == "--feature");
        assert (items[0].detail == "Fixture option");
        items = complete (provider, "vcomfixture --feedb", "/tmp");
        assert (items.length == 1 && items[0].detail == "日本語 <literal description>");
        items = complete (provider, "vcomfixture --pla", "/tmp");
        assert (items.length == 1 && items[0].detail == "Fish completion");
        // Draft substitution syntax must never be executed by a query worker.
        string marker = "/tmp/vcom-no-eval-" + Uuid.string_random ();
        assert (complete (provider, "echo (touch " + marker + ") ./fi", "/tmp").length == 0);
        assert (!FileUtils.test (marker, FileTest.EXISTS));
    });
    Test.add_func ("/fish-services/quoted-unicode-filename", () => {
        string? directory = null;
        try {
            directory = DirUtils.make_tmp ("vcom-fish-service-XXXXXX");
            string filename = Path.build_filename (directory, "vcomfile 'quote\\ 日本.txt");
            FileUtils.set_contents (filename, "");
            var items = complete (new Shadow.FishProvider (), "cat ./vcomfi", directory);
            assert (items.length == 1);
            string output; int status;
            Process.spawn_sync (directory, {"fish", "--no-config", "-c", "printf '%s' " + items[0].insertion}, null,
                SpawnFlags.SEARCH_PATH, null, out output, null, out status);
            assert (status == 0 && output == "./vcomfile 'quote\\ 日本.txt");
            items = complete (new Shadow.FishProvider (), "cat './vcomfi", directory);
            assert (items.length == 1 && items[0].insertion.has_prefix ("'./vcomfile"));
            Process.spawn_sync (directory, {"fish", "--no-config", "-c", "printf '%s' " + items[0].insertion}, null,
                SpawnFlags.SEARCH_PATH, null, out output, null, out status);
            assert (status == 0 && output == "./vcomfile 'quote\\ 日本.txt");
            FileUtils.unlink (filename);
        } catch (Error error) { Test.message (error.message); Test.fail (); }
        if (directory != null) DirUtils.remove (directory);
    });
    Test.add_func ("/fish-services/abbreviations-position-quotes-and-cursor", () => {
        var provider = new Shadow.FishProvider ();
        provider.configure ("abbr -a -- gco 'git checkout'\nabbr -a --position anywhere -- 日本 'a b'\nabbr -a --set-cursor=! -- loop 'for x in y; !; end'\nabbr -a --command git -- co checkout\nabbr -a --function unsupported -- dynamic\n", "", "", "");
        var item = provider.expand (new VCom.CompletionContext ("gco", 3, true, ""));
        assert (item != null && item.insertion == "git checkout");
        assert (provider.expand (new VCom.CompletionContext ("echo gco", 8, true, "")) == null);
        item = provider.expand (new VCom.CompletionContext ("echo 日本", 7, true, ""));
        assert (item != null && item.insertion == "a b" && item.start == 5);
        item = provider.expand (new VCom.CompletionContext ("loop", 4, true, ""));
        assert (item != null && item.insertion == "for x in y; ; end" && item.cursor == 12);
        item = provider.expand (new VCom.CompletionContext ("git co", 6, true, ""));
        assert (item != null && item.insertion == "checkout");
        assert (provider.expand (new VCom.CompletionContext ("echo co", 7, true, "")) == null);
        item = provider.expand (new VCom.CompletionContext ("echo yes; git co", 16, true, ""));
        assert (item != null && item.insertion == "checkout");
        assert (provider.expand (new VCom.CompletionContext ("dynamic", 7, true, "")) == null);
        assert (provider.expand (new VCom.CompletionContext ("# words 日本", 10, true, "")) == null);
        var candidates = complete (provider, "gc", "/tmp");
        bool found = false;
        foreach (var candidate in candidates) if (candidate.insertion == "gco") found = true;
        assert (found);
        provider.enabled = false;
        assert (provider.expand (new VCom.CompletionContext ("gco", 3, true, "")) == null);
    });
    Test.add_func ("/fish-services/query-timeout-and-child-group", () => {
        var provider = new Shadow.FishProvider ();
        provider.configure ("", "complete -c vcomslow -f -a '(sleep 10; echo late)'\n", "", "");
        var loop = new MainLoop ();
        int64 before = get_monotonic_time ();
        provider.complete.begin (new VCom.CompletionContext ("vcomslow ", 9, true, "/tmp"), new Cancellable (), (obj, res) => {
            try { provider.complete.end (res); Test.fail (); }
            catch (Error error) { assert (error is IOError.CANCELLED); }
            loop.quit ();
        });
        loop.run ();
        assert (get_monotonic_time () - before < 2500000);
    });
    return Test.run ();
}
