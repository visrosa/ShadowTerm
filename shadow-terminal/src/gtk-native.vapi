// These declarations retain the C headers' pointer types where the installed
// Vala 0.56 bindings lose array constness or the GtkWidget upcast.
namespace Shadow.Native {
    // These display-level functions remain supported even though their Vala
    // container class is deprecated along with per-widget style contexts.
    [CCode (cname = "gtk_style_context_add_provider_for_display", cheader_filename = "gtk/gtk.h")]
    public static void add_css (Gdk.Display display, Gtk.StyleProvider provider, uint priority);
    [CCode (cname = "gtk_style_context_remove_provider_for_display", cheader_filename = "gtk/gtk.h")]
    public static void remove_css (Gdk.Display display, Gtk.StyleProvider provider);
    [CCode (cname = "gtk_menu_button_set_popover", cheader_filename = "gtk/gtk.h")]
    public static void menu_popover (Gtk.MenuButton menu, Gtk.Widget? popover);
    [CCode (cname = "gtk_drop_down_new_from_strings", cheader_filename = "gtk/gtk.h")]
    public static Gtk.Widget drop_down ([CCode (array_length = false, array_null_terminated = true, type = "const char * const *")] string[] labels);
}
