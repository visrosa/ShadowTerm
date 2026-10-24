namespace Shadow {
    public const string VERSION = "0.0.7";

    public errordomain OptionError { INVALID }

    // Requests contain argv, never a shell command assembled from text. The
    // same representation crosses the local application bus on later calls.
    public class Request : Object {
        public string session = "default";
        public string action = "show";
        public string cwd = Environment.get_current_dir ();
        public string title = "Shadow Term";
        public string[] command = {};
        public int width = 0;
        public int height = 0;
        public bool hide_on_blur = false;
        public bool hold = false;
        public bool explicit_command = false;
        public bool configured = false;
        public bool cwd_specified = false;
        public string input_mode = "auto";
        public bool input_specified = false;

        public static Request parse (string[] args) throws Error {
            var r = new Request ();
            bool action_seen = false;
            for (int i = 1; i < args.length; i++) {
                string arg = args[i];
                if (arg == "--") {
                    if (i + 1 == args.length) throw new OptionError.INVALID ("Expected a command after --");
                    r.command = args[i + 1:args.length];
                    r.explicit_command = true;
                    r.configured = true;
                    break;
                }
                if (arg == "--show" || arg == "--hide" || arg == "--toggle" ||
                    arg == "--quit" || arg == "--list") {
                    if (action_seen) throw new OptionError.INVALID ("Choose one session action");
                    r.action = arg.substring (2);
                    action_seen = true;
                } else if (arg == "--hide-on-focus-loss") {
                    r.hide_on_blur = true;
                    r.configured = true;
                } else if (arg == "--hold") {
                    r.hold = true;
                    r.configured = true;
                } else if (arg == "--session" || arg == "--cwd" || arg == "--title" || arg == "--size" || arg == "--input") {
                    if (++i == args.length) throw new OptionError.INVALID ("Missing value for %s", arg);
                    string value = args[i];
                    if (arg == "--session") r.session = value;
                    else if (arg == "--input") {
                        if (value != "auto" && value != "composer" && value != "terminal")
                            throw new OptionError.INVALID ("Input must be auto, composer or terminal");
                        r.input_mode = value; r.input_specified = true; r.configured = true;
                    }
                    else if (arg == "--cwd") {
                        r.cwd = Filename.canonicalize (value);
                        r.cwd_specified = true;
                        r.configured = true;
                    } else if (arg == "--title") {
                        r.title = value;
                        r.configured = true;
                    } else {
                        string[] parts = value.split ("x");
                        if (parts.length != 2 || !int.try_parse (parts[0], out r.width) ||
                            !int.try_parse (parts[1], out r.height) ||
                            r.width < 320 || r.height < 200 || r.width > 8192 || r.height > 8192)
                            throw new OptionError.INVALID ("Size must be WIDTHxHEIGHT, between 320x200 and 8192x8192");
                        r.configured = true;
                    }
                } else throw new OptionError.INVALID ("Unknown option: %s (commands follow --)", arg);
            }
            if (r.session.length == 0 || r.session.length > 80)
                throw new OptionError.INVALID ("Session names must contain 1–80 ASCII letters, digits, dots, dashes or underscores");
            foreach (uint8 byte in r.session.data)
                if (!(((char) byte).isalnum () || byte == '.' || byte == '-' || byte == '_'))
                    throw new OptionError.INVALID ("Invalid session name: %s", r.session);
            if (!FileUtils.test (r.cwd, FileTest.IS_DIR))
                throw new OptionError.INVALID ("Working directory does not exist: %s", r.cwd);
            if (r.input_mode == "composer" && !r.supports_composer ())
                throw new OptionError.INVALID ("Composer input requires an interactive fish command");
            if ((r.action == "hide" || r.action == "quit" || r.action == "list") && r.configured)
                throw new OptionError.INVALID ("This action does not accept launch options");
            return r;
        }

        public string[] argv () {
            if (explicit_command) return command;
            string? shell = Environment.get_variable ("SHELL");
            if (shell == null || shell == "") shell = "/bin/sh";
            return {shell};
        }

        public bool supports_composer () {
            string[] args = command.length > 0 ? command : argv ();
            if (Path.get_basename (args[0]) != "fish") return false;
            for (int i = 1; i < args.length; i++) {
                string arg = args[i];
                if (arg == "-C" || arg == "--init-command" || arg == "--init-cmd") { i++; continue; }
                if (arg.has_prefix ("--command") || arg == "--no-execute" || arg == "--version" || arg == "--help") return false;
                if (arg.has_prefix ("--init-command=") || arg.has_prefix ("--init-cmd=")) continue;
                if (!arg.has_prefix ("-")) return false;
                if (!arg.has_prefix ("--") && (arg.contains ("c") || arg.contains ("n") || arg.contains ("v") || arg.contains ("h"))) return false;
            }
            return true;
        }

        public bool composer_enabled () { return input_mode != "terminal" && supports_composer (); }

        public string encode () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("session"); b.add_string_value (session);
            b.set_member_name ("action"); b.add_string_value (action);
            b.set_member_name ("cwd"); b.add_string_value (cwd);
            b.set_member_name ("title"); b.add_string_value (title);
            b.set_member_name ("width"); b.add_int_value (width);
            b.set_member_name ("height"); b.add_int_value (height);
            b.set_member_name ("blur"); b.add_boolean_value (hide_on_blur);
            b.set_member_name ("hold"); b.add_boolean_value (hold);
            b.set_member_name ("explicit"); b.add_boolean_value (explicit_command);
            b.set_member_name ("configured"); b.add_boolean_value (configured);
            b.set_member_name ("cwd_specified"); b.add_boolean_value (cwd_specified);
            b.set_member_name ("input_mode"); b.add_string_value (input_mode);
            b.set_member_name ("input_specified"); b.add_boolean_value (input_specified);
            b.set_member_name ("argv"); b.begin_array ();
            foreach (string arg in argv ()) b.add_string_value (arg);
            b.end_array (); b.end_object ();
            var g = new Json.Generator ();
            g.set_root (b.get_root ());
            return g.to_data (null);
        }

        public static Request decode (string data) throws Error {
            var p = new Json.Parser (); p.load_from_data (data);
            var o = p.get_root ().get_object ();
            var r = new Request ();
            r.session = o.get_string_member ("session");
            r.action = o.get_string_member ("action");
            r.cwd = o.get_string_member ("cwd");
            r.title = o.get_string_member ("title");
            r.width = (int) o.get_int_member ("width"); r.height = (int) o.get_int_member ("height");
            r.hide_on_blur = o.get_boolean_member ("blur"); r.hold = o.get_boolean_member ("hold");
            r.explicit_command = o.get_boolean_member ("explicit"); r.configured = o.get_boolean_member ("configured");
            r.cwd_specified = o.get_boolean_member ("cwd_specified");
            r.input_mode = o.get_string_member ("input_mode");
            r.input_specified = o.get_boolean_member ("input_specified");
            var a = o.get_array_member ("argv");
            string[] command = {};
            for (uint i = 0; i < a.get_length (); i++) command += a.get_string_element (i);
            r.command = command;
            return r;
        }

        public bool compatible (Request existing) {
            if (explicit_command) {
                if (command.length != existing.command.length) return false;
                for (int i = 0; i < command.length; i++)
                    if (command[i] != existing.command[i]) return false;
            }
            return (!cwd_specified || cwd == existing.cwd) &&
                (width == 0 || width == existing.width) && (height == 0 || height == existing.height) &&
                (!hide_on_blur || existing.hide_on_blur) && (!hold || existing.hold) &&
                (!input_specified || input_mode == existing.input_mode) &&
                (title == "Shadow Term" || title == existing.title);
        }
    }

    public class Geometry : Object {
        public int width = 1000;
        public int height = 700;
        public int x;
        public int y;
        public bool positioned = false;

        private static string path () {
            return Path.build_filename (Environment.get_user_state_dir (), "shadow-term", "geometry.ini");
        }

        public Geometry (string name, int default_width = 1000, int default_height = 700) {
            width = default_width; height = default_height;
            try {
                var file = new KeyFile (); file.load_from_file (path (), KeyFileFlags.NONE);
                width = int.max (320, int.min (8192, file.get_integer (name, "width")));
                height = int.max (200, int.min (8192, file.get_integer (name, "height")));
                if (file.has_key (name, "x") && file.has_key (name, "y")) {
                    x = file.get_integer (name, "x"); y = file.get_integer (name, "y"); positioned = true;
                }
            } catch (Error error) {}
        }

        public void save (string name) {
            try {
                var file = new KeyFile ();
                try { file.load_from_file (path (), KeyFileFlags.NONE); } catch (Error error) {}
                file.set_integer (name, "width", width); file.set_integer (name, "height", height);
                if (positioned) { file.set_integer (name, "x", x); file.set_integer (name, "y", y); }
                DirUtils.create_with_parents (Path.get_dirname (path ()), 0700);
                FileUtils.set_contents (path (), file.to_data ());
            } catch (Error error) { warning ("Cannot save window geometry: %s", error.message); }
        }
    }
}
