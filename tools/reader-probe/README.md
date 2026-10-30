# External shell reader experiment

This Linux-only prototype replaces fish's native key loop for an explicitly adapted read. It returns accepted source directly to the existing interactive execution loop; it does not feed `commandline --replace` or an execute binding. The patch is pinned to fish commit `141e1cb742614e0bcc2f43515f65b6fa2b1d595d`. It is an experiment with a fake editor, not a supported shell adapter or a replacement system shell.

Build and test from the ShadowTerm root with an existing fish source checkout and cached Cargo dependencies:

```fish
nice -n 19 python3 tools/reader-probe/prepare.py ../fish-shell --build /tmp/shadowterm-reader-build
```

The script exports the pinned commit, applies the patch, builds one job offline and runs `check.py` on a private PTY. It never edits the supplied fish checkout or installs its binary. To test a previously built patched binary:

```fish
nice -n 19 python3 tools/reader-probe/check.py /absolute/path/to/patched/fish
```

All four XDG homes and `fish_history` are disposable. This fish revision makes `--no-config` enable private mode; the fixture clears that flag only in its temporary environment so it can assert actual history persistence. Commands, native input and captured markers are synthetic. No GUI or live history is used.

## Experimental contract

`FISH_EXTERNAL_READER_PROBE` opts the disposable shell into a same-UID Unix-socket peer. Each read has a new monotonically increasing identity and connection. Frames have a four-byte big-endian byte length followed by UTF-8, bounded to 1 MiB. Fields are NUL-separated; submitted source cannot contain NUL. The first message is `v1`, `begin`, read identity, kind and initial source. Kinds are `command` or `literal`.

The peer sends `submit`, identity and source. Fish responds `accepted`, `incomplete` or `rejected` with that identity. Incomplete/rejected source starts another edit on the same identity and carries the proposed source unchanged. Accepted source enters the ordinary shell loop exactly once, including empty input. The immutable value may be copied into reader state for shell history; no native edit loop runs during the external read. Command history remains subject to fish's policy and trailing-whitespace normalization; execution source retains trailing newlines. UTF-8 uses fish’s byte-preserving conversion functions in both directions, including code points fish reserves internally for non-UTF-8 bytes.

`interrupt` and `eof` are distinct actions. `native`, identity and source transfers an unsubmitted draft back to the native editor and receives a `native` acknowledgement. Connection failure before submission falls back to the native reader; losing the acceptance acknowledgement never replays a submitted command. The fake editor uses a three-second transport deadline so failed experiments cannot strand a reader indefinitely. This is unsuitable for a human editing session.

The fixture covers live variables/functions/cwd, exact Unicode and trailing newlines through `fish_preexec`, incomplete and empty submissions, nested literal reads, literal and outer EOF, interrupts, history once, stop/resume job control, foreground PTY reads, native source transfer and disconnect before/after submission. Silent and character-limited reads stay native; their input never enters the peer or command history.

## Migration boundary

The reader seam is feasible at this pinned revision. The next production adapter must negotiate capabilities, authenticate a particular launched shell rather than only its account, bind ownership epochs and source revisions, and resolve acceptance without automatic retries. A private socket path and same UID alone do not establish that production authority. Invalid frames and fallback need a complete draft-preserving rejection contract before exposure to a real editor.

The prototype does not bridge live completion, abbreviations, editable history navigation, user keybinding functions, prompt metadata/events or cross-editor undo. It does not support secret input, timed or character-limited reads, non-TTY reads, remote shells, other shell families or GNU readline ABI users. A nested `read --shell` also needs a separate capability decision. It does not connect GTK Composer or change ShadowTerm's default adapter. The current adapter remains the reversible production baseline; this experiment justifies developing a maintained opt-in fish reader patch before selecting a supported upstream API.
