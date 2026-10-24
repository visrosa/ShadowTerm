#!/usr/bin/env python3
"""Own a private-display clipboard until the test terminates this process."""
from pathlib import Path
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, GLib, Gtk

Gtk.init()
clipboard = Gdk.Display.get_default().get_clipboard()
loop = GLib.MainLoop()
if sys.argv[1] == "--read":
    def received(clipboard, result):
        print(clipboard.read_text_finish(result), end="", flush=True)
        loop.quit()
    clipboard.read_text_async(None, received)
else:
    clipboard.set(Path(sys.argv[1]).read_text())
    print("ready", flush=True)
loop.run()
