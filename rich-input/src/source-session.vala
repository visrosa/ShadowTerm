namespace VCom {
    // Editing, display and shell transport share source through this state
    // machine, rather than reconstructing it from terminal cells.
    public class SourceSession : Object {
        public string token { get; private set; }
        public bool ready { get; private set; default = false; }
        public bool pending { get { return source != null; } }
        private string? source;
        private bool taken = false;
        private uint deadline = 0;
        public signal void changed ();
        public signal void accepted (string source);
        public signal void rejected (string reason);

        private uint timeout_ms;
        private string consumer;

        public SourceSession (string consumer = "Consumer", uint timeout_ms = 3000) {
            this.consumer = consumer;
            this.timeout_ms = timeout_ms;
            token = Uuid.string_random ();
        }

        public void reset () {
            cancel ();
            token = Uuid.string_random ();
            ready = false;
            changed ();
        }

        public void prepare (string text) throws IOError {
            if (!ready || pending) throw new IOError.BUSY ("%s is not ready for another input".printf (consumer));
            if (text == "" || text.length > 65536)
                throw new IOError.INVALID_DATA ("Input must contain 1–65536 UTF-8 bytes");
            source = text;
            taken = false;
            deadline = Timeout.add (timeout_ms, () => {
                deadline = 0;
                reject ("%s did not accept the input; draft retained".printf (consumer));
                return Source.REMOVE;
            });
            changed ();
        }

        public string take (string credential) throws IOError {
            authenticate (credential);
            if (!ready || source == null || taken)
                throw new IOError.CLOSED ("No unclaimed input request");
            taken = true;
            return source;
        }

        public void report (string credential, string phase, string detail) throws IOError {
            authenticate (credential);
            switch (phase) {
            case "ready": ready = true; changed (); break;
            case "busy":
                ready = false;
                if (pending) reject ("%s became busy; draft retained".printf (consumer));
                changed ();
                break;
            case "accepted":
                if (source == null || !taken) throw new IOError.CLOSED ("Input request expired");
                string submitted = source;
                cancel ();
                ready = false;
                accepted (submitted);
                changed ();
                break;
            case "rejected":
                if (!pending) throw new IOError.CLOSED ("Input request expired");
                reject (detail);
                break;
            default: throw new IOError.INVALID_ARGUMENT ("Unknown consumer event");
            }
        }

        private void authenticate (string credential) throws IOError {
            if (credential != token) throw new IOError.PERMISSION_DENIED ("Stale consumer integration");
        }

        public void reject (string reason) {
            cancel ();
            changed ();
            rejected (reason);
        }

        public void cancel () {
            if (deadline != 0) { Source.remove (deadline); deadline = 0; }
            source = null;
            taken = false;
        }
    }

}
