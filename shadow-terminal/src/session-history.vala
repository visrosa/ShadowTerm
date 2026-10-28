namespace Shadow {
    // This model records confirmed focus independently of tabs or GTK widgets.
    // A cycle snapshot is immutable; closed targets are skipped via live IDs.
    public class SessionHistory : Object {
        private HashTable<string, bool> live = new HashTable<string, bool> (str_hash, str_equal);
        private List<string> recent = new List<string> ();
        private string[] snapshot = {};
        private int index;
        private string? confirmed;
        public string? requested { get; private set; }
        public bool cycling { get { return snapshot.length > 0; } }

        public void register (string id) {
            if (live.contains (id)) return;
            live.insert (id, true); recent.append (id);
        }
        public void remove (string id) {
            live.remove (id); forget (id);
            if (confirmed == id) confirmed = null;
            if (requested == id) requested = null;
        }
        private void forget (string id) {
            var retained = new List<string> ();
            foreach (var entry in recent) if (entry != id) retained.append (entry);
            recent = (owned) retained;
        }
        private void touch (string id) { forget (id); recent.prepend (id); }
        public void focused (string id) {
            if (!live.contains (id)) return;
            if (cycling && requested == id) { confirmed = id; return; }
            if (cycling) finish ();
            touch (id);
        }
        public string? step (string current, int direction) {
            if (!cycling) {
                if (!live.contains (current)) return null;
                snapshot = {current};
                foreach (var id in recent) if (id != current && live.contains (id)) snapshot += id;
                index = 0; confirmed = current;
            }
            for (int count = 0; count < snapshot.length; count++) {
                index = (index + direction + snapshot.length) % snapshot.length;
                if (live.contains (snapshot[index])) {
                    requested = snapshot[index]; return requested;
                }
            }
            finish (); return null;
        }
        public void finish () {
            if (confirmed != null && live.contains (confirmed)) touch (confirmed);
            snapshot = {}; confirmed = requested = null; index = 0;
        }
    }
}
