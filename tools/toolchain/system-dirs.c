#include "vala-system-dirs.h"

int main(void) {
    const gchar * const *original = g_get_system_data_dirs();
    gchar **copy = vala_system_data_dirs_copy();
    gsize i = 0;
    for (; original[i]; i++) {
        g_assert_cmpstr(copy[i], ==, original[i]);
        g_assert(copy[i] != original[i]);
    }
    g_assert_null(copy[i]);
    if (i) {
        gchar *first = g_strdup(original[0]);
        g_free(copy[0]); copy[0] = g_strdup("synthetic-change");
        g_assert_cmpstr(original[0], ==, first);
        g_free(first);
    }
    g_strfreev(copy);
    return 0;
}
