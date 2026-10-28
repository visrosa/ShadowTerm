// These declarations retain the C headers' pointer types where the installed
// Vala 0.56 bindings lose array constness or the GtkWidget upcast.
namespace Shadow.Native {
    [CCode (cname = "gtk_menu_button_set_popover", cheader_filename = "gtk/gtk.h")]
    public static void menu_popover (Gtk.MenuButton menu, Gtk.Widget? popover);
    [CCode (cname = "gtk_drop_down_new_from_strings", cheader_filename = "gtk/gtk.h")]
    public static Gtk.Widget drop_down ([CCode (array_length = false, array_null_terminated = true, type = "const char * const *")] string[] labels);
}
