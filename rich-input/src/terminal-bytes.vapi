// VTE accepts counted char bytes, including embedded NUL; its uint8 Vala
// binding otherwise emits a signedness mismatch against the C header.
namespace VCom.TerminalBytes {
    [CCode (cname = "vte_terminal_feed", cheader_filename = "vte/vte.h")]
    public static void feed (Vte.Terminal terminal, [CCode (array_length_type = "gssize")] char[] data);
    [CCode (cname = "vte_terminal_feed_child", cheader_filename = "vte/vte.h")]
    public static void feed_child (Vte.Terminal terminal, [CCode (array_length_type = "gssize")] char[] data);
}
