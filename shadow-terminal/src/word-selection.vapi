namespace Shadow {
    [Compact]
    [CCode (cname = "ShadowWord", free_function = "shadow_word_free", cheader_filename = "word-selection.h")]
    public class WordSelection {
        [CCode (cname = "shadow_word_at")]
        public static WordSelection? at (Vte.Terminal terminal, double x, double y);
        [CCode (cname = "shadow_word_text")]
        public unowned string text ();
        [CCode (cname = "shadow_word_draw")]
        public void draw (Cairo.Context context);
    }

}
