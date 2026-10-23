namespace Shadow {
    [DBus (name = "io.github.visrosa.Vibrant.Shell1")]
    public class ShellBridge : Object {
        private weak Host host;
        public ShellBridge (Host host) { this.host = host; }

        public string get_state (string session) throws DBusError, IOError {
            return host.input_status (session);
        }

        public string take_input (string session, string token, int pid) throws DBusError, IOError {
            return host.shell_window (session, pid).input_session.take (token);
        }

        public bool get_presentation (string session, string token, int pid) throws DBusError, IOError {
            var window = host.shell_window (session, pid);
            if (token != window.input_session.token) throw new IOError.PERMISSION_DENIED ("Expired shell identity");
            return window.composer_active ();
        }

        public void metadata (string session, string token, int pid, string abbreviations, string completions, string paths, string functions) throws DBusError, IOError {
            var window = host.shell_window (session, pid);
            if (token != window.input_session.token) throw new IOError.PERMISSION_DENIED ("Expired shell identity");
            window.shell_metadata (abbreviations, completions, paths, functions);
        }

        public void report (string session, string token, int pid, string phase, string detail) throws DBusError, IOError {
            var window = host.shell_window (session, pid);
            window.input_session.report (token, phase, detail);
            if (phase == "ready") window.shell_directory (detail);
        }
    }
}
