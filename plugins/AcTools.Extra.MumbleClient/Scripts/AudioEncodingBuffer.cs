/*
 * This puts data from the mics taken on the main thread
 * Then another thread pulls frame data out
 * 
 * We now assume that each mic packet placed into the buffer is an acceptable size
 */

using System.Threading;
using AcTools.Extra.MumbleClient.Implementation.Utils;
using Debug = UnityEngine.Debug;

namespace Mumble {
    public class AudioEncodingBuffer {
        private const int QueueSize = 64;
        private readonly TargettedSpeech[] _unencodedBuffer = new TargettedSpeech[QueueSize];
        private int _queueWritePos;
        private int _queueReadPos;
        private int _queueLeft;
        private readonly object _bufferLock = new object();
        private volatile bool _isWaitingToSendLastPacket;

        private void Enqueue(PcmArray pcm, SpeechTarget target, bool lastPacket) {
            _unencodedBuffer[_queueWritePos].Set(pcm, target, lastPacket);
            if (++_queueWritePos == QueueSize) _queueWritePos = 0;
            ++_queueLeft;
        }

        public void Add(PcmArray pcm, SpeechTarget target, bool lastPacket) {
            lock (_bufferLock) {
                Enqueue(pcm, target, lastPacket);
                Monitor.Pulse(_bufferLock);
            }
        }

        public void Stop() {
            lock (_bufferLock) {
                // If we still have an item in the queue, mark the last one as last
                _isWaitingToSendLastPacket = true;
                if (_queueLeft == 0) {
                    Debug.Log("Adding stop packet");
                    Enqueue(null, SpeechTarget.Normal, true);
                } else {
                    Debug.Log("Marking last packet");
                }
                Monitor.Pulse(_bufferLock);
            }
        }

        public int GetNumUncompressedPending() {
            return _queueLeft;
        }

        private static readonly byte[] EmptyPacket = new byte[0];

        public void Encode(OpusEncoder encoder, ref CompressedBuffer ret) {
            lock (_bufferLock) {
                // Make sure we have data, or an end event
                if (_queueLeft == 0) {
                    Monitor.Wait(_bufferLock);
                }

                // If there are still no unencoded buffers, then we return an empty packet
                if (_queueLeft == 0) {
                    ret.EncodedDataBuffer = null;
                    ret.LastPacket = false;
                    ret.Position = MuVec3.Invalid;
                } else {
                    var nextToSend = _unencodedBuffer[_queueReadPos];
                    if (++_queueReadPos == QueueSize) _queueReadPos = 0;
                    ret.LastPacket = --_queueLeft == 0 && _isWaitingToSendLastPacket || nextToSend.IsStop;
                    if (nextToSend.PcmData != null) {
                        ret.EncodedDataBuffer = encoder.Encode(nextToSend.PcmData.Pcm, out ret.EncodedDataSize);
                        ret.Position = nextToSend.PcmData.Position;
                        nextToSend.PcmData.Release();
                    } else {
                        ret.EncodedDataBuffer = EmptyPacket;
                        ret.EncodedDataSize = 0;
                        ret.Position = MuVec3.Invalid;
                    }
                    ret.Target = nextToSend.Target;
                    
                    if (ret.LastPacket) {
                        Debug.Log("Resetting encoder state");
                        _isWaitingToSendLastPacket = false;
                        encoder.ResetState();
                    }
                }
            }
        }

        public struct CompressedBuffer {
            public byte[] EncodedDataBuffer;
            public int EncodedDataSize;
            public SpeechTarget Target;
            public MuVec3 Position;
            public bool LastPacket;
        }

        private struct TargettedSpeech {
            public PcmArray PcmData;
            public SpeechTarget Target;
            public bool IsStop;

            public void Set(PcmArray pcm, SpeechTarget target, bool lastPacket) {
                Target = target;
                PcmData = pcm;
                IsStop = lastPacket;
            }
        }
    }
}