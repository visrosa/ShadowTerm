#pragma once
#include <glib.h>

/* GBytes exposes immutable data. Keep constness inside C rather than letting
 * the Vala byte-array binding create a mutable intermediate pointer. */
static inline void
vcom_byte_buffer_append (GByteArray *buffer, GBytes *bytes)
{
    gsize size;
    const guint8 *data = g_bytes_get_data (bytes, &size);
    g_byte_array_append (buffer, data, size);
}
