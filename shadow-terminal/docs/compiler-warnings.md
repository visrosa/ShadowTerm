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

The remaining unused diagnostics arise in generated C, including `_tmpN__length1`, `_array_size_`, unused property tables and async finish wrappers for fire-and-forget operations. Removing application variables does not remove those generator bookkeeping declarations. No diagnostic class is disabled, and generated C is not edited. These diagnostics require a compiler/code-generation remedy; they are not evidence by themselves of an application runtime failure.

Remaining qualifier diagnostics include generated string-property setters assigning a borrowed getter result to `old_value` before comparing it and duplicating the replacement. Byte-array and list adapters also lose qualifiers in generated intermediates. Signedness diagnostics arise from the unsigned-byte representation in VTE/libxml bindings. GTK padding and per-widget font providers use deprecated style APIs; replacement must preserve supported toolkit versions and widget-scoped styling. These classes remain visible for future generator/binding/toolkit work rather than being hidden by global flags.

To reproduce, configure a fresh build with `VALAC=valac-0.56` when that is the installed compiler name, compile every target serially and retain the complete log. Promote incompatible pointer diagnostics to errors with Meson's `-Dc_args=-Werror=incompatible-pointer-types`, then run the model suites and the private-display harness described in [Verification and limits](../README.md#verification-and-limits). Warning totals vary with compiler, optimization, target set and generator version; incremental logs do not establish clean-build totals. Package-manager QA requires a package build and is separate from a checkout build.
