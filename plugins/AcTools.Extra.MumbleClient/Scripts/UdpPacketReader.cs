using System;
using AcTools.Extra.MumbleClient.Implementation.Utils;

namespace Mumble {
    public static class UdpPacketReader {
        private static readonly MemoryPool<byte> OpusVoiceData = new MemoryPool<byte>("Received OPUS Data", 480, true);

        public static byte[] GetOpusVoiceData(byte[] data, ref int pos, int length) {
            var buffer = OpusVoiceData.GetOrAllocate(length);
            Buffer.BlockCopy(data, pos, buffer, 0, length);
            pos += length;
            return buffer;
        }

        public static void ReleaseOpusVoiceData(ref byte[] data) {
            OpusVoiceData.Release(ref data);
        }

        public static MuVec3 ReadVec3(byte[] data, int dataLength, ref int pos) {
            if (dataLength - pos != 12) return MuVec3.Invalid;
            var ret = MuVec3.Deserialize(data, pos);
            pos += 12;
            return ret;
        }

        public static long ReadVarInt64(byte[] data, ref int pos) {
            var b0 = data[pos++];
            var b = (long)b0;
            var leadingOnes = LeadingOnes(b0);
            switch (leadingOnes) {
                case 0:
                    return b & 127;
                case 1:
                    // 10xxxxxx + 1 byte
                    return ((b & 63) << 8) | data[pos++];
                case 2:
                    // 110xxxxx + 2 bytes
                    return ((b & 31) << 16) | ((long)data[pos++] << 8) | data[pos++];
                case 3:
                    // 1110xxxx + 3 bytes
                    return ((b & 15) << 24) | ((long)data[pos++] << 16) | ((long)data[pos++] << 8) | data[pos++];
                case 4:
                    // Either:
                    //  > 111100__ + int (4 bytes)
                    //  > 111101__ + long (8 bytes)
                    if ((b & 4) == 4) {
                        //111101__ + long (8 bytes)
                        return ((long)data[pos++] << 56) | ((long)data[pos++] << 48) | ((long)data[pos++] << 40) | ((long)data[pos++] << 32) 
                                | ((long)data[pos++] << 24) | ((long)data[pos++] << 16) | ((long)data[pos++] << 8) | data[pos++];
                    } else {
                        //111100__ + int (4 bytes)
                        return ((long)data[pos++] << 24) | ((long)data[pos++] << 16) | ((long)data[pos++] << 8) | data[pos++];
                    }
                case 5:
                    // 111110 + varint (negative)
                    return ~ReadVarInt64(data, ref pos);
                case 6:
                case 7:
                case 8:
                    // 111111xx Byte-inverted negative two bit number (~xx)
                    // We need three cases here because all the other leading parts are capped off by a zero, e.g. 11110xxx
                    // However in this case it's just 6 ones, and then the data (111111xx). Depending on the data, the leading count changes
                    return ~(b & 3);
                default:
                    throw new Exception("Invalid varint encoding");
            }
        }

        private static int LeadingOnes(byte value) {
            if (value < 128) return 0;
            if (value < 192) return 1;
            if (value < 224) return 2;
            if (value < 240) return 3;
            if (value < 248) return 4;
            if (value < 252) return 5;
            if (value < 254) return 6;
            if (value < 255) return 7;
            return 8;
        }
    }
}