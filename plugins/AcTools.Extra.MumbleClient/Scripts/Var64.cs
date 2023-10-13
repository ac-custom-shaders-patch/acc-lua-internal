namespace Mumble {
    static class Var64 {
        public static void Write(byte[] dst, ref int pos, ulong value) {
            var i = value;
            if ((i & 0x8000000000000000L) != 0 && ~i < 0x100000000L) {
                // Signed number.
                i = ~i;
                if (i <= 0x3) {
                    // Shortcase for -1 to -4
                    dst[pos++] = (byte)(0xFC | i);
                    return;
                }
                dst[pos++] = 0xF8;
            }
            if (i < 0x80) {
                // Need top bit clear
                dst[pos++] = (byte)i;
            } else if (i < 0x4000) {
                // Need top two bits clear
                dst[pos++] = (byte)((i >>  8) | 0x80);
                dst[pos++] = (byte)(i & 0xFF);
            } else if (i < 0x200000) {
                // Need top three bits clear
                dst[pos++] = (byte)((i >>  16) | 0xC0);
                dst[pos++] = (byte)((i >>  8) & 0xFF);
                dst[pos++] = (byte)(i & 0xFF);
            } else if (i < 0x10000000) {
                // Need top four bits clear
                dst[pos++] = (byte)((i >>  24) | 0xE0);
                dst[pos++] = (byte)((i >>  16) & 0xFF);
                dst[pos++] = (byte)((i >>  8) & 0xFF);
                dst[pos++] = (byte)(i & 0xFF);
            } else if (i < 0x100000000L) {
                // It's a full 32-bit integer.
                dst[pos++] = 0xF0;
                dst[pos++] = (byte)((i >>  24) & 0xFF);
                dst[pos++] = (byte)((i >>  16) & 0xFF);
                dst[pos++] = (byte)((i >>  8) & 0xFF);
                dst[pos++] = (byte)(i & 0xFF);
            } else {
                // It's a 64-bit value.
                dst[pos++] = 0xF4;
                dst[pos++] = (byte)((i >>  56) & 0xFF);
                dst[pos++] = (byte)((i >>  48) & 0xFF);
                dst[pos++] = (byte)((i >>  40) & 0xFF);
                dst[pos++] = (byte)((i >>  32) & 0xFF);
                dst[pos++] = (byte)((i >>  24) & 0xFF);
                dst[pos++] = (byte)((i >>  16) & 0xFF);
                dst[pos++] = (byte)((i >>  8) & 0xFF);
                dst[pos++] = (byte)(i & 0xFF);
            }
        }
    }
}