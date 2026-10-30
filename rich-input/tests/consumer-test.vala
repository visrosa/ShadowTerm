// A non-shell consumer exercises the shared lifecycle without GTK or a PTY.
private class FakeConsumer : Object {
    public VCom.SourceSession session = new VCom.SourceSession ("Fixture", 10);
    public string buffer = "";
    public string received = "";
    public void accept () throws IOError {
        string source = session.take (session.token);
        if (buffer != "") { session.report (session.token, "rejected", "Occupied"); return; }
        received = source;
        session.report (session.token, "accepted", "");
    }
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/consumer/exact-source-and-concurrent-edit", () => {
        var consumer = new FakeConsumer ();
        string draft = "日本語 e\u0301\n\n";
        string source = draft;
        consumer.session.accepted.connect ((accepted) => { if (draft == accepted) draft = ""; });
        try {
            consumer.session.report (consumer.session.token, "ready", "");
            consumer.session.prepare (source);
            draft += "new edit";
            consumer.accept ();
            assert (consumer.received == source && draft == source + "new edit");
        } catch (IOError error) { Test.fail (); }
    });
    Test.add_func ("/consumer/occupied-and-disconnect", () => {
        var consumer = new FakeConsumer ();
        consumer.buffer = "native work";
        bool accepted = false;
        consumer.session.accepted.connect (() => { accepted = true; });
        try {
            consumer.session.report (consumer.session.token, "ready", "");
            consumer.session.prepare ("replacement");
            consumer.accept ();
            assert (!accepted && !consumer.session.pending && consumer.buffer == "native work");
            consumer.session.prepare ("disconnect");
            string old_token = consumer.session.token;
            consumer.session.reset ();
            try { consumer.session.take (old_token); Test.fail (); } catch (IOError error) {}
            assert (!consumer.session.ready && !consumer.session.pending);
            consumer.session.report (consumer.session.token, "ready", "");
            consumer.session.prepare ("reconnect");
            consumer.buffer = ""; consumer.accept ();
            assert (consumer.received == "reconnect");
        } catch (IOError error) { Test.fail (); }
    });
    Test.add_func ("/consumer/timeout-cancel-and-late-ack", () => {
        var state = new VCom.SourceSession ("Fixture", 10);
        var loop = new MainLoop ();
        bool rejected = false;
        state.rejected.connect (() => { rejected = true; loop.quit (); });
        try {
            state.report (state.token, "ready", ""); state.prepare ("pending"); state.take (state.token);
            loop.run ();
            assert (rejected && !state.pending);
            try { state.report (state.token, "accepted", ""); Test.fail (); } catch (IOError error) {}
            state.prepare ("cancelled"); state.cancel ();
            try { state.take (state.token); Test.fail (); } catch (IOError error) {}
        } catch (IOError error) { Test.fail (); }
    });
    return Test.run ();
}
