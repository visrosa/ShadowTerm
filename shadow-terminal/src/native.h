#pragma once
#include <gio/gio.h>

/* The returned environment is borrowed and deeply const. Copy each string so
 * Vala can own an ordinary string vector without weakening the API contract. */
static inline gchar **
shadow_command_environment (GApplicationCommandLine *invocation)
{
    const gchar * const *source = g_application_command_line_get_environ (invocation);
    gsize length = 0;
    if (source != NULL)
        while (source[length] != NULL) length++;
    gchar **copy = g_new0 (gchar *, length + 1);
    for (gsize i = 0; i < length; i++) copy[i] = g_strdup (source[i]);
    return copy;
}
