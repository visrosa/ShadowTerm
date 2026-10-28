namespace Shadow {
    // This snapshot contains only named prompt fields. It is never a dump of
    // the shell environment and never supplies executable text to a provider.
    public class PromptContext : Object {
        public bool has_result { get; private set; default = false; }
        public int exit_status { get; private set; default = 0; }
        public string pipeline { get; private set; default = ""; }
        public int64 duration_ms { get; private set; default = 0; }
        public string virtual_env { get; private set; default = ""; }
        public string conda_env { get; private set; default = ""; }
        public bool ssh { get; private set; default = false; }
        public int jobs { get; private set; default = 0; }
        public string user { get; private set; default = ""; }
        public string hostname { get; private set; default = ""; }
        public signal void changed ();

        public static string display_text (string value) {
            var text = new StringBuilder ();
            for (int i = 0; i < value.length && text.len < 512;) {
                unichar c; value.get_next_char (ref i, out c);
                if (!c.iscntrl ()) text.append_unichar (c);
            }
            return text.str;
        }

        private static bool number (string value, out int64 parsed) {
            parsed = 0;
            if (value == "" || value.length > 16) return false;
            foreach (uint8 c in value.data) if (c < '0' || c > '9') return false;
            return int64.try_parse (value, out parsed);
        }

        public bool update (string[] fields) {
            if (fields.length != 10) return false;
            int size = 0;
            foreach (string field in fields) { size += field.length; if (!field.validate () || size > 8192) return false; }
            if (fields[0] != "0" && fields[0] != "1") return false;
            int64 status = 0, duration = 0, count = 0;
            if (!number (fields[1], out status) || status > 65535 ||
                !number (fields[3], out duration) || !number (fields[7], out count) || count > 65535) return false;
            string[] codes = fields[2].split (",");
            if (codes.length > 128) return false;
            foreach (string code in codes) { int64 part; if (!number (code, out part) || part > 65535) return false; }
            if (fields[6] != "0" && fields[6] != "1") return false;
            has_result = fields[0] == "1";
            exit_status = (int) status;
            pipeline = string.joinv ("|", codes);
            duration_ms = duration;
            virtual_env = display_text (fields[4]); conda_env = display_text (fields[5]);
            ssh = fields[6] == "1"; jobs = (int) count;
            user = display_text (fields[8]); hostname = display_text (fields[9]);
            changed ();
            return true;
        }

        public string result_summary () {
            if (!has_result) return "";
            bool pipeline_failed = false;
            foreach (string code in pipeline.split ("|")) if (code != "0") pipeline_failed = true;
            if (exit_status != 0) return "exit %d".printf (exit_status);
            return pipeline_failed ? "pipe " + pipeline : "";
        }

        public string duration_summary () {
            if (!has_result || duration_ms < 1000) return "";
            if (duration_ms < 60000) return "%.1f s".printf (duration_ms / 1000.0);
            return ("%" + int64.FORMAT + " m %02" + int64.FORMAT + " s").printf (duration_ms / 60000, (duration_ms / 1000) % 60);
        }

        public string environment_summary () {
            string text = "";
            if (virtual_env != "") text = "venv " + Path.get_basename (virtual_env);
            if (conda_env != "") text += (text == "" ? "" : " · ") + "conda " + Path.get_basename (conda_env);
            return text;
        }

        public string identity_summary () {
            if (user == "" && hostname == "") return "";
            return (ssh ? "SSH · " : "") + user + (user != "" && hostname != "" ? "@" : "") + hostname;
        }
    }
}
