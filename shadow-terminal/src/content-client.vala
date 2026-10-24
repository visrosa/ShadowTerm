namespace Shadow {
    // All content queries run outside the command PTY. The existing worker
    // launcher bounds output/time and kills its private process group on exit.
    public class ContentService : Object {
        public static async Json.Node request (Json.Object data, string directory, Cancellable cancel) throws Error {
            var node = new Json.Node (Json.NodeType.OBJECT); node.set_object (data);
            string output = yield FishProvider.query ({"python3", CONTENT_SERVICE_PATH},
                Json.to_string (node, false), directory, cancel);
            var parser = new Json.Parser (); parser.load_from_data (output);
            var result = parser.get_root ().get_object ();
            if (result.has_member ("error")) throw new IOError.FAILED (result.get_string_member ("error"));
            return result.get_member ("result").copy ();
        }

        public static Json.Object make_request (string kind) {
            var data = new Json.Object (); data.set_string_member ("kind", kind); return data;
        }

        public static string configuration () {
            return Path.build_filename (Environment.get_user_config_dir (), "shadow-term", "documentation.json");
        }
    }

}
