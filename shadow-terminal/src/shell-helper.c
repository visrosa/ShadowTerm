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
    gboolean metadata = strcmp(argv[1], "metadata") == 0;
    gboolean ready = strcmp(argv[1], "ready") == 0;
    gboolean history = ready;
    gboolean context = strcmp(argv[1], "context") == 0;
    if (metadata && argc != 6) { g_object_unref(bus); return 2; }
    if (history && argc > 202) { g_object_unref(bus); return 2; }
    if (context && argc != 12) { g_object_unref(bus); return 2; }
    GPtrArray *history_values = NULL;
    if (history) {
        history_values = g_ptr_array_new_with_free_func(g_free);
        GString *entry = g_string_new(NULL);
        size_t total = 0;
        int c;
        while (total++ < 131072 && history_values->len < 200 && (c = fgetc(stdin)) != EOF) {
            if (c == 0) {
                if (entry->len > 0 && entry->len <= 16384 && g_utf8_validate(entry->str, entry->len, NULL))
                    g_ptr_array_add(history_values, g_strdup(entry->str));
                g_string_truncate(entry, 0);
            } else g_string_append_c(entry, c);
        }
        g_string_free(entry, TRUE);
        g_ptr_array_add(history_values, NULL);
    }
    char *cwd = g_get_current_dir();
    const char *detail = argc > 2 ? argv[2] : (strcmp(argv[1], "ready") == 0 ? cwd : "");
    GVariant *parameters = ready ? g_variant_new("(ssis^as)", session, token, (gint) getppid(), cwd, (char **)history_values->pdata) :
        context ? g_variant_new("(ssi^as)", session, token, (gint) getppid(), &argv[2]) :
        metadata ? g_variant_new("(ssissss)", session, token, (gint) getppid(), argv[2], argv[3], argv[4], argv[5]) :
        (take || presentation) ? g_variant_new("(ssi)", session, token, (gint) getppid()) :
        g_variant_new("(ssiss)", session, token, (gint) getppid(), argv[1], detail);
    GVariant *reply = g_dbus_connection_call_sync(bus,
        "io.github.visrosa.Vibrant.ShadowTerm", "/io/github/visrosa/Vibrant/Shell",
        "io.github.visrosa.Vibrant.Shell1", ready ? "Prompt" : context ? "PromptContext" : metadata ? "Metadata" : take ? "TakeInput" : presentation ? "GetPresentation" : "Report", parameters,
        take ? G_VARIANT_TYPE("(s)") : (presentation || ready) ? G_VARIANT_TYPE("(b)") : G_VARIANT_TYPE("()"),
        G_DBUS_CALL_FLAGS_NONE, 1500, NULL, &error);
    g_free(cwd);
    if (history_values) g_ptr_array_unref(history_values);
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
    if (reply && (presentation || ready)) {
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
