#include <gio/gio.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/* This helper links only GIO, so prompt notifications never initialize GTK or
 * create another terminal. Source travels on D-Bus, separately from PTY bytes. */
int main(int argc, char **argv) {
    const char *session = g_getenv("SHADOW_TERM_SESSION");
    const char *token = g_getenv("SHADOW_TERM_TOKEN");
    if (argc < 2 || !session || !token) return 2;
    GError *error = NULL;
    GDBusConnection *bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
    if (!bus) goto failed;
    gboolean take = strcmp(argv[1], "take") == 0;
    gboolean presentation = strcmp(argv[1], "presentation") == 0;
    char *cwd = g_get_current_dir();
    const char *detail = argc > 2 ? argv[2] : (strcmp(argv[1], "ready") == 0 ? cwd : "");
    GVariant *parameters = (take || presentation) ? g_variant_new("(ssi)", session, token, (gint) getppid()) :
        g_variant_new("(ssiss)", session, token, (gint) getppid(), argv[1], detail);
    GVariant *reply = g_dbus_connection_call_sync(bus,
        "io.github.visrosa.Vibrant.ShadowTerm", "/io/github/visrosa/Vibrant/Shell",
        "io.github.visrosa.Vibrant.Shell1", take ? "TakeInput" : presentation ? "GetPresentation" : "Report", parameters,
        take ? G_VARIANT_TYPE("(s)") : presentation ? G_VARIANT_TYPE("(b)") : G_VARIANT_TYPE("()"),
        G_DBUS_CALL_FLAGS_NONE, 1500, NULL, &error);
    g_free(cwd);
    if (reply && take) {
        const char *source;
        g_variant_get(reply, "(&s)", &source);
        /* NUL framing preserves trailing newlines in fish's command substitution. */
        size_t length = strlen(source);
        if (fwrite(source, 1, length, stdout) != length || fputc('\0', stdout) == EOF) {
            g_variant_unref(reply);
            g_object_unref(bus);
            return 1;
        }
    }
    if (reply && presentation) {
        gboolean active;
        g_variant_get(reply, "(b)", &active);
        g_variant_unref(reply);
        g_object_unref(bus);
        return active ? 0 : 1;
    }
    g_object_unref(bus);
    if (reply) { g_variant_unref(reply); return 0; }
failed:
    if (error) { fprintf(stderr, "vcom-shell: %s\n", error->message); g_error_free(error); }
    return 1;
}
