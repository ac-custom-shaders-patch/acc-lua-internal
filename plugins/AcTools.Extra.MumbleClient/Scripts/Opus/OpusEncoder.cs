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
using System.Threading;

namespace Mumble {
    public class OpusEncoder : IDisposable {
        private const int MaxPacketSize = 1020;
        private IntPtr _encoder;

        public int Bitrate {
            get {
                var ret = NativeMethods.opus_encoder_ctl(_encoder, OpusCtl.GET_BITRATE_REQUEST, out var bitrate);
                if (ret < 0) throw new Exception("Encoder error: " + (OpusErrors)ret);
                return bitrate;
            }
            set {
                var ret = NativeMethods.opus_encoder_ctl(_encoder, OpusCtl.SET_BITRATE_REQUEST, value);
                if (ret < 0) throw new Exception("Encoder error: " + (OpusErrors)ret);
            }
        }

        public bool EnableForwardErrorCorrection {
            get {
                var ret = NativeMethods.opus_encoder_ctl(_encoder, OpusCtl.GET_INBAND_FEC_REQUEST, out var fec);
                if (ret < 0) throw new Exception("Encoder error: " + (OpusErrors)ret);
                return fec > 0;
            }
            set {
                var req = Convert.ToInt32(value);
                var ret = NativeMethods.opus_encoder_ctl(_encoder, OpusCtl.SET_INBAND_FEC_REQUEST, req);
                if (ret < 0) throw new Exception("Encoder error: " + (OpusErrors)ret);
            }
        }

        private readonly byte[] _encodedPacket = new byte[MaxPacketSize];

        public OpusEncoder(int srcSamplingRate, int srcChannelCount) {
            _encoder = NativeMethods.opus_encoder_create(srcSamplingRate, srcChannelCount, OpusApplication.Voip, out var error);
            if (error != OpusErrors.Ok) {
                throw new Exception("Exception occured while creating encoder");
            }
        }

        ~OpusEncoder() {
            Dispose();
        }

        public byte[] Encode(float[] pcmSamples, out int size) {
            size = NativeMethods.opus_encode(_encoder, pcmSamples, pcmSamples.Length, _encodedPacket);
            return _encodedPacket;
        }

        public void ResetState() {
            NativeMethods.opus_reset_encoder(_encoder);
        }

        public void Dispose() {
            var encoder = Interlocked.Exchange(ref _encoder, IntPtr.Zero);
            if (encoder != IntPtr.Zero) NativeMethods.destroy_opus(encoder);
        }
    }
}