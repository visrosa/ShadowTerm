// These declarations retain the C headers' pointer types where the installed
// Vala 0.56 bindings lose array constness or the GtkWidget upcast.
namespace Shadow.Native {
    [CCode (cname = "g_subprocess_launcher_spawnv", cheader_filename = "gio/gio.h")]
    public static GLib.Subprocess spawn (GLib.SubprocessLauncher launcher, [CCode (array_length = false, array_null_terminated = true, type = "const gchar * const *")] string[] argv) throws GLib.Error;
    [CCode (cname = "g_subprocess_newv", cheader_filename = "gio/gio.h")]
    public static GLib.Subprocess subprocess ([CCode (array_length = false, array_null_terminated = true, type = "const gchar * const *")] string[] argv, GLib.SubprocessFlags flags) throws GLib.Error;
    [CCode (cname = "shadow_command_environment", cheader_filename = "native.h", array_length = false, array_null_terminated = true)]
    public static string[] environment (GLib.ApplicationCommandLine invocation);
}
