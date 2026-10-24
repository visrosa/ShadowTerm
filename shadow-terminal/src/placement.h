#pragma once
#include <gtk/gtk.h>

gboolean shadow_position(GtkWindow *window, int x, int y, gboolean restore);
gboolean shadow_get_position(GtkWindow *window, int *x, int *y);
