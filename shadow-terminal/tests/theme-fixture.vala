private string theme_preset (bool optional = true) {
    var xml = new StringBuilder ("<?xml version=\"1.0\"?><!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"><plist version=\"1.0\"><dict>");
    string[] extra = {"Foreground Color", "Background Color", "Cursor Color", "Cursor Text Color", "Selection Color", "Selected Text Color"};
    for (int i = 0; i < (optional ? 22 : 18); i++) {
        string key = i < 16 ? "Ansi %d Color".printf (i) : extra[i - 16];
        xml.append ("<key>" + key + "</key><dict><key>Color Space</key><string>sRGB</string><key>Red Component</key><real>" + (i / 22.0).to_string () + "</real><key>Green Component</key><real>0.25</real><key>Blue Component</key><real>0.5</real></dict>");
    }
    xml.append ("<key>Unrelated setting</key><true/></dict></plist>");
    return xml.str;
}
