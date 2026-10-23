public class Composer : Gtk.Application {
    private string? socket_path;
    private RichInput editor;
    private Vte.Terminal terminal;
    private Gtk.Label feedback;
    private Gtk.Button send_button;
    private Gtk.Button recall_button;
    private SocketConnection? connection;
    private InputStream? input;
    private ByteArray incoming = new ByteArray ();
    private bool ready = false;
    private bool sending = false;
    private string last_source = "";
    private string sent_source = "";

    public Composer (string? socket_path) {
        Object (application_id: "io.github.visrosa.Vibrant.RichInput",
                flags: ApplicationFlags.NON_UNIQUE);
        this.socket_path = socket_path;
    }

    protected override void activate () {
        Granite.init ();
        var settings = Granite.Settings.get_default ();
        var window = new Gtk.ApplicationWindow (this) {
            title = _("V Composer"), default_width = 920, default_height = 740
        };
        var header = new Gtk.HeaderBar ();
        var source_toggle = new Gtk.ToggleButton.with_label (_("Show Source"));
        var mode = new Gtk.DropDown.from_strings ({_("Markdown"), _("Fish")});
        header.pack_start (mode);
        header.pack_end (source_toggle);
        window.titlebar = header;
        editor = new RichInput () {vexpand = true};
        editor.dark = settings.prefers_color_scheme == Granite.Settings.ColorScheme.DARK;
        settings.notify["prefers-color-scheme"].connect (() => {
            editor.dark = settings.prefers_color_scheme == Granite.Settings.ColorScheme.DARK;
        });
        source_toggle.bind_property ("active", editor, "source-mode", BindingFlags.SYNC_CREATE);
        mode.notify["selected"].connect (() => { editor.fish_mode = mode.selected == 1; });
        // The source editor owns focus and all input. The VTE widget receives
        // bytes only; allowing it to reply to terminal queries would create a
        // second terminal authority competing with the launcher's real PTY.
        terminal = new Vte.Terminal () {vexpand = true, hexpand = true};
        terminal.set_input_enabled (false);
        terminal.set_scrollback_lines (10000);
        terminal.set_font (Pango.FontDescription.from_string ("monospace 11"));
        var shadow_scroll = new Gtk.ScrolledWindow () {child = terminal, min_content_height = 200};
        var edit_scroll = new Gtk.ScrolledWindow () {child = editor, min_content_height = 150};
        var prompt_label = new Gtk.Label.with_mnemonic (_("_Message")) {
            mnemonic_widget = editor, xalign = 0, margin_start = 18, margin_top = 12
        };
        var prompt = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        var assistance = new ComposerAssist (editor);
        header.pack_start (editor.formatting_toolbar ());
        var suggest = new Gtk.Button.from_icon_name ("insert-text-symbolic") {tooltip_text = "Suggestions (Ctrl+Space)", focus_on_click = false};
        suggest.clicked.connect (() => { editor.grab_focus (); assistance.request.begin (); });
        header.pack_end (suggest);
        prompt.append (prompt_label);
        prompt.append (edit_scroll);
        prompt.append (assistance.panel);
        var paned = new Gtk.Paned (Gtk.Orientation.VERTICAL) {
            start_child = shadow_scroll, end_child = prompt, position = 410,
            resize_start_child = true, resize_end_child = true, vexpand = true
        };
        send_button = new Gtk.Button.with_mnemonic (_("_Send")) {sensitive = false};
        send_button.add_css_class ("suggested-action");
        send_button.clicked.connect (submit);
        recall_button = new Gtk.Button.with_mnemonic (_("_Edit Last Prompt")) {sensitive = false};
        recall_button.clicked.connect (() => {
            // Recall never silently overwrites an unfinished draft.
            if (editor.source () == "") editor.buffer.insert_at_cursor (last_source, -1);
            editor.grab_focus ();
        });
        feedback = new Gtk.Label (socket_path == null ? _("Standalone editor") : _("Connecting…")) {
            hexpand = true, xalign = 0, wrap = true
        };
        var footer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            margin_start = 18, margin_end = 18, margin_top = 12, margin_bottom = 12
        };
        footer.append (feedback);
        footer.append (recall_button);
        footer.append (send_button);
        var root = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        if (socket_path != null) root.append (paned);
        else root.append (prompt);
        root.append (footer);
        window.child = root;
        var keys = new Gtk.EventControllerKey ();
        keys.key_pressed.connect ((key, code, modifiers) => {
            if (assistance.handle_key (key, modifiers)) return true;
            if ((modifiers & Gdk.ModifierType.CONTROL_MASK) != 0 && key == Gdk.Key.q) {
                window.close ();
                return true;
            }
            if ((modifiers & Gdk.ModifierType.CONTROL_MASK) != 0 && key == Gdk.Key.Return) {
                submit ();
                return true;
            }
            return false;
        });
        editor.add_controller (keys);
        editor.buffer.changed.connect (refresh_actions);
        window.close_request.connect (() => { disconnect_peer (); return false; });
        window.present ();
        editor.grab_focus ();
        if (socket_path != null) connect_peer.begin ();
    }

    private void refresh_actions () {
        send_button.sensitive = ready && !sending && editor.source () != "";
        recall_button.sensitive = last_source != "" && editor.source () == "";
    }

    private void disconnect_peer () {
        ready = false;
        sending = false;
        if (connection != null) {
            try { connection.close (); } catch (Error error) {}
            connection = null;
        }
        feedback.label = _("Disconnected — draft retained");
        refresh_actions ();
    }

    private async void connect_peer () {
        try {
            var client = new SocketClient ();
            connection = yield client.connect_async (new UnixSocketAddress (socket_path), null);
            input = connection.input_stream;
            yield write_message ("hello");
            while (connection != null) {
                string? line = yield read_frame ();
                if (line == null) break;
                var parser = new Json.Parser ();
                parser.load_from_data (line);
                var message = parser.get_root ().get_object ();
                if (message.get_int_member ("v") != 1) throw new IOError.INVALID_DATA ("Protocol version");
                switch (message.get_string_member ("type")) {
                    case "hello":
                        last_source = message.get_string_member ("source");
                        ready = message.get_boolean_member ("ready");
                        if (message.get_boolean_member ("truncated"))
                            terminal.feed (_("Earlier terminal output omitted\r\n").data);
                        update_ready ();
                        break;
                    case "ready":
                        ready = message.get_boolean_member ("ready");
                        update_ready ();
                        break;
                    case "terminal":
                        terminal.feed (Base64.decode (message.get_string_member ("data")));
                        break;
                    case "source":
                        last_source = message.get_string_member ("text");
                        break;
                    case "accepted":
                        sending = false;
                        // A user may continue typing while the acknowledgement
                        // is in flight. Clear only the draft actually sent.
                        if (editor.source () == sent_source) editor.buffer.text = "";
                        feedback.label = _("Prompt sent");
                        break;
                    case "error":
                        sending = false;
                        feedback.label = message.get_string_member ("message");
                        break;
                }
                refresh_actions ();
            }
            disconnect_peer ();
        } catch (Error error) {
            disconnect_peer ();
            feedback.label = _("Connection failed: %s").printf (error.message);
        }
    }

    private async string? read_frame () throws Error {
        while (true) {
            for (uint i = 0; i < incoming.len; i++) {
                if (incoming.data[i] != '\n') continue;
                uint8[] frame = new uint8[i + 1];
                Memory.copy (frame, incoming.data, i);
                incoming.remove_range (0, i + 1);
                string line = (string) frame;
                if (!line.validate ()) throw new IOError.INVALID_DATA ("Expected UTF-8");
                return line;
            }
            // Bound allocation before waiting for a delimiter, rather than
            // checking the length only after an unbounded read_line operation.
            if (incoming.len > 2 * 1024 * 1024) throw new IOError.INVALID_DATA ("Frame too large");
            var chunk = yield input.read_bytes_async (65536);
            if (chunk.get_size () == 0) return null;
            incoming.append (chunk.get_data ());
        }
    }

    private void update_ready () {
        feedback.label = ready ? _("Ready — Ctrl+Enter to send") : _("Waiting for cv — draft retained");
        refresh_actions ();
    }

    private async void write_message (string type, string? text = null) throws Error {
        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("v"); builder.add_int_value (1);
        builder.set_member_name ("type"); builder.add_string_value (type);
        if (text != null) {
            builder.set_member_name ("text"); builder.add_string_value (text);
        }
        builder.end_object ();
        var generator = new Json.Generator ();
        generator.set_root (builder.get_root ());
        var line = generator.to_data (null) + "\n";
        size_t written;
        yield connection.output_stream.write_all_async (line.data, Priority.DEFAULT, null, out written);
    }

    private void submit () {
        if (!ready || sending || editor.source () == "") return;
        sent_source = editor.source ();
        if (sent_source.length > 64 * 1024) {
            feedback.label = _("Message exceeds 64 KiB");
            return;
        }
        sending = true;
        refresh_actions ();
        write_message.begin ("submit", sent_source, (obj, result) => {
            try { write_message.end (result); }
            catch (Error error) { disconnect_peer (); }
        });
    }
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "");
    Intl.bindtextdomain ("vibrant-rich-input", "/usr/share/locale");
    Intl.textdomain ("vibrant-rich-input");
    string? socket_path = null;
    if (args.length == 3 && args[1] == "--socket") socket_path = args[2];
    else if (args.length != 1) {
        stderr.printf ("Usage: %s [--socket PATH]\n", args[0]);
        return 2;
    }
    var app = new Composer (socket_path);
    return app.run ({args[0]});
}
