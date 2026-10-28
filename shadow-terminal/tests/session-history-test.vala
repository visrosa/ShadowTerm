int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/session-history/stable-cycle-and-confirmation", () => {
        var history = new Shadow.SessionHistory ();
        foreach (var id in new string[] {"a", "b", "c"}) { history.register (id); history.focused (id); }
        assert (history.step ("c", 1) == "b"); history.focused ("b");
        assert (history.step ("b", 1) == "a"); history.focused ("a");
        assert (history.step ("a", -1) == "b"); history.focused ("b"); history.finish ();
        assert (history.step ("b", 1) == "c"); history.focused ("c"); history.finish ();
        assert (history.step ("c", 1) == "b");
        // A requested window can be denied activation. Only confirmed focus
        // changes recency when the initiating modifier is released.
        history.finish ();
        assert (history.step ("c", 1) == "b"); history.finish ();
    });
    Test.add_func ("/session-history/closure-new-session-and-external-focus", () => {
        var history = new Shadow.SessionHistory ();
        foreach (var id in new string[] {"a", "b", "c"}) { history.register (id); history.focused (id); }
        assert (history.step ("c", 1) == "b"); history.remove ("b"); history.register ("d");
        assert (history.step ("c", 1) == "a"); history.focused ("a");
        assert (history.step ("a", 1) == "c");
        history.focused ("d"); assert (!history.cycling);
        assert (history.step ("d", 1) == "a"); history.finish ();
        history.remove ("a"); history.remove ("c");
        assert (history.step ("d", -1) == "d"); history.focused ("d"); history.finish ();
        history.remove ("d"); assert (history.step ("d", 1) == null);
    });
    return Test.run ();
}
