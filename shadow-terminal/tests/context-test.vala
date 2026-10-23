private void git (string directory, string[] arguments) throws Error {
    var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
    launcher.set_cwd (directory);
    launcher.setenv ("GIT_CONFIG_GLOBAL", "/dev/null", true);
    launcher.setenv ("GIT_CONFIG_NOSYSTEM", "1", true);
    string[] command = {"git"};
    foreach (string arg in arguments) command += arg;
    var child = launcher.spawnv (command);
    child.wait_check ();
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
            assert (context.summary == "fixture · 1 changed");
            git (directory, {"add", "file"});
            git (directory, {"-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-m", "fixture"});
            git (directory, {"checkout", "--detach"});
            refresh (context, directory);
            assert (context.summary == "Detached HEAD");
            var loop = new MainLoop ();
            context.refresh.begin (directory, () => loop.quit ());
            context.cancel ();
            loop.run ();
            assert (context.summary == "");
            FileUtils.unlink (Path.build_filename (directory, "file"));
            // Git owns this fixture's private metadata; remove only its temp tree.
            var cleanup = new Subprocess.newv ({"rm", "-rf", "--", directory}, SubprocessFlags.NONE);
            cleanup.wait_check ();
            directory = null;
        } catch (Error error) { Test.message (error.message); Test.fail (); }
        if (directory != null) DirUtils.remove (directory);
    });
    return Test.run ();
}
