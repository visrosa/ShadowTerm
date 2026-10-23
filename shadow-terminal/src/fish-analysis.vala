namespace Shadow {
    // Diagnostics describe an immutable draft. Neither parsing nor filesystem
    // checks execute source, and inconclusive expansion contexts stay unmarked.
    public class FishAnalysis : Object {
        public bool enabled { get; set; default = true; }
        private weak RichInput editor;
        public Gtk.Label status = new Gtk.Label ("") {xalign = 0, visible = false, ellipsize = Pango.EllipsizeMode.END};
        private uint debounce = 0;
        private Cancellable? pending;
        private uint generation = 0;

        public FishAnalysis (RichInput editor) {
            this.editor = editor;
            editor.buffer.changed.connect (schedule);
            editor.notify["working-directory"].connect (schedule);
            editor.notify["fish-mode"].connect (schedule);
            editor.map.connect (schedule);
            editor.unmap.connect (cancel);
            notify["enabled"].connect (schedule);
        }

        public void cancel () {
            generation++;
            if (debounce != 0) { Source.remove (debounce); debounce = 0; }
            if (pending != null) pending.cancel ();
            pending = null;
        }

        private void schedule () {
            cancel ();
            status.visible = false;
            editor.set_analysis (editor.source (), {});
            if (!enabled || !editor.get_mapped () || !editor.editable || !editor.fish_mode || editor.source () == "" || editor.source ().length > 16384) return;
            debounce = Timeout.add (300, () => { debounce = 0; refresh.begin (); return Source.REMOVE; });
        }

        private async void refresh () {
            uint version = generation;
            string text = editor.source (), directory = editor.working_directory;
            var cancel = new Cancellable ();
            pending = cancel;
            uint deadline = Timeout.add (1500, () => { cancel.cancel (); return Source.REMOVE; });
            RichSpan[] spans = {};
            string message = "", detail = "";
            try {
                string syntax = yield FishProvider.query ({"fish", "--no-config", "--no-execute"}, text, directory, cancel, "", "", true);
                if (syntax != "") { message = "Check fish syntax"; detail = syntax.strip (); }
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
                                    yield file.query_info_async ("standard::type", FileQueryInfoFlags.NONE, Priority.LOW, cancel);
                                    spans += new RichSpan ("path", start, end);
                                } catch (IOError.NOT_FOUND error) {
                                    if (required_input) {
                                        spans += new RichSpan ("diagnostic", start, end);
                                        if (message == "") { message = "Path does not exist: " + literal[0]; detail = "Advisory only; the command can still be run."; }
                                    }
                                } catch (IOError.NOT_DIRECTORY error) {
                                    if (required_input) {
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
                if (!(error is IOError.CANCELLED)) { message = "Analysis unavailable"; detail = error.message; }
            }
            var timer = MainContext.default ().find_source_by_id (deadline);
            if (timer != null) timer.destroy ();
            if (version != generation || cancel.is_cancelled () || text != editor.source () || directory != editor.working_directory) return;
            pending = null;
            editor.set_analysis (text, spans);
            status.label = message; status.tooltip_text = detail; status.visible = message != "";
        }
    }
}
