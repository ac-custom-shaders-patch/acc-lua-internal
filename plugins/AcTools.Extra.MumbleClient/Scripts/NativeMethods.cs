// 
// Author: John Carruthers (johnc@frag-labs.com)
// 
// Copyright (C) 2013 John Carruthers
// 
// Permission is hereby granted, free of charge, to any person obtaining
// a copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to
// the following conditions:
//  
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//  
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
// LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
// OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
// WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
// 

using System;
using System.Runtime.InteropServices;
using UnityEngine;

namespace Mumble {
    internal static class NativeMethods {
        private const string PluginName = "libopus";

        [DllImport(PluginName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        private static extern int opus_encoder_get_size(int numChannels);

        [DllImport(PluginName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        private static extern int opus_decoder_get_size(int numChannels);

        [DllImport(PluginName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        private static extern OpusErrors opus_encoder_init(IntPtr encoder, int sampleRate, int channelCount, int application);

        [DllImport(PluginName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        private static extern OpusErrors opus_decoder_init(IntPtr decoder, int sampleRate, int channelCount);

        [DllImport(PluginName, CallingConvention = CallingConvention.Cdecl)]
        private static extern int opus_encode_float(IntPtr st, float[] pcm, int frame_size, byte[] data, int max_data_bytes);

        [DllImport(PluginName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        internal static extern int opus_packet_get_nb_channels(byte[] encodedData);

        [DllImport(PluginName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern int opus_encoder_ctl(IntPtr encoder, OpusCtl request, out int value);

        [DllImport(PluginName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern int opus_encoder_ctl(IntPtr encoder, OpusCtl request, int value);

        [DllImport(PluginName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern int opus_encoder_ctl(IntPtr encoder, OpusCtl request);

        [DllImport(PluginName, CallingConvention = CallingConvention.Cdecl)]
        private static extern IntPtr opus_decoder_create(int sampleRate, int channelCount, out IntPtr error);

        [DllImport(PluginName, CallingConvention = CallingConvention.Cdecl)]
        private static extern int opus_decode(IntPtr decoder, IntPtr data, int len, IntPtr pcm, int frameSize, int decodeFec);

        [DllImport(PluginName, CallingConvention = CallingConvention.Cdecl)]
        private static extern int opus_decode_float(IntPtr decoder, byte[] data, int len, float[] pcm, int frameSize, int useFEC);

        [DllImport(PluginName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void opus_decoder_destroy(IntPtr decoder);

        [DllImport(PluginName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern int opus_decoder_ctl(IntPtr decoder, OpusCtl request, out int value);

        [DllImport(PluginName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern int opus_decoder_ctl(IntPtr decoder, OpusCtl request, int value);

        [DllImport(PluginName, CallingConvention = CallingConvention.Cdecl)]
        private static extern int opus_decoder_ctl(IntPtr decoder, OpusCtl request);

        internal static IntPtr opus_encoder_create(int sampleRate, int channelCount, OpusApplication application, out OpusErrors error) {
            var size = opus_encoder_get_size(channelCount);
            var ptr = Marshal.AllocHGlobal(size);
            error = opus_encoder_init(ptr, sampleRate, channelCount, (int)application);
            opus_encoder_ctl(ptr, OpusCtl.SET_INBAND_FEC_REQUEST, 1);
            opus_encoder_ctl(ptr, OpusCtl.SET_PACKET_LOSS_PERC_REQUEST, 50);
            if (error == OpusErrors.Ok || ptr == IntPtr.Zero) return ptr;
            destroy_opus(ptr);
            return IntPtr.Zero;
        }

        internal static int opus_encode(IntPtr encoder, float[] pcmData, int frameSize, byte[] encodedData) {
            if (encoder == IntPtr.Zero) return 0;
            var byteLength = opus_encode_float(encoder, pcmData, frameSize, encodedData, encodedData.Length);
            if (byteLength > 0) return byteLength;
            Debug.LogError($"Encoding error: {(OpusErrors)byteLength}, input: {pcmData.Length} bytes");
            return 0;
        }

        internal static void destroy_opus(IntPtr ptr) {
            Marshal.FreeHGlobal(ptr);
        }

        internal static IntPtr opus_decoder_create(int sampleRate, int channelCount, out OpusErrors error) {
            var decoderSize = opus_decoder_get_size(channelCount);
            var ptr = Marshal.AllocHGlobal(decoderSize);
            error = opus_decoder_init(ptr, sampleRate, channelCount);
            return ptr;
        }

        internal static int opus_decode(IntPtr decoder, byte[] encodedData, int encodedLength, float[] outputPcm, int channelRate, int channelCount,
                bool useForwardErrorCorrection) {
            if (decoder == IntPtr.Zero) return 0;
            var length = opus_decode_float(decoder, encodedData, encodedLength, outputPcm,
                    encodedData == null ? (channelRate / 100) * channelCount : outputPcm.Length / channelCount,
                    useForwardErrorCorrection ? 1 : 0);
            if (length > 0) return length * channelCount;
            
            Debug.LogError("Decoding error: " + (OpusErrors)length);
            return 0;
        }

        internal static void opus_reset_decoder(IntPtr decoder) {
            if (decoder == IntPtr.Zero) return;
            if (opus_decoder_ctl(decoder, OpusCtl.RESET_STATE) != 0) Debug.LogError("Resetting decoder failed");
        }

        internal static void opus_reset_encoder(IntPtr encoder) {
            if (encoder == IntPtr.Zero) return;
            if (opus_encoder_ctl(encoder, OpusCtl.RESET_STATE) != 0) Debug.LogError("Resetting encoder failed");
        }
    }
}