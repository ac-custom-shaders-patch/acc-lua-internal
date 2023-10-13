using System;
using System.Collections.Generic;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using UnityEngine;

namespace AcTools.Extra.MumbleClient.Implementation.Utils {
    public static class MarshalMatters {
        public static readonly Encoding ExchangeEncoding = new UTF8Encoding(false, false);

        public static unsafe T ToStruct<T>(this byte[] data) where T : struct {
            fixed (byte* p = &data[0]) {
                return (T)Marshal.PtrToStructure((IntPtr)p, typeof(T));
            }
        }

        public static unsafe T ToStruct<T>(byte* data) where T : struct {
            return (T)Marshal.PtrToStructure((IntPtr)data, typeof(T));
        }

        public static unsafe void ToBytes<T>(this T structure, byte[] destination) where T : struct {
            fixed (byte* byteArrayPtr = destination) {
                Marshal.StructureToPtr(structure, (IntPtr)byteArrayPtr, true);
            }
        }

        public static unsafe void ToBytes<T>(this T structure, byte* destination) where T : struct {
            Marshal.StructureToPtr(structure, (IntPtr)destination, true);
        }

        public static byte[] ToBytes<T>(this T structure) where T : struct {
            var ret = new byte[Marshal.SizeOf(structure)];
            structure.ToBytes(ret);
            return ret;
        }

        public static void CopyString(ref byte[] dst, int maxLength, string str) {
            if (str == null) {
                str = string.Empty;
            }

            if (dst == null) {
                dst = new byte[maxLength];
            }

            var strSize = ExchangeEncoding.GetByteCount(str);
            if (strSize <= maxLength) {
                ExchangeEncoding.GetBytes(str, 0, str.Length, dst, 0);
            } else if (strSize == str.Length) {
                ExchangeEncoding.GetBytes(str, 0, maxLength, dst, 0);
            } else {
                var bytes = ExchangeEncoding.GetBytes(str);
                Buffer.BlockCopy(bytes, 0, dst, 0, Math.Min(maxLength, bytes.Length));
                Debug.LogWarning($"String is too long: {str}, size limit: {maxLength}");
            }
        }

        public delegate void FillCallback<in TSource, TDestination>(TSource src, ref TDestination destination);

        public static void Fill<TSource, TDestination>(out int num, TDestination[] destination, IEnumerable<TSource> source,
                FillCallback<TSource, TDestination> callback) {
            using (var input = source.GetEnumerator()) {
                var filled = 0;
                while (input.MoveNext()) {
                    if (filled >= destination.Length) break;
                    callback(input.Current, ref destination[filled++]);
                }
                num = filled;
            }
        }

        private unsafe delegate string CreateStringFromEncoding(byte* bytes, int byteLength, Encoding encoding);

        private static readonly CreateStringFromEncoding FnCreateString = (CreateStringFromEncoding)Delegate.CreateDelegate(typeof(CreateStringFromEncoding),
                typeof(string).GetMethod("CreateStringFromEncoding", BindingFlags.NonPublic | BindingFlags.Static)
                        ?? throw new Exception("Internal method string.CreateStringFromEncoding is missing"));

        private unsafe delegate int GetBytesFromEncoding(string s, byte* bytes, int byteLength, Encoding encoding);

        private static readonly GetBytesFromEncoding FnGetBytesFromEncoding = (GetBytesFromEncoding)Delegate.CreateDelegate(typeof(GetBytesFromEncoding),
                typeof(string).GetMethod("GetBytesFromEncoding", BindingFlags.NonPublic | BindingFlags.Instance)
                        ?? throw new Exception("Internal method string.GetBytesFromEncoding is missing"));

        public static unsafe void StringToBytes(string input, byte* dst, int length) {
            FnGetBytesFromEncoding(input, dst, length, ExchangeEncoding);
        }

        public static unsafe string BytesToString(byte* data, int length) {
            for (var i = 0; i < length; ++i) {
                if (data[i] == 0) {
                    return FnCreateString(data, i, ExchangeEncoding);
                }
            }
            return FnCreateString(data, length, ExchangeEncoding);
        }

        public static unsafe void BytesToStringPair(byte* data, int length, out string a, out string b) {
            for (var i = 0; i < length; ++i) {
                if (data[i] == '\t') {
                    a = FnCreateString(data, i, ExchangeEncoding);
                    b = i + 1 < length ? BytesToString(&data[i + 1], length - i - 1) : null;
                    return;
                }
                if (data[i] == 0) {
                    a = FnCreateString(data, i, ExchangeEncoding);
                    b = null;
                    return;
                }
            }
            a = FnCreateString(data, length, ExchangeEncoding);
            b = null;
        }
    }
}