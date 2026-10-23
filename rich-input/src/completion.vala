namespace VCom {
    // Provider offsets are Unicode character offsets, matching Gtk.TextBuffer.
    // The full immutable source/cursor snapshot lets consumers reject stale edits.
    public class CompletionContext : Object {
        public string source { get; private set; }
        public int cursor { get; private set; }
        public bool fish { get; private set; }
        public string directory { get; private set; }
        public int start { get; private set; default = 0; }
        public int end { get; private set; }
        public string prefix { get; private set; default = ""; }
        public bool simple { get; private set; default = true; }
        public bool literal { get; private set; default = true; }
        public bool query_safe { get; private set; default = true; }
        public string command_prefix { get; private set; default = ""; }

        public CompletionContext (string source, int cursor, bool fish, string directory) {
            this.source = source; this.cursor = cursor; this.fish = fish; this.directory = directory;
            end = cursor;
            if (cursor < 0 || cursor > source.char_count () || source.length > 65536) { simple = literal = query_safe = false; return; }
            unichar quote = 0;
            bool escaped = false;
            bool comment = false;
            int byte_offset = 0;
            int command_start = 0;
            for (int i = 0; i < cursor; i++) {
                unichar c;
                source.get_next_char (ref byte_offset, out c);
                if (comment) {
                    if (c == '\n') { comment = false; start = command_start = i + 1; simple = literal = true; }
                    continue;
                }
                if (escaped) { escaped = false; continue; }
                if (c == '\\' && (quote != '\'' || (byte_offset < source.length && (source[byte_offset] == '\'' || source[byte_offset] == '\\')))) { escaped = true; simple = false; continue; }
                if (quote != 0) {
                    if (c == quote) quote = 0;
                    else if (quote == '"' && c == '(') query_safe = false;
                    continue;
                }
                if (c == '\'' || c == '"') { quote = c; simple = false; continue; }
                if (c == '#' && i == start) { comment = true; simple = literal = false; continue; }
                if (c == '(' || c == '`') query_safe = false;
                if (separator (c)) {
                    start = i + 1; simple = literal = true;
                    if ("|;&\n".index_of_char (c) >= 0) command_start = i + 1;
                }
                else if ("$(){}[]*?`#".index_of_char (c) >= 0) simple = literal = false;
            }
            if (escaped) literal = false;
            if (quote != 0 || escaped) simple = false;
            while (byte_offset < source.length) {
                unichar c;
                source.get_next_char (ref byte_offset, out c);
                if (escaped) { escaped = false; end++; continue; }
                if (c == '\\' && (quote != '\'' || (byte_offset < source.length && (source[byte_offset] == '\'' || source[byte_offset] == '\\')))) { escaped = true; simple = false; end++; continue; }
                if (quote != 0) { if (c == quote) quote = 0; end++; continue; }
                if (c == '\'' || c == '"') { quote = c; simple = false; end++; continue; }
                if (separator (c)) break;
                if ("$(){}[]*?`#".index_of_char (c) >= 0) simple = literal = false;
                end++;
            }
            prefix = source.substring (source.index_of_nth_char (start),
                source.index_of_nth_char (cursor) - source.index_of_nth_char (start));
            command_prefix = source.substring (source.index_of_nth_char (command_start), source.index_of_nth_char (start) - source.index_of_nth_char (command_start));
        }

        private static bool separator (unichar c) {
            return c.isspace () || "|;&<>".index_of_char (c) >= 0;
        }
    }

    public class CompletionItem : Object {
        public string label;
        public string insertion;
        public string detail;
        public int start;
        public int end;
        public int cursor = -1;
        public CompletionItem (CompletionContext context, string label, string insertion, string detail) {
            start = context.start; end = context.end;
            this.label = label; this.insertion = insertion; this.detail = detail;
        }
    }

    public abstract class CompletionProvider : Object {
        public abstract async CompletionItem[] complete (CompletionContext context, Cancellable cancel) throws Error;
        public virtual CompletionItem? expand (CompletionContext context) { return null; }
    }

    public class BuiltinProvider : CompletionProvider {
        public override async CompletionItem[] complete (CompletionContext context, Cancellable cancel) throws Error {
            cancel.set_error_if_cancelled ();
            CompletionItem[] items = {};
            if (!context.simple) return items;
            string[] names = context.fish ?
                new string[] {"begin", "cd", "echo", "end", "for", "function", "if", "printf", "set", "string", "switch", "while"} :
                new string[] {"bold", "code", "heading", "italic", "link", "quote"};
            string[] insertions = context.fish ? names :
                new string[] {"**text**", "`code`", "# Heading", "*text*", "[text](https://example.org/)", "> Quote"};
            string[] details = context.fish ?
                new string[] {"begin; COMMANDS; end — group commands", "cd DIRECTORY — change working directory",
                    "echo ARGUMENTS — write arguments", "end — close a block", "for NAME in VALUES; COMMANDS; end — iterate",
                    "function NAME; COMMANDS; end — define a function", "if CONDITION; COMMANDS; end — conditional block",
                    "printf FORMAT ARGUMENTS — formatted output", "set NAME VALUES — shell variables",
                    "string SUBCOMMAND — string operations", "switch VALUE; case PATTERN; COMMANDS; end — choose a case",
                    "while CONDITION; COMMANDS; end — repeat a block"} :
                new string[] {"Strong emphasis", "Inline code", "ATX heading", "Emphasis", "Markdown link", "Block quotation"};
            for (int i = 0; i < names.length; i++)
                if (names[i].has_prefix (context.prefix))
                    items += new CompletionItem (context, names[i], insertions[i], details[i]);
            return items;
        }
    }

    public class LocalFilesProvider : CompletionProvider {
        public override async CompletionItem[] complete (CompletionContext context, Cancellable cancel) throws Error {
            CompletionItem[] items = {};
            if (!context.fish || !context.simple || context.directory == "") return items;
            string token = context.prefix;
            int slash = token.last_index_of_char ('/');
            string head = slash >= 0 ? token.substring (0, slash + 1) : "";
            string name = slash >= 0 ? token.substring (slash + 1) : token;
            string path = head;
            if (head.has_prefix ("~/")) path = Environment.get_home_dir () + head.substring (1);
            var directory = File.new_for_path (context.directory).resolve_relative_path (path == "" ? "." : path);
            var enumerator = yield directory.enumerate_children_async ("standard::name,standard::type",
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, cancel);
            Error? failure = null;
            try {
                // Bound metadata work even when a directory contains millions of files.
                for (int scanned = 0; scanned < 512 && items.length < 64; scanned += 64) {
                    var batch = yield enumerator.next_files_async (64, Priority.LOW, cancel);
                    if (batch == null) break;
                    foreach (var info in batch) {
                        string filename = info.get_name ();
                        if (!filename.validate () || !filename.has_prefix (name) ||
                            (filename.has_prefix (".") && !name.has_prefix (".")) ||
                            filename.contains ("\n") || filename.contains ("\r") || filename.contains ("\t")) continue;
                        bool folder = info.get_file_type () == FileType.DIRECTORY;
                        string value = head + filename + (folder ? "/" : "");
                        if (value.has_prefix ("~/")) value = Environment.get_home_dir () + value.substring (1);
                        items += new CompletionItem (context, filename + (folder ? "/" : ""),
                            fish_literal (value), folder ? "Directory" : "Local file");
                        if (items.length == 64) break;
                    }
                }
            } catch (Error error) { failure = error; }
            yield enumerator.close_async (Priority.LOW, null);
            if (failure != null) throw failure;
            return items;
        }

        public static string fish_literal (string value) {
            bool simple = value != "";
            for (int i = 0; i < value.length;) {
                unichar c;
                value.get_next_char (ref i, out c);
                if (!c.isalnum () && "_./-+".index_of_char (c) < 0) simple = false;
            }
            return simple ? value : "'" + value.replace ("\\", "\\\\").replace ("'", "\\'") + "'";
        }
    }
}
