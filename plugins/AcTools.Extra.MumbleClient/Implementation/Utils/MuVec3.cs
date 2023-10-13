#define ALLOW_UNSAFE

using System;
using System.Runtime.InteropServices;

namespace AcTools.Extra.MumbleClient.Implementation.Utils {
    [StructLayout(LayoutKind.Sequential, Pack = 4, Size = 12)]
    public struct MuVec3 {
        public float X;
        public float Y;
        public float Z;

#if ALLOW_UNSAFE
        public unsafe void Serialize(byte[] dst, int offset) {
            fixed (byte* numPtr = &dst[offset]) {
                ((float*)numPtr)[0] = X;
                ((float*)numPtr)[1] = Y;
                ((float*)numPtr)[2] = Z;
            }
        }

        public static unsafe MuVec3 Deserialize(byte[] src, int offset) {
            fixed (byte* numPtr = &src[offset]) {
                return new MuVec3 { X = ((float*)numPtr)[0], Y = ((float*)numPtr)[1], Z = ((float*)numPtr)[2] };
            }
        }
#else
        public void Serialize(byte[] dst, int offset) {
            Buffer.BlockCopy(BitConverter.GetBytes(X), 0, dst, offset, sizeof(float));
            Buffer.BlockCopy(BitConverter.GetBytes(Y), 0, dst, offset + sizeof(float), sizeof(float));
            Buffer.BlockCopy(BitConverter.GetBytes(Z), 0, dst, offset + sizeof(float) * 2, sizeof(float));
        }

        public static MuVec3 Deserialize(byte[] src, int offset) {
            return new MuVec3 {
                X = BitConverter.ToSingle(src, offset),
                Y = BitConverter.ToSingle(src, offset + sizeof(float)),
                Z = BitConverter.ToSingle(src, offset + sizeof(float) * 2)
            };
        }
#endif

        public static readonly MuVec3 Invalid = new MuVec3 { X = float.MaxValue };

        public static MuVec3 DeserializeLerp(byte[] posA, byte[] posB, float posLerp) {
            if (posA != null && posB != null) {
                return Lerp(Deserialize(posA, 0), Deserialize(posB, 0), posLerp);
            }
            var pos = posA ?? posB;
            return pos != null ? Deserialize(pos, 0) : Invalid;
        }

        public static MuVec3 operator +(MuVec3 a, MuVec3 b) {
            return new MuVec3 { X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z };
        }

        public static MuVec3 operator -(MuVec3 a, MuVec3 b) {
            return new MuVec3 { X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z };
        }

        public static MuVec3 operator *(MuVec3 a, float b) {
            return new MuVec3 { X = a.X * b, Y = a.Y * b, Z = a.Z * b };
        }

        public static MuVec3 operator /(MuVec3 a, float b) {
            return new MuVec3 { X = a.X / b, Y = a.Y / b, Z = a.Z / b };
        }

        public MuVec3 Normalize() {
            return this / Length();
        }

        public float Length() {
            return (float)Math.Sqrt(X * X + Y * Y + Z * Z);
        }

        public static float Dot(MuVec3 a, MuVec3 b) {
            return a.X * b.X + a.Y * b.Y + a.Z * b.Z;
        }

        public static MuVec3 Cross(MuVec3 a, MuVec3 b) {
            return new MuVec3 { X = a.Y * b.Z - b.Y * a.Z, Y = a.Z * b.X - b.Z * a.X, Z = a.X * b.Y - b.X * a.Y };
        }

        public static MuVec3 Lerp(MuVec3 a, MuVec3 b, float v) {
            return new MuVec3 { X = a.X * (1f - v) + b.X * v, Y = a.Y * (1f - v) + b.Y * v, Z = a.Z * (1f - v) + b.Z * v };
        }

        public override string ToString() {
            return $"(X={X}, Y={Y}, Z={Z})";
        }

        public bool IsValid() {
            return X != float.MaxValue;
        }

        public const int Size = sizeof(float) * 3;
    }
}