# Composer consumer contracts

A consumer accepts canonical UTF-8 source independently of its rendered editor. Readiness, source acceptance and terminal transport are separate capabilities; a visible Composer does not imply that a shell is ready.

| Consumer | Readiness | Delivery and acceptance | Cancellation | Terminal authority |
| -------- | --------- | ----------------------- | ------------ | ------------------ |
| Shadow Term outer fish | Authenticated prompt/preexec events; native buffer checked by fish | One-use exact-source request, syntax validation, native commandline/execute, explicit acknowledgement | Revokes an unaccepted request; cannot retract a command fish accepted | One session VTE owns its PTY, replies and resize |
| Foreground program | Running process, without generic prompt-readiness evidence | VTE paste followed by separate Return; queued delivery has no program acknowledgement | Interrupt uses the program's normal terminal contract | The same VTE remains authoritative |
| CV demonstration | Broker readiness/source messages | Versioned framed source messages and accepted notification | Broker protocol owns cancellation and last-client behavior | Broker owns input/replies/resize; mirror is read-only |
| Fake consumer | Explicit fixture state | Direct calls into the shared request lifecycle, without shell or PTY | Reset, timeout and rejection invalidate pending source | None |

`src/source-session.vala` supplies `VCom.SourceSession`, a transport-independent single-request state machine used by Shadow Term's `InputSession`. A consumer label and timeout are constructor parameters. Source is 1–65,536 UTF-8 bytes. `report(token, "ready", "")` enables preparation; `prepare(source)` starts a deadline, and `take(token)` retrieves the source once. Acceptance requires that retrieval. Busy, rejection, timeout or reset discard pending delivery; reset also rotates the credential. Completion, history and advisory context do not call these methods or gain submission authority.

The adapter must bind the credential to the actual peer/process. A token comparison inside this object alone does not authenticate a transport. Occupied-input rejection belongs to the consumer before native insertion. The editor retains its draft while delivery is pending and clears only the unchanged source snapshot on acceptance. Late acknowledgements fail; edits made during acceptance survive. A consumer disconnect resets the lifecycle before accepting a new peer. Cancellation after retrieval cannot prove the consumer did not act, so adapters must not promise rollback or retry automatically.

The generic editor imports no shell or consumer transport. A host can compose `RichInput` with `SourceSession`; transport, focus and program execution stay host-owned. Empty foreground responses are a different contract and do not pass through the nonempty exact-source request. The shared lifecycle does not choose a Composer→Pane→consumer topology or establish GNU readline ABI compatibility.

`tests/consumer-test.vala` is a fake non-shell consumer covering Unicode/combining marks/trailing newlines, concurrent edits, occupied-buffer rejection, reset/disconnect/reconnect, timeout, cancellation and late acknowledgements. Shadow Term's existing input and frontend suites cover the concrete fish bridge. [The CV protocol](../../../ClaudeVassal/SHADOW_PROTOCOL.md) owns its distinct framing and lifecycle; no protocol unification is implied.
