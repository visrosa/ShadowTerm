#!/usr/bin/env python3
"""Own a private-display clipboard until the test terminates this process."""
from pathlib import Path
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, GLib, Gtk

Gtk.init()
Gdk.Display.get_default().get_clipboard().set(Path(sys.argv[1]).read_text())
print("ready", flush=True)
GLib.MainLoop().run()
