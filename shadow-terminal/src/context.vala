namespace Shadow {
    // Context is advisory. It never executes a draft, changes directories in the
    // shell, acquires optional Git locks, or refreshes on an idle timer.
    public class RepositoryContext : Object {
        public string summary { get; private set; default = ""; }
        public string detail { get; private set; default = ""; }
        private bool active = true;
        public bool enabled {
            get { return active; }
            set { if (active == value) return; active = value; if (!value) { cancel (); summary = ""; detail = ""; } }
        }
        private Cancellable? pending;
        private uint generation = 0;
        private string last_directory = "";

        public void cancel () {
            generation++;
            if (pending != null) pending.cancel ();
        }

        public async void refresh (string directory) {
            cancel ();
            if (!enabled) return;
            uint request = generation;
            var cancellable = new Cancellable ();
            pending = cancellable;
            if (directory != last_directory) { summary = ""; detail = ""; last_directory = directory; }
            Subprocess? process = null;
            string[] records = {};
            bool success = false;
            uint timer = Timeout.add (1500, () => { cancellable.cancel (); return Source.REMOVE; });
            try {
                var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
                launcher.set_cwd (directory);
                launcher.setenv ("GIT_OPTIONAL_LOCKS", "0", true);
                // An exported repository override belongs to its caller, not
                // necessarily to the directory reported by this shell session.
                foreach (var key in new string[] {"GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"}) launcher.unsetenv (key);
                process = launcher.spawnv ({"git", "-c", "core.fsmonitor=false", "status", "--porcelain=v2", "-z",
                    "--branch", "--show-stash", "--untracked-files=normal", "--ignore-submodules=all"});
                var bytes = new ByteArray ();
                while (true) {
                    var block = yield process.get_stdout_pipe ().read_bytes_async (4096, Priority.LOW, cancellable);
                    if (block.get_size () == 0) break;
                    if (bytes.len + block.get_size () > 65536) throw new IOError.NO_SPACE ("Repository status exceeds the display limit");
                    bytes.append (block.get_data ());
                }
                yield process.wait_async (cancellable);
                if (process.get_successful ()) {
                    // Filenames can contain newlines and rename records have
                    // a second pathname. NUL framing keeps counts unambiguous.
                    var record = new StringBuilder ();
                    foreach (uint8 b in bytes.data) {
                        if (b == 0) { records += record.str; record.truncate (0); }
                        else record.append_c ((char) b);
                    }
                    success = record.len == 0;
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
            if (request != generation) return;
            pending = null;
            if (cancellable.is_cancelled () || !success) { summary = ""; detail = ""; return; }
            string branch = "", oid = "", upstream = "";
            int staged = 0, modified = 0, untracked = 0, conflicts = 0, ahead = 0, behind = 0, stash = 0;
            bool rename_path = false;
            foreach (string record in records) {
                if (rename_path) { rename_path = false; continue; }
                if (record.has_prefix ("# branch.head ")) branch = record.substring (14).make_valid ();
                else if (record.has_prefix ("# branch.oid ")) oid = record.substring (13);
                else if (record.has_prefix ("# branch.upstream ")) upstream = record.substring (18).make_valid ();
                else if (record.has_prefix ("# branch.ab ")) record.substring (12).scanf ("+%d -%d", out ahead, out behind);
                else if (record.has_prefix ("# stash ")) stash = int.parse (record.substring (8));
                else if (record.has_prefix ("? ")) untracked++;
                else if (record.has_prefix ("u ")) conflicts++;
                else if (record.length >= 4 && (record.has_prefix ("1 ") || record.has_prefix ("2 "))) {
                    if (record[2] != '.') staged++;
                    if (record[3] != '.') modified++;
                    rename_path = record[0] == '2';
                }
            }
            if (branch == "") return;
            if (branch == "(detached)") branch = "Detached " + oid.substring (0, int.min (7, oid.length));
            branch = PromptContext.display_text (branch);
            string text = branch;
            if (ahead > 0) text += " · ↑%d".printf (ahead);
            if (behind > 0) text += " · ↓%d".printf (behind);
            if (staged > 0) text += " · +%d".printf (staged);
            if (modified > 0) text += " · ~%d".printf (modified);
            if (untracked > 0) text += " · ?%d".printf (untracked);
            if (conflicts > 0) text += " · !%d".printf (conflicts);
            if (stash > 0) text += " · stash %d".printf (stash);
            detail = branch + (upstream == "" ? "" : " → " + PromptContext.display_text (upstream)) +
                "\n%d staged · %d modified · %d untracked · %d conflicted\n%d ahead · %d behind · %d stashed".printf (
                    staged, modified, untracked, conflicts, ahead, behind, stash);
            if (staged + modified + untracked + conflicts == 0) detail += "\nWorking tree clean";
            summary = text;
        }
    }
}
