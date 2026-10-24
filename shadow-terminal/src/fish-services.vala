namespace Shadow {
    // Query workers receive only shell-generated definitions as program text.
    // A draft is always an argv/stdin data value, never part of that program.
    public class FishProvider : VCom.CompletionProvider {
        public bool enabled { get; set; default = true; }
        private string definitions = "";
        private string complete_path = "";
        private string function_path = "";
        private Abbreviation[] abbreviations = {};

        public void configure (string abbrs, string completions, string paths, string functions) {
            if (abbrs.length + completions.length + paths.length + functions.length > 131072) return;
            definitions = completions;
            complete_path = paths; function_path = functions;
            abbreviations = {};
            foreach (string line in abbrs.split ("\n")) {
                var words = words (line);
                if (words.length < 5 || words[0] != "abbr") continue;
                string position = "command", marker = "";
                string[] commands = {};
                bool supported = true;
                int index = 2;
                while (index < words.length && words[index] != "--") {
                    string option = words[index++];
                    if (option == "--position" && index < words.length) position = words[index++];
                    else if ((option == "--command" || option == "-c") && index < words.length) { commands += words[index++]; position = "anywhere"; }
                    else if (option == "--description" && index < words.length) index++;
                    else if (option.has_prefix ("--description=")) continue;
                    else if (option == "--set-cursor") marker = "%";
                    else if (option.has_prefix ("--set-cursor=")) marker = option.substring (13);
                    else { supported = false; break; }
                }
                if (!supported || index + 2 >= words.length) continue;
                index++;
                string expansion = string.joinv (" ", words[index + 1:words.length]);
                abbreviations += new Abbreviation (words[index], expansion, position, commands, marker);
            }
            foreach (var abbr in abbreviations) {
                definitions += "\nabbr -a --position " + abbr.position;
                foreach (var command in abbr.commands) definitions += " --command " + VCom.LocalFilesProvider.fish_literal (command);
                definitions += " -- " + VCom.LocalFilesProvider.fish_literal (abbr.name) + " " + VCom.LocalFilesProvider.fish_literal (abbr.expansion) + "\n";
            }
        }

        // fish's exported single-quoted literals allow escaped quote/backslash,
        // unlike POSIX sh. Do not feed this serialization to Shell.parse_argv.
        internal static string[] words (string text) {
            string[] result = {};
            var word = new StringBuilder ();
            unichar quote = 0;
            bool active = false;
            for (int i = 0; i < text.length;) {
                unichar c; text.get_next_char (ref i, out c);
                if (c == '\\' && i < text.length) {
                    unichar next; text.get_next_char (ref i, out next);
                    if (quote == '\'' && next != '\\' && next != '\'') word.append_unichar ('\\');
                    if (quote == 0) {
                        if (next == 'n') next = '\n';
                        else if (next == 't') next = '\t';
                        else if (next == 'r') next = '\r';
                        else if (next == 'e') next = 0x1b;
                        else if (next == 'b') next = '\b';
                        else if (next == 'a') next = 7;
                        else if (next == 'v') next = 11;
                        else if (next == 'f') next = 12;
                    }
                    word.append_unichar (next); active = true;
                } else if (quote != 0) {
                    if (c == quote) quote = 0; else word.append_unichar (c);
                } else if (c == '\'' || c == '"') { quote = c; active = true; }
                else if (c.isspace ()) {
                    if (active) { result += word.str; word.truncate (0); active = false; }
                } else { word.append_unichar (c); active = true; }
            }
            if (quote != 0) return {};
            if (active) result += word.str;
            return result;
        }

        public override VCom.CompletionItem? expand (VCom.CompletionContext context) {
            if (!enabled || !context.fish || !context.simple || context.cursor != context.end) return null;
            string before = context.command_prefix;
            string[] preceding = words (before);
            bool command_position = before.strip () == "";
            foreach (var abbr in abbreviations) {
                bool command_matches = abbr.commands.length == 0;
                foreach (var command in abbr.commands)
                    if ((preceding.length == 0 ? "" : preceding[0]) == command) command_matches = true;
                if (abbr.name != context.prefix || (abbr.position == "command" && !command_position) ||
                    !command_matches) continue;
                var item = new VCom.CompletionItem (context, abbr.name, abbr.expansion, "Abbreviation");
                if (abbr.marker != "") {
                    int marker = item.insertion.index_of (abbr.marker);
                    if (marker >= 0) {
                        item.cursor = item.insertion.char_count (marker);
                        item.insertion = item.insertion.substring (0, marker) + item.insertion.substring (marker + abbr.marker.length);
                    }
                }
                return item;
            }
            return null;
        }

        private bool truncated;
        public override async VCom.CompletionBatch complete_batch (VCom.CompletionContext context, Cancellable cancel) throws Error {
            var values = yield complete (context, cancel);
            return new VCom.CompletionBatch (values, truncated ? VCom.CompletionState.TRUNCATED : VCom.CompletionState.COMPLETE);
        }

        public override async string preview (VCom.CompletionContext context, VCom.CompletionItem item, Cancellable cancel) throws Error {
            var request = new Json.Object ();
            request.set_string_member ("kind", "preview");
            request.set_string_member ("value", item.preview_value);
            request.set_string_member ("cwd", context.directory);
            request.set_string_member ("description", item.detail);
            request.set_string_member ("preview_kind", item.preview_kind);
            return (yield ContentService.request (request, context.directory, cancel)).get_string ();
        }

        public override async VCom.CompletionItem[] complete (VCom.CompletionContext context, Cancellable cancel) throws Error {
            truncated = false;
            if (!enabled || !context.fish) return yield new VCom.BuiltinProvider ().complete (context, cancel);
            // Fish returns a complete escaped token, including an opening quote.
            // Skip substitutions anywhere in the query rather than expanding a
            // draft as a side effect of asking for suggestions.
            if (!context.literal || !context.query_safe) return {};
            string source = context.source.substring (0, context.source.index_of_nth_char (context.cursor));
            string setup = "set -g fish_complete_path (string split : -- \"$VCOM_COMPLETE_PATH\"); set -g fish_function_path (string split : -- \"$VCOM_FUNCTION_PATH\"); source /dev/stdin; complete --escape --do-complete \"$argv[1]\"";
            string output = yield query ({"fish", "--no-config", "-c", setup, source}, definitions, context.directory, cancel, complete_path, function_path);
            VCom.CompletionItem[] items = {};
            foreach (string line in output.split ("\n")) {
                if (line == "") continue;
                if (items.length >= 128) { truncated = true; break; }
                int tab = line.index_of_char ('\t');
                string insertion = tab < 0 ? line : line.substring (0, tab);
                // --escape provides fish source, including literal filenames.
                string description = tab < 0 ? "" : line.substring (tab + 1);
                // Prefix/suffix constraints prevent a mid-token completion from
                // dropping source that the prefix-only fish query never saw.
                string suffix = context.source.substring (context.source.index_of_nth_char (context.cursor),
                    context.source.index_of_nth_char (context.end) - context.source.index_of_nth_char (context.cursor));
                if (suffix != "" && !insertion.has_suffix (suffix)) continue;
                var item = new VCom.CompletionItem (context, insertion, insertion,
                    description == "" ? "Fish completion" : description);
                item.id = insertion; item.provenance = "fish";
                var values = words (insertion);
                if (values.length == 1) {
                    item.preview_value = values[0];
                    item.continue_after = values[0].has_suffix ("/");
                    item.kind = item.continue_after ? "directory" : "";
                    if (context.command_prefix.strip ().has_prefix ("git ")) item.preview_kind = "git";
                }
                items += item;
            }
            return items;
        }

        internal static async string query (string[] argv, string input, string directory, Cancellable cancel,
                                             string complete_path = "", string function_path = "", bool diagnostics = false) throws Error {
            var launcher = new SubprocessLauncher (SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_PIPE | (diagnostics ? SubprocessFlags.STDERR_MERGE : SubprocessFlags.STDERR_SILENCE));
            if (directory != "") launcher.set_cwd (directory);
            launcher.setenv ("VCOM_COMPLETE_PATH", complete_path, true);
            launcher.setenv ("VCOM_FUNCTION_PATH", function_path, true);
            launcher.setenv ("fish_history", "", true);
            launcher.set_child_setup (() => { Posix.setsid (); });
            var process = launcher.spawnv (argv);
            int pid = int.parse (process.get_identifier ());
            uint deadline = Timeout.add (1200, () => { cancel.cancel (); return Source.REMOVE; });
            try {
                yield process.get_stdin_pipe ().write_all_async (input.data, Priority.LOW, cancel, null);
                yield process.get_stdin_pipe ().close_async (Priority.LOW, cancel);
                var bytes = new ByteArray ();
                while (true) {
                    var block = yield process.get_stdout_pipe ().read_bytes_async (4096, Priority.LOW, cancel);
                    if (block.get_size () == 0) break;
                    if (bytes.len + block.get_size () > 65536) throw new IOError.NO_SPACE ("Fish assistance output exceeds its limit");
                    bytes.append (block.get_data ());
                }
                yield process.wait_async (cancel);
                bytes.append ({0});
                string output = (string) bytes.data;
                if (!output.validate ()) throw new IOError.INVALID_DATA ("Fish assistance returned invalid text");
                return output;
            } finally {
                var timer = MainContext.default ().find_source_by_id (deadline);
                if (timer != null) timer.destroy ();
                // Completion functions may have launched descendants. The worker
                // owns a private process group, distinct from the interactive PTY.
                Posix.kill (-pid, Posix.Signal.KILL);
                process.force_exit ();
                try { yield process.wait_async (null); } catch (Error ignored) {}
            }
        }
    }

    public class NativeProvider : VCom.CompletionProvider {
        public bool enabled = false;
        public override async VCom.CompletionItem[] complete (VCom.CompletionContext context, Cancellable cancel) throws Error {
            return (yield complete_batch (context, cancel)).items;
        }

        public override async VCom.CompletionBatch complete_batch (VCom.CompletionContext context, Cancellable cancel) throws Error {
            if (!enabled || !context.fish || !context.literal || !context.query_safe) return new VCom.CompletionBatch ({});
            if (!FileUtils.test (Path.build_filename (Environment.get_user_config_dir (), "shadow-term", "completions"), FileTest.IS_DIR))
                return new VCom.CompletionBatch ({}, VCom.CompletionState.COMPLETE);
            var data = ContentService.make_request ("lookup");
            data.set_string_member ("source", context.command_prefix);
            data.set_int_member ("cursor", context.command_prefix.char_count ());
            var lookup = yield ContentService.request (data, context.directory, cancel);
            var object = lookup.get_object ();
            object.set_string_member ("prefix", context.prefix);
            object.set_string_member ("suffix", context.source.substring (context.source.index_of_nth_char (context.cursor),
                context.source.index_of_nth_char (context.end) - context.source.index_of_nth_char (context.cursor)));
            object.set_string_member ("cwd", context.directory);
            data = ContentService.make_request ("complete");
            data.set_member ("context", lookup);
            data.set_string_member ("config", Path.build_filename (Environment.get_user_config_dir (), "shadow-term", "completions"));
            var result = (yield ContentService.request (data, context.directory, cancel)).get_object ();
            VCom.CompletionItem[] items = {};
            var values = result.get_array_member ("items");
            for (uint i = 0; i < values.get_length (); i++) {
                var value = values.get_object_element (i);
                string literal = value.get_string_member ("value");
                var item = new VCom.CompletionItem (context, literal, VCom.LocalFilesProvider.fish_literal (literal), value.get_string_member ("description"));
                item.id = literal; item.provenance = "native";
                if (value.has_member ("kind")) item.kind = value.get_string_member ("kind");
                if (value.has_member ("group")) item.group = value.get_string_member ("group");
                item.preview_value = value.has_member ("preview") ? value.get_string_member ("preview") : literal;
                item.continue_after = value.has_member ("continue") && value.get_boolean_member ("continue");
                items += item;
            }
            bool complete = result.get_boolean_member ("complete");
            if (result.get_boolean_member ("matched") && result.get_boolean_member ("files")) {
                foreach (var item in yield new VCom.LocalFilesProvider ().complete (context, cancel)) {
                    item.id = item.insertion; item.provenance = "local";
                    var literal = FishProvider.words (item.insertion);
                    if (literal.length == 1) item.preview_value = literal[0];
                    item.continue_after = item.label.has_suffix ("/");
                    items += item;
                }
                // The legacy bounded enumerator cannot establish completeness.
                complete = false;
            }
            var batch = new VCom.CompletionBatch (items, complete ? VCom.CompletionState.COMPLETE : VCom.CompletionState.TRUNCATED, result.get_string_member ("message"));
            batch.authoritative = result.get_boolean_member ("matched");
            return batch;
        }

        public override async string preview (VCom.CompletionContext context, VCom.CompletionItem item, Cancellable cancel) throws Error {
            return yield new FishProvider ().preview (context, item, cancel);
        }
    }

    private class Abbreviation : Object {
        public string name; public string expansion; public string position; public string[] commands; public string marker;
        public Abbreviation (string name, string expansion, string position, string[] commands, string marker) {
            this.name = name; this.expansion = expansion; this.position = position; this.commands = commands; this.marker = marker;
        }
    }
}
