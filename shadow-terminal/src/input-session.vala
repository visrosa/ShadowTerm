namespace Shadow {
    // The fish adapter supplies authentication and transport around the generic
    // exact-source request lifecycle; the editor imports neither adapter.
    public class InputSession : VCom.SourceSession {
        public InputSession () { base ("fish"); }
    }
}
