private void git (string directory, string[] arguments, int expected = 0) throws Error {
    var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
    launcher.set_cwd (directory);
    launcher.setenv ("GIT_CONFIG_GLOBAL", "/dev/null", true);
    launcher.setenv ("GIT_CONFIG_NOSYSTEM", "1", true);
    string[] command = {"git"};
    foreach (string arg in arguments) command += arg;
    var child = Shadow.Native.spawn (launcher, command);
    child.wait ();
    assert (child.get_if_exited () && child.get_exit_status () == expected);
}

private void refresh (Shadow.RepositoryContext context, string directory) {
    var loop = new MainLoop ();
    context.refresh.begin (directory, () => loop.quit ());
    loop.run ();
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/context/repository-states-and-cancellation", () => {
        string? directory = null;
        try {
            directory = DirUtils.make_tmp ("shadow-context-XXXXXX");
            var context = new Shadow.RepositoryContext ();
            refresh (context, directory);
            assert (context.summary == "");
            git (directory, {"init", "--initial-branch=fixture"});
            refresh (context, directory);
            assert (context.summary == "fixture");
            FileUtils.set_contents (Path.build_filename (directory, "file"), "fixture\n");
            refresh (context, directory);
            assert (context.summary == "fixture · ?1");
            git (directory, {"add", "file"});
            git (directory, {"-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-m", "fixture"});
            git (directory, {"checkout", "--detach"});
            refresh (context, directory);
            assert (context.summary.has_prefix ("Detached "));
            var loop = new MainLoop ();
            context.refresh.begin ("/", () => loop.quit ());
            context.cancel ();
            loop.run ();
            assert (context.summary == "");
            FileUtils.unlink (Path.build_filename (directory, "file"));
            // Git owns this fixture's private metadata; remove only its temp tree.
            var cleanup = Shadow.Native.subprocess ({"rm", "-rf", "--", directory}, SubprocessFlags.NONE);
            cleanup.wait_check ();
            directory = null;
        } catch (Error error) { Test.message (error.message); Test.fail (); }
        if (directory != null) DirUtils.remove (directory);
    });
    Test.add_func ("/context/git-counts-tracking-stash-and-rename-framing", () => {
        string? directory = null;
        try {
            directory = DirUtils.make_tmp ("shadow-context-XXXXXX");
            git (directory, {"init", "--initial-branch=fixture"});
            git (directory, {"config", "user.name", "Fixture"});
            git (directory, {"config", "user.email", "fixture@example.invalid"});
            string filename = Path.build_filename (directory, "first\nline");
            FileUtils.set_contents (filename, "original\n");
            git (directory, {"add", "."}); git (directory, {"commit", "-m", "initial"});
            git (directory, {"branch", "upstream"});
            git (directory, {"branch", "--set-upstream-to=upstream"});
            FileUtils.set_contents (filename, "modified\n");
            git (directory, {"stash", "push", "-m", "fixture"});
            git (directory, {"mv", "first\nline", "renamed\nline"});
            FileUtils.set_contents (Path.build_filename (directory, "renamed\nline"), "modified again\n");
            FileUtils.set_contents (Path.build_filename (directory, "untracked\nline"), "new\n");
            var context = new Shadow.RepositoryContext ();
            refresh (context, directory);
            assert (context.summary.contains ("+1") && context.summary.contains ("~1") && context.summary.contains ("?1"));
            assert (context.summary.contains ("stash 1") && context.detail.contains ("1 staged · 1 modified · 1 untracked"));
            assert (context.detail.contains ("upstream"));
            git (directory, {"add", "."}); git (directory, {"commit", "-m", "next"});
            refresh (context, directory);
            assert (context.summary.contains ("↑1") && context.detail.contains ("1 ahead"));
            git (directory, {"checkout", "upstream"});
            FileUtils.set_contents (Path.build_filename (directory, "upstream-file"), "new\n");
            git (directory, {"add", "."}); git (directory, {"commit", "-m", "upstream"});
            git (directory, {"checkout", "fixture"});
            refresh (context, directory);
            assert (context.summary.contains ("↑1") && context.summary.contains ("↓1"));
            git (directory, {"reset", "--hard", "upstream"});
            git (directory, {"checkout", "-b", "conflict"});
            FileUtils.set_contents (Path.build_filename (directory, "upstream-file"), "side one\n");
            git (directory, {"commit", "-am", "side one"});
            git (directory, {"checkout", "fixture"});
            FileUtils.set_contents (Path.build_filename (directory, "upstream-file"), "side two\n");
            git (directory, {"commit", "-am", "side two"});
            git (directory, {"merge", "conflict"}, 1);
            refresh (context, directory);
            assert (context.summary.contains ("!1") && context.detail.contains ("1 conflicted"));
            context.enabled = false;
            refresh (context, directory);
            assert (context.summary == "");
            var cleanup = Shadow.Native.subprocess ({"rm", "-rf", "--", directory}, SubprocessFlags.NONE);
            cleanup.wait_check (); directory = null;
        } catch (Error error) { Test.message (error.message); Test.fail (); }
        if (directory != null) DirUtils.remove (directory);
    });
    Test.add_func ("/context/prompt-validation-results-and-environments", () => {
        var context = new Shadow.PromptContext ();
        assert (context.update ({"0", "0", "0", "0", "", "", "0", "0", "fixture", "host"}));
        assert (context.result_summary () == "" && context.duration_summary () == "");
        assert (context.update ({"1", "0", "1,0", "1234", "/tmp/日本語", "science", "1", "2", "fixture", "host"}));
        assert (context.result_summary () == "pipe 1|0" && context.duration_summary () == "1.2 s");
        assert (context.environment_summary () == "venv 日本語 · conda science");
        assert (context.identity_summary () == "SSH · fixture@host" && context.jobs == 2);
        assert (!context.update ({"1", "bad", "0", "0", "", "", "0", "0", "", ""}));
        assert (context.jobs == 2 && context.pipeline == "1|0");
        assert (context.update ({"1", "130", "130", "61000", "", "", "0", "0", "root", "host\n\x1b"}));
        assert (context.result_summary () == "exit 130" && context.duration_summary () == "1 m 01 s");
        assert (context.environment_summary () == "" && context.identity_summary () == "root@host");
        assert (!context.update ({"1", "0", "oops", "0", "", "", "0", "0", "", ""}));
    });
    return Test.run ();
}
