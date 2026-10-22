// All offsets at the parser boundary are UTF-8 byte offsets. GtkTextBuffer
// uses character offsets, so conversion happens only when tags are applied.
public class RichSpan : Object {
    public string tag;
    public int start;
    public int end;
    public RichSpan (string tag, int start, int end) {
        this.tag = tag;
        this.start = start;
        this.end = end;
    }
}

public class RichInput : Gtk.TextView {
    public bool source_mode { get; set; default = false; }
    public bool fish_mode { get; set; default = false; }
    public bool dark { get; set; default = false; }
    private bool restyling = false;

    public RichInput () {
        wrap_mode = Gtk.WrapMode.WORD_CHAR;
        left_margin = right_margin = 18;
        top_margin = bottom_margin = 12;
        buffer.enable_undo = true;
        buffer.create_tag ("bold", "weight", Pango.Weight.BOLD);
        buffer.create_tag ("italic", "style", Pango.Style.ITALIC);
        buffer.create_tag ("code", "family", "monospace");
        buffer.create_tag ("heading", "weight", Pango.Weight.BOLD, "scale", 1.3);
        buffer.create_tag ("hidden", "invisible", true);
        buffer.create_tag ("keyword", "weight", Pango.Weight.BOLD);
        buffer.create_tag ("string", "foreground", "#25703c");
        buffer.create_tag ("variable", "foreground", "#1c5eaa");
        buffer.create_tag ("comment", "style", Pango.Style.ITALIC);
        buffer.create_tag ("option", "underline", Pango.Underline.SINGLE);
        buffer.changed.connect (restyle);
        // Revealing punctuation on the cursor's line makes delimiters editable
        // without deleting invisible characters by accident.
        buffer.mark_set.connect ((iter, mark) => {
            if (mark == buffer.get_insert ()) restyle ();
        });
        notify["source-mode"].connect (restyle);
        notify["fish-mode"].connect (restyle);
        notify["dark"].connect (() => {
            buffer.tag_table.lookup ("string").foreground = dark ? "#8ff0a4" : "#25703c";
            buffer.tag_table.lookup ("variable").foreground = dark ? "#99c1f1" : "#1c5eaa";
        });
    }

    public string source () {
        Gtk.TextIter start, end;
        buffer.get_bounds (out start, out end);
        // include_hidden_chars is essential: visible text is not the source.
        return buffer.get_text (start, end, true);
    }

    private static bool overlaps (int start, int end, RichSpan[] spans) {
        foreach (var span in spans)
            if (start < span.end && end > span.start) return true;
        return false;
    }

    public static RichSpan[] parse (string text, bool fish) {
        RichSpan[] spans = {};
        try {
            if (fish) {
                var tokens = new Regex ("#[^\\n]*|\"(?:\\\\.|[^\"\\\\])*\"|'[^']*'|\\$[\\p{L}\\p{N}_]+|--?[\\p{L}][\\p{L}\\p{N}_-]*|\\b(?:if|else|end|for|while|function|set|and|or|not|begin|switch|case|in)\\b");
                MatchInfo match;
                tokens.match (text, 0, out match);
                while (match.matches ()) {
                    int start, end;
                    match.fetch_pos (0, out start, out end);
                    var token = match.fetch (0);
                    string tag = token.has_prefix ("#") ? "comment" :
                        token.has_prefix ("$") ? "variable" :
                        token.has_prefix ("-") ? "option" :
                        (token.has_prefix ("\"") || token.has_prefix ("'")) ? "string" : "keyword";
                    spans += new RichSpan (tag, start, end);
                    match.next ();
                }
                return spans;
            }

            // Opaque code ranges are recognized first, so Markdown-looking
            // characters inside them never become emphasis or headings.
            var fences = new Regex ("(?m)^(```+|~~~+)[^\\n]*\\n[\\s\\S]*?^\\1[ \\t]*(?:$|\\n)");
            MatchInfo found;
            fences.match (text, 0, out found);
            RichSpan[] opaque = {};
            while (found.matches ()) {
                int start, end;
                found.fetch_pos (0, out start, out end);
                spans += new RichSpan ("code", start, end);
                opaque += new RichSpan ("code", start, end);
                found.next ();
            }
            var code = new Regex ("(?<![\\\\`])(`+)([^`\\n]+)\\1(?!`)");
            code.match (text, 0, out found);
            while (found.matches ()) {
                int start, end, body_start, body_end;
                found.fetch_pos (0, out start, out end);
                found.fetch_pos (2, out body_start, out body_end);
                if (!overlaps (start, end, opaque)) {
                    spans += new RichSpan ("code", body_start, body_end);
                    spans += new RichSpan ("hidden", start, body_start);
                    spans += new RichSpan ("hidden", body_end, end);
                    opaque += new RichSpan ("code", start, end);
                }
                found.next ();
            }
            string[] patterns = {
                "(?m)^(#{1,6}[ \\t]+)([^\\n]+)$",
                "(?<![\\\\*])([*]{2})([^\\n]+?)\\1(?![*])",
                "(?<![\\\\*])([*])([^*\\n]+)\\1(?![*])"
            };
            string[] tags = {"heading", "bold", "italic"};
            for (int i = 0; i < patterns.length; i++) {
                var pattern = new Regex (patterns[i]);
                pattern.match (text, 0, out found);
                while (found.matches ()) {
                    int start, end, body_start, body_end;
                    found.fetch_pos (0, out start, out end);
                    found.fetch_pos (2, out body_start, out body_end);
                    if (!overlaps (start, end, opaque)) {
                        spans += new RichSpan (tags[i], body_start, body_end);
                        spans += new RichSpan ("hidden", start, body_start);
                        if (body_end < end) spans += new RichSpan ("hidden", body_end, end);
                        opaque += new RichSpan (tags[i], start, end);
                    }
                    found.next ();
                }
            }
        } catch (RegexError error) {
            warning ("Highlighter: %s", error.message);
        }
        return spans;
    }

    public void restyle () {
        if (restyling) return;
        restyling = true;
        Gtk.TextIter start, end, cursor;
        buffer.get_bounds (out start, out end);
        buffer.get_iter_at_mark (out cursor, buffer.get_insert ());
        int active_line = cursor.get_line ();
        string text = source ();
        buffer.remove_all_tags (start, end);
        foreach (var span in parse (text, fish_mode)) {
            buffer.get_iter_at_offset (out start, text.char_count (span.start));
            buffer.get_iter_at_offset (out end, text.char_count (span.end));
            if (span.tag == "hidden" && (source_mode || start.get_line () == active_line)) continue;
            buffer.apply_tag_by_name (span.tag, start, end);
        }
        monospace = source_mode || fish_mode;
        restyling = false;
    }
}
