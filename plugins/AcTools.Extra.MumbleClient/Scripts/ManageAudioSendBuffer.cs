using System;
using System.Diagnostics;
using System.Threading;
using AcTools.Extra.MumbleClient.Implementation.Utils;
using Debug = UnityEngine.Debug;

namespace Mumble {
    public class ManageAudioSendBuffer : IDisposable {
        private readonly MumbleUdpConnection _udpConnection;
        private readonly AudioEncodingBuffer _encodingBuffer;
        private readonly AutoResetEvent _waitHandle;
        private OpusEncoder _encoder;
        private bool _running = true;

        private Thread _encodingThread;
        private uint _sequenceIndex;
        private bool _stopSendingRequested;
        private int _encodingBitrate = 48000;
        private int _encodingInputSampleRate = -1;

        /// <summary>
        /// How long of a duration, in ms should there be between sending two packets. This helps ensure that fewer UDP packets are dropped.
        /// </summary>
        private const long MinSendingElapsedMilliseconds = 5;

        /// <summary>
        /// How many pending uncompressed buffers are too many to use any sleep. This is so that the sleep never causes us to
        /// have an uncompressed buffer overflow.
        /// </summary>
        private const int MaxPendingBuffersForSleep = 4;

        public ManageAudioSendBuffer(MumbleUdpConnection udpConnection) {
            _udpConnection = udpConnection;
            _encodingBuffer = new AudioEncodingBuffer();
            _waitHandle = new AutoResetEvent(false);
        }

        internal void Initialize(int sampleRate) {
            if (_encodingInputSampleRate == sampleRate) return;
            _encodingInputSampleRate = sampleRate;
            Interlocked.Exchange(ref _encoder, new OpusEncoder(sampleRate, 1) {
                EnableForwardErrorCorrection = false, 
                Bitrate = _encodingBitrate
            })?.Dispose();
            if (_encodingThread == null) {
                _encodingThread = new Thread(EncodingThreadEntry);
                _encodingThread.Start();
            }
        }

        public int GetBitrate() {
            return _encodingBitrate;
        }

        public void SetBitrate(int bitrate) {
            if (bitrate == _encodingBitrate) return;
            _encodingBitrate = bitrate;
            if (_encoder != null) {
                _encoder.Bitrate = bitrate;
            }
        }

        ~ManageAudioSendBuffer() {
            Dispose();
        }

        public void SendVoice(PcmArray pcm, SpeechTarget target, bool lastPacket) {
            _stopSendingRequested = false;
            _encodingBuffer.Add(pcm, target, lastPacket);
            _waitHandle.Set();
        }

        public void SendVoiceStopSignal() {
            _encodingBuffer.Stop();
            _stopSendingRequested = true;
        }

        public void Dispose() {
            _running = false;
            _waitHandle.Set();
            _encoder?.Dispose();
        }

        private const byte VoiceOpus = 128;
        private const int LastPacketFlag = 0x2000;

        private void EncodingThreadEntry() {
            // Wait for an initial voice packet
            _waitHandle.WaitOne();
            var encoded = new AudioEncodingBuffer.CompressedBuffer();
            var stopwatch = Stopwatch.StartNew();
            var encodedData = new byte[256];

            while (_running) {
                try {
                    // Keep running until a stop has been requested and we've encoded the rest of the buffer, then wait for a new voice packet
                    while (_stopSendingRequested && encoded.LastPacket) _waitHandle.WaitOne();
                    if (!_running) return;

                    _encodingBuffer.Encode(_encoder, ref encoded);
                    if (encoded.EncodedDataBuffer == null) {
                        // This should not normally occur
                        Thread.Sleep(MumbleConstants.FRAME_SIZE_MS);
                        Debug.LogWarning("Empty packet");
                        continue;
                    }

                    var expectedSize = encoded.EncodedDataSize + 24;
                    if (encodedData.Length < expectedSize) {
                        Array.Resize(ref encodedData, expectedSize);
                    }
                    
                    // Packet:
                    // [type|target] [sequence] [opus length header] [packet data]
                    encodedData[0] = (byte)(VoiceOpus | (byte)encoded.Target);
                            
                    var pos = 1;
                    Var64.Write(encodedData, ref pos, _sequenceIndex);

                    // Write header to show how long the encoded data is
                    var opusHeaderNum = encoded.EncodedDataSize;
                    if (encoded.LastPacket) {
                        opusHeaderNum |= LastPacketFlag;
                        Debug.Log("Adding end flag");
                    }

                    Var64.Write(encodedData, ref pos, (ulong)opusHeaderNum);
                    Array.Copy(encoded.EncodedDataBuffer, 0, 
                            encodedData, pos, encoded.EncodedDataSize);
                    pos += encoded.EncodedDataSize;
                    if (encoded.Position.IsValid()) {
                        encoded.Position.Serialize(encodedData, pos);
                        pos += MuVec3.Size;
                    }

                    stopwatch.Stop();
                    var timeSinceLastSend = stopwatch.ElapsedMilliseconds;
                    if (timeSinceLastSend < MinSendingElapsedMilliseconds
                            && _encodingBuffer.GetNumUncompressedPending() < MaxPendingBuffersForSleep) {
                        Thread.Sleep((int)(MinSendingElapsedMilliseconds - timeSinceLastSend));
                    }

                    _udpConnection.SendVoicePacket(encodedData, pos);
                    
                    // If we’ve hit a stop packet, then reset the seq number
                    if (encoded.LastPacket) {
                        _sequenceIndex = 0;
                    } else {
                        _sequenceIndex += MumbleConstants.NUM_FRAMES_PER_OUTGOING_PACKET;
                    }
                    
                    stopwatch.Restart();
                } catch (Exception e) {
                    if (e is ThreadAbortException) {
                        // This is ok
                        break;
                    }
                    Debug.LogError("Error: " + e);
                }
            }
        }
    }

    /// <summary>
    /// Small class to help this script re-use float arrays after their data has become encoded
    /// Obviously, it's weird to ref-count in a managed environment, but it really
    /// Does help identify leaks and makes zero-copy buffer sharing easier
    /// </summary>
    public class PcmArray {
        private static readonly MemoryPool<float> Pool = new MemoryPool<float>("PCM Data", 0);

        public float[] Pcm;
        public MuVec3 Position;

        public PcmArray(int pcmLength, MuVec3 pos) {
            Pcm = Pool.GetOrAllocate(pcmLength);
            Position = pos;
        }

        public void Release() {
            Pool.Release(ref Pcm);
        }
    }
}