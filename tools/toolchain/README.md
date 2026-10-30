# Private Vala constness correction

The pinned Vala 0.56.19 patch corrects two generated-C ownership contracts: an automatic string-property comparison uses the getter's actual return type, and the GLib List/SList/Queue removal implementations pass their owned elements as mutable destructor data. Borrowed string getters remain const; owned getters remain owned. The patch also updates the existing property-notification C expectation. The compiler itself obtains an owned copy of GLib’s immutable system-directory vector, avoiding a borrowed mutable-array declaration on newer GLib headers. Application APIs and generated application C are unchanged.

Build a private compiler from the ShadowTerm root:

```fish
nice -n 19 python3 tools/toolchain/prepare-vala.py
```

The script verifies the official 0.56.19 archive checksum, applies the source/binding patch and bootstraps with an existing compiler. `--archive PATH` avoids downloading; `--bootstrap PATH` selects a compiler. Hash-named source, build and prefix directories remain beneath `shadow-terminal/build/vala-toolchain/`. The final printed path is a wrapper selecting both the private compiler and its patched VAPI. It replaces no system files. An absolute bootstrap path is necessary: the release's configure script can otherwise fail to locate `valac` and silently retain the unpatched generated C.

Configure a fresh host build with that wrapper; changing `VALAC` does not change an already configured Meson compiler:

```fish
set patched_valac /absolute/path/printed/by/prepare-vala.py
set private_vte /absolute/path/to/private-vte/compile/src
env VALAC=$patched_valac meson setup /tmp/shadowterm-constness shadow-terminal -Dvte-library-dir=$private_vte '-Dc_args=-Werror=incompatible-pointer-types -Werror=pointer-sign -Werror=discarded-qualifiers'
nice -n 19 meson compile -C /tmp/shadowterm-constness -j 1
nice -n 19 meson test -C /tmp/shadowterm-constness --no-rebuild --num-processes 1 --print-errorlogs
env SHADOW_TERM_TEST_BUILD=/tmp/shadowterm-constness nice -n 19 python3 shadow-terminal/tests/integration.py --presentation
```

The helper compiles and runs `constness.vala` with the three pointer/qualifier classes as errors. It checks nullable property notifications, an owned string getter and element identity/reference lifetimes across all six collection-removal helpers. A C regression verifies directory-copy identity and independence from GLib’s original vector. The existing Vala property, owned-getter, generic-property and async regressions also exercise the compiler correction. This patch is local toolchain work, not a claim that an upstream release contains it.

The system compiler remains unchanged. The ShadowTerm Portage package selects a private build of the same correction with its default `private-vala` flag; disabling it retains the system compiler. Unused generator bookkeeping and GTK padding/X11 compatibility diagnostics remain visible. This correction removes the qualifier class; it does not establish warning-free builds or replace toolkit APIs.
