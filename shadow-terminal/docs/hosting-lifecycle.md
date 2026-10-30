# Persistent command hosting and view dismissal

A named Shadow Term session can hide and reappear without restarting its command. Closing remains an explicit termination operation. This distinction supports tasklineUI as an ordinary persistent command window without requiring desktop panels or layer-shell.

Build tasklineUI's complete package, then use the same launch options on repeated invocations:

```fish
cd /data/Homework/tasklineUI
go build -buildvcs=false -o /tmp/taskline-ui .
shadow-term --session tasks --input terminal --hide-on-blur -- /tmp/taskline-ui
shadow-term --session tasks --toggle
shadow-term --session tasks --quit
```

Use a persistent executable path for a permanent launcher. The temporary path above is a local trial. `--toggle` preserves the command, input state and viewport; `--quit` ends it. Reusing a named session with conflicting launch options is rejected. The host removes inherited Kitty identity; tasklineUI must provide plain text equivalents for its OSC 66 header and badges. Its companion renderer retains Kitty sizing only inside Kitty. The application does not claim OSC 66 support.

The optional `/presentation/taskline-persistent-consumer` fixture creates a synthetic TaskChampion database in the private harness's temporary data directory and runs a real tasklineUI binary. It checks visible task labels, unsent input, stable child PID across hide/show, resize and child termination. Enable it with `SHADOWTERM_TASKLINE_FIXTURE` when running the [private presentation harness](../README.md#verification-and-limits). The ordinary baseline separately verifies named launch reuse, focus/hide, saved geometry and cleanup. Neither fixture establishes native desktop activation, compositor placement or external-focus-loss policy.

## Last-view dismissal contract

A future dismiss action must be distinct from close and terminate. Its requirements are:

- The process-wide session registry retains the session and an application hold while it has a live producer, even with no presented view.
- One retained VTE owns parsed terminal state, input/replies, scrollback and PTY resize. Detaching a view never creates a second emulator or replays a tail to reconstruct the screen.
- A detached producer keeps draining output under explicit scrollback/resource limits; presentation, context queries and syntax analysis pause. Reattachment uses the same VTE, draft, credential and readiness state without calling `start()`.
- With no view, the last negotiated grid size remains authoritative until an attached view supplies dimensions. Simultaneous views need a separate size/input policy.
- Explicit termination cancels requests, ends/reaps owned children, releases resources and removes the application hold. A producer exit follows the existing hold/output policy; dismissal cannot silently become termination.
- A dismiss operation identifies a view and its session explicitly. The existing `detach_session` name means moving a pane into another window; it must not be repurposed to imply an unattached session.

Before implementing this API, test hidden output beyond scrollback limits, peer disconnect/reconnect, close during pending source delivery, reattachment after exit and application shutdown. CV's broker currently has its own last-client cancellation and launcher lifetime; preserving a Shadow Term producer does not change that contract. Desktop placement adapters remain optional. Existing close behavior must not change as a side effect of adding dismissal.
