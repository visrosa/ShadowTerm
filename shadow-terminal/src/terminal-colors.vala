namespace Shadow {
    public class TerminalColors : Object {
        public const string[] KEYS = {"ansi-0", "ansi-1", "ansi-2", "ansi-3", "ansi-4", "ansi-5", "ansi-6", "ansi-7",
            "ansi-8", "ansi-9", "ansi-10", "ansi-11", "ansi-12", "ansi-13", "ansi-14", "ansi-15",
            "cursor", "cursor-text", "selection", "selection-text"};
        public const string[] LABELS = {"Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White",
            "Bright black", "Bright red", "Bright green", "Bright yellow", "Bright blue", "Bright magenta", "Bright cyan", "Bright white",
            "Cursor", "Cursor text", "Selection background", "Selection text"};
        private string[] values = new string[20];
        public string foreground = "#eeeeec";
        public string background = "#20242b";

        public TerminalColors () {
            // Match VTE's default 16-bit palette; keep special roles automatic.
            for (int i = 0; i < values.length; i++) {
                if (i >= 16) { values[i] = ""; continue; }
                float low = i > 7 ? 0x3fff / 65535.0f : 0;
                float high = i > 7 ? 1 : 0xc000 / 65535.0f;
                Gdk.RGBA color = {(i & 1) != 0 ? high : low, (i & 2) != 0 ? high : low, (i & 4) != 0 ? high : low, 1};
                values[i] = color.to_string ();
            }
        }

        public string get_color (int index) { return values[index]; }
        public void set_color (int index, string value) throws Error {
            if (index < 0 || index >= values.length) throw new IOError.INVALID_ARGUMENT ("Unknown color slot");
            if (index >= 16 && value == "") { values[index] = ""; return; }
            Gdk.RGBA color = {};
            if (value.length > 128 || !color.parse (value)) throw new IOError.INVALID_ARGUMENT ("Invalid color");
            color.alpha = 1;
            values[index] = color.to_string ();
        }
        public Gdk.RGBA[] palette () {
            var result = new Gdk.RGBA[16];
            for (int i = 0; i < 16; i++) result[i].parse (values[i]);
            return result;
        }
        public Gdk.RGBA? special (int index) {
            if (values[index] == "") return null;
            Gdk.RGBA color = {}; color.parse (values[index]); return color;
        }
        public void load (KeyFile file) {
            for (int i = 0; i < values.length; i++) {
                try { set_color (i, file.get_string ("terminal-colors", KEYS[i])); } catch (Error error) {}
            }
        }
        public void save (KeyFile file) {
            for (int i = 0; i < values.length; i++) file.set_string ("terminal-colors", KEYS[i], values[i]);
        }

        private static Xml.Node* element (Xml.Node* node) {
            while (node != null && node->type != Xml.ElementType.ELEMENT_NODE) node = node->next;
            return node;
        }
        private static HashTable<string, string> dictionary (Xml.Node* node) throws Error {
            if (node == null || node->name != "dict") throw new IOError.INVALID_DATA ("Expected an iTerm2 color dictionary");
            var result = new HashTable<string, string> (str_hash, str_equal);
            for (var key = element (node->children); key != null;) {
                var value = element (key->next);
                if (key->name != "key" || value == null) throw new IOError.INVALID_DATA ("Invalid iTerm2 dictionary");
                string name = key->get_content ();
                if (result.contains (name)) throw new IOError.INVALID_DATA ("Duplicate iTerm2 key: " + name);
                result.insert (name, value->get_content ());
                key = element (value->next);
            }
            return result;
        }
        private static string read_rgb (Xml.Node* node) throws Error {
            var fields = dictionary (node);
            var space = fields.lookup ("Color Space");
            if (space != null && space != "sRGB") throw new IOError.INVALID_DATA ("Only sRGB iTerm2 colors are supported");
            string[] keys = {"Red Component", "Green Component", "Blue Component"};
            float[] components = new float[3];
            for (int i = 0; i < keys.length; i++) {
                var text = fields.lookup (keys[i]); double number = 0;
                if (text == null || !double.try_parse (text.strip (), out number) || !number.is_finite () || number < 0 || number > 1)
                    throw new IOError.INVALID_DATA ("Invalid or missing " + keys[i]);
                components[i] = (float) number;
            }
            Gdk.RGBA color = {components[0], components[1], components[2], 1};
            return color.to_string ();
        }
        public static TerminalColors import_iterm (string text) throws Error {
            if (text.length == 0 || text.length > 262144 || text.contains ("<!ENTITY"))
                throw new IOError.INVALID_DATA ("Theme must be an XML iTerm2 preset under 256 KiB without entity declarations");
            // Do not load DTDs, substitute entities or resolve network resources.
            Xml.Doc* doc = Xml.Parser.read_memory (text, text.length, null, null,
                Xml.ParserOption.NONET | Xml.ParserOption.NOERROR | Xml.ParserOption.NOWARNING);
            if (doc == null) throw new IOError.INVALID_DATA ("Could not read the XML iTerm2 preset");
            try {
                var root = doc->get_root_element ();
                if (root == null || root->name != "plist") throw new IOError.INVALID_DATA ("Expected an XML iTerm2 plist");
                var dict = element (root->children);
                dictionary (dict);
                if (element (dict->next) != null) throw new IOError.INVALID_DATA ("Expected one preset dictionary");
                var result = new TerminalColors ();
                bool[] seen = new bool[22];
                string[] special_keys = {"Cursor Color", "Cursor Text Color", "Selection Color", "Selected Text Color", "Foreground Color", "Background Color"};
                for (var key = element (dict->children); key != null;) {
                    var value = element (key->next);
                    string name = key->get_content ();
                    int index = -1;
                    for (int i = 0; i < 16; i++) if (name == "Ansi %d Color".printf (i)) index = i;
                    for (int i = 0; i < special_keys.length; i++) if (name == special_keys[i]) index = 16 + i;
                    if (index >= 0) {
                        var color = read_rgb (value);
                        if (index < 20) result.set_color (index, color);
                        else if (index == 20) result.foreground = color;
                        else result.background = color;
                        seen[index] = true;
                    }
                    key = element (value->next);
                }
                for (int i = 0; i < seen.length; i++) {
                    if (!seen[i] && (i < 16 || i >= 20)) throw new IOError.INVALID_DATA ("Preset needs all 16 ANSI colors, foreground and background");
                }
                return result;
            } finally { delete doc; }
        }
    }
}
