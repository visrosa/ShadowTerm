namespace VCom.ByteBuffer {
    [CCode (cname = "vcom_byte_buffer_append", cheader_filename = "byte-buffer.h")]
    public static void append (GLib.ByteArray buffer, GLib.Bytes bytes);
}
