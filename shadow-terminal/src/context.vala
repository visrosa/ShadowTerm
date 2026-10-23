namespace Shadow {
    // Context is advisory. It never executes a draft, changes directories in the
    // shell, acquires optional Git locks, or refreshes on an idle timer.
    public class RepositoryContext : Object {
        public string summary { get; private set; default = ""; }
        public string detail { get; private set; default = ""; }
        private Cancellable? pending;
        private uint generation = 0;

        public void cancel () {
            generation++;
            if (pending != null) pending.cancel ();
        }

        public async void refresh (string directory) {
            cancel ();
            uint request = generation;
            var cancellable = new Cancellable ();
            pending = cancellable;
            summary = ""; detail = "";
            Subprocess? process = null;
            string text = "";
            bool success = false;
            uint timer = Timeout.add (1500, () => { cancellable.cancel (); return Source.REMOVE; });
            try {
                var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
                launcher.set_cwd (directory);
                launcher.setenv ("GIT_OPTIONAL_LOCKS", "0", true);
                // An exported repository override belongs to its caller, not
                // necessarily to the directory reported by this shell session.
                foreach (var key in new string[] {"GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"}) launcher.unsetenv (key);
                process = launcher.spawnv ({"git", "-c", "core.fsmonitor=false", "status", "--porcelain=v1",
                    "--branch", "--untracked-files=normal", "--ignore-submodules=all"});
                var bytes = new ByteArray ();
                while (true) {
                    var block = yield process.get_stdout_pipe ().read_bytes_async (4096, Priority.LOW, cancellable);
                    if (block.get_size () == 0) break;
                    if (bytes.len + block.get_size () > 65536) throw new IOError.NO_SPACE ("Repository status exceeds the display limit");
                    bytes.append (block.get_data ());
                }
                yield process.wait_async (cancellable);
                if (process.get_successful ()) {
                    bytes.append ({0});
                    text = (string) bytes.data;
                    success = text.validate ();
                }
            } catch (Error error) {
                if (process != null) {
                    process.force_exit ();
                    try { yield process.wait_async (null); } catch (Error ignored) {}
                }
            }
            // The timeout may already have removed itself.
            var source = MainContext.default ().find_source_by_id (timer);
            if (source != null) source.destroy ();
            if (request != generation || cancellable.is_cancelled ()) return;
            pending = null;
            if (!success || !text.has_prefix ("## ")) return;
            string[] lines = text.split ("\n");
            string branch = lines[0].substring (3);
            if (branch.has_prefix ("No commits yet on ")) branch = branch.substring (18);
            else if (branch.has_prefix ("Initial commit on ")) branch = branch.substring (18);
            int tracking = branch.index_of ("...");
            if (tracking >= 0) branch = branch.substring (0, tracking);
            if (branch == "HEAD (no branch)") branch = "Detached HEAD";
            int changes = 0;
            foreach (var line in lines[1:lines.length]) if (line != "") changes++;
            summary = changes == 0 ? branch : "%s · %d changed".printf (branch, changes);
            detail = lines[0].substring (3) + (changes == 0 ? " · working tree clean" : " · %d status entries".printf (changes));
        }
    }
}
