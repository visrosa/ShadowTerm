# Compiler warning boundaries

A full debug build with GCC 16.2.1, Vala 0.56.19, GTK 4.20.4 and GLib 2.88.2 emitted 1,145 C warnings before the boundary corrections. These counts include separate application and test compilations of shared sources; they are diagnostics, not independent defects. The baseline used Meson's warning level 1 without diagnostic suppression.

| Diagnostic                     | Emissions | Source boundary |
| ------------------------------ | --------- | --------------- |
| unused but set variable        | 663       | Generated array lengths, allocation sizes, closure/self temporaries |
| unused variable                | 167       | Generated array traversal sizes and unused GObject property tables |
| discarded qualifiers           | 179       | Generated volatile type initialization, property setters, byte-array and list bindings |
| pointer signedness             | 46        | VTE byte input and libxml node-name bindings |
| incompatible pointer types     | 31        | GTK popovers/string vectors, subprocess argv, command environment and hash-table callbacks |
| deprecated declarations        | 26        | GTK style-context providers and padding access |
| unused function                | 17        | Generated async finish/closure helpers |
| duplicate declaration specifier | 8        | Generated membership helper for constant string arrays |
| format                         | 8         | Hardcoded long-long format for platform-dependent gint64 |

The pointer corrections preserve the installed C header contracts in `src/native.vapi` and `src/gtk-native.vapi`. GTK popovers require a widget upcast. Read-only argv/string-vector inputs retain both levels of constness. The command-line environment remains borrowed and deeply const in GIO; `src/native.h` copies it into an owned vector before passing it to session setup. Preferences use typed key iteration instead of generated hash-table callback adapters. Duration labels use `int64.FORMAT`, and constant-array membership avoids the generated duplicate-const helper. The GLib code-generation target follows the dependency baseline rather than generating obsolete volatile initialization declarations.

## Current application and test inventory

A clean GCC 16.2.1/Vala 0.56.19 build at `de9f2ae` emitted 1,070 C warnings and 21 Vala deprecation diagnostics. After the counted-byte, immutable-buffer and styling corrections, a fresh build emits 1,008 C warnings and four Vala deprecation diagnostics. The latter build additionally includes the generic consumer test and new presentation/font fixtures; totals count repeated target emissions rather than independent defects. Both builds use warning level 1 with no diagnostic classes disabled.

| Diagnostic                 | Before | After | Remaining cause |
| -------------------------- | ------ | ----- | --------------- |
| Unused but set variable     | 713    | 714   | Vala bookkeeping and temporaries |
| Unused variable             | 196    | 200   | Generated lengths/property tables and fixture code |
| Unused function             | 13     | 13    | Generated async/closure helpers |
| Discarded qualifiers        | 70     | 61    | Generated string-property setters and list removal helper |
| Pointer signedness          | 52     | 0     | Counted VTE char bytes and explicit libxml name conversion |
| Deprecated C declarations   | 26     | 20    | GTK padding access and best-effort GDK X11 placement |
| Incompatible pointer types | 0      | 0     | Header contracts retained |

`rich-input/src/terminal-bytes.vapi` retains VTE's counted `char` byte contract, including embedded NUL data. `src/xml-native.h` converts libxml's immutable unsigned UTF-8 node names at the C boundary. The shared `byte-buffer.h` appends immutable GBytes without introducing a mutable intermediate. Composer font CSS uses a unique per-editor selector registered before initial layout and released on unrealize/dispose; fonts remain independent across reparenting. Namespace-level declarations retain the supported display-provider APIs without inheriting the deprecated Vala `StyleContext` container marker. Shortcut controls use native accelerator labels in ordinary GTK labels.

The remaining qualifier warnings originate in the generator and core bindings, rather than application storage. The [private Vala correction](../../tools/toolchain/README.md) uses the actual getter return type for property comparisons and corrects all six GLib List/SList/Queue removal helpers. Its regression checks borrowed/owned getters, notification count, object identity and reference lifetimes. The existing Vala property, owned-getter, generic-property and async tests also pass with the updated notification expectation. Generated application C is not edited and diagnostic classes are not disabled.

The helper builds a private compiler and binding set; select both through its wrapper when configuring a fresh Meson build. The ShadowTerm Portage package's default `private-vala` flag selects the separately packaged `dev-lang/vala-shadowterm:0.56` toolchain. It adds qualifier mismatches to the pointer error gates without replacing system Vala. Disabling that flag restores the system compiler and its original qualifier warnings. Unused generator declarations and GTK padding/X11 compatibility paths remain visible; a warning-free build is not claimed.

## Private toolchain comparison

Clean debug builds of the same final application/test roster with GCC 16.2.1 and warning level 1 emit 1,012 C warnings with system Vala 0.56.19 and 951 with the private correction. This roster includes expanded icon fixtures, so its unused totals differ from the earlier 1,008-warning inventory. Both builds promote pointer/sign mismatches to errors; the private build also promotes qualifier mismatches. Neither disables a diagnostic class.

| Diagnostic                 | System compiler | Private compiler |
| -------------------------- | --------------- | ---------------- |
| Unused but set variable     | 716             | 716              |
| Unused variable             | 202             | 202              |
| Unused function             | 13              | 13               |
| Discarded qualifiers        | 61              | 0                |
| Deprecated C declarations   | 20              | 20               |
| Pointer/sign mismatches     | 0               | 0                |

The 931 unused emissions require generator work beyond the constness correction. The 20 C toolkit deprecations and four Vala deprecation diagnostics retain the supported padding and X11 behavior. The private compiler package itself has separate bootstrap diagnostics; its pointer gates and ownership regressions cover the GLib directory-vector adapter as well as generated application code. Package builds use their own optimization and target roster, so their totals must be reported separately.

Generated examples include `_tmpN__length1`, `_array_size_`, unused property tables and async finish wrappers for fire-and-forget operations. Removing application variables does not remove these declarations. Generated C is not edited and diagnostics are not disabled. Their presence alone does not establish an application runtime failure.

GTK padding and X11 placement replacements must preserve supported toolkit versions, coordinate correctness and ordinary-window fallback. The private presentation suite checks word hit testing, editor fonts and reparenting; native compositor placement remains separate validation.

To reproduce, configure a fresh build with `VALAC=valac-0.56` when that is the installed compiler name, compile every target serially and retain the complete log. Promote incompatible pointer diagnostics to errors with Meson's `'-Dc_args=-Werror=incompatible-pointer-types -Werror=pointer-sign'`, then run the model suites and the private-display harness described in [Verification and limits](../README.md#verification-and-limits). Warning totals vary with compiler, optimization, target set and generator version; incremental logs do not establish clean-build totals. Package-manager QA requires a package build and is separate from a checkout build.
