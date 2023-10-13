//  
//  Author: John Carruthers (johnc@frag-labs.com)
//  
//  Copyright (C) 2013 John Carruthers
//  
//  Permission is hereby granted, free of charge, to any person obtaining
//  a copy of this software and associated documentation files (the
//  "Software"), to deal in the Software without restriction, including
//  without limitation the rights to use, copy, modify, merge, publish,
//  distribute, sublicense, and/or sell copies of the Software, and to
//  permit persons to whom the Software is furnished to do so, subject to
//  the following conditions:
//   
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//   
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
//  LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
//  OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
//  WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//  

using System;

namespace Mumble {
    public class OpusDecoder : IDisposable {
        private IntPtr _decoder;
        private readonly int _outputSampleRate;
        private readonly int _outputChannelCount;

        public OpusDecoder(int outputSampleRate, int outputChannelCount) {
            if (outputSampleRate != 8000 && outputSampleRate != 12000 && outputSampleRate != 16000 && outputSampleRate != 24000 && outputSampleRate != 48000) {
                throw new ArgumentOutOfRangeException(nameof(outputSampleRate));
            }
            if (outputChannelCount != 1 && outputChannelCount != 2) {
                throw new ArgumentOutOfRangeException(nameof(outputChannelCount));
            }

            _decoder = NativeMethods.opus_decoder_create(outputSampleRate, outputChannelCount, out var error);
            if (error != OpusErrors.Ok) throw new Exception($"Exception occured while creating decoder: {error}");
            _outputSampleRate = outputSampleRate;
            _outputChannelCount = outputChannelCount;
        }

        ~OpusDecoder() {
            Dispose();
        }

        public void Dispose() {
            if (_decoder == IntPtr.Zero) return;
            NativeMethods.destroy_opus(_decoder);
            _decoder = IntPtr.Zero;
        }

        public void ResetState() {
            NativeMethods.opus_reset_decoder(_decoder);
        }

        public int Decode(byte[] packetData, int packetLength, float[] floatBuffer, bool useForwardErrorCorrection) {
            return NativeMethods.opus_decode(_decoder, packetData, packetLength, floatBuffer, _outputSampleRate, _outputChannelCount, useForwardErrorCorrection);
        }

        public static int GetChannels(byte[] srcEncodedBuffer) {
            return NativeMethods.opus_packet_get_nb_channels(srcEncodedBuffer);
        }
    }
}