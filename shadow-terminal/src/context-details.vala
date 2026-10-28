namespace Shadow {
    public enum ContextDetailsKind { DIRECTORY, GIT }
    public enum ContextActionKind { DIRECTORY, SWITCH_BRANCH, PULL, PUSH }

    public class ContextAction : Object {
        public ContextActionKind kind { get; private set; }
        public string directory { get; private set; }
        public string target { get; private set; }
        public ContextAction (ContextActionKind kind, string directory, string target = "") {
            this.kind = kind; this.directory = directory; this.target = target;
        }
        // Preparing source grants no execution authority. Only the session's
        // ordinary Send path can submit it to its authenticated consumer.
        public string command () {
            string cwd = VCom.LocalFilesProvider.fish_literal (directory);
            string value = VCom.LocalFilesProvider.fish_literal (target);
            switch (kind) {
            case ContextActionKind.DIRECTORY: return "cd -- " + value;
            case ContextActionKind.SWITCH_BRANCH: return "git -C " + cwd + " switch -- " + value;
            case ContextActionKind.PULL: return "git -C " + cwd + " pull --ff-only";
            case ContextActionKind.PUSH: return "git -C " + cwd + " push";
            default: return "";
            }
        }
    }

    public class ContextDetailsProvider : Object {
        public virtual async Json.Object query (ContextDetailsKind kind, string directory, Cancellable cancel) throws Error {
            var request = ContentService.make_request (kind == ContextDetailsKind.DIRECTORY ? "context-directory" : "context-git"); request.set_string_member ("cwd", directory);
            string? scratch = null;
            try {
                if (kind == ContextDetailsKind.DIRECTORY) {
                    scratch = DirUtils.make_tmp ("shadow-context-XXXXXX");
                    request.set_string_member ("scratch", scratch);
                }
                return (yield ContentService.request (request, directory, cancel)).get_object ();
            } finally {
                // The subprocess group has exited before request() unwinds, so
                // cancellation cannot leave a copied directory database behind.
                if (scratch != null) {
                    try {
                        var files = Dir.open (scratch);
                        string? name;
                        while ((name = files.read_name ()) != null) FileUtils.unlink (Path.build_filename (scratch, name));
                    } catch (FileError ignored) {}
                    DirUtils.remove (scratch);
                }
            }
        }
    }

    public class ContextDetailsPopover : Gtk.Popover {
        private ContextDetailsProvider provider;
        private ContextDetailsKind kind;
        private Gtk.Box contents = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
        private Cancellable? pending;
        private uint generation;
        public signal bool action_requested (ContextAction action, string origin_directory);

        public ContextDetailsPopover (ContextDetailsKind kind, ContextDetailsProvider? provider = null) {
            this.kind = kind; this.provider = provider ?? new ContextDetailsProvider ();
            add_css_class ("context-details");
            child = new Gtk.ScrolledWindow () {child = contents, hscrollbar_policy = Gtk.PolicyType.NEVER,
                min_content_width = 240, max_content_width = 380, max_content_height = 420,
                propagate_natural_width = true, propagate_natural_height = true};
            unmap.connect (cancel);
        }
        public void cancel () { generation++; if (pending != null) pending.cancel (); }
        private void clear () { while (contents.get_first_child () != null) contents.remove (contents.get_first_child ()); }
        private void text (string value) {
            contents.append (new Gtk.Label (PromptContext.display_text (value)) {xalign = 0, wrap = true, selectable = true, max_width_chars = 42});
        }
        private void prepare (string label, ContextAction action, string origin, bool available) {
            var button = new Gtk.Button () {has_frame = false, sensitive = available,
                child = new Gtk.Label (PromptContext.display_text (label)) {ellipsize = Pango.EllipsizeMode.MIDDLE, max_width_chars = 38}};
            button.add_css_class ("context-prepare");
            button.tooltip_text = "Prepare in Composer: " + PromptContext.display_text (label);
            button.clicked.connect (() => { if (action_requested (action, origin)) popdown (); });
            contents.append (button);
        }
        public async void load (string directory, bool available) {
            cancel (); clear (); text ("Loading…");
            uint version = generation;
            var cancel = new Cancellable (); pending = cancel;
            try {
                var result = yield provider.query (kind, directory, cancel);
                if (cancel.is_cancelled () || version != generation || !get_mapped ()) return;
                clear ();
                if (!available) text ("Commands can be prepared at a ready shell prompt.");
                if (kind == ContextDetailsKind.DIRECTORY) {
                    string group = "";
                    var entries = result.get_array_member ("entries");
                    for (uint i = 0; i < entries.get_length (); i++) {
                        var entry = entries.get_object_element (i);
                        string path = entry.get_string_member ("path");
                        string heading = entry.get_string_member ("group");
                        if (heading != group) { group = heading; text (group); }
                        prepare (path, new ContextAction (ContextActionKind.DIRECTORY, directory, path), directory, available);
                        var copy = new Gtk.Button.from_icon_name ("edit-copy-symbolic") {has_frame = false, tooltip_text = "Copy directory path"};
                        copy.clicked.connect (() => get_clipboard ().set_text (path));
                        // Keep a path's action and its non-executing copy option together.
                        var action = contents.get_last_child (); contents.remove (action);
                        var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
                        action.hexpand = true; row.append (action); row.append (copy); contents.append (row);
                    }
                    text (result.get_string_member ("notice"));
                } else {
                    string root = result.get_string_member ("root");
                    text (result.get_string_member ("summary"));
                    text (root);
                    text ("Working tree");
                    var files = result.get_array_member ("files");
                    if (files.get_length () == 0) text (result.get_int_member ("total") == 0 ? "Working tree clean" : "Changed files exceed the display limit");
                    for (uint i = 0; i < files.get_length (); i++) text (files.get_string_element (i));
                    text ("Local branches · select to prepare a switch command");
                    var branches = result.get_array_member ("branches");
                    for (uint i = 0; i < branches.get_length (); i++) {
                        var branch = branches.get_object_element (i);
                        string name = branch.get_string_member ("name");
                        prepare ((branch.get_boolean_member ("current") ? "Current: " : "") + name,
                            new ContextAction (ContextActionKind.SWITCH_BRANCH, root, name), directory,
                            available && !branch.get_boolean_member ("current"));
                    }
                    prepare ("Prepare Pull (fast-forward only)", new ContextAction (ContextActionKind.PULL, root), directory, available);
                    prepare ("Prepare Push", new ContextAction (ContextActionKind.PUSH, root), directory, available);
                    text ("Review and send the command in Composer. Git reports conflicts and authentication in the terminal.");
                }
                if (result.get_boolean_member ("truncated")) text ("Showing a bounded subset of results.");
            } catch (Error error) {
                if (!cancel.is_cancelled () && version == generation && get_mapped ()) { clear (); text ("Unavailable: " + error.message); }
            }
        }
    }
}
