#include "placement.h"
#ifdef HAVE_X11
#include <gdk/x11/gdkx.h>
#include <X11/Xlib.h>
#endif

/* Global coordinates are deliberately confined to the optional X11 backend.
 * Ordinary Wayland toplevels retain the compositor's placement policy. */
gboolean shadow_get_position(GtkWindow *window, int *x, int *y) {
#ifdef HAVE_X11
    GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));
    if (surface && GDK_IS_X11_SURFACE(surface)) {
        Display *display = gdk_x11_display_get_xdisplay(gdk_surface_get_display(surface));
        Window child;
        int scale = gdk_surface_get_scale_factor(surface);
        if (XTranslateCoordinates(display, gdk_x11_surface_get_xid(surface), DefaultRootWindow(display),
                                  0, 0, x, y, &child)) {
            *x /= scale;
            *y /= scale;
            return TRUE;
        }
    }
#endif
    return FALSE;
}

gboolean shadow_position(GtkWindow *window, int x, int y, gboolean restore) {
#ifdef HAVE_X11
    GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));
    if (surface && GDK_IS_X11_SURFACE(surface)) {
        GdkDisplay *gdisplay = gdk_surface_get_display(surface);
        GdkMonitor *monitor = gdk_display_get_monitor_at_surface(gdisplay, surface);
        if (!monitor) return FALSE;
        GdkRectangle bounds;
        gdk_monitor_get_geometry(monitor, &bounds);
        int width = gdk_surface_get_width(surface), height = gdk_surface_get_height(surface);
        if (!restore || x + width < bounds.x || y + height < bounds.y ||
            x >= bounds.x + bounds.width || y >= bounds.y + bounds.height) {
            x = bounds.x + (bounds.width - width) / 2;
            y = bounds.y + (bounds.height - height) / 2;
        }
        x = CLAMP(x, bounds.x, MAX(bounds.x, bounds.x + bounds.width - width));
        y = CLAMP(y, bounds.y, MAX(bounds.y, bounds.y + bounds.height - height));
        Display *display = gdk_x11_display_get_xdisplay(gdisplay);
        int scale = gdk_surface_get_scale_factor(surface);
        XMoveWindow(display, gdk_x11_surface_get_xid(surface), x * scale, y * scale);
        XFlush(display);
        return TRUE;
    }
#endif
    return FALSE;
}
