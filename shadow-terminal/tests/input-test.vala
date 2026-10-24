int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/input/source-and-one-use", () => {
        var state = new Shadow.InputSession ();
        string source = "printf '%s' '日本語 e\u0301'\n\n";
        string accepted = "";
        state.accepted.connect ((text) => { accepted = text; });
        try {
            state.report (state.token, "ready", "");
            state.prepare (source);
            assert (state.take (state.token) == source);
            try { state.take (state.token); Test.fail (); } catch (IOError error) {}
            state.report (state.token, "accepted", "");
            assert (accepted == source && !state.pending && !state.ready);
        } catch (IOError error) { Test.fail (); }
    });
    Test.add_func ("/input/busy-token-and-cancellation", () => {
        var state = new Shadow.InputSession ();
        try { state.prepare ("echo no"); Test.fail (); } catch (IOError error) {}
        try {
            state.report (state.token, "ready", "");
            state.prepare ("echo yes");
            try { state.prepare ("duplicate"); Test.fail (); } catch (IOError error) {}
            try { state.take ("wrong-token"); Test.fail (); } catch (IOError error) {}
            state.report (state.token, "busy", "");
            assert (!state.pending && !state.ready);
            string old_token = state.token;
            state.reset ();
            try { state.report (old_token, "ready", ""); Test.fail (); } catch (IOError error) {}
        } catch (IOError error) { Test.fail (); }
    });
    Test.add_func ("/input/expired-ack", () => {
        var state = new Shadow.InputSession ();
        try {
            state.report (state.token, "ready", "");
            state.prepare ("echo pending");
            state.take (state.token);
            state.reject ("expired");
            try { state.report (state.token, "accepted", ""); Test.fail (); } catch (IOError error) {}
            assert (!state.pending);
        } catch (IOError error) { Test.fail (); }
    });
    return Test.run ();
}
