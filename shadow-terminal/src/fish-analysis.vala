namespace Shadow {
    // One syntax process per editor and two across the application. New edits
    // replace the queued snapshot without repeatedly killing/forking a worker.
    public class FishAnalysis : Object {
        public bool enabled { get; set; default = true; }
        private weak RichInput editor;
        public Gtk.Label status = new Gtk.Label ("") {xalign = 0, visible = false, ellipsize = Pango.EllipsizeMode.END};
        private uint dispatch = 0;
        private Cancellable? syntax_cancel;
        private Cancellable? path_cancel;
        private uint generation = 0;
        private bool running = false;
        private bool queued = false;
        private static int workers = 0;
        private string syntax_message = "";
        private string syntax_detail = "";

        public FishAnalysis (RichInput editor) {
            this.editor = editor;
            editor.buffer.changed.connect (schedule);
            editor.notify["working-directory"].connect (schedule);
            editor.notify["fish-mode"].connect (schedule);
            editor.map.connect (schedule);
            editor.unmap.connect (cancel);
            notify["enabled"].connect (schedule);
        }

        private bool eligible () {
            return enabled && editor.get_mapped () && editor.editable && editor.fish_mode &&
                editor.source () != "" && editor.source ().length <= 16384;
        }

        public void cancel () {
            generation++; queued = false;
            if (dispatch != 0) { Source.remove (dispatch); dispatch = 0; }
            if (syntax_cancel != null) syntax_cancel.cancel ();
            if (path_cancel != null) path_cancel.cancel ();
        }

        private void schedule () {
            generation++;
            if (path_cancel != null) path_cancel.cancel ();
            status.visible = false;
            syntax_message = syntax_detail = "";
            editor.set_analysis (editor.source (), {});
            queued = eligible ();
            if (!queued) { cancel (); return; }
            // Run after the complete edit transaction (including abbreviation,
            // paste and IME commits), never from a raw Space key callback.
            if (dispatch == 0 && !running) dispatch = Idle.add (() => { dispatch = 0; launch (); return Source.REMOVE; });
        }

        private void launch () {
            if (!queued || !eligible () || running) return;
            if (workers >= 2) {
                dispatch = Timeout.add (16, () => { dispatch = 0; launch (); return Source.REMOVE; });
                return;
            }
            queued = false; running = true; workers++;
            refresh.begin ();
        }

        private bool current (uint version, string text, string directory) {
            return version == generation && eligible () && text == editor.source () && directory == editor.working_directory;
        }

        public virtual async string check_syntax (string text, string directory, Cancellable cancel) throws Error {
            return yield FishProvider.query ({"fish", "--no-config", "--no-execute"}, text, directory, cancel, "", "", true);
        }

        public virtual async void check_path (File file, Cancellable cancel) throws Error {
            yield file.query_info_async ("standard::type", FileQueryInfoFlags.NONE, Priority.LOW, cancel);
        }

        private async void refresh () {
            uint version = generation;
            string text = editor.source (), directory = editor.working_directory;
            var cancel = new Cancellable ();
            syntax_cancel = cancel;
            uint deadline = Timeout.add (1500, () => { cancel.cancel (); return Source.REMOVE; });
            string message = "", detail = "";
            try {
                string syntax = yield check_syntax (text, directory, cancel);
                if (syntax != "") { message = "Check fish syntax"; detail = syntax.strip (); }
            } catch (Error error) {
                if (!(error is IOError.CANCELLED)) { message = "Analysis unavailable"; detail = error.message; }
            }
            var timer = MainContext.default ().find_source_by_id (deadline);
            if (timer != null) timer.destroy ();
            syntax_cancel = null; running = false; workers--;
            if (current (version, text, directory) && !cancel.is_cancelled ()) {
                syntax_message = message; syntax_detail = detail;
                status.label = message; status.tooltip_text = detail; status.visible = message != "";
                paths.begin (version, text, directory);
            }
            launch ();
        }

        private async void paths (uint version, string text, string directory) {
            var cancel = new Cancellable ();
            path_cancel = cancel;
            uint deadline = Timeout.add (1500, () => { cancel.cancel (); return Source.REMOVE; });
            RichSpan[] spans = {};
            string message = "", detail = "";
            try {
                var regex = new Regex ("#[^\\n]*|'(?:\\\\.|[^'\\\\])*'|\"(?:\\\\.|[^\"\\\\])*\"|[^\\s;|&<>]+|[;|&<>]");
                MatchInfo match;
                regex.match (text, 0, out match);
                string command = "";
                bool output = false, redirected = false;
                bool ambiguous_options = false, options_ended = false;
                int checked = 0;
                while (match.matches () && checked < 32) {
                    cancel.set_error_if_cancelled ();
                    int start, end; match.fetch_pos (0, out start, out end);
                    string token = match.fetch (0);
                    if (token.has_prefix ("#")) { match.next (); continue; }
                    if (token == ";" || token == "|" || token == "&") { command = ""; output = redirected = ambiguous_options = options_ended = false; }
                    else if (token == ">" || token == "<") { output = token == ">"; redirected = true; }
                    else {
                        bool is_command = command == "" && !redirected;
                        if (is_command) { command = token; spans += new RichSpan ("command", start, end); }
                        bool explicit_path = token.has_prefix ("./") || token.has_prefix ("../") || token.has_prefix ("/") || token.has_prefix ("~/");
                        bool input_command = "|cat|less|more|head|tail|stat|file|source|cd|ls|".contains ("|" + command + "|");
                        bool dynamic = token.contains ("$") || token.contains ("(") || token.contains ("*") || token.contains ("[") || token.contains ("\\");
                        bool option = !options_ended && token.has_prefix ("-");
                        if (token == "--" && !options_ended) { options_ended = true; ambiguous_options = false; }
                        else if (option && !token.contains ("=")) ambiguous_options = true;
                        bool required_input = (input_command && !is_command && !ambiguous_options) || redirected || (is_command && explicit_path);
                        if (!output && !dynamic && !option && token != "-" && (explicit_path || required_input)) {
                            var literal = FishProvider.words (token);
                            if (literal.length == 1 && literal[0] != "") {
                                string path = literal[0];
                                if (path.has_prefix ("~/")) path = Environment.get_home_dir () + path.substring (1);
                                var file = File.new_for_path (directory).resolve_relative_path (path);
                                try {
                                    yield check_path (file, cancel);
                                    spans += new RichSpan ("path", start, end);
                                } catch (IOError.NOT_FOUND error) {
                                    if (required_input && end < text.length) {
                                        spans += new RichSpan ("diagnostic", start, end);
                                        if (message == "") { message = "Path does not exist: " + literal[0]; detail = "Advisory only; the command can still be run."; }
                                    }
                                } catch (IOError.NOT_DIRECTORY error) {
                                    if (required_input && end < text.length) {
                                        spans += new RichSpan ("diagnostic", start, end);
                                        if (message == "") message = "A path component is not a directory";
                                    }
                                }
                                checked++;
                            }
                        }
                        if (redirected) { output = redirected = false; }
                    }
                    // A newline starts a new command even though regex whitespace
                    // also skips indentation, tabs and ordinary token separators.
                    int next = end;
                    while (next < text.length && text[next].isspace ()) {
                        if (text[next] == '\n') { command = ""; ambiguous_options = options_ended = false; }
                        next++;
                    }
                    match.next ();
                }
            } catch (Error error) {
                // Metadata is advisory; inconclusive or cancelled work does not
                // overwrite an independently published syntax diagnostic.
            }
            var timer = MainContext.default ().find_source_by_id (deadline);
            if (timer != null) timer.destroy ();
            if (!current (version, text, directory) || cancel.is_cancelled ()) return;
            path_cancel = null;
            editor.set_analysis (text, spans);
            status.label = syntax_message != "" ? syntax_message : message;
            status.tooltip_text = syntax_message != "" ? syntax_detail : detail;
            status.visible = status.label != "";
        }
    }
}
