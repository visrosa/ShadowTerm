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
    public bool reveal_active_line { get; set; default = true; }
    public string working_directory { get; set; default = ""; }
    private bool restyling = false;
    private RichSpan[] analysis = {};
    private string analyzed_source = "";
    private Gtk.CssProvider font_css = new Gtk.CssProvider ();

    protected override void dispose () {
        // TextView does not own the layout of manually parented native popups.
        // Release these accessories before GTK checks for remaining children.
        var child = get_first_child ();
        while (child != null) {
            var next = child.get_next_sibling ();
            if (child is Gtk.Popover) child.unparent ();
            child = next;
        }
        base.dispose ();
    }

    public RichInput () {
        wrap_mode = Gtk.WrapMode.WORD_CHAR;
        left_margin = right_margin = 18;
        top_margin = bottom_margin = 12;
        buffer.enable_undo = true;
        get_style_context ().add_provider (font_css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
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
        buffer.create_tag ("command", "foreground", "#1c5eaa");
        buffer.create_tag ("path", "underline", Pango.Underline.SINGLE);
        buffer.create_tag ("diagnostic", "underline", Pango.Underline.ERROR, "underline-rgba", Gdk.RGBA () {red = 0.9f, green = 0.3f, blue = 0.3f, alpha = 1});
        buffer.changed.connect (restyle);
        // Revealing punctuation on the cursor's line makes delimiters editable
        // without deleting invisible characters by accident.
        buffer.mark_set.connect ((iter, mark) => {
            if (mark == buffer.get_insert ()) restyle ();
        });
        notify["source-mode"].connect (restyle);
        notify["fish-mode"].connect (restyle);
        notify["reveal-active-line"].connect (restyle);
        notify["dark"].connect (() => {
            buffer.tag_table.lookup ("string").foreground = dark ? "#8ff0a4" : "#25703c";
            buffer.tag_table.lookup ("variable").foreground = dark ? "#99c1f1" : "#1c5eaa";
            buffer.tag_table.lookup ("command").foreground = dark ? "#99c1f1" : "#1c5eaa";
        });
        var keys = new Gtk.EventControllerKey () {propagation_phase = Gtk.PropagationPhase.CAPTURE};
        keys.key_pressed.connect ((key, code, state) => {
            if (!editable || (state & Gdk.ModifierType.CONTROL_MASK) == 0) return false;
            if ((state & (Gdk.ModifierType.SHIFT_MASK | Gdk.ModifierType.ALT_MASK)) != 0) return false;
            switch (Gdk.keyval_to_lower (key)) {
            case Gdk.Key.b: return toggle_format ("**");
            case Gdk.Key.i: return toggle_format ("*");
            case Gdk.Key.grave: return toggle_format ("`");
            }
            return false;
        });
        add_controller (keys);
    }

    public void set_editor_font (string font) {
        var description = Pango.FontDescription.from_string (font);
        string family = description.get_family () ?? "Sans";
        // Font families are data, not CSS: escape quotes and line breaks.
        family = family.replace ("\\", "\\\\").replace ("\"", "\\\"").replace ("\n", " ").replace ("\r", " ");
        double size = description.get_size () / (double) Pango.SCALE;
        if (size <= 0) size = 12;
        string style = description.get_style () == Pango.Style.ITALIC ? "italic" :
            description.get_style () == Pango.Style.OBLIQUE ? "oblique" : "normal";
        font_css.load_from_string ("textview { font-family: \"%s\"; font-size: %s%s; font-weight: %d; font-style: %s; }".printf (
            family, size.to_string (), description.get_size_is_absolute () ? "px" : "pt", (int) description.get_weight (), style));
    }

    public Gtk.Box formatting_toolbar () {
        var tools = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        tools.add_css_class ("linked");
        var bold = new Gtk.Button.from_icon_name ("format-text-bold-symbolic") {tooltip_text = "Bold (Ctrl+B)", focus_on_click = false};
        var italic = new Gtk.Button.from_icon_name ("format-text-italic-symbolic") {tooltip_text = "Italic (Ctrl+I)", focus_on_click = false};
        var code = new Gtk.Button.with_label ("</>") {tooltip_text = "Inline Code (Ctrl+`)", focus_on_click = false};
        bold.clicked.connect (() => { toggle_format ("**"); grab_focus (); });
        italic.clicked.connect (() => { toggle_format ("*"); grab_focus (); });
        code.clicked.connect (() => { toggle_format ("`"); grab_focus (); });
        tools.append (bold); tools.append (italic); tools.append (code);
        bind_property ("fish-mode", tools, "visible", BindingFlags.SYNC_CREATE | BindingFlags.INVERT_BOOLEAN);
        return tools;
    }

    public bool toggle_format (string delimiter) {
        if (!editable || fish_mode || (delimiter != "**" && delimiter != "*" && delimiter != "`")) return false;
        Gtk.TextIter start, end;
        buffer.get_selection_bounds (out start, out end);
        int a = start.get_offset (), b = end.get_offset ();
        string selected = buffer.get_text (start, end, true);
        string text = source ();
        int width = delimiter.char_count ();
        bool wrapped_selection = selected.length >= delimiter.length * 2 &&
            selected.has_prefix (delimiter) && selected.has_suffix (delimiter);
        bool wrapped_outside = a >= width && b + width <= text.char_count () &&
            text.substring (text.index_of_nth_char (a - width), delimiter.length) == delimiter &&
            text.substring (text.index_of_nth_char (b), delimiter.length) == delimiter;
        buffer.begin_user_action ();
        if (wrapped_selection) {
            selected = selected.substring (delimiter.length, selected.length - 2 * delimiter.length);
            buffer.delete (ref start, ref end);
            buffer.insert (ref start, selected, -1);
            select_offsets (a, a + selected.char_count ());
        } else if (wrapped_outside) {
            buffer.get_iter_at_offset (out start, a - width);
            buffer.get_iter_at_offset (out end, b + width);
            buffer.delete (ref start, ref end);
            buffer.insert (ref start, selected, -1);
            select_offsets (a - width, b - width);
        } else {
            buffer.delete (ref start, ref end);
            buffer.insert (ref start, delimiter + selected + delimiter, -1);
            select_offsets (a + width, b + width);
        }
        buffer.end_user_action ();
        return true;
    }

    private void select_offsets (int a, int b) {
        Gtk.TextIter start, end;
        buffer.get_iter_at_offset (out start, a);
        buffer.get_iter_at_offset (out end, b);
        buffer.select_range (end, start);
    }

    public bool find_text (string query, bool backwards = false, bool match_case = false) {
        if (query == "") return false;
        Gtk.TextIter cursor, bound, start, end;
        buffer.get_selection_bounds (out cursor, out bound);
        if (!backwards) cursor = bound;
        Gtk.TextSearchFlags flags = match_case ? (Gtk.TextSearchFlags) 0 : Gtk.TextSearchFlags.CASE_INSENSITIVE;
        bool found = backwards ? cursor.backward_search (query, flags, out start, out end, null) :
            cursor.forward_search (query, flags, out start, out end, null);
        if (!found) {
            if (backwards) buffer.get_end_iter (out cursor); else buffer.get_start_iter (out cursor);
            found = backwards ? cursor.backward_search (query, flags, out start, out end, null) :
                cursor.forward_search (query, flags, out start, out end, null);
        }
        if (found) {
            buffer.select_range (end, start);
            scroll_to_iter (start, 0.1, false, 0, 0);
        }
        return found;
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
            if (span.tag == "hidden" && (source_mode || (reveal_active_line && start.get_line () == active_line))) continue;
            buffer.apply_tag_by_name (span.tag, start, end);
        }
        if (fish_mode && text == analyzed_source) {
            foreach (var span in analysis) {
                if (span.start < 0 || span.end < span.start || span.end > text.length) continue;
                buffer.get_iter_at_offset (out start, text.char_count (span.start));
                buffer.get_iter_at_offset (out end, text.char_count (span.end));
                buffer.apply_tag_by_name (span.tag, start, end);
            }
        }
        monospace = source_mode || fish_mode;
        restyling = false;
    }

    public void set_analysis (string source, RichSpan[] spans) {
        if (source != this.source ()) return;
        analyzed_source = source; analysis = spans;
        restyle ();
    }
}
