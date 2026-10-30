private class OwnedValue : Object {
    public static int destroyed;
    ~OwnedValue () { destroyed++; }
}

private class Properties : Object {
    public string? label { get; set; }
    public string copied { owned get; set; default = "initial"; }
}

void main () {
    var properties = new Properties ();
    int notifications = 0;
    properties.notify["label"].connect (() => { notifications++; });
    properties.label = "exact λ";
    properties.label = "exact λ";
    assert (notifications == 1 && properties.label == "exact λ");
    properties.label = null;
    assert (notifications == 2 && properties.label == null);
    properties.copied = "owned";
    assert (properties.copied == "owned");
    {
        var value = new OwnedValue ();
        var other = new OwnedValue ();
        var list = new List<OwnedValue> ();
        list.append (value); list.append (other);
        list.remove (value);
        assert (list.length () == 1 && list.data == other);
        list.remove_all (other); assert (list == null);
        var slist = new SList<OwnedValue> ();
        slist.append (value); slist.append (other);
        slist.remove (value);
        assert (slist.length () == 1 && slist.data == other);
        slist.remove_all (other); assert (slist == null);
        var queue = new Queue<OwnedValue> ();
        queue.push_tail (value); queue.push_tail (other);
        assert (queue.remove (value));
        assert (queue.get_length () == 1 && queue.peek_head () == other);
        assert (queue.remove_all (other) == 1 && queue.is_empty ());
        assert (OwnedValue.destroyed == 0);
    }
    assert (OwnedValue.destroyed == 2);
    print ("Property notification and List/SList/Queue identity and lifetime passed\n");
}
